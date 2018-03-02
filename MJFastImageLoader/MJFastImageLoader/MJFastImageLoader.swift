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
		intakeQueue.sync {
			if nil != (ignoreCacheForTest ? nil : items.index(forKey: identity))
			{
				let item = items[identity]
				if let workItem = item?.workItem
				{
					workItem.retain()

					// Increase priority if needed
					if priority.rawValue < workItem.basePriority.rawValue {
						workItem.basePriority = priority
					}

					if ( workItem.isCancelled ) {
						workItem.isCancelled = false
						enqueueWork(item: item!)
					}
				}
				else if ( item?.results.count ?? 0 > 0 )
				{
					// We have results but no work item, so we must be fully formed
				}
				else {
					fatalError("error to have no workItem or result but have hint")
				}
			}
			else
			{
				let uid = nextUID
				nextUID += 1

				let workItem = WorkItem(data: image, uid: uid, basePriority: priority)
				let item = Item(workItem: workItem)
				items[identity] = item
				leastRecentlyUsed.append(identity)
				enqueueWork(item: item)

				checkQuotas()
			}
		}
	}

	func enqueueWork(item: Item) {
		if let workItem = item.workItem {
			workItemQueueDispatchQueue.sync {
				if ( nil == workItemQueues[workItem.priority] ) {
					workItemQueues[workItem.priority] = []
				}
				workItemQueues[workItem.priority]!.append(item)

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
			processWorkItem()
		}
	}

	func checkQuotas() {
		let overImageCountLimit = leastRecentlyUsed.count > maximumCachedImages
		let overImageBytesLimit = maxResultsVolumeBytes > maximumCachedBytes
		NSLog("quota check at \(leastRecentlyUsed.count) and \(maxResultsVolumeBytes)")

		if ( (overImageCountLimit || overImageBytesLimit) && !ignoreCacheForTest ) {
			// Cache limits are incompatible with ignoreCacheForTest.

			quotaRecoveryDispatchQueue.sync {
				removeLeastRecentlyUsedItemsToFitQuota(force: false)

				NSLog("quota recovered to \(leastRecentlyUsed.count) and \(maxResultsVolumeBytes)")
			}
		}
	}

	func removeLeastRecentlyUsedItemsToFitQuota( force:Bool ) {
		var removedSomething = false

		// Fabrication of a traditional for-loop, since we are removing N items matching a criteria from an array, starting at the front of the array
		var i = 0
		var count = leastRecentlyUsed.count
		while ( i < count ) {
			let lru = leastRecentlyUsed[i]
			if let item = items[lru] {
			let noLongerNeeded = items[lru]?.workItem?.isCancelled ?? true
			let noLongerRunning = items[lru]?.workItem?.final ?? true
			if ( force || noLongerNeeded ) {
				// Remove the largest version of each image, or all versions if we are over count.
				let sizes = item.results
				allImages: while let max = sizes.keys.max() {
					if let image = sizes[max] {
						let bytesThis = image.cgImage!.height * image.cgImage!.bytesPerRow
						NSLog("ARC want to deinit \(Unmanaged.passUnretained(image).toOpaque()) \(noLongerNeeded) \(noLongerRunning) for \(bytesThis)")
						maxResultsVolumeBytes -= bytesThis
						removedSomething = true
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
					removedSomething = true
				}

				if ( items.count <= maximumCachedImages
					&& maxResultsVolumeBytes <= maximumCachedBytes ) {
					break
				}
				}
			}

			i += 1
		}

		if ( !removedSomething ) {
			// Try again without filtering.

			if ( force ) {
				fatalError("Failed to recover anything while over quota.")
			}

			removeLeastRecentlyUsedItemsToFitQuota(force: true)
		}
	}

	public func cancel(image: Data) {
		let identity = DataIdentity(data: image)
		if let item = items[identity] {
			if let workItem = item.workItem
			{
				NSLog("cancel \(workItem.uid)")
				if ( !workItem.release() ) {
					workItem.isCancelled = true
					item.workItem = nil
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
			else if ( item.results.count == 0 )
			{
				fatalError("Cancelled before processing anything")
			}
		}
	}

	public func image(image: Data, notification: MJFastImageLoaderNotification?) -> UIImage? {
		print("lookup")
		let identity = DataIdentity(data: image)
		if let item = items[identity] {
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
			if let index = leastRecentlyUsed.index(of: identity) {
				leastRecentlyUsed.remove(at: index)
			}
			leastRecentlyUsed.append(identity)

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
		// Remove all retains from each workItem so that any still in processing will be avoided.
		items.values.forEach { (item) in
			item.workItem?.retainCount = 0
		}
		// Get rid of the work
		items = [:]
		// Clear the rest
		maxResultsVolumeBytes = 0
		leastRecentlyUsed = []
	}

	// MARK: Private Variables - Settings

	var criticalProcessingConcurrencyLimit = 12

	// MARK: Private Variables - Other

	let intakeQueue = DispatchQueue(label: "MJFastImageLoader.intakeQueue")
	var nextUID:Int = 0
	var items:[DataIdentity:Item] = [:]
	var leastRecentlyUsed:[DataIdentity] = []
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

	func processWorkItem() {
// fixme - wrap this all in a non-concurrent GCD queue
		if let item = nextWorkItem() {
			if let workItem = item.workItem {
				print("processWorkItem is \(workItem.uid) retain \(workItem.retainCount) pri \(workItem.priority)")
				if ( workItem.retainCount <= 0 )
				{
					print("skipped old")
					fatalError("shouldn't be able to get to skipped old")
					return
				}
				if ( workItem.priority > 1 ) {
					processingQueue.async {
						// Check if we can get the semaphore before starting work, but don't hold it.
						NSLog("Checking noncriticalProcessingAllowedSemaphore")
						self.noncriticalProcessingAllowedSemaphore.wait()
						self.noncriticalProcessingAllowedSemaphore.signal()
						NSLog("Checked noncriticalProcessingAllowedSemaphore")
						self.executeWorkItem(item: item)
					}
				}
				else {
					criticalProcessingDispatchQueue.async {
						self.workItemQueueDispatchQueue.sync {
							self.criticalProcessingActiveCount += 1
						}
						self.dispatchCriticalWorkItem(item: item)
					}
				}
			}
		}
	}

	func dispatchCriticalWorkItem( item: Item ) {
		// Since the criticalProcessingWorkQueue is concurrent, limit the concurrent volume here.
		criticalProcessingDispatchQueueSemaphore.wait()

		criticalProcessingWorkQueue.async {
			self.executeWorkItem(item: item)

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

	func executeWorkItem( item: Item ) {
		if let workItem = item.workItem {
			NSLog("execute \(workItem.uid) at \(workItem.state)")
			if let result = workItem.next(thumbnailPixels: self.thumbnailPixels) {
				NSLog("execute good \(workItem.uid)")
				item.results[result.size.height] = result
				maxResultsVolumeBytes += result.cgImage!.height * result.cgImage!.bytesPerRow
				checkQuotas()
				processingQueue.async {
					/*print("sleep")
					sleep(10)
					print("slept")*/
					self.workItemQueueDispatchQueue.sync {
						if ( nil == self.workItemQueues[workItem.priority] ) {
							self.workItemQueues[workItem.priority] = []
						}
						self.workItemQueues[workItem.priority]?.append(item) // To process next level of image
					}
					self.processWorkItem()
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

	func nextWorkItem() -> Item? {
		var result:Item? = nil

		workItemQueueDispatchQueue.sync {
			let priorities = workItemQueues.keys.sorted()

			outerLoop: for priority in priorities {
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

			NSLog("nextWorkItem is \(result?.workItem?.uid)")
		}

		return result
	}

	private let criticalProcessingDispatchQueueSemaphore = DispatchSemaphore(value: 0)
	private let noncriticalProcessingAllowedSemaphore = DispatchSemaphore(value: 1)
	let criticalProcessingDispatchQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingDispatchQueue")
	var criticalProcessingActiveCount = 0
	let criticalProcessingWorkQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingQueue", qos: .userInitiated, attributes: .concurrent)
	let processingQueue = DispatchQueue(label: "MJFastImageLoader.processingQueue")
	var workItemQueues:[Int:[Item]] = [:]
	var workItemQueuesHasNoCritical = true
	let workItemQueueDispatchQueue = DispatchQueue(label: "MJFastImageLoader.workItemQueueDispatchQueue")
	let quotaRecoveryDispatchQueue = DispatchQueue(label: "MJFastImageLoader.quotaRecoveryDispatchQueue")

}
