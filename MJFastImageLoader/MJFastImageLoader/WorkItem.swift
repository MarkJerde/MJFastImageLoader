//
//  WorkItem.swift
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

class WorkItem {
	init(data: Data, uid: Int, basePriority: MJFastImageLoader.Priority) {
		self.data = data
		self.uid = uid
		self.basePriority = basePriority
	}

	var priority: Int {
		// Only add state to decrease priority if we have rendered something already
		return basePriority.rawValue + (haveImage ? state : 0)
	}

	let data:Data
	let uid:Int
	var basePriority:MJFastImageLoader.Priority
	var isCancelled = false
	var isForcedOut = false
	var state:Int = 0
	var currentImage:UIImage? = nil
	var haveImage = false
	var notification:MJFastImageLoaderNotification? = nil

	public static let retainQueue = DispatchQueue(label: "MJFastImageLoader.workItemRetention")
	var retainCount = 1

	public func retain () {
		WorkItem.retainQueue.sync {
			self.retainCount += 1
		}
	}
	public func release () -> Bool {
		var nonZero = true
		WorkItem.retainQueue.sync {
			self.retainCount -= 1
			nonZero = self.retainCount > 0
		}
		return nonZero
	}

	public func next( thumbnailPixels: Float ) -> UIImage? {
		let thumbnailMaxPixels = thumbnailPixels
		let cgThumbnailMaxPixels = CGFloat(thumbnailPixels)

		print("state \(state)")
		switch state {
		case 0:
			// Fastest first.  Use thumbnail if present.
			state += 1

			let imageSource = CGImageSourceCreateWithData(data as CFData, nil)

			let options: CFDictionary = [
				kCGImageSourceShouldAllowFloat as String: true as NSNumber,
				kCGImageSourceCreateThumbnailWithTransform as String: true as NSNumber,
				kCGImageSourceCreateThumbnailFromImageIfAbsent as String: true as NSNumber,
				kCGImageSourceThumbnailMaxPixelSize as String: thumbnailMaxPixels as NSNumber
				] as CFDictionary

			if let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource!, 0, options)
			{
				let result = UIImage(cgImage: thumbnail)

				if ( result.size.width >= cgThumbnailMaxPixels
					|| result.size.height >= cgThumbnailMaxPixels )
				{
					state += 1
				}

				currentImage = result
				haveImage = true
				notify(notification: notification, image: result, previous: nil)
				return result
			}

			return next(thumbnailPixels: thumbnailPixels) // Immediately provide next image if we couldn't provide this one.

		case 1:
			// Generate better thumbnail if appropriate.
			state += 1

			let imageSource = CGImageSourceCreateWithData(data as CFData, nil)

			let options: CFDictionary = [
				kCGImageSourceShouldAllowFloat as String: true as NSNumber,
				kCGImageSourceCreateThumbnailWithTransform as String: true as NSNumber,
				kCGImageSourceCreateThumbnailFromImageAlways as String: true as NSNumber,
				kCGImageSourceThumbnailMaxPixelSize as String: thumbnailMaxPixels as NSNumber
				] as CFDictionary

			if let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource!, 0, options)
			{
				let result = UIImage(cgImage: thumbnail)
				currentImage = result
				haveImage = true
				notify(notification: notification, image: result, previous: nil)
				return result
			}

			return next(thumbnailPixels: thumbnailPixels) // Immediately provide next image if we couldn't provide this one.

		case 2:
			// Generate final image last.
			state += 1

			let previousImage = currentImage
			currentImage = nil // Since we won't need this after this stage.

			if let image = UIImage(data: data) {
				if ( image.size == previousImage?.size )
				{
					// Prior call produced full-size image, so stop now.
					return nil
				}

				UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
				image.draw(at: .zero)
				let resultImage = UIGraphicsGetImageFromCurrentImageContext()
				UIGraphicsEndImageContext()
				if let resultImage = resultImage
				{
					notify(notification: notification, image: resultImage, previous: nil)
				}
				if ( nil != resultImage ) {
					haveImage = true
				}
				final = true
				return resultImage
			}

			return nil

		default:
			return nil
		}
	}
	var final = false

	func notify(notification: MJFastImageLoaderNotification?, image: UIImage, previous: MJFastImageLoaderNotification?) {
		// Handle the linked list ourselves so it is not vulnerable to breakage by implementors of items in it
		if ( nil == notification && nil == previous )
		{
			print("old nobody cares")
			MJFastImageLoader.wasteCount += 1
		}
		if let notification = notification {
			if ( notification.cancelled ) {
				// Clear out cancelled item
				if let previous = previous {
					previous.next = notification.next
				}
				else {
					self.notification = notification.next
				}
			}
			else {
				notification.queueNotifyEvent(image: image)
			}

			// Notify next link in the list
			notify(notification: notification.next, image: image, previous: notification)
		}
	}
}

