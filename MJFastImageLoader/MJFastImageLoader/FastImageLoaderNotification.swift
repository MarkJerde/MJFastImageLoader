//
//  FastImageLoaderNotification.swift
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

open class FastImageLoaderNotification: Equatable {
	// Use a linked list because the most likely cases will be zero or one node, and multi-node won't involve searching.
	/// The notification following this one.
	var next:FastImageLoaderNotification? = nil
	/// The state of having been cancelled.
	var cancelled = false
	/// The work item which should be informed if this notification is cancelled.
	var workItem:WorkItem? = nil
	/// The batch this notification is part of.
	private let batch:FastImageLoaderBatch?

	/// Creates a notification coordinating with the provided batch.
	///
	/// - Parameter batch: The batch to coordinate with if desired.
	public init(batch: FastImageLoaderBatch?) {
		self.batch = batch
	}

	/// Adds the provided image to the batch and / or provides notification immediately.
	///
	/// - Parameter image: The image to notify with.
	func queueNotifyEvent(image: UIImage) {
		if let batch = batch {
			batch.queueNotifyEvent(image: image, notification: self)
		}
		else {
			notify(image: image)
		}
	}

	/// Performs the notification.
	///
	/// - Parameter image: The image that has been rendered.
	open func notify(image: UIImage) {
	}

	open func cancel() {
		cancelled = true
		_ = workItem?.release() // for our retain
		workItem = nil
		// TODO: If workItem?.release() brings the WorkItem's interest down to zero the WorkItem should be cleaned up in FastImageLoader.
	}

	/// Responds with the equality of two notifications.
	///
	/// - Parameters:
	///   - lhs: A notification to check for equality.
	///   - rhs: A notification to check for equality.
	/// - Returns: True if both are the same instance.  False if they are not the same instance even if their content is the same.
	public static func == (lhs: FastImageLoaderNotification, rhs: FastImageLoaderNotification) -> Bool {
		return lhs === rhs
	}
}
