//
//  MJFastImageLoader.swift
//  MJFastImageLoader
//
//  Created by Mark Jerde on 2/19/18.
//  Copyright © 2018 Mark Jerde.
//
//  This file is part of MJFastImageLoader
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of MJFastImageLoader and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

public class MJFastImageLoader {
	// Allow a singleton, for those who prefer that pattern
	public static let shared = MJFastImageLoader()

	public static var wasteCount = 0

	// Allow instance use, for those who prefer that
	public init() {
		for _ in 1...criticalProcessingConcurrencyLimit {
			criticalProcessingDispatchQueueSemaphore.signal()
		}
	}

	// Priority level.  These could be arbitrary values, but the priority will be incremented one for each processing level, so a minimum separation of three is a good idea.
	public enum Priority: Int {
		case critical = 1
		case high = 5
		case medium = 10
		case low = 20
		case prospective = 100
	}

	// MARK: Public Properties - Settings

	public var thumbnailPixels:Float = 400.0
	public var maximumCachedImages = 150
	public var maximumCachedBytes = 360 * 1024 * 1024 // 360 MB
	public var ignoreCacheForTest = false // To limit benefit for test / demo

	// MARK: Public Methods - Settings

	public func setCriticalProcessingConcurrencyLimit( limit: Int ) {
		if ( limit < self.criticalProcessingConcurrencyLimit ) {
			// Adjust down
			// Just use the intakeQueue so we don't block while waiting for work to complete
			intakeQueue.async {
				repeat {
					self.criticalProcessingDispatchQueueSemaphore.wait()
					self.criticalProcessingConcurrencyLimit -= 1
				} while ( limit < self.criticalProcessingConcurrencyLimit )

			}
		}
		else {
			// Adjust up if needed
			while ( limit > self.criticalProcessingConcurrencyLimit ) {
				self.criticalProcessingDispatchQueueSemaphore.signal()
				self.criticalProcessingConcurrencyLimit += 1
			}
		}
	}

	// MARK: Public Methods - Interaction

	public func enqueue(image: Data, priority: Priority) {
		let identity = DataIdentity(data: image)
		if ( !ignoreCacheForTest ) {
			var item:Item? = nil
			itemsAccessQueue.sync {
				item = items[identity]
			}
			if let item = item {
				if let workItem = item.workItem
				{
					workItem.retain()

					// Increase priority if needed
					if priority.rawValue < workItem.basePriority.rawValue {
						workItem.basePriority = priority
					}

					if ( workItem.isCancelled ) {
						workItem.isCancelled = false
						enqueueWork(item: item)
					}
				}
				else if ( item.results.count > 0 )
				{
					// We have results but no work item, so we must be fully formed
				}
				else {
					fatalError("error to have no workItem or result but have hint")
				}
				return
			}
		}

		let uid = nextUID
		nextUID += 1

		let item = Item(workItem: WorkItem(data: image, uid: uid, basePriority: priority))
		itemsAccessQueue.sync {
			items[identity] = item
			leastRecentlyUsed.append(identity)
		}
		enqueueWork(item: item)

		checkQuotas()
	}

	func enqueueWork(item: Item) {
		if let workItem = item.workItem {
			let priority = workItem.priority
			workItemQueueDispatchQueue.sync {
				if ( nil == workItemQueues[priority] ) {
					workItemQueues[priority] = []
				}
				workItemQueues[priority]!.append(item)

				if ( 1 == priority ) {
					if let queue = workItemQueues[1] {
						let haveCritical = queue.count > 0
						if ( haveCritical && workItemQueuesHasNoCritical ) {
							workItemQueuesHasNoCritical = false
							// Nobody else should be holding this
							NSLog("Taking noncriticalProcessingAllowedSemaphore")
							noncriticalProcessingAllowedSemaphore.wait()
							NSLog("Took noncriticalProcessingAllowedSemaphore")
						}
					}
				}
			}
			processWorkItem( critical: 1 == priority )
		}
	}

	func checkQuotas() {
		// Store values that are usually accessed thread-safe, but for a quick glance we are okay not synchronizing
		let lruCount = leastRecentlyUsed.count
		let maxResultsVolumeBytes = self.maxResultsVolumeBytes

		let overImageCountLimit = lruCount > maximumCachedImages
		let overImageBytesLimit = maxResultsVolumeBytes > maximumCachedBytes
		NSLog("quota check at \(lruCount) and \(maxResultsVolumeBytes)")

		if ( (overImageCountLimit || overImageBytesLimit) && !ignoreCacheForTest ) {
			// Cache limits are incompatible with ignoreCacheForTest.

			quotaRecoveryDispatchQueue.sync {
				removeLeastRecentlyUsedItemsToFitQuota(pass: 0)

				NSLog("quota recovered to \(leastRecentlyUsed.count) and \(self.maxResultsVolumeBytes)")
			}

			// The memory release will be delayed until GCD gets a chance to breathe.  So suspend the queues for a very short moment to allow time.
			processingQueue.suspend()
			quotaRecoveryDispatchQueue.suspend()
			itemsAccessQueue.asyncAfter(deadline: .now() + .milliseconds(1), execute: {
				self.quotaRecoveryDispatchQueue.resume()
				self.processingQueue.resume()
			})
		}
	}

	func removeLeastRecentlyUsedItemsToFitQuota( pass:Int ) {
		itemsAccessQueue.sync {
			// Fabrication of a traditional for-loop, since we are removing N items matching a criteria from an array, starting at the front of the array
			var i = 0
			var count = leastRecentlyUsed.count
			while ( i < count ) {
				let lru = leastRecentlyUsed[i]
				if let item = items[lru] {
					let noLongerNeeded = items[lru]?.workItem?.isCancelled ?? true
					let noLongerRunning = items[lru]?.workItem?.final ?? true
					var okayToRemove = false
					switch pass {
					case 0,2,4:
						// First / third / fifth pass.  Only those noLongerNeeded with 2+ resolution options in the oldest half.
						if ( !noLongerNeeded
							&& item.results.count > 1
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					case 1,3,5:
						// Second / fourth / sixth pass.  Anything noLongerNeeded in the oldest half.
						if ( !noLongerNeeded
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					case 6:
						// Seventh pass.  Only those with 2+ resolution options in the oldest half.
						if ( item.results.count > 1
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					case 7:
						// Eighth pass.  Anything the oldest half.
						if ( !noLongerNeeded
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					default:
						// Ninth+ pass.  Anything at all.
						okayToRemove = true
						break
					}

					if ( okayToRemove ) {
						// Remove the largest version of each image, or all versions if we are over count.
						let sizes = item.results
						allImages: while let max = sizes.keys.max() {
							if let image = sizes[max] {
								let bytesThis = image.cgImage!.height * image.cgImage!.bytesPerRow
								NSLog("ARC want to deinit \(Unmanaged.passUnretained(image).toOpaque()) \(noLongerNeeded) \(noLongerRunning) for \(bytesThis)")
								maxResultsVolumeBytes -= bytesThis
							}
							item.results[max] = nil
							if ( leastRecentlyUsed.count <= maximumCachedImages ) {
								break allImages
							}
						}

						// If there are no more versions, indicate forced out.
						if ( item.results.count == 0 && !noLongerNeeded ) {
							// fixme - This is just preventative, in case WorkItem doesn't deinit right away.  Make sure it does deinit right away and then remove this
							item.workItem?.isForcedOut = true
						}

						// Don't work on it any more, since we have removed at least its largest product
						if ( nil != item.workItem?.currentImage ) {
							// fixme - This is just preventative, in case WorkItem doesn't deinit right away.  Make sure it does deinit right away and then remove this
							item.workItem?.currentImage = nil
						}
						item.workItem = nil

						// If we removed it completely, remove it from items, LRU, and count
						if ( item.results.count == 0 ) {
							items[lru] = nil
							leastRecentlyUsed.remove(at: i)
							i -= 1
							count -= 1
						}

						if ( items.count <= maximumCachedImages
							&& maxResultsVolumeBytes <= maximumCachedBytes ) {
							break
						}
					}
				}

				i += 1
			}
		}

		if ( (items.count > maximumCachedImages
			|| maxResultsVolumeBytes > maximumCachedBytes)
			&& leastRecentlyUsed.count > 0 ) {
			// Try again with less filtering.

			removeLeastRecentlyUsedItemsToFitQuota(pass: pass + 1)
		}
	}

	public func cancel(image: Data) {
		let identity = DataIdentity(data: image)
		var item:Item? = nil
		itemsAccessQueue.sync {
			item = items[identity]
		}
		if let item = item {
			if let workItem = item.workItem
			{
				NSLog("cancel \(workItem.uid)")
				if ( !workItem.release() ) {
					workItem.isCancelled = true
					item.workItem = nil
					workItemQueueDispatchQueue.sync {
						if let index = workItemQueues[workItem.priority]?.index(of: item) {
							workItemQueues[workItem.priority]!.remove(at: index)
						}
						else {
							NSLog("brute removal of \(workItem.uid) from workItemQueues")
							var removed = false
							workItemQueues.keys.forEach({ (priority) in
								if let index = workItemQueues[priority]?.index(of: item) {
									workItemQueues[priority]!.remove(at: index)
									removed = true
								}
							})
							if ( !removed ) {
								NSLog("failed at brute removal of \(workItem.uid) from workItemQueues")
							}
						}
					}
				}
			}
			else if ( item.results.count == 0 )
			{
				fatalError("Cancelled before processing anything")
			}
		}
	}

	public func image(image: Data, notification: MJFastImageLoaderNotification?) -> UIImage? {
		print("lookup")
		let identity = DataIdentity(data: image)
		var item:Item? = nil
		itemsAccessQueue.sync {
			item = items[identity]
		}
		if let item = item {
			// Register notification if there is an active work item and we have a notification.
			if let workItem = item.workItem {
				print("register \(workItem.uid)")
				if let notification = notification {
					// Insert ourselves at the front.
					notification.next = workItem.notification
					workItem.notification = notification
					workItem.retain() // For the notification
					notification.workItem = workItem
				}
				print("registered \(workItem.uid)")
			}

			// Move to back of LRU since someone asked for it
			itemsAccessQueue.sync {
				// Ensure it is still in items, since it could have been removed between now and our last check.
				if nil != items[identity] {
					if let index = leastRecentlyUsed.index(of: identity) {
						leastRecentlyUsed.remove(at: index)
					}
					leastRecentlyUsed.append(identity)
				}
			}

			if let max = item.results.keys.max() {
				return item.results[max]
			}
			return nil
		}
		return nil
	}

	public func flush() {
		print("flush")
		// fixme - this is a bit race-prone.  Should stop outstanding work and / or prevent the actions below from being concurrent with other use of these objects.
		// Stop the queues first
		workItemQueues = [:]
		itemsAccessQueue.sync {
			// Remove all retains from each workItem so that any still in processing will be avoided.
			items.values.forEach { (item) in
				item.workItem?.retainCount = 0
			}
			// Get rid of the items
			items = [:]
			leastRecentlyUsed = []
		}
		// Clear the rest
		maxResultsVolumeBytes = 0
	}

	// MARK: Private Variables - Settings

	var criticalProcessingConcurrencyLimit = 12

	// MARK: Private Variables - Other

	let intakeQueue = DispatchQueue(label: "MJFastImageLoader.intakeQueue")
	var nextUID:Int = 0

	// All access to items and leastRecentlyUsed is thread-safe via itemsAccessQueue
	var items:[DataIdentity:Item] = [:]
	var leastRecentlyUsed:[DataIdentity] = []
	let itemsAccessQueue = DispatchQueue(label: "MJFastImageLoader.itemsAccessQueue")

	var maxResultsVolumeBytes = 0

	class DataIdentity : Equatable, Hashable {
		// A simple mechanism to store a representation of a large object in a small space.
		// Uses the hash value of the original object, which has a risk of collision so it
		// stores a secondary hash of a subset of the original content providing 1-in-n-squared
		// probability of a incorrect equality.
		var hashValue: Int
		var partialHash: Int

		init(data: Data) {
			hashValue = data.hashValue
			let short = data.count < 1000
			let partialStart = short ? 1 : (data.count / 10 * 5)
			let partialEnd = short ? data.count : (data.count / 10 * 6)
			partialHash = data.subdata(in: Range<Data.Index>(partialStart...partialEnd)).hashValue
		}

		static func ==(lhs: MJFastImageLoader.DataIdentity, rhs: MJFastImageLoader.DataIdentity) -> Bool {
			return lhs.hashValue == rhs.hashValue && lhs.partialHash == rhs.partialHash
		}
	}

	class Item : Equatable {
		var workItem:WorkItem? = nil
		var results:[CGFloat:UIImage] = [:]

		init(workItem: WorkItem) {
			self.workItem = workItem
		}

		static func ==(lhs: MJFastImageLoader.Item, rhs: MJFastImageLoader.Item) -> Bool {
			return lhs === rhs
		}
	}

	func processWorkItem(critical: Bool) {
		if ( critical ) {
			self.dispatchCriticalWorkItem()
		}
		else {
			processingQueue.async {
				// Check if we can get the semaphore before starting work, but don't hold it.
				NSLog("Checking noncriticalProcessingAllowedSemaphore")
				self.noncriticalProcessingAllowedSemaphore.wait()
				self.noncriticalProcessingAllowedSemaphore.signal()
				NSLog("Checked noncriticalProcessingAllowedSemaphore")

				if let item = self.nextWorkItem( critical: false ) {
					if let workItem = item.workItem {
						print("processWorkItem is \(workItem.uid) retain \(workItem.retainCount) pri \(workItem.priority)")
						if ( workItem.retainCount <= 0 )
						{
							print("skipped old")
							fatalError("shouldn't be able to get to skipped old")
							return
						}
					}

					self.executeWorkItem(item: item)
				}
			}
		}
	}

	func dispatchCriticalWorkItem() {
		criticalProcessingDispatchQueue.async {

			// Since the criticalProcessingWorkQueue is concurrent, limit the concurrent volume here.
			self.criticalProcessingDispatchQueueSemaphore.wait()

			self.criticalProcessingWorkQueue.async {
				self.workItemQueueDispatchQueue.sync {
					self.criticalProcessingActiveCount += 1
				}

				if let item = self.nextWorkItem( critical: true ) {
					if let workItem = item.workItem {
						print("processWorkItem is \(workItem.uid) retain \(workItem.retainCount) pri \(workItem.priority)")
						if ( workItem.retainCount <= 0 )
						{
							print("skipped old")
							fatalError("shouldn't be able to get to skipped old")
							return
						}
					}
					self.executeWorkItem(item: item)
				}
				else {
					fatalError("Tried to execute critical item but found none.  This is probably okay and should just be ignored.")
				}

				self.workItemQueueDispatchQueue.sync {
					self.criticalProcessingActiveCount -= 1

					if ( 0 == self.criticalProcessingActiveCount ) {
						if let queue = self.workItemQueues[1] {
							let haveCritical = queue.count > 0
							if ( !haveCritical && !self.workItemQueuesHasNoCritical ) {
								self.workItemQueuesHasNoCritical = true
								self.noncriticalProcessingAllowedSemaphore.signal()
								NSLog("Gave noncriticalProcessingAllowedSemaphore")
							}
						}
					}
				}

				self.criticalProcessingDispatchQueueSemaphore.signal()
			}
		}
	}

	func executeWorkItem( item: Item ) {
		if let workItem = item.workItem {
			NSLog("execute \(workItem.uid) at \(workItem.state)")
			if let result = workItem.next(thumbnailPixels: self.thumbnailPixels) {
				NSLog("execute good \(workItem.uid)")
				item.results[result.size.height] = result
				maxResultsVolumeBytes += result.cgImage!.height * result.cgImage!.bytesPerRow
				checkQuotas()

				if ( workItem.final ) {
					item.workItem = nil
				}
				else {
					enqueueWork(item: item) // To process next level of image
				}
			}
			else {
				NSLog("execute nil \(workItem.uid)")
				if ( item.results.count == 0 && workItem.retainCount > 0 ) {
					if ( workItem.isForcedOut ) {
						print("was forced out")
					}
					else {
						fatalError("done without result is bad")
					}
				}
				// nil result so it is done.  Remove from work items.
				item.workItem = nil
			}
		}
	}

	func nextWorkItem( critical: Bool ) -> Item? {
		var result:Item? = nil

		workItemQueueDispatchQueue.sync {
			let priorities = workItemQueues.keys.sorted()

			outerLoop: for priority in priorities {
				// Only check this priority if critical XOR non-critical-priority
				if ( critical != (priority != 1) ) {
					if let queue = workItemQueues[priority] {
						var removeCount = 0
						for item in queue {
							removeCount += 1
							if ( item.workItem?.retainCount ?? 0 > 0 ) {
								workItemQueues[priority]!.removeFirst(removeCount)
								result = item
								break outerLoop
							}
							else {
								// Remove from queue if it is not retained, so they will not accumulate
								item.workItem?.isCancelled = true
								workItemQueues[priority]!.remove(at: removeCount - 1)
								removeCount -= 1
							}
						}
					}
				}
			}

			NSLog("nextWorkItem is \(result?.workItem?.uid)")
		}

		return result
	}

	// Limit the number of concurrent critical items
	private let criticalProcessingDispatchQueueSemaphore = DispatchSemaphore(value: 0)

	// Block non-critical work when appropriate
	private let noncriticalProcessingAllowedSemaphore = DispatchSemaphore(value: 1)

	// Used in one place to make critical processing semi-concurrent and non-blocking
	let criticalProcessingDispatchQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingDispatchQueue")

	// Used in one place to make critical processing concurrent and non-blocking
	let criticalProcessingWorkQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingQueue", qos: .userInitiated, attributes: .concurrent)

	// Used in one place to make non-critical processing non-concurrent and non-blocking
	let processingQueue = DispatchQueue(label: "MJFastImageLoader.processingQueue")

	// All access to workItemQueues, workItemQueuesHasNoCritical, and criticalProcessingActiveCount is thread-safe via workItemQueueDispatchQueue
	var workItemQueues:[Int:[Item]] = [:]
	var workItemQueuesHasNoCritical = true
	var criticalProcessingActiveCount = 0
	let workItemQueueDispatchQueue = DispatchQueue(label: "MJFastImageLoader.workItemQueueDispatchQueue")

	let quotaRecoveryDispatchQueue = DispatchQueue(label: "MJFastImageLoader.quotaRecoveryDispatchQueue")

}
