//
//  UIImageViewUpdater.swift
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

/// A notification mechanism that provides image updates from FastImageLoader to a UIImageView.
open class UIImageViewUpdater : FastImageLoaderNotification {
	/// Creates an updater object updating the provided imageView per the provided batch.
	///
	/// - Parameters:
	///   - imageView: The UIImageView to provide images to.
	///   - batch: The batch to group updates with if provided.
	public init(imageView: UIImageView, batch: FastImageLoaderBatch?) {
		self.imageView = imageView
		super.init(batch: batch)
	}

	/// The method called when an updated render has completed.
	///
	/// - Parameter image: The image resulting from the most recent render.
	override open func notify(image: UIImage) {
		print("notify")
		if ( Thread.isMainThread ) {
			self.updateImage(image: image)
		}
		else {
			DispatchQueue.main.async {
				self.updateImage(image: image)
			}
		}
	}

	/// Updates the image on imageView.
	///
	/// - Parameter image: The image to use.
	private func updateImage(image: UIImage) {
		print("update \(imageView.accessibilityHint) \(Date().timeIntervalSince1970)")
		imageView.image = image
	}

	/// The UIImageView this instance will update.
	private let imageView:UIImageView
}
