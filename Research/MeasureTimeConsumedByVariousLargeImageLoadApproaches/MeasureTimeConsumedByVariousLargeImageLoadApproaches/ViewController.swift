//
//  ViewController.swift
//  MeasureTimeConsumedByVariousLargeImageLoadApproaches
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

// ===============
// RESEARCH CODE - NOT TO HIGH STANDARD
//                 Intentionally runs on the main thread to ensure performance for data measurement
//                 Is not well tolerated by an actual iPhone running iOS 10, so data is from Simulator.
// ^^^^^^^^^^^^^^^

import UIKit

class ViewController: UIViewController {
	@IBOutlet weak var iterationLabel: UILabel!
	@IBOutlet weak var imageView: UIImageView!
	@IBOutlet weak var resultsLabel: UILabel!
	var nTestTimesRemaining = 4
	let iterationsPerTest = 100

	let burnInLoad = 10 // To simulate loading a queue of different images, load a different image a few times first.
	var needBurnInLoad = true
	var burnData:Data? = nil
	var testData:Data? = nil

	let approaches = [ "Direct", "Preprocess1", "Thumbnail", "Thumbnail2", "DrawInRect" ] // CILanczosScaleTransform

	var images:[UIImage] = []
	var datas:[Data] = []
	var timings:[Double] = []

	// MARK: Standard Overrides
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.

		startTest()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	// MARK: Image Download

	// Image capture adapted from: https://stackoverflow.com/questions/24231680/loading-downloading-image-from-url-on-swift

	func getDataFromUrl(url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> ()) {
		URLSession.shared.dataTask(with: url) { data, response, error in
			completion(data, response, error)
			}.resume()
	}

	func downloadImage(url: URL) {
		print("Download Started")
		getDataFromUrl(url: url) { data, response, error in
			guard var data = data, error == nil else { return }
			print(response?.suggestedFilename ?? url.lastPathComponent)
			print("Download Finished")
			DispatchQueue.main.async() {
				if ( !self.needBurnInLoad )
				{
					// If there were a file with the name found below in the bundle, it would load here.  Useful for injecting a specific file, such as one known to have a thumbnail or a different image format.
					do {
						data = try NSData(contentsOfFile: Bundle.main.resourceURL!.appendingPathComponent("Trumpet.png").path) as Data
					} catch { }
				}
				for _ in 1...(self.needBurnInLoad ? self.burnInLoad : self.iterationsPerTest) {
					self.images.append(UIImage(data: data)!)
					self.datas.append(data)
				}

				if ( self.needBurnInLoad )
				{
					self.burnData = data
					self.needBurnInLoad = false
					self.startTest()
				}
				else
				{
					self.testData = data
					self.approaches.forEach({ (approach) in
						// Clear old data to prepare for the test
						self.timings = []

						// Use a small delay to separate processing.
						//DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(4), execute: {
							var burnCount = self.images.count - self.iterationsPerTest
						var valid = true
						var index = -1
							self.images.forEach({ (image) in
								index += 1
								var resultImage:UIImage? = nil

								var start = Date()
								var end = Date()
								switch approach {
								case "Direct":
									// Is fast because processing never happens except for the final image and doesn't happen during our timer.
									start = Date()
									self.imageView.image = image
									if ( nil == image )
									{
										valid = false
									}
									end = Date()
									break;

								case "Preprocess1":
									start = Date()
									UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
									image.draw(at: .zero)
									resultImage = UIGraphicsGetImageFromCurrentImageContext()
									UIGraphicsEndImageContext()
									end = Date()
									break;

								case "Thumbnail":
									// Consumes ~13% time of Preprocess1 at 100px
									// Consumes ~55% time of Preprocess1 at 800px
									start = Date()

									let imageSource = CGImageSourceCreateWithData(((burnCount > 0) ? self.burnData : self.testData)! as CFData, nil)

									let options: CFDictionary = [
										kCGImageSourceShouldAllowFloat as String: true as NSNumber,
										kCGImageSourceCreateThumbnailWithTransform as String: true as NSNumber,
										kCGImageSourceCreateThumbnailFromImageAlways as String: true as NSNumber,
										kCGImageSourceThumbnailMaxPixelSize as String: 800 as NSNumber
										] as CFDictionary

									if let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource!, 0, options)
									{
										resultImage = UIImage(cgImage: thumbnail)
									}

									end = Date()
									break;

								case "Thumbnail2":
									// Equal to Thumbnail if there is no thumbnail in the file at 100px
									// Consumes ~3% time of Thumbnail if there is a thumbnail in the file at 100px
									// Equal to Thumbnail if there is no thumbnail in the file at 800px
									// Consumes ~1.3% time of Thumbnail if there is a thumbnail in the file at 800px
									// Will take thumbnail image even if lower resolution than target.
									start = Date()

									let imageSource = CGImageSourceCreateWithData(((burnCount > 0) ? self.burnData : self.testData)! as CFData, nil)

									let options: CFDictionary = [
										kCGImageSourceShouldAllowFloat as String: true as NSNumber,
										kCGImageSourceCreateThumbnailWithTransform as String: true as NSNumber,
										kCGImageSourceCreateThumbnailFromImageIfAbsent as String: true as NSNumber,
										kCGImageSourceThumbnailMaxPixelSize as String: 800 as NSNumber
										] as CFDictionary

									if let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource!, 0, options)
									{
										resultImage = UIImage(cgImage: thumbnail)
									}

									end = Date()
									break;

								case "CILanczosScaleTransform":
									let data = self.datas[index]
									start = Date()
									if let image = CIImage(data: data) {

										let filter = CIFilter(name: "CILanczosScaleTransform")!
										filter.setValue(image, forKey: "inputImage")
										filter.setValue(0.5, forKey: "inputScale")
										filter.setValue(1.0, forKey: "inputAspectRatio")
										let outputImage = filter.value(forKey: "outputImage") as! CIImage

										let context = CIContext(options: [kCIContextUseSoftwareRenderer: false])
										let scaledImage = UIImage(cgImage: context.createCGImage(outputImage, from: outputImage.extent)!)

										resultImage = scaledImage
									}
									end = Date()
									break;

								case "DrawInRect":
									start = Date()
									let size = image.size

									let widthRatio  = 800.0  / size.width
									let heightRatio = 800.0 / size.height

									// Figure out what our orientation is, and use that to form the rectangle
									var newSize: CGSize
									if(widthRatio > heightRatio) {
										newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
									} else {
										newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
									}

									// This is the rect that we've calculated out and this is what is actually used below
									let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)

									UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
									image.draw(in: rect)
									resultImage = UIGraphicsGetImageFromCurrentImageContext()
									UIGraphicsEndImageContext()
									end = Date()
									break;

								default:
									start = Date()
									end = Date()
									break;
								}

								if ( nil != resultImage )
								{
									//print("\(approach) Set image \(resultImage?.size.width) x \(resultImage?.size.height)")
									self.imageView.image = resultImage
									if ( nil == resultImage )
									{
										valid = false
									}
								}

								let milliseconds = (end.timeIntervalSince(start) * 1000);

								var prefix = "Took"
								if ( burnCount > 0 )
								{
									burnCount -= 1
									prefix = "Burn"
								}
								else
								{
									self.timings.append(milliseconds)
								}

								print("\(approach) \(prefix) \(milliseconds)")
							})
							print("Done")

						print("\(approach)\(valid ? "" : " INVALID") \(self.timings.count) Average \( self.timings.reduce(0, +) / Double(self.timings.count) )  Median \(self.timings.sorted()[self.iterationsPerTest/2])")
						//})
					})

					self.nTestTimesRemaining -= 1
					if ( self.nTestTimesRemaining > 0 )
					{
						self.startTest()
					}
				}
			}
		}
	}

	func startTest() {
		print("Begin of code")
		if let url = URL(string: "https://picsum.photos/4000/3000/?random") {
			imageView.contentMode = .scaleAspectFit
			downloadImage(url: url)
		}
		print("End of code. The image will continue downloading in the background and it will be loaded when it ends.")
	}
}

