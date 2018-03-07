//
//  FastImageLoader.swift
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

/// An image processing mechanism to provide faster image rendering of large images into UIImageView for improved user experience.
///
/// ### Usage Example: ###
///
/// *Add image to loader.*
///
/// This example adds the image in a `Data` instance to the `FastImageLoader`.
///
/// ```
/// FastImageLoader.shared.enqueue(image: data, priority: .critical)
/// ```
///
/// *Configure batching.*
///
/// This example configures batching for simultaneous burst display of content.
///
/// ```
/// // Group up to six updates or as many as arrive within half a second of the first.
/// FastImageLoaderBatch.shared.batchUpdateQuantityLimit = 6
/// FastImageLoaderBatch.shared.batchUpdateTimeLimit = 0.5
/// ```
///
/// *Retrieve image from loader.*
///
/// This example retrieves the processed UIImage from FastImageLoader and registers an update notification.
///
/// ```
/// DispatchQueue.main.sync {
///	    let updater = UIImageViewUpdater(imageView: imageView, batch: FastImageLoaderBatch.shared)
///	    imageView.image = FastImageLoader.shared.image(image: data, notification: updater)
/// }
/// ```
///
/// *Cancel update notifications.*
///
/// This example cancels update notifications and processing, such as when you want a different image in that UIImageView.
///
/// ```
/// updater.cancel()
/// FastImageLoader.shared.cancel(image: data)
/// ```
public class FastImageLoader {

	// MARK: - Public Instantiation and Access

	// Allow a singleton, for those who prefer that pattern
	/// Returns the shared fast image loader.
	public static let shared = FastImageLoader()

	// Allow instance use, for those who prefer that pattern
	public init() {
		for _ in 1...criticalProcessingConcurrencyLimit {
			criticalProcessingDispatchQueueSemaphore.signal()
		}
	}


	// MARK: - Public Properties - Settings

	/// The maximum width or height in pixels of the thumbnail render.  Can be decreased to limit render times.
	public var thumbnailPixels:Float = 400.0

	/// The maximum number of images to keep cached for reuse, excluding any that have not been cancelled or completed.
	public var maximumCachedImages = 150

	/// The maximum number of bytes the cache for reuse can consume.  Compliance is based on an estimated consumption that usually overestimates but will never underestimate.  Overage is allowed during processing and is corrected immediately after each image is processed.
	public var maximumCachedBytes = 360 * 1024 * 1024 // 360 MB


	// MARK: Public Methods - Settings

	/// Sets the maximum number of critical-processing allowed to actually concurrently execute on CPU, allowing quicker results.
	///
	/// Does not limit the number of critical-processing tasks that can be queued.
	///
	/// - important: Setting too high will slow rendering as the system has too few resources to render concurrently without interruption and keeps switching task mid-render.
	///
	/// - Parameter limit: The maximum number allowed.
	public func setCriticalProcessingConcurrencyLimit( limit: Int ) {
		if ( limit < self.criticalProcessingConcurrencyLimit ) {
			// Adjust down
			// Go async so we don't block the caller.  Use our own special queue to not block anything else.
			DispatchQueue(label: "FastImageLoader.concurrencyAdjustQueue").async {
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


	// MARK: - Public Methods and Values - Interaction

	/// The priority level for processing.
	///
	/// These could be arbitrary values, with the exception that critical will enable concurrent processing.
	///
	/// - critical: Immediately needed.  Will generate initial image concurrently with other processing if allowed.
	/// - high: Needed soon, but not holding up UI.
	/// - medium: Needed, but less soon.
	/// - low: Needed, but least soon.
	/// - prospective: Might be needed eventually.
	public enum Priority: Int {
		case critical = 1
		case high = 5
		case medium = 10
		case low = 20
		case prospective = 100
	}

	/// Adds an image to the loader and starts processsing.
	///
	/// - Parameters:
	///   - image: The image to add to the loader.
	///   - priority: The priority at which to process the image.
	public func enqueue(image: Data, priority: Priority) {
		let identity = DataIdentity(data: image)
		if ( !ignoreCacheForTest ) {
			var item:LoaderItem? = nil
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
					return
				}
				else if ( item.results.count > 0 )
				{
					// We have results but no work item, so we must be fully formed
					return
				}

				// It is possible to have an entry in items with no work and no results due to race timing.  This is okay.  Just create a new one below.
			}
		}

		let uid = nextUID
		nextUID += 1

		let item = LoaderItem(workItem: WorkItem(data: image, uid: uid, basePriority: priority))
		itemsAccessQueue.sync {
			items[identity] = item
			leastRecentlyUsed.append(identity)
		}
		enqueueWork(item: item)

		checkQuotas()
	}

	/// Cancels a processing for an image in the loader.
	///
	/// - Parameter image: The image to cancel processing for.
	public func cancel(image: Data) {
		// TODO: Should this also cancel all notifications for this item?  Otherwise the notification could come back to life if a future enqueue of this data resumes processing.
		let identity = DataIdentity(data: image)
		var item:LoaderItem? = nil
		itemsAccessQueue.sync {
			item = items[identity]
		}
		if let item = item {
			if let workItem = item.workItem
			{
				NSLog("cancel \(workItem.uid)")
				if ( !workItem.release() ) {
					workItem.isCancelled = true
					NSLog("cancel() workItem \(item.uid)")
					item.workItem = nil
					var removed = false
					workItemQueueDispatchQueue.sync {
						if let index = workItemQueues[workItem.priority]?.index(of: item) {
							workItemQueues[workItem.priority]!.remove(at: index)
							removed = true
						}
						else {
							NSLog("brute removal of \(workItem.uid) from workItemQueues")
							workItemQueues.keys.forEach({ (priority) in
								if let index = workItemQueues[priority]?.index(of: item) {
									workItemQueues[priority]!.remove(at: index)
									removed = true
								}
							})
						}
						if ( !removed ) {
							// This is pretty common.  It's okay.  It happens because the item is currently being executed.
							NSLog("failed to removal \(workItem.uid) from workItemQueues")
						}
					}

					if ( removed && 0 == item.results.count ) {
						// If we got it out of the workItemQueues and nothing has been produced from it, also remove it from items since it will just stay empty.
						itemsAccessQueue.async {
							// Double check that it didn't get recreated before we got here.
							if ( nil == item.workItem && 0 == item.results.count ) {
								self.items[identity] = nil
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

	/// Retrieve any processed form of an image in the loader and registers notification for further versions.
	///
	/// - Parameters:
	///   - image: The image to retrieve render for.
	///   - notification: The notification to register with that image.
	/// - Returns: Rendered image.
	public func image(image: Data, notification: FastImageLoaderNotification?) -> UIImage? {
		print("lookup")
		let identity = DataIdentity(data: image)
		var item:LoaderItem? = nil
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

	/// Removes all content from cache and work queues.
	public func flush() {
		print("flush")
		// TODO: Check for any possible race conditions.  Maybe should stop/flush outstanding work queues and/or put the actions below in their corresponding GCD queues.
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


	// MARK: - Public Properties - Development / Debug Only

	// Just for development / debug to record quantity of processing that completes with nobody wanting notification any longer.
	/// Development metric.  Do not use.
	@available(*, deprecated)
	public static var wasteCount = 0

	/// Development control.  Do not use.
	@available(*, deprecated)
	public var ignoreCacheForTest = false // To limit benefit for test / demo


	// MARK: - Quota management

	/// Checks to ensure quotas are adhered to and releases resources if necessary.
	private func checkQuotas() {
		// Store values that are usually accessed thread-safe, but for a quick glance we are okay not synchronizing
		let lruCount = leastRecentlyUsed.count
		let maxResultsVolumeBytes = self.maxResultsVolumeBytes

		let overImageCountLimit = lruCount > maximumCachedImages
		let overImageBytesLimit = maxResultsVolumeBytes > maximumCachedBytes
		NSLog("quota check at \(lruCount) and \(maxResultsVolumeBytes)")

		if ( (overImageCountLimit || overImageBytesLimit) && !ignoreCacheForTest ) {
			// Cache limits are incompatible with ignoreCacheForTest.

			quotaRecoveryDispatchQueue.sync {
				removeLeastRecentlyUsedItemsToFitQuota(pass: 0, overImageBytesLimit: overImageBytesLimit)

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

	/// Releases resources to comply with quota.
	///
	/// - Parameters:
	///   - pass: The attempt number for recursive calls.  Always provide zero outside for calls outside this method.
	///   - overImageBytesLimit: The current condition of being over the memory limit.
	private func removeLeastRecentlyUsedItemsToFitQuota( pass:Int, overImageBytesLimit:Bool ) {
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
						if ( noLongerNeeded
							&& item.results.count > 1
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					case 1,3,5:
						// Second / fourth / sixth pass.  Anything noLongerNeeded in the oldest half.
						if ( noLongerNeeded
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					case 6:
						// Seventh pass.  Only those with 2+ resolution options in the oldest half, but only if it is no longer needed or we need to free memory.
						if ( (noLongerNeeded || overImageBytesLimit)
							&& item.results.count > 1
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					case 7:
						// Eighth pass.  Anything the oldest half, but only if it is no longer needed or we need to free memory.
						if ( (noLongerNeeded || overImageBytesLimit)
							&& i < count / 2 ) {
							okayToRemove = true
						}
						break

					default:
						// Ninth pass.  Anything at all, but only if it is no longer needed or we need to free memory.
						okayToRemove = noLongerNeeded || overImageBytesLimit
						break
					}

					if ( okayToRemove ) {
						// Remove the largest version of each image, or all versions if we are over count.
						let sizes = item.results
						allImages: while let max = sizes.keys.max() {
							if let image = sizes[max] {
								let bytesThis = image.cgImage!.height * image.cgImage!.bytesPerRow
								maxResultsVolumeBytes -= bytesThis

								// If we are doing debug / analysis, help that along.
								if let image = image as? WorkItem.TrackedUIImage {
									image.shouldDeinitSoon(bool1: noLongerNeeded, bool2: noLongerRunning)
								}
							}
							item.results[max] = nil
							if ( leastRecentlyUsed.count <= maximumCachedImages ) {
								break allImages
							}
						}

						// If there are no more versions, indicate forced out.
						if ( item.results.count == 0 && !noLongerNeeded ) {
							// TODO: Setting isForcedOut is just preventative, in case WorkItem doesn't deinit right away.  Make sure it does deinit right away and then remove this
							item.workItem?.isForcedOut = true
						}

						// Don't work on it any more, since we have removed at least its largest product
						if ( nil != item.workItem?.currentImage ) {
							// TODO: Clearing currentImage is just preventative, in case WorkItem doesn't deinit right away.  Make sure it does deinit right away and then remove this
							item.workItem?.currentImage = nil
						}
						NSLog("Remove workItem \(item.uid)")
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
			&& leastRecentlyUsed.count > 0
			&& pass < 8 ) {
			// Try again with less filtering.

			removeLeastRecentlyUsedItemsToFitQuota(pass: pass + 1, overImageBytesLimit: overImageBytesLimit)
		}
	}


	// MARK: - Execution flow

	/// Adds an item to the workItemQueues, sets block on non-critical work if appropriate, and enqueues GCD call to execution method.
	///
	/// - Parameter item: The item to enqueue.
	private func enqueueWork(item: LoaderItem) {
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

	/// Enqueues execution of a WorkItem.
	///
	/// - Parameter critical: The critical status of the work item which was enqueued and for which this is being called.
	private func processWorkItem(critical: Bool) {
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

				self.obtainAndExecuteWorkItem(critical: false)
			}
		}
	}

	/// Starts execution of a critical work item pursuant to concurrency limits.
	private func dispatchCriticalWorkItem() {
		criticalProcessingDispatchQueue.async {

			// Since the criticalProcessingWorkQueue is concurrent, limit the concurrent volume here.
			self.criticalProcessingDispatchQueueSemaphore.wait()

			self.criticalProcessingWorkQueue.async {
				self.workItemQueueDispatchQueue.sync {
					self.criticalProcessingActiveCount += 1
				}

				self.obtainAndExecuteWorkItem(critical: true)

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

	/// Retrieves WorkItem from the queue and immediately executes it.
	///
	/// - Parameter critical: True if for critical work, false otherwise.
	private func obtainAndExecuteWorkItem( critical:Bool ) {
		if let item = self.nextWorkItem( critical: critical ) {
			if let workItem = item.workItem {
				print("processWorkItem is \(workItem.uid) retain \(workItem.retainCount) pri \(workItem.priority)")
				if ( workItem.retainCount <= 0 )
				{
					print("skipped old")
					return
				}
			}

			self.executeWorkItem(item: item)
		}
	}

	/// Retreives the next Item from the workItemQueues.
	///
	/// - Parameter critical: True if for critical work, false otherwise.
	/// - Returns: Item to execute.
	private func nextWorkItem( critical: Bool ) -> LoaderItem? {
		var result:LoaderItem? = nil

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
								NSLog("Cancel unretained workItem \(item.uid)")
								item.workItem?.isCancelled = true
								item.workItem = nil // Clear the reference for now, but if we kept it we would be able to resume it later, so this could be revisited.
								workItemQueues[priority]!.remove(at: removeCount - 1)
								removeCount -= 1
							}
						}
					}
				}
			}

			NSLog("nextWorkItem is \(String(describing: result?.workItem?.uid))")
		}

		return result
	}

	/// Retrieves next result from WorkItem, stores it, and sets up next steps.
	///
	/// - Parameter item: The item to execute on.
	private func executeWorkItem( item: LoaderItem ) {
		if let workItem = item.workItem {
			NSLog("execute \(workItem.uid) at \(workItem.state)")
			if let result = workItem.next(thumbnailPixels: self.thumbnailPixels) {
				NSLog("execute good \(workItem.uid)")
				item.results[result.size.height] = result
				maxResultsVolumeBytes += result.cgImage!.height * result.cgImage!.bytesPerRow
				checkQuotas()

				if ( workItem.final ) {
					NSLog("Final workItem \(item.uid)")
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
				NSLog("nil workItem \(item.uid)")
				item.workItem = nil
			}
		}
	}


	// MARK: - Private Variables - Settings

	/// The last set concurrency limit, so we know how much to adjust by in what direction if a change is requested, since we can't query the semaphore for maximum value (since it doesn't even have a configurable maximum that it would allow us to put in).
	private var criticalProcessingConcurrencyLimit = 12

	
	// MARK: Private Variables - Storage

	/// The next value to use for uid.
	private var nextUID:Int = 0

	// All access to items and leastRecentlyUsed is thread-safe via itemsAccessQueue
	/// All items in the loader in any state.
	private var items:[DataIdentity:LoaderItem] = [:]
	/// The identities of the items in the loader, sorted in order of increasingly-recent use.
	private var leastRecentlyUsed:[DataIdentity] = []
	/// The GCD queue for all access to items and leastRecentlyUsed.
	private let itemsAccessQueue = DispatchQueue(label: "FastImageLoader.itemsAccessQueue")

	/// A pessimistic estimate of the volume of memory held by images in the loader.
	private var maxResultsVolumeBytes = 0


	// MARK: Private variables, queues, and semaphores - Execution

	/// The semaphore to limit the number of concurrent critical items executing.
	private let criticalProcessingDispatchQueueSemaphore = DispatchSemaphore(value: 0)

	/// The semaphore to block non-critical work when appropriate.
	private let noncriticalProcessingAllowedSemaphore = DispatchSemaphore(value: 1)

	/// The semaphore used in one place to make critical processing semi-concurrent and non-blocking.
	private let criticalProcessingDispatchQueue = DispatchQueue(label: "FastImageLoader.criticalProcessingDispatchQueue")

	/// The semaphore used in one place to make critical processing concurrent and non-blocking.
	private let criticalProcessingWorkQueue = DispatchQueue(label: "FastImageLoader.criticalProcessingQueue", qos: .userInitiated, attributes: .concurrent)

	/// The semaphore used in one place to make non-critical processing non-concurrent and non-blocking.
	private let processingQueue = DispatchQueue(label: "FastImageLoader.processingQueue")

	// All access to workItemQueues, workItemQueuesHasNoCritical, and criticalProcessingActiveCount is thread-safe via workItemQueueDispatchQueue
	/// The lists of items needing processing grouped by priority.
	private var workItemQueues:[Int:[LoaderItem]] = [:]
	/// A value representing the last-known state of if any critical items are in queue or in processing.
	private var workItemQueuesHasNoCritical = true
	/// The current number of critical items in processing.
	private var criticalProcessingActiveCount = 0
	/// The GCD queue for all access to workItemQueues, workItemQueuesHasNoCritical, and criticalProcessingActiveCount.
	private let workItemQueueDispatchQueue = DispatchQueue(label: "FastImageLoader.workItemQueueDispatchQueue")

	/// The GCD queue to ensure serialization of quota compliance work.
	private let quotaRecoveryDispatchQueue = DispatchQueue(label: "FastImageLoader.quotaRecoveryDispatchQueue")

}
