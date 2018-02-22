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

	public static var wasteCount = 0

	// Allow instance use, for those who prefer that
	public init() {
		for _ in 1...criticalProcessingConcurrencyLimit {
			criticalProcessingDispatchQueueSemaphore.signal()
		}
	}

	// Priority level.  These could be arbitrary values, but the priority will be incremented one for each processing level, so a minimum separation of three is a good idea.
	public enum Priority: Int {
		case critical = 1
		case high = 5
		case medium = 10
		case low = 20
		case prospective = 100
	}

	// MARK: Public Properties - Settings

	// MARK: Public Methods - Settings

	public func setThumbnailPx( pixels: Int ) {
		thumbnailPixels = Float(pixels)
	}

	public func setMinimalCaching( value: Bool ) {
		minimalCaching = value
	}

	// MARK: Public Methods - Interaction

	public func enqueue(image: Data, priority: Priority) -> Int {
		var uid = -1
		var doProcess = true
		intakeQueue.sync {
			if nil != (minimalCaching ? nil : hintMap.index(forKey: image))
			{
				uid = hintMap[image]!
				if let workItem = workItems[uid]
				{
					workItem.retain()

					// Increase priority if needed
					if priority.rawValue < workItem.basePriority.rawValue {
						workItem.basePriority = priority
					}
				}
				else if ( nil != results[uid] )
				{
					// We have results but no work item, so we must be fully formed
					doProcess = false
				}
				else {
					print("error to have no workItem or result but have hint")
				}
			}
			else
			{
				uid = nextUID
				nextUID += 1
				hintMap[image] = uid

				let workItem = WorkItem(data: image, uid: uid, basePriority: priority)
				workItems[uid] = workItem
			}
		}
		if ( doProcess ) {
			let workItem = workItems[uid]!
			workItemQueueDispatchQueue.sync {
				if ( nil == workItemQueues[workItem.priority] ) {
					workItemQueues[workItem.priority] = []
				}
				workItemQueues[workItem.priority]!.append(workItem)
			}
			processWorkItem()
		}
		return uid
	}

	public func cancel(image: Data) {
		if let index = hintMap.index(forKey: image)
		{
			var uid = -1
			uid = hintMap[index].value
			uid = hintMap[image]!
			if let workItem = workItems[uid]
			{
				if ( !workItem.release() ) {

				}
			}
			else if ( nil == results[uid] )
			{
				print("bad things not old")
			}
		}
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
					workItem.retain() // For the notification
					notification.workItem = workItem
					print("registered \(uid)")
				}
			}
			return results[uid]
		}
		return nil
	}

	public func flush() {
		workItems = [:]
		results = [:]
		hintMap = [:]
	}

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
		}

		public static func == (lhs: MJFastImageLoaderNotification, rhs: MJFastImageLoaderNotification) -> Bool {
			return lhs === rhs
		}
	}

	open class MJFastImageLoaderBatch {
		public static let shared = MJFastImageLoaderBatch()

		open var batchUpdateQuantityLimit = 1
		public var batchUpdateTimeLimit = 0.1
		
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
					timeLimitWorkItem = DispatchWorkItem {
						// Cancel the timeout, if there were one
						self.timeLimitWorkItem?.cancel()
						self.timeLimitWorkItem = nil

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

	// MARK: Private Variables - Settings

	var thumbnailPixels:Float = 400.0
	var minimalCaching = false // To limit benefit for test / demo

	// MARK: Private Variables - Other

	let intakeQueue = DispatchQueue(label: "MJFastImageLoader.intakeQueue")
	var nextUID:Int = 0
	var workItems:[Int:WorkItem] = [:]
	var results:[Int:UIImage] = [:]
	var hintMap:[Data:Int] = [:]

	class WorkItem {
		init(data: Data, uid: Int, basePriority: Priority) {
			self.data = data
			self.uid = uid
			self.basePriority = basePriority
		}

		var priority: Int {
			// Only add state to decrease priority if we have rendered something already
			return basePriority.rawValue + ((nil == currentImage) ? 0 : state)
		}

		let data:Data
		let uid:Int
		var basePriority:Priority
		var state:Int = 0
		var currentImage:UIImage? = nil
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
					notify(notification: notification, image: result, previous: nil)
					return result
				}

				return next(thumbnailPixels: thumbnailPixels) // Immediately provide next image if we couldn't provide this one.

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
					if let resultImage = resultImage
					{
						notify(notification: notification, image: resultImage, previous: nil)
					}
					return resultImage
				}

				return nil

			default:
				return nil
			}
		}

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

	func processWorkItem() {
// fixme - wrap this all in a non-concurrent GCD queue
		if let item = nextWorkItem() {
			if ( item.retainCount <= 0 )
			{
				print("skipped old")
				return
			}
			if ( item.priority > 1 ) {
				processingQueue.async {
					self.executeWorkItem(item: item)
				}
			}
			else {
				criticalProcessingDispatchQueue.async {
					self.dispatchCriticalWorkItem(workItem: item)
				}
			}
		}
	}

	func dispatchCriticalWorkItem( workItem: WorkItem ) {
		// Since the criticalProcessingWorkQueue is concurrent, limit the concurrent volume here.
		criticalProcessingDispatchQueueSemaphore.wait()
		criticalProcessingWorkQueue.async {
			self.executeWorkItem(item: workItem)
			self.criticalProcessingDispatchQueueSemaphore.signal()
		}
	}

	func executeWorkItem( item: WorkItem ) {
		if let result = item.next(thumbnailPixels: self.thumbnailPixels) {
			print("next!")
			results[item.uid] = result
			processingQueue.async {
				/*print("sleep")
				sleep(10)
				print("slept")*/
				self.workItemQueueDispatchQueue.sync {
					if ( nil == self.workItemQueues[item.priority] ) {
						self.workItemQueues[item.priority] = []
					}
					self.workItemQueues[item.priority]?.append(item) // To process next level of image
				}
				self.processWorkItem()
			}
		}
		else {
			// nil result so it is done.  Remove from work items.
			workItems.removeValue(forKey: item.uid)
		}
	}

	func nextWorkItem() -> WorkItem? {
		var result:WorkItem? = nil

		workItemQueueDispatchQueue.sync {
			let priorities = workItemQueues.keys.sorted()

			outerLoop: for priority in priorities {
				if let queue = workItemQueues[priority] {
					var removeCount = 0
					for workItem in queue {
						removeCount += 1
						if ( workItem.retainCount > 0 ) {
							workItemQueues[priority]!.removeFirst(removeCount)
							result = workItem
							break outerLoop
						}
					}
				}
			}
		}

		return result
	}

	var criticalProcessingConcurrencyLimit = 12
	private let criticalProcessingDispatchQueueSemaphore = DispatchSemaphore(value: 0)
	let criticalProcessingDispatchQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingDispatchQueue")
	let criticalProcessingWorkQueue = DispatchQueue(label: "MJFastImageLoader.criticalProcessingQueue", qos: .userInitiated, attributes: .concurrent)
	let processingQueue = DispatchQueue(label: "MJFastImageLoader.processingQueue")
	var workItemQueues:[Int:[WorkItem]] = [:]
	let workItemQueueDispatchQueue = DispatchQueue(label: "MJFastImageLoader.workItemQueueDispatchQueue")

}
