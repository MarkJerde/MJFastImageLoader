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

extension MutableCollection {
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
	var failed = false
	var failStatusLock = false
	var enabled = true
	var runTooFastToKeepUp = false
	var imageDatas:[Data] = []
	var imageDatasInUse:[Data?] = [nil,nil,nil,nil,nil,nil]
	var imageUpdaters:[UIImageViewUpdater?] = [nil,nil,nil,nil,nil,nil]
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

		FastImageLoader.shared.setCriticalProcessingConcurrencyLimit(limit: ProcessInfo.processInfo.activeProcessorCount)

		reportMemoryTimer = Timer.scheduledTimer(timeInterval: 0.1,
												 target: self,
												 selector: #selector(self.reportMemory),
												 userInfo: nil,
												 repeats: true)

		self.startTest()
	}

	var reportMemoryTimer = Timer()
	@objc func reportMemory() {
		var info = mach_task_basic_info()
		var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
		
		let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
			$0.withMemoryRebound(to: integer_t.self, capacity: 1) {
				task_info(mach_task_self_,
						  task_flavor_t(MACH_TASK_BASIC_INFO),
						  $0,
						  &count)
			}
		}

		if kerr == KERN_SUCCESS {
			NSLog("MEM_REPORT \(info.resident_size) bytes")
		}
	}

	//Calls this function when the tap is recognized.
	@objc func dismissKeyboard() {
		//Causes the view (or one of its embedded text fields) to resign the first responder status.
		view.endEditing(true)
	}

	let testQueue = DispatchQueue(label: "FastImageLoaderDemo.testQueue")


	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
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

	@IBAction func enableAction(_ sender: UISwitch) {
		enabled = sender.isOn
	}

	@IBAction func tooFastAction(_ sender: UISwitch) {
		runTooFastToKeepUp = sender.isOn
	}

	@IBAction func changeThumbPx(_ sender: UITextField) {
		if let value = sender.text {
			FastImageLoader.shared.thumbnailPixels = Float(value)!
		}
	}

	var disabledModeApproach = 0
	@IBAction func changeDisabledApproach(_ sender: UITextField) {
		if let value = sender.text {
			disabledModeApproach = Int(value)!
		}
	}


	// MARK: Test Execution

	func step() {
		// Clear data
		imagesSet = 0
		cacheHits = 0
		FastImageLoader.wasteCount = 0
		failed = false

		// Clear the cache
		FastImageLoader.shared.flush()

		// Configure for simultaneous burst display of content
		FastImageLoaderBatch.shared.batchUpdateQuantityLimit = 6

		// Blank out all images
		imageViews.forEach({ (imageView) in
			imageView.accessibilityHint = String( describing: imageViews.index(of: imageView) )
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
				FastImageLoaderBatch.shared.batchUpdateQuantityLimit = 1

				self.autoRefresh()
			})
		}
	}

	func setStatus( force:Bool ) {
		var status:String? = nil

		if ( force || 0 == self.imagesSet % 6 ) {
			if ( failed ) {
				if ( !failStatusLock ) {
					status = "Failed with Set \(imagesSet) Hit \(cacheHits) Waste \(FastImageLoader.wasteCount)"
					failStatusLock = true
				}
			}
			else {
				status = "Set \(imagesSet) Hit \(cacheHits) Waste \(FastImageLoader.wasteCount)"
				failStatusLock = false
			}
		}

		if let status = status {
			DispatchQueue.main.async {
				self.statusLabel.text = status
			}
		}
	}

	var random = false

	var nextViewIndex = 0
	func autoRefresh() {
		DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
			self.setStatus( force: false )
		})

		if ( running ) {
			// Select a random UIImageView and update it
			let randomImageView = random
				? imageViews.shuffled().first!
				: imageViews[nextViewIndex % imageViews.count]
			nextViewIndex += 1

			NSLog("Update \(String(describing: randomImageView.accessibilityHint))")

			// Do another one in 100ms, even if we haven't finished this one
			testQueue.asyncAfter(deadline: .now() + .milliseconds(100), execute: {
				// Not infinite recursion, due to GCD.  Thank goodness.
				self.autoRefresh()
			})

			// Blank it out
			doFastSlowMainQueue(item: DispatchWorkItem {
				DispatchQueue.main.sync {
					if ( self.runTooFastToKeepUp && nil == randomImageView.image ) {
						// If we caught our own tail, just stop.
						self.running = false
						self.failed = true
						self.stopAction(self)
						self.setStatus( force: true )
						return
					}

					let imgView = randomImageView
					let imageIndex = self.imageViews.index(of: imgView)!
					if let updater = self.imageUpdaters[imageIndex] {
						updater.cancel()
						self.imageUpdaters[imageIndex] = nil
					}
					if let data = self.imageDatasInUse[imageIndex] {
						FastImageLoader.shared.cancel(image: data)
						self.imageDatasInUse[imageIndex] = nil
					}

					randomImageView.image = nil
					randomImageView.backgroundColor = UIColor.orange
				}
				NSLog("Update blank  \(String(describing: randomImageView.accessibilityHint))")
			}, fast: true)

			// Put a new image in
			doFastSlowMainQueue(item: DispatchWorkItem {
				self.setNewImage(imgView: randomImageView)
				NSLog("Update done  \(String(describing: randomImageView.accessibilityHint))")
			}, fast: false)
		}
	}

	// fastSlowMainQueue is a mechanism to prioritize quick operations in bursts between slow operations.
	var mainQueueFastItems:[DispatchWorkItem] = []
	var mainQueueSlowItems:[DispatchWorkItem] = []
	let fastSlowMainListQueue = DispatchQueue(label: "FastImageLoaderDemo.fastSlowMainListQueue")
	let fastSlowMainExecQueue = DispatchQueue(label: "FastImageLoaderDemo.fastSlowMainExecQueue")
	func doFastSlowMainQueue( item: DispatchWorkItem, fast: Bool ) {
		if ( !runTooFastToKeepUp ) {
			item.perform()
			return
		}
		fastSlowMainListQueue.async {
			if ( fast ) {
				self.mainQueueFastItems.append(item)
			}
			else {
				self.mainQueueSlowItems.append(item)
			}
		}
		fastSlowMainExecQueue.async {
			var item:DispatchWorkItem? = nil
			self.fastSlowMainListQueue.sync {
				if let workItem = self.mainQueueFastItems.first {
					item = workItem
					self.mainQueueFastItems.remove(at: 0)
				}
				else if let workItem = self.mainQueueSlowItems.first {
					item = workItem
					self.mainQueueSlowItems.remove(at: 0)
				}
			}
			item?.perform()
		}
	}


	var imagesSet = 0
	var cacheHits = 0

	func setNewImage( imgView: UIImageView ) {
		imagesSet += 1
		print("set image \(String(describing: imageViews.index(of: imgView))) from index \(imageDataIndex % imageDatas.count)")
		let imageIndex = imageViews.index(of: imgView)!
		if let updater = imageUpdaters[imageIndex] {
			updater.cancel()
			imageUpdaters[imageIndex] = nil
		}
		if let data = imageDatasInUse[imageIndex] {
			FastImageLoader.shared.cancel(image: data)
			imageDatasInUse[imageIndex] = nil
		}
		let data = imageDatas[imageDataIndex % imageDatas.count]
		imageDataIndex += 1
		if ( enabled ) {
			FastImageLoader.shared.enqueue(image: data, priority: .critical)
			DispatchQueue.main.sync {
				print("do set image \(imageIndex) from index \(String(describing: imageDatas.index(of: data)))")
				let updater = UIImageViewUpdater(imageView: imgView, batch: FastImageLoaderBatch.shared)
				imageDatasInUse[imageIndex] = data
				imageUpdaters[imageIndex] = updater
				imgView.image = FastImageLoader.shared.image(image: data, notification: updater)
				if ( nil != imgView.image ) {
					print("non nil image")
					cacheHits += 1
				}
			}
		}
		else {
			switch disabledModeApproach {
			case 1:
				// http://nshipster.com/image-resizing/
				if let image = CIImage(data: data) {

					let filter = CIFilter(name: "CILanczosScaleTransform")!
					filter.setValue(image, forKey: "inputImage")
					filter.setValue(0.5, forKey: "inputScale")
					filter.setValue(1.0, forKey: "inputAspectRatio")
					let outputImage = filter.value(forKey: "outputImage") as! CIImage

					let context = CIContext(options: [kCIContextUseSoftwareRenderer: false])
					let scaledImage = UIImage(cgImage: context.createCGImage(outputImage, from: outputImage.extent)!)

					DispatchQueue.main.sync {
						imgView.image = scaledImage
					}
				}
				break

			case 2:
				// http://nshipster.com/image-resizing/
				if let image = CGImageSourceCreateWithData(data as CFData, nil) {

					var maxy:CGFloat = 1.0
					DispatchQueue.main.sync {
						// Mutiply by four for super-retina, I think.
						maxy = max( imgView.frame.size.width * 4, imgView.frame.size.height * 4)
					}

					let options: [NSString: NSObject] = [
						kCGImageSourceThumbnailMaxPixelSize: maxy as NSNumber,
						kCGImageSourceCreateThumbnailFromImageAlways: true as NSNumber
					]

					let scaledImage = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary).flatMap { UIImage(cgImage: $0) }


					DispatchQueue.main.sync {
						imgView.image = scaledImage
					}
				}
				break

			case 3:
				// http://nshipster.com/image-resizing/
				if let image = CGImageSourceCreateWithData(data as CFData, nil) {

					var maxy:CGFloat = 1.0
					DispatchQueue.main.sync {
						maxy = max( imgView.frame.size.width * 4, imgView.frame.size.height * 4)
					}

					let options: [NSString: NSObject] = [
					kCGImageSourceThumbnailMaxPixelSize: maxy as NSNumber,
					kCGImageSourceCreateThumbnailFromImageAlways: true as NSNumber
					]

					let scaledImage = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary).flatMap { UIImage(cgImage: $0) }


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
			FastImageLoader.shared.enqueue(image: data, priority: .critical)
			DispatchQueue.main.sync {
				self.imageView.image = FastImageLoader.shared.image(image: data, notification: UIImageViewUpdater(imageView: self.imageView))
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
							while ( i > self.imageDatas.count ) {
								// Normally a busy-wait would be undesirable, but for a demo to avoid smashing the source server this is good enough.
								sleep(1)
							}
						}
					}
				}
				print("End of code. The image will continue downloading in the background and it will be loaded when it ends.")
			}

			if ( self.imageDatas.count < FastImageLoader.shared.maximumCachedImages * 2
				&& self.imageDatas.count < FastImageLoader.shared.maximumCachedBytes * 2 / 60000000 ) {
				// If we don't have enough images to kick things out of cache before we come back to them, set this flag to avoid using cache.  I'm testing with images that use up to 60 MB of RAM, so use that to estimate potential memory load per cache quota.
				FastImageLoader.shared.ignoreCacheForTest = true
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

