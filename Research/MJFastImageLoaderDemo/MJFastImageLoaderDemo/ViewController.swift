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

class ViewController: UIViewController {

	@IBOutlet weak var imageView: UIImageView!
	
	override func viewDidLoad() {
		super.viewDidLoad()
		// Do any additional setup after loading the view, typically from a nib.


		self.startTest()
	}

	let testQueue = DispatchQueue(label: "MJFastImageLoaderDemo.testQueue")


	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	class UIImageUpdater : MJFastImageLoader.MJFastImageLoaderNotification {
		let imageView:UIImageView
		init(imageView: UIImageView) {
			self.imageView = imageView
			super.init()
		}

		override func notify(image: UIImage) {
			print("notify")
			DispatchQueue.main.async {
				print("update")
				self.imageView.image = image
			}
			super.notify(image: image)
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
			DispatchQueue.main.sync {
				self.imageView.backgroundColor = UIColor.black
			}
			MJFastImageLoader.shared.enqueue(image: data, priority: .critical)
			DispatchQueue.main.sync {
				self.imageView.image = MJFastImageLoader.shared.image(image: data, notification: UIImageUpdater(imageView: self.imageView))
			}
		}
	}

	func startTest() {
		print("Begin of code")
		if let url = URL(string: "https://picsum.photos/5000/3000") {
			imageView.contentMode = .scaleAspectFit
			testQueue.async {
				self.downloadImage(url: url)
			}
		}
		print("End of code. The image will continue downloading in the background and it will be loaded when it ends.")
	}

}

