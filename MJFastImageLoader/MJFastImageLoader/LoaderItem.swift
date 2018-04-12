//
//  LoaderItem.swift
//  MJFastImageLoader
//
//  Created by Mark Jerde on 3/6/18.
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

/// A tracking mechanism to store WorkItem and processed results for a given input, providing Equatable protocol.
class LoaderItem : Equatable {
	/// The WorkItem for the LoaderItem.
	var workItem:WorkItem? = nil

	/// The processed outputs for the LoaderItem.
	var results:[CGFloat:UIImage] = [:]

	/// The uid for the LoaderItem.
	private(set) var uid = -1

	/// The condition of being fully rendered at fullest resolution.
	var final = false

	/// The condition of having determined the input data contained no image.
	var dataWasCorrupt = false

	/// The WorkItem state to resume at if cancelled and resumed.
	var resumeState = 0

	/// Creates a loader item object initialized with the provided WorkItem.
	///
	/// - Parameter workItem: The WorkItem to use.
	init(workItem: WorkItem) {
		self.workItem = workItem
		uid = workItem.uid
	}

	/// Responds with the equality of two loader items.
	///
	/// - Parameters:
	///   - lhs: A loader item to check for equality.
	///   - rhs: A loader item to check for equality.
	/// - Returns: True if both are the same instance.  False if they are not the same instance even if their content is the same.
	static func ==(lhs: LoaderItem, rhs: LoaderItem) -> Bool {
		return lhs === rhs
	}
}
