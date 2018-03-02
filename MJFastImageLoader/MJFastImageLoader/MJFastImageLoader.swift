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

	public func enqueue(image: Data, priority: Priority) -> Int {
		var uid = -1
		var doProcess = true
		intakeQueue.sync {
			if nil != (ignoreCacheForTest ? nil : hintMap.index(forKey: image))
			{
				uid = hintMap[image]!
				if let workItem = workItems[uid]
				{
					workItem.retain()

					// Increase priority if needed
					if priority.rawValue < workItem.basePriority.rawValue {
						workItem.basePriority = priority
					}

					if ( workItem.isCancelled ) {
						workItem.isCancelled = false
					}
					else {
						doProcess = false
					}
				}
				else if ( results[uid]?.count ?? 0 > 0 )
				{
					// We have results but no work item, so we must be fully formed
					doProcess = false
				}
				else {
					fatalError("error to have no workItem or result but have hint")
				}
			}
			else
			{
				uid = nextUID
				nextUID += 1
				hintMap[image] = uid

				let workItem = WorkItem(data: image, uid: uid, basePriority: priority)
				workItems[uid] = workItem
				leastRecentlyUsed.append(image)

				checkQuotas()
			}
		}
		if ( doProcess ) {
			if let workItem = workItems[uid] {
				workItemQueueDispatchQueue.sync {
					if ( nil == workItemQueues[workItem.priority] ) {
						workItemQueues[workItem.priority] = []
					}
					workItemQueues[workItem.priority]!.append(workItem)

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
		return uid
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
			let index = hintMap[lru]!
			let noLongerNeeded = workItems[index]?.isCancelled ?? true
			let noLongerRunning = workItems[index]?.final ?? true
			if ( force || noLongerNeeded ) {
				// Remove the largest version of each image, or all versions if we are over count.
				if let sizes = results[index] {
					allImages: while let max = sizes.keys.max() {
						if let image = sizes[max] {
							let bytesThis = image.cgImage!.height * image.cgImage!.bytesPerRow
							maxResultsVolumeBytes -= bytesThis
							removedSomething = true
						}
						results[index]![max] = nil
						if ( leastRecentlyUsed.count <= maximumCachedImages ) {
							break allImages
						}
					}

					// If there are no more versions, remove empty dictionary from results.
					if ( results[index]!.count == 0 ) {
						if ( !noLongerNeeded ) {
							workItems[index]?.isForcedOut = true
						}
						results[index] = nil
					}
				}

				// Don't work on it any more, since we have removed at least its largest product
				if ( nil != workItems[index]?.currentImage ) {
					workItems[index]?.currentImage = nil
				}
				workItems.removeValue(forKey: index)

				// If we removed it completely, remove it from hints, LRU, and count
				if ( results[index]?.count ?? 0 == 0 ) {
					hintMap[lru] = nil
					leastRecentlyUsed.remove(at: i)
					i -= 1
					count -= 1
					removedSomething = true
				}

				if ( hintMap.count <= maximumCachedImages
					&& maxResultsVolumeBytes <= maximumCachedBytes ) {
					break
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
		if let index = hintMap.index(forKey: image)
		{
			var uid = -1
			uid = hintMap[index].value
			uid = hintMap[image]!
			if let workItem = workItems[uid]
			{
				if ( !workItem.release() ) {
				}
			}
			else if ( results[uid]?.count ?? 0 == 0 )
			{
				fatalError("Cancelled before processing anything")
			}
		}
	}

	public func image(image: Data, notification: MJFastImageLoaderNotification?) -> UIImage? {
		print("lookup")
		if let uid = hintMap[image] {
			// Register notification if there is an active work item and we have a notification.
			print("register \(uid)")
			if let workItem = workItems[uid] {
				if let notification = notification {
					// Insert ourselves at the front.
					notification.next = workItem.notification
					workItem.notification = notification
					workItem.retain() // For the notification
					notification.workItem = workItem
					print("registered \(uid)")
				}
			}

			// Move to back of LRU since someone asked for it
			if leastRecentlyUsed.contains(image) {
				leastRecentlyUsed.remove(at: leastRecentlyUsed.index(of: image)!)
			}
			leastRecentlyUsed.append(image)

			if let sizes = results[uid] {
				if let max = sizes.keys.max() {
					return sizes[max]
				}
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
		workItems.values.forEach { (workItem) in
			workItem.retainCount = 0
		}
		// Get rid of the work
		workItems = [:]
		// Clear the rest
		results = [:]
		maxResultsVolumeBytes = 0
		hintMap = [:]
		leastRecentlyUsed = []
	}

	// MARK: Private Variables - Settings

	var criticalProcessingConcurrencyLimit = 12

	// MARK: Private Variables - Other

	let intakeQueue = DispatchQueue(label: "MJFastImageLoader.intakeQueue")
	var nextUID:Int = 0
	var workItems:[Int:WorkItem] = [:]
	var leastRecentlyUsed:[Data] = []
	var hintMap:[Data:Int] = [:]
	var results:[Int:[CGFloat:UIImage]] = [:]
	var maxResultsVolumeBytes = 0

	func processWorkItem() {
// fixme - wrap this all in a non-concurrent GCD queue
		if let item = nextWorkItem() {
			print("processWorkItem is \(item.uid) retain \(item.retainCount) pri \(item.priority)")
			if ( item.retainCount <= 0 )
			{
				print("skipped old")
				return
			}
			if ( item.priority > 1 ) {
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
					self.dispatchCriticalWorkItem(workItem: item)
				}
			}
		}
	}

	func dispatchCriticalWorkItem( workItem: WorkItem ) {
		// Since the criticalProcessingWorkQueue is concurrent, limit the concurrent volume here.
		criticalProcessingDispatchQueueSemaphore.wait()

		criticalProcessingWorkQueue.async {
			self.executeWorkItem(item: workItem)

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

	func executeWorkItem( item: WorkItem ) {
		NSLog("execute \(item.uid) at \(item.state)")
		if let result = item.next(thumbnailPixels: self.thumbnailPixels) {
			NSLog("execute good \(item.uid)")
			if ( nil == results[item.uid] ) {
				results[item.uid] = [:]
			}
			results[item.uid]![result.size.height] = result
			maxResultsVolumeBytes += result.cgImage!.height * result.cgImage!.bytesPerRow
			checkQuotas()
			processingQueue.async {
				/*print("sleep")
				sleep(10)
				print("slept")*/
				self.workItemQueueDispatchQueue.sync {
					if ( nil == self.workItemQueues[item.priority] ) {
						self.workItemQueues[item.priority] = []
					}
					self.workItemQueues[item.priority]?.append(item) // To process next level of image
				}
				self.processWorkItem()
			}
		}
		else {
			NSLog("execute nil \(item.uid)")
			if ( results[item.uid]?.count ?? 0 == 0 && item.retainCount > 0 ) {
				if ( item.isForcedOut ) {
					print("was forced out")
				}
				else {
					fatalError("done without result is bad")
				}
			}
			// nil result so it is done.  Remove from work items.
			workItems.removeValue(forKey: item.uid)
		}
	}

	func nextWorkItem() -> WorkItem? {
		var result:WorkItem? = nil

		workItemQueueDispatchQueue.sync {
			let priorities = workItemQueues.keys.sorted()

			outerLoop: for priority in priorities {
				if let queue = workItemQueues[priority] {
					var removeCount = 0
					for workItem in queue {
						removeCount += 1
						if ( workItem.retainCount > 0 ) {
							workItemQueues[priority]!.removeFirst(removeCount)
							result = workItem
							break outerLoop
						}
						else {
							// Remove from queue if it is not retained, so they will not accumulate
							workItem.isCancelled = true
							workItemQueues[priority]!.remove(at: removeCount - 1)
							removeCount -= 1
						}
					}
				}
			}

			print("nextWorkItem is \(result?.uid)")
		}

		return result
	}

	private let criticalProcessingDispatchQueueSemaphore = DispatchSemaphore(value: 0)
	private let noncriticalProcessingAllowedSemaphore = DispatchSemaphore(value: 1)
	let criticalProcessingDispatchQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingDispatchQueue")
	var criticalProcessingActiveCount = 0
	let criticalProcessingWorkQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingQueue", qos: .userInitiated, attributes: .concurrent)
	let processingQueue = DispatchQueue(label: "MJFastImageLoader.processingQueue")
	var workItemQueues:[Int:[WorkItem]] = [:]
	var workItemQueuesHasNoCritical = true
	let workItemQueueDispatchQueue = DispatchQueue(label: "MJFastImageLoader.workItemQueueDispatchQueue")
	let quotaRecoveryDispatchQueue = DispatchQueue(label: "MJFastImageLoader.quotaRecoveryDispatchQueue")

}
