//
//  MJFastImageLoaderNotification.swift
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

open class MJFastImageLoaderNotification: Equatable {
	// Use a linked list because the most likely cases will be zero or one node, and multi-node won't involve searching.
	var next:MJFastImageLoaderNotification? = nil
	var cancelled = false
	var workItem:WorkItem? = nil
	private let batch:MJFastImageLoaderBatch?

	public init(batch: MJFastImageLoaderBatch?) {
		self.batch = batch
	}

	func queueNotifyEvent(image: UIImage) {
		if let batch = batch {
			batch.queueNotifyEvent(image: image, notification: self)
		}
		else {
			notify(image: image)
		}
	}

	open func notify(image: UIImage) {
	}

	open func cancel() {
		cancelled = true
		_ = workItem?.release() // for our retain
		workItem = nil
		// fixme - if release brings it down to zero it should be cleaned up in MJFastImageLoader
	}

	public static func == (lhs: MJFastImageLoaderNotification, rhs: MJFastImageLoaderNotification) -> Bool {
		return lhs === rhs
	}
}
