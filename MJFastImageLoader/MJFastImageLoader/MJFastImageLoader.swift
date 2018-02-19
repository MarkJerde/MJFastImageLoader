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

	public func enqueue(image: Data, priority: Int) -> Int {
		var uid = -1
		intakeQueue.sync {
			uid = nextUID
			nextUID += 1
		}
		processWorkItem(item: WorkItem(data: image, uid: uid))
		return uid
	}

	// MARK: Private Variables

	let intakeQueue = DispatchQueue(label: "MJFastImageLoader.intakeQueue")
	var nextUID:Int = 0
	var results:[Int:UIImage] = [:]

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

		public func next() -> UIImage? {
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
			if let result = item?.next() {
				self.results[item!.uid] = result
				self.processingQueue.async {
					self.processWorkItem(item: item) // Task to process next level of image
				}
			}
		}
	}

	let processingQueue = DispatchQueue(label: "MJFastImageLoader.processingQueue")
	var workItems:[Int:[WorkItem]] = [:]
}
