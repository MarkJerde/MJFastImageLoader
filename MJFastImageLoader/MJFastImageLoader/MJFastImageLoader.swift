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

	// Allow instance use, for those who prefer that
	public init() {
	}

	public enum Priority: Int {
		case critical = 1
		case high = 5
		case medium = 10
		case low = 20
		case prospective = 100
	}

	// MARK: Public Methods

	public func enqueue(image: Data, priority: Priority) -> Int {
		var uid = -1
		intakeQueue.sync {
			uid = nextUID
			nextUID += 1
			hintMap[image] = uid
		}
		processWorkItem(item: WorkItem(data: image, uid: uid))
		return uid
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
					print("registered \(uid)")
				}
			}
			return results[uid]
		}
		return nil
	}

	open class MJFastImageLoaderNotification {
		// Use a linked list because the most likely cases will be zero or one node, and multi-node won't involve searching.
		var next:MJFastImageLoaderNotification? = nil

		public init() {
		}

		open func notify(image: UIImage) {
			next?.notify(image: image)
		}
	}

	// MARK: Private Variables

	let intakeQueue = DispatchQueue(label: "MJFastImageLoader.intakeQueue")
	var nextUID:Int = 0
	var workItems:[Int:WorkItem] = [:]
	var results:[Int:UIImage] = [:]
	var hintMap:[Data:Int] = [:]

	class WorkItem {
		init(data: Data, uid: Int) {
			self.data = data
			self.uid = uid
		}

		let data:Data
		let uid:Int
		var state:Int = 0
		let thumbnailMaxPixels = 400.0
		let cgThumbnailMaxPixels = CGFloat(400)
		var currentImage:UIImage? = nil
		var notification:MJFastImageLoaderNotification? = nil

		public func next() -> UIImage? {
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
					notification?.notify(image: result)
					return result
				}

				return next() // Immediately provide next image if we couldn't provide this one.

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
					notification?.notify(image: result)
					return result
				}

				return next() // Immediately provide next image if we couldn't provide this one.

			case 2:
				// Generate final image last.
				state += 1

				if let image = UIImage(data: data) {
					if ( image.size == currentImage?.size )
					{
						// Prior call produced full-size image, so stop now.
						currentImage = nil
						return nil
					}

					UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
					image.draw(at: .zero)
					let resultImage = UIGraphicsGetImageFromCurrentImageContext()
					UIGraphicsEndImageContext()
					currentImage = nil
					if ( nil != resultImage )
					{
						notification?.notify(image: resultImage!)
					}
					return resultImage
				}

				return nil

			default:
				return nil
			}
		}
	}

	func processWorkItem(item: WorkItem?) {
		processingQueue.async {
			if let item = item {
				self.workItems[item.uid] = item
				if let result = item.next() {
					print("next!")
					self.results[item.uid] = result
					self.processingQueue.async {
						/*print("sleep")
						sleep(10)
						print("slept")*/
						self.processWorkItem(item: item) // Task to process next level of image
					}
				}
				else {
					// nil result so it is done.  Remove from work items.
					self.workItems.removeValue(forKey: item.uid)
				}
			}
		}
	}

	let processingQueue = DispatchQueue(label: "MJFastImageLoader.processingQueue")
	var workItemQueues:[Int:[WorkItem]] = [:]
}
