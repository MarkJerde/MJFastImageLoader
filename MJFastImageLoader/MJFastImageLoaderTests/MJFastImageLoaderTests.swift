//
//  MJFastImageLoaderTests.swift
//  MJFastImageLoaderTests
//
//  Created by Mark Jerde on 2/19/18.
//  Copyright © 2018 Mark Jerde. All rights reserved.
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
			let image = FastImageLoader.shared.image(image: imageData, notification: nil)
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
			let image = FastImageLoader.shared.image(image: imageData, notification: nil)
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
			let image = FastImageLoader.shared.image(image: imageData, notification: nil)
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
			let image = FastImageLoader.shared.image(image: imageData, notification: nil)
			XCTAssertNil(image, "Unexpected image data for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
		}

		FastImageLoaderTests.images[3...8].forEach { (imageData) in
			let image = FastImageLoader.shared.image(image: imageData, notification: nil)
			XCTAssertNotNil(image, "Missing image data for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			if let image = image {
				XCTAssertEqual(image.size.width, expectedWidth, "Expected width \(expectedWidth) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
				XCTAssertEqual(image.size.height, expectedHeight, "Expected height \(expectedHeight) but found \(image.size.width) for \(String(describing: FastImageLoaderTests.images.index(of: imageData))).")
			}
		}
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
