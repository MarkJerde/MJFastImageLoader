//
//  ViewController.swift
//  MJFastImageLoaderDemo
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
//                 This is a demonstration / test app which is not intended to be suitable for market.
// ^^^^^^^^^^^^^^^

import UIKit
import MJFastImageLoader

// MARK: Sequence Shuffle Extensions

extension MutableCollection where Indices.Iterator.Element == Index {
	/// Shuffles the contents of this collection.
	mutating func shuffle() {
		let c = count
		guard c > 1 else { return }

		for (firstUnshuffled , unshuffledCount) in zip(indices, stride(from: c, to: 1, by: -1)) {
			let d: IndexDistance = numericCast(arc4random_uniform(numericCast(unshuffledCount)))
			guard d != 0 else { continue }
			let i = index(firstUnshuffled, offsetBy: d)
			self.swapAt(firstUnshuffled, i)
		}
	}
}

extension Sequence {
	/// Returns an array with the contents of this sequence, shuffled.
	func shuffled() -> [Iterator.Element] {
		var result = Array(self)
		result.shuffle()
		return result
	}
}

// MARK: ViewController

class ViewController: UIViewController {

	@IBOutlet weak var imageView: UIImageView!
	@IBOutlet weak var imageView2: UIImageView!
	@IBOutlet weak var imageView3: UIImageView!
	@IBOutlet weak var imageView4: UIImageView!
	@IBOutlet weak var imageView5: UIImageView!
	@IBOutlet weak var imageView6: UIImageView!
	var imageViews:[UIImageView] = []

	@IBOutlet weak var statusLabel: UILabel!

	@IBOutlet weak var runButton: UIButton!
	@IBOutlet weak var stopButton: UIButton!
	@IBOutlet weak var stepButton: UIButton!

	var running = false
	var enabled = true
	var imageDatas:[Data] = []
	var imageDatasInUse:[Data?] = [nil,nil,nil,nil,nil,nil]
	var imageUpdaters:[UIImageUpdater?] = [nil,nil,nil,nil,nil,nil]
	var imageDataIndex = 0

	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.

		//Looks for single or multiple taps.
		let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.dismissKeyboard))

		//Uncomment the line below if you want the tap not not interfere and cancel other interactions.
		//tap.cancelsTouchesInView = false

		view.addGestureRecognizer(tap)

		imageViews = [imageView,
					  imageView2,
					  imageView3,
					  imageView4,
					  imageView5,
					  imageView6]

		runButton.isEnabled = false
		stepButton.isEnabled = false
		stopButton.isEnabled = false

		MJFastImageLoader.shared.setCriticalProcessingConcurrencyLimit(limit: 6)

		self.startTest()
	}

	//Calls this function when the tap is recognized.
	@objc func dismissKeyboard() {
		//Causes the view (or one of its embedded text fields) to resign the first responder status.
		view.endEditing(true)
	}

	let testQueue = DispatchQueue(label: "MJFastImageLoaderDemo.testQueue")


	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	public class UIImageUpdater : MJFastImageLoader.MJFastImageLoaderNotification {
		let imageView:UIImageView

		init(imageView: UIImageView, batch: MJFastImageLoader.MJFastImageLoaderBatch?) {
			self.imageView = imageView
			super.init(batch: batch)
		}

		override func notify(image: UIImage) {
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

		func updateImage(image: UIImage) {
			print("update \(self.imageView.accessibilityHint) \(Date().timeIntervalSince1970)")
			self.imageView.image = image
		}
	}

	// MARK: Buttons

	@IBAction func runAction(_ sender: Any) {
		running = true
		runButton.isEnabled = false
		stepButton.isEnabled = false
		stopButton.isEnabled = true
		step()
	}

	@IBAction func stopAction(_ sender: Any) {
		running = false
		runButton.isEnabled = true
		stepButton.isEnabled = true
		stopButton.isEnabled = false
	}

	@IBAction func stepAction(_ sender: Any) {
		runButton.isEnabled = true
		stepButton.isEnabled = true
		stopButton.isEnabled = false
		step()
	}

	@IBAction func switchAction(_ sender: UISwitch) {
		enabled = sender.isOn
	}

	@IBAction func changeThumbPx(_ sender: UITextField) {
		if let value = sender.text {
			MJFastImageLoader.shared.thumbnailPixels = Float(value)!
		}
	}

	// MARK: Test Execution

	func step() {
		// Clear the cache
		MJFastImageLoader.shared.flush()

		// Configure for simultaneous burst display of content
		MJFastImageLoader.MJFastImageLoaderBatch.shared.batchUpdateQuantityLimit = 6
		
		// Blank out all images
		imageViews.forEach({ (imageView) in
			self.imageView.accessibilityHint = String( describing: imageViews.index(of: imageView) )
			imageView.image = nil
			imageView.backgroundColor = UIColor.red
		})

		// Put an image into each in rapid succesion, with goal of having a good user experience
		testQueue.async {
			self.imageViews.forEach({ (imgView) in
				self.setNewImage(imgView: imgView)
			})
		}

		if ( running ) {
			// Start auto activity in three seconds
			self.testQueue.asyncAfter(deadline: .now() + .seconds(3), execute: {
				// Configure for rapid rolling display of content
				MJFastImageLoader.MJFastImageLoaderBatch.shared.batchUpdateQuantityLimit = 1

				self.autoRefresh()
			})
		}
	}

	func autoRefresh() {
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
			if ( 0 == self.imagesSet % 6 )
			{
				self.statusLabel.text = "Set \(self.imagesSet) Hit \(self.cacheHits) Waste \(MJFastImageLoader.wasteCount)"
			}
		})

		if ( running ) {
			// Select a random UIImageView and update it
			let random = false
			let randomImageView = random
				? imageViews.shuffled().first!
				: imageViews[imageDataIndex % imageViews.count]

			// Blank it out
			DispatchQueue.main.sync {
				randomImageView.image = nil
				randomImageView.backgroundColor = UIColor.orange
			}

			// Put a new image in
			setNewImage(imgView: randomImageView)

			// Do another one in 100ms
			testQueue.asyncAfter(deadline: .now() + .milliseconds(100), execute: {
				// Not infinite recursion, due to GCD.  Thank goodness.
				self.autoRefresh()
			})
		}
	}

	var imagesSet = 0
	var cacheHits = 0

	func setNewImage( imgView: UIImageView ) {
		imagesSet += 1
		print("set image \(imageViews.index(of: imgView)) from index \(imageDataIndex % imageDatas.count)")
		let imageIndex = imageViews.index(of: imgView)!
		if let updater = imageUpdaters[imageIndex] {
			updater.cancel()
		}
		if let data = imageDatasInUse[imageIndex] {
			MJFastImageLoader.shared.cancel(image: data)
		}
		let data = imageDatas[imageDataIndex % imageDatas.count]
		imageDataIndex += 1
		if ( enabled )
		{
			_ = MJFastImageLoader.shared.enqueue(image: data, priority: .critical)
			DispatchQueue.main.sync {
				print("do set image \(imageIndex) from index \(imageDatas.index(of: data))")
				let updater = UIImageUpdater(imageView: imgView, batch: MJFastImageLoader.MJFastImageLoaderBatch.shared)
				imageDatasInUse[imageIndex] = data
				imageUpdaters[imageIndex] = updater
				imgView.image = MJFastImageLoader.shared.image(image: data, notification: updater)
				if ( nil != imgView.image )
				{
					print("non nil image")
					cacheHits += 1
				}
			}
		}
		else
		{
			var approach = 1
			switch approach {
			case 1:
				// http://nshipster.com/image-resizing/
				if let image = UIImage(data: data) {
					var xformScale = CGFloat(1.0)

					DispatchQueue.main.sync {
						let xScale = CGFloat(imgView.frame.size.width) / image.size.width
						let yScale = CGFloat(imgView.frame.size.height) / image.size.height
						xformScale = xScale < yScale ? xScale : yScale
					}

					let size = image.size.applying(CGAffineTransform(scaleX: xformScale, y: xformScale))
					let hasAlpha = false
					let scale: CGFloat = 0.0 // Automatically use scale factor of main screen

					UIGraphicsBeginImageContextWithOptions(size, !hasAlpha, scale)
					image.draw(at: .zero)

					let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
					UIGraphicsEndImageContext()

					DispatchQueue.main.sync {
						imgView.image = scaledImage
					}
				}
				break

			default:
				DispatchQueue.main.sync {
					imgView.image = UIImage(data: data)
				}
				break
			}
		}
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
			guard let data = data, error == nil else { return }
			print(response?.suggestedFilename ?? url.lastPathComponent)
			print("Download Finished")
			self.imageDatas.append(data)
			/*DispatchQueue.main.sync {
				self.imageView.backgroundColor = UIColor.black
			}
			MJFastImageLoader.shared.enqueue(image: data, priority: .critical)
			DispatchQueue.main.sync {
				self.imageView.image = MJFastImageLoader.shared.image(image: data, notification: UIImageUpdater(imageView: self.imageView))
			}*/
		}
	}

	func startTest() {
		print("Begin of code")

		testQueue.async {
			let fileManager = FileManager.default
			let enumerator2:FileManager.DirectoryEnumerator = fileManager.enumerator(atPath: Bundle.main.resourceURL!.appendingPathComponent("TestImages").path)!
			while let element = enumerator2.nextObject() as? String {
				if ( element.hasSuffix(".jpg") ) {
					DispatchQueue.main.sync {
						self.statusLabel.text = "Loading image \(self.imageDatas.count + 1)..."
					}
					let data = NSData(contentsOfFile: Bundle.main.resourceURL!.appendingPathComponent("TestImages").appendingPathComponent(element).path)
					if let data = data as Data? {
						self.imageDatas.append(data)
					}
				}
			}

			if ( 0 == self.imageDatas.count ) {
				self.statusLabel.text = "Downloading images..."
				if let url = URL(string: "https://picsum.photos/5000/3000/?random") {
					self.imageViews.forEach({ (imgView) in
						imgView.contentMode = .scaleAspectFit
					})
					self.testQueue.async {
						let imageCount = 10
						for i in 1...imageCount {
							DispatchQueue.main.sync {
								self.statusLabel.text = "Downloading image (\(i) of \(imageCount))..."
							}
							self.downloadImage(url: url)
							while ( i > self.imageDatas.count )
							{
								// Normally a busy-wait would be undesirable, but for a demo to avoid smashing the source server this is good enough.
								sleep(1)
							}
						}
					}
				}
				print("End of code. The image will continue downloading in the background and it will be loaded when it ends.")
			}

			if ( self.imageDatas.count < MJFastImageLoader.shared.maximumCachedImages * 2 ) {
				// If we don't have enough images to kick things out of cache before we come back to them, set this flag to avoid using cache
				MJFastImageLoader.shared.ignoreCacheForTest = true
			}

			DispatchQueue.main.sync {
				self.statusLabel.text = "Ready"
				self.runButton.isEnabled = true
				self.stepButton.isEnabled = true
				self.stopButton.isEnabled = false
			}
		}
	}

}

