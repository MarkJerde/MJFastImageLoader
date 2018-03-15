//
//  FastImageLoaderBatch.swift
//  MJFastImageLoader
//
//  Created by Mark Jerde on 2/28/18.
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

/// A queueing mechanism to improve user experience by grouping up to N updates that occur within a time limit.
open class FastImageLoaderBatch {
	// MARK: - Public Instantiation and Settings

	// Allow a singleton, for those who prefer that pattern
	/// Returns the shared batch.
	public static let shared = FastImageLoaderBatch()

	/// The maximum number of notifications to enqueue before notifying.
	public var batchUpdateQuantityLimit:Int {
		get {
			return _batchUpdateQuantityLimit
		}
		set {
			let decrease = newValue < _batchUpdateQuantityLimit

			_batchUpdateQuantityLimit = newValue

			if decrease {
				// Only check quotas on decrease, since an increase won't result in there being too many existing items.
				checkQuotas()
			}
		}
	}

	/// The maximum number of seconds to delay any notification before notifying all queued notifications.
	public var batchUpdateTimeLimit = 0.2

	// MARK: - Private Variables and Execution

	/// The queued notifications.
	private var batchItems:[FastImageLoaderBatchItem] = []
	/// The GCD queue providing serialized accumulation.
	private let queue = DispatchQueue(label: "FastImageLoaderBatch.queue")
	/// The dispatch work item that will ensure the time limit.
	private var timeLimitWorkItem:DispatchWorkItem? = nil
	/// The maximum number of notifications to enqueue before notifying.
	private var _batchUpdateQuantityLimit = 1

	func queueNotifyEvent(image: UIImage, notification: FastImageLoaderNotification) {
		// TODO: This isn't blocking a UI thread, but it would still be good to evalute sync vs async for this method.
		queue.sync {
			// Check if we already have a pending image for that notification.
			if let item = batchItems.first(where: {$0.notification == notification}) {
				// We do, so update the image.
				item.image = image
			}
			else {
				// We don't, so add one and its image.
				batchItems.append(FastImageLoaderBatchItem(notification: notification,
														   image: image))
			}
		}

		checkQuotas()
	}

	/// Checks to see if notifications should be sent or if a timer should be set.
	func checkQuotas() {
		queue.sync {
			// Count how many non-cancelled notifications we have.  Ignore cancelled since nobody cares about them.
			var nonCancelledCount = 0
			for i in 0..<batchItems.count {
				if ( !batchItems[i].notification.cancelled ) {
					nonCancelledCount += 1
				}
			}

			if ( nonCancelledCount > 0 ) {
				// See what we should do.
				let first = 1 == nonCancelledCount
				let hitCountLimit = nonCancelledCount >= batchUpdateQuantityLimit
				if ( first ) {
					// In case the previous timer were still running for content that had all been cancelled.
					timeLimitWorkItem?.cancel()
					timeLimitWorkItem = nil
				}
				if ( first || hitCountLimit ) {
					let timeout:Double = hitCountLimit ? 0.0 : batchUpdateTimeLimit

					// Cancel the previous timeLimitWorkItem if there were one.
					timeLimitWorkItem?.cancel()

					// Create work item to do after timeout.
					timeLimitWorkItem = DispatchWorkItem {
						// Cancel the timeout, if there were one
						let timeLimitWorkItem = self.timeLimitWorkItem
						self.timeLimitWorkItem?.cancel()
						self.timeLimitWorkItem = nil

						if ( !hitCountLimit ) {
							let now = Date()
							if nil == self.batchItems.first(where: {!$0.notification.cancelled && $0.earliestTimestamp + self.batchUpdateTimeLimit <= now}) {
								// We did not find anything that was due at or before now and is not cancelled.  So nothing is actually due yet.  See if we can requeue or clear the list.

								if let item = self.batchItems.first(where: {!$0.notification.cancelled}) {
									// Requeue for updated timeout.
									let alreadyPassedTime = Date().timeIntervalSince(item.earliestTimestamp)
									self.timeLimitWorkItem = timeLimitWorkItem
									self.queue.asyncAfter(deadline: .now() + timeout - alreadyPassedTime, execute: timeLimitWorkItem!)

								}
								else {
									// Everything must be cancelled now, so just remove them and return.
									self.batchItems = []
									return
								}
							}
						}

						DLog("notify \(nonCancelledCount) for \(hitCountLimit ? "count" : "timeout")")

						// Do our queued work
						DispatchQueue.main.sync {
							// Use the main queue so that batches will draw as one.  Yes, this matters.
							self.batchItems.forEach({ (item) in
								if ( !item.notification.cancelled ) {
									item.notification.notify(image: item.image)								}
							})
						}
						self.batchItems = []
					}

					// Submit work item to be done.
					queue.asyncAfter(deadline: .now() + timeout, execute: timeLimitWorkItem!)
				}
			}
		}
	}
}

/// A simple collection of data to track notifications in the batch and what they are notified for.  Prevents having a multitude of arrays.
// TODO: Evaluate the benefits of class vs struct for this.
open class FastImageLoaderBatchItem {
	/// The notification this item is for.
	public let notification:FastImageLoaderNotification
	/// The latest image for this notification.  Could be updated if additional renders happen before batch completion.
	public var image:UIImage
	/// The date at which this item joined that batch.  Will not be changed by additional renders since the display may still show no image.
	public let earliestTimestamp:Date

	public init( notification:FastImageLoaderNotification,
				 image:UIImage ) {
		self.notification = notification
		self.image = image
		earliestTimestamp = Date()
	}
}
