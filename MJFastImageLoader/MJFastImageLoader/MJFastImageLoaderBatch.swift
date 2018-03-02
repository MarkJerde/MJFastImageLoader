//
//  MJFastImageLoaderBatch.swift
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

open class MJFastImageLoaderBatch {
	public static let shared = MJFastImageLoaderBatch()

	open var batchUpdateQuantityLimit = 1
	public var batchUpdateTimeLimit = 0.2

	private var notifications:[MJFastImageLoaderNotification] = []
	private var images:[UIImage] = []
	private let queue = DispatchQueue(label: "MJFastImageLoaderBatch.queue")
	private var timeLimitWorkItem:DispatchWorkItem? = nil

	func queueNotifyEvent(image: UIImage, notification: MJFastImageLoaderNotification) {
		queue.sync {
			if let index = notifications.index(of: notification) {
				images[index] = image
			}
			else {
				notifications.append(notification)
				images.append(image)
			}

			var nonCancelledCount = 0
			for i in 0..<notifications.count {
				if ( !notifications[i].cancelled ) {
					nonCancelledCount += 1
				}
			}

			let first = 1 == nonCancelledCount
			let hitQuota = nonCancelledCount >= batchUpdateQuantityLimit
			if ( first ) {
				// In case the previous timer were still running for content that had all been cancelled.
				timeLimitWorkItem?.cancel()
				timeLimitWorkItem = nil
			}
			if ( first || hitQuota ) {
				let timeout:Double = hitQuota ? 0.0 : batchUpdateTimeLimit
				//let timeout2:Int = hitQuota ? 0 : 5

				// Cancel the previous timeLimitWorkItem if there were one.
				timeLimitWorkItem?.cancel()

				timeLimitWorkItem = DispatchWorkItem {
					// Cancel the timeout, if there were one
					self.timeLimitWorkItem?.cancel()
					self.timeLimitWorkItem = nil

					NSLog("notify \(self.notifications.count) for \(hitQuota ? "quota" : "timeout")")

					// Do our work
					DispatchQueue.main.sync {
						// Use the main queue so that batches will draw as one.  Yes, this matters.
						for i in 0..<self.notifications.count {
							if ( !self.notifications[i].cancelled ) {
								self.notifications[i].notify(image: self.images[i])
							}
						}
					}
					self.notifications = []
					self.images = []
				}
				queue.asyncAfter(deadline: .now() + timeout, execute: timeLimitWorkItem!)
			}
		}
	}
}

