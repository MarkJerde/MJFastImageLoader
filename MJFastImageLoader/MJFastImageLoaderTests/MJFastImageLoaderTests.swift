//
//  MJFastImageLoaderTests.swift
//  MJFastImageLoaderTests
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

import XCTest
@testable import MJFastImageLoader


// MARK: - Extensions

// Extension to create images for test, from https://stackoverflow.com/questions/26542035/create-uiimage-with-solid-color-in-swift

public extension UIImage {
	public convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
		let rect = CGRect(origin: .zero, size: size)
		UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
		color.setFill()
		UIRectFill(rect)
		let image = UIGraphicsGetImageFromCurrentImageContext()
		UIGraphicsEndImageContext()

		guard let cgImage = image?.cgImage else { return nil }
		self.init(cgImage: cgImage)
	}
}


// MARK: - Tests

class FastImageLoaderTests: XCTestCase {

	static var images:[Data] = []

	override class func setUp() {
		super.setUp()
		// Called once before all tests are run

		// Get some unique images to work with.
		[ UIColor.black,
		  UIColor.blue,
		  UIColor.brown,
		  UIColor.cyan,
		  UIColor.darkGray,
		  UIColor.green,
		  UIColor.magenta,
		  UIColor.lightGray,
		  UIColor.purple,
		  UIColor.red].forEach { (color) in
			// UIImageJPEGRepresentation document says that compression is 1.0 (least compression) to 0.0 (most compression) but this appears to be reversed.
			images.append( UIImageJPEGRepresentation(UIImage(color: color, size: CGSize(width: 3000,height: 4000))!, 0)! )
		}
	}
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.

		// Clear loader state.
		FastImageLoader.shared.flush()

        super.tearDown()
    }
    
    func testDataLoadingAndCacheLimits() {
        // This is a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.

		// Configure the loader
		FastImageLoader.shared.maximumCachedImages = 6
		FastImageLoader.shared.maximumCachedBytes = 2 * 1024 * 1024 * 1024

		// Load three images.
		FastImageLoaderTests.images[0...2].forEach { (imageData) in
			FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
		}

		FastImageLoader.shared.blockUntilAllWorkCompleted()

		// Verify that all are loaded.
		XCTAssertEqual(FastImageLoader.shared.count, 3, "Expected to have three items in the loader.")

		let scale = UIScreen.main.scale
		let expectedWidth = 3000 * scale
		let expectedHeight = 4000 * scale

		FastImageLoaderTests.images[0...2].forEach { (imageData) in
			let image = FastImageLoader.shared.image(image: imageData, notification: nil, notifyImmediateIfAvailable: false)
			XCTAssertNotNil(image, "Missing image data for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			if let image = image {
				XCTAssertEqual(image.size.width, expectedWidth, "Expected width \(expectedWidth) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
				XCTAssertEqual(image.size.height, expectedHeight, "Expected height \(expectedHeight) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			}
		}

		// Load three images, with only one being new.
		FastImageLoaderTests.images[1...3].forEach { (imageData) in
			FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
		}

		FastImageLoader.shared.blockUntilAllWorkCompleted()

		// Verify that all are loaded and the duplicates were detected.
		XCTAssertEqual(FastImageLoader.shared.count, 4, "Expected to have four items in the loader.")

		FastImageLoaderTests.images[0...3].forEach { (imageData) in
			let image = FastImageLoader.shared.image(image: imageData, notification: nil, notifyImmediateIfAvailable: false)
			XCTAssertNotNil(image, "Missing image data for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			if let image = image {
				XCTAssertEqual(image.size.width, expectedWidth, "Expected width \(expectedWidth) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
				XCTAssertEqual(image.size.height, expectedHeight, "Expected height \(expectedHeight) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			}
		}

		// Load two new images.
		FastImageLoaderTests.images[4...5].forEach { (imageData) in
			FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
		}

		FastImageLoader.shared.blockUntilAllWorkCompleted()

		// Verify that all are loaded.
		XCTAssertEqual(FastImageLoader.shared.count, 6, "Expected to have six items in the loader.")

		FastImageLoaderTests.images[0...5].forEach { (imageData) in
			let image = FastImageLoader.shared.image(image: imageData, notification: nil, notifyImmediateIfAvailable: false)
			XCTAssertNotNil(image, "Missing image data for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			if let image = image {
				XCTAssertEqual(image.size.width, expectedWidth, "Expected width \(expectedWidth) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
				XCTAssertEqual(image.size.height, expectedHeight, "Expected height \(expectedHeight) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			}
		}

		// Load three new images.
		FastImageLoaderTests.images[6...8].forEach { (imageData) in
			FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
		}

		FastImageLoader.shared.blockUntilAllWorkCompleted()

		// Verify that the quota was enforced.
		XCTAssertEqual(FastImageLoader.shared.count, 6, "Expected to have six items in the loader.")

		FastImageLoaderTests.images[0...2].forEach { (imageData) in
			let image = FastImageLoader.shared.image(image: imageData, notification: nil, notifyImmediateIfAvailable: false)
			XCTAssertNil(image, "Unexpected image data for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		}

		FastImageLoaderTests.images[3...8].forEach { (imageData) in
			let image = FastImageLoader.shared.image(image: imageData, notification: nil, notifyImmediateIfAvailable: false)
			XCTAssertNotNil(image, "Missing image data for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			if let image = image {
				XCTAssertEqual(image.size.width, expectedWidth, "Expected width \(expectedWidth) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
				XCTAssertEqual(image.size.height, expectedHeight, "Expected height \(expectedHeight) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			}
		}
	}

	func testNotificationsAndRenderSizes() {

		let scale = UIScreen.main.scale
		let expectedWidth = 3000 * scale
		let expectedHeight = 4000 * scale
		let expectedThumbnailWidth = CGFloat(300)
		let expectedThumbnailHeight = CGFloat(400)

		let imageData = FastImageLoaderTests.images[0]

		let notification = TestNotification(batch: nil)
		FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
		let cacheImage = FastImageLoader.shared.image(image: imageData, notification: notification, notifyImmediateIfAvailable: false)

		XCTAssertNil(cacheImage, "Expected nil cacheImage.")

		var ( count, width, height ) = notification.waitForNotify()

		XCTAssertEqual(count, 1, "Expected first notification.")
		XCTAssertEqual(width, expectedThumbnailWidth, "Expected width \(expectedThumbnailWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		XCTAssertEqual(height, expectedThumbnailHeight, "Expected height \(expectedThumbnailHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")

		( count, width, height ) = notification.waitForNotify()

		XCTAssertEqual(count, 2, "Expected second notification.")
		XCTAssertEqual(width, expectedWidth, "Expected width \(expectedWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		XCTAssertEqual(height, expectedHeight, "Expected height \(expectedHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
	}

	func testCancel() {

		let scale = UIScreen.main.scale
		let expectedWidth = 3000 * scale
		let expectedHeight = 4000 * scale
		let expectedThumbnailWidth = CGFloat(300)
		let expectedThumbnailHeight = CGFloat(400)

		let imageData = FastImageLoaderTests.images[0]

		let notification = TestNotification(batch: nil)
		notification.setCompletion {
			notification.cancel()
			FastImageLoader.shared.cancel(image: imageData)
		}
		FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
		let cacheImage = FastImageLoader.shared.image(image: imageData, notification: notification, notifyImmediateIfAvailable: false)

		XCTAssertNil(cacheImage, "Expected nil cacheImage.")

		var ( count, width, height ) = notification.waitForNotify()

		XCTAssertEqual(count, 1, "Expected first notification.")
		XCTAssertEqual(width, expectedThumbnailWidth, "Expected width \(expectedThumbnailWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		XCTAssertEqual(height, expectedThumbnailHeight, "Expected height \(expectedThumbnailHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")

		FastImageLoader.shared.blockUntilAllWorkCompleted()

		let finalImage = FastImageLoader.shared.image(image: imageData, notification: nil, notifyImmediateIfAvailable: false)

		XCTAssertNotNil(finalImage, "Expected not-nil cacheImage.")

		width = finalImage!.size.width
		height = finalImage!.size.height

		XCTAssertEqual(width, expectedThumbnailWidth, "Expected width \(expectedThumbnailWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		XCTAssertEqual(height, expectedThumbnailHeight, "Expected height \(expectedThumbnailHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
	}

	func testCancelAndRequeue() {

		let scale = UIScreen.main.scale
		let expectedWidth = 3000 * scale
		let expectedHeight = 4000 * scale
		let expectedThumbnailWidth = CGFloat(300)
		let expectedThumbnailHeight = CGFloat(400)

		let imageData = FastImageLoaderTests.images[0]

		let notification = TestNotification(batch: nil)
		notification.setCompletion {
			notification.cancel()
			FastImageLoader.shared.cancel(image: imageData)
		}
		FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
		var cacheImage = FastImageLoader.shared.image(image: imageData, notification: notification, notifyImmediateIfAvailable: false)

		XCTAssertNil(cacheImage, "Expected nil cacheImage.")

		var ( count, width, height ) = notification.waitForNotify()

		XCTAssertEqual(count, 1, "Expected first notification.")
		XCTAssertEqual(width, expectedThumbnailWidth, "Expected width \(expectedThumbnailWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		XCTAssertEqual(height, expectedThumbnailHeight, "Expected height \(expectedThumbnailHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")

		FastImageLoader.shared.blockUntilAllWorkCompleted()

		let finalImage = FastImageLoader.shared.image(image: imageData, notification: nil, notifyImmediateIfAvailable: false)

		XCTAssertNotNil(finalImage, "Expected not-nil finalImage.")

		width = finalImage!.size.width
		height = finalImage!.size.height

		XCTAssertEqual(width, expectedThumbnailWidth, "Expected width \(expectedThumbnailWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		XCTAssertEqual(height, expectedThumbnailHeight, "Expected height \(expectedThumbnailHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")

		let expect = expectation(description: "Expect to be notified of new render within one second.")

		DispatchQueue(label: "FastImageLoaderTest.asyncQueue").async {
			let notification2 = TestNotification(batch: nil)
			FastImageLoader.shared.enqueue(image: imageData, priority: .critical)
			cacheImage = FastImageLoader.shared.image(image: imageData, notification: notification2, notifyImmediateIfAvailable: false)

			XCTAssertNotNil(cacheImage, "Expected not-nil cacheImage.")

			width = cacheImage!.size.width
			height = cacheImage!.size.height

			XCTAssertEqual(width, expectedThumbnailWidth, "Expected width \(expectedThumbnailWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			XCTAssertEqual(height, expectedThumbnailHeight, "Expected height \(expectedThumbnailHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")

			( count, width, height ) = notification2.waitForNotify()

			expect.fulfill()

			XCTAssertEqual(count, 1, "Expected first notification.")
			XCTAssertEqual(width, expectedWidth, "Expected width \(expectedWidth) but found \(width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			XCTAssertEqual(height, expectedHeight, "Expected height \(expectedHeight) but found \(height) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		}

		waitForExpectations(timeout: 60) { (error) in
			if let error = error {
				XCTFail("Error: \(error.localizedDescription)")
			}
		}
	}

	func testDataIdentitySmallCount() {
		let smallImage = UIImageJPEGRepresentation(UIImage(color: UIColor.blue, size: CGSize(width: 30,height: 40))!, 0)!

		_ = DataIdentity(data: smallImage)
	}
    
    func testDataIdentityPerformance() {
        // This is an example of a performance test case.
		let image = FastImageLoaderTests.images[1]
        self.measure {
            // Put the code you want to measure the time of here.
			_ = DataIdentity(data: image)
        }
    }
    
}
