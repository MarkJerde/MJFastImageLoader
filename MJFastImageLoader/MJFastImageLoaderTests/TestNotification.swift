//
//  TestNotification.swift
//  MJFastImageLoaderTests
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
import MJFastImageLoader

/// A notification mechanism that provides image updates from FastImageLoader to a UIImageView.
open class TestNotification : FastImageLoaderNotification {
	// MARK: - Public Interfaces

	func setCompletion(completionHandler: @escaping () -> ()) {
		completion = completionHandler
	}

	/// Performs the notification.
	///
	/// - Note: It is unlikely that anyone outside MJFastImageLoader will call this method.  It is only given "open" access to allow it to be overridden in a subclass.
	///
	/// - Parameter image: The image that has been rendered.
	override open func notify(image: UIImage) {
		completion?()
		notificationDataSemaphore.wait()
		notificationCount += 1
		width = image.size.width
		height = image.size.height
		notificationWaiterSemaphore.signal()
		notificationDataSemaphore.signal()
	}

	func waitForNotify() -> ( Int, CGFloat, CGFloat ) {
		notificationWaiterSemaphore.wait()
		return ( notificationCount, width, height )
	}

	// MARK: - Private Variables and Execution

	private let notificationDataSemaphore = DispatchSemaphore(value: 1)
	private let notificationWaiterSemaphore = DispatchSemaphore(value: 0)
	private var notificationCount = 0
	private var width:CGFloat = 0.0
	private var height:CGFloat = 0.0
	private var completion:(() -> ())? = nil
}

