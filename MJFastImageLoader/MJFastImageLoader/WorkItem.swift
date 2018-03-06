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

/// A tracking mechanism to store data to be processed, processing priority, and processing state.
class WorkItem : Equatable {
	/// Creates a work item object initialized with the provided data, uid, and priority.
	///
	/// - Parameters:
	///   - data: The data to processs.
	///   - uid: The uid of this data to process.
	///   - basePriority: The priority at which it should be processed.
	init(data: Data, uid: Int, basePriority: FastImageLoader.Priority) {
		self.data = data
		self.uid = uid
		self.basePriority = basePriority

		// Fix any defect in priority being lower than minimum, critical being lowest numbered.
		if ( Decimal(self.basePriority.rawValue) < Decimal(FastImageLoader.Priority.critical.rawValue) ) {
			self.basePriority = .critical
		}
	}

	/// The current priority of the work item, which decays as each render completes.
	var priority: Int {
		// Only add state to decrease priority if we have rendered something already.
		// Multiply priority by three to provide separation for state, retaining the 1 is the lowest possible (most critical) value.
		return ((basePriority.rawValue - 1) * 3 + 1) + (haveImage ? state : 0)
	}

	/// The base priority to work from.
	var basePriority:FastImageLoader.Priority
	/// The uid of the data.
	let uid:Int
	/// The state of cancellation.
	var isCancelled = false
	/// The state of having been forced out by quota limits.
	var isForcedOut = false
	/// The notification(s) to inform when renders complete.
	var notification:FastImageLoaderNotification? = nil
	/// The most recent rendering.
	var currentImage:UIImage? = nil

	/// The current state.
	private(set) var state:Int = 0
	/// The state of having completed the final possible render (full resolution).
	private(set) var final = false
	
	/// The data to process.
	private let data:Data
	/// The state of having already rendered at least one image.
	private var haveImage = false


	// MARK: Counting interested parties

	/// The GCD queue to provide thread-safe access to interest retention.
	private static let retainQueue = DispatchQueue(label: "FastImageLoader.workItemRetention")
	/// The current number of interested parties.
	var retainCount = 1

	/// Indicates that there is an additional party interested in the results of this work.
	func retain () {
		WorkItem.retainQueue.sync {
			self.retainCount += 1
		}
	}
	/// Indicates that their is one fewer party interested in the results of this work.
	///
	/// - Returns: True if there are still interested parties, false otherwise.
	func release () -> Bool {
		var nonZero = true
		WorkItem.retainQueue.sync {
			self.retainCount -= 1
			nonZero = self.retainCount > 0
		}
		return nonZero
	}


	// MARK: Execute work

	/// Renders the next-higher-resolution version of the image.
	///
	/// - Parameter thumbnailPixels: Maximum height or width of initial version in pixels.
	/// - Returns: The image rendered.
	func next( thumbnailPixels: Float ) -> UIImage? {
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
				//let result = UIImage(cgImage: thumbnail)
				let result = TrackedUIImage(cgImage: thumbnail)
				result.uid = self.uid
				result.thumb = true

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
				let resultImageA = UIGraphicsGetImageFromCurrentImageContext()
				let resultImage = (nil == resultImageA) ? nil : TrackedUIImage(cgImage: resultImageA!.cgImage!)
				UIGraphicsEndImageContext()
				resultImage?.uid = self.uid
				resultImage?.thumb = false

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

	/// Notifies any registered notifications that a new render has been produced.
	///
	/// - Parameters:
	///   - notification: The notification to start with.
	///   - image: The image that has been rendered.
	///   - previous: The previous notification in the linked list.
	private func notify(notification: FastImageLoaderNotification?, image: UIImage, previous: FastImageLoaderNotification?) {
		// Handle the linked list ourselves so it is not vulnerable to breakage by implementors of items in it
		if ( nil == notification && nil == previous )
		{
			print("old nobody cares")
			FastImageLoader.wasteCount += 1
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

	/// Responds with the equality of two work items.
	///
	/// - Parameters:
	///   - lhs: A work item to check for equality.
	///   - rhs: A work item to check for equality.
	/// - Returns: True if both are the same instance.  False if they are not the same instance even if their content is the same.
	public static func == (lhs: WorkItem, rhs: WorkItem) -> Bool {
		return lhs === rhs
	}

	
	// MARK: Diagnostic mechanisms

	// Debug / diagnostic class which can be used in place of UIImage to provide QoS data for memory recovery.
	// This was created to aid in identifying a pseudo-memory-leak which could have been caused by excess references but which turned out to be a side-effect of GCD being kept 100% busy.  Provides NSLog reporting intended and actual time of deinit and milliseconds delta between them.
	/// A diagnostic mechanism to provide a UIImage that monitors the timeliness of its removal from memory.
	class TrackedUIImage : UIImage {
		// Details the user can set if they see need.
		/// The state of being a thumbnail version rather than final render.
		var thumb = false
		/// The uid of the data this was rendered for.
		var uid = 0

		/// The time at which shouldDeinitSoon was called.
		private var deinitTime:Date? = nil

		/// Informs the object that we expect deinit to be called shortly, so that it can give a time delta between intention and action.
		///
		/// - Parameters:
		///   - bool1: An arbitrary bool for logging of data from caller.
		///   - bool2: Another arbitrary bool for logging of data from caller.
		public func shouldDeinitSoon(bool1:Bool, bool2:Bool) {
			log(event: "want to deinit", extra: "\(bool1) \(bool2) ")
			deinitTime = Date()
		}

		/// Calculates bytes estimate and NSLogs some info.
		///
		/// - Parameters:
		///   - event: Description of what event is happening.
		///   - extra: Extra description of state to include.
		private func log(event:String, extra:String) {
			let bytesThis = cgImage!.height * cgImage!.bytesPerRow
			NSLog("TrackedUIImage \(event) \(uid) \(thumb ? "thumb" : "final") \(Unmanaged.passUnretained(self).toOpaque()) \(extra)for \(bytesThis) bytes")
		}

		// Report some identifying information and the delta in milliseconds since intention to deinit.
		deinit {
			let late = Date().timeIntervalSince(deinitTime ?? Date())
			log(event: "deinit", extra: "\(late * 1000) ms late ")
		}
	}
}

