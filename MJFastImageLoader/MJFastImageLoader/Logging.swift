//
//  Logging.swift
//  MJFastImageLoader
//
//  Created by Mark Jerde on 3/7/18.
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

// Adapted from https://gist.github.com/xmzio/fccd29fc945de7924b71

#if DEBUG
	func DLog(_ message: @autoclosure () -> String, filename: String = #file, function: String = #function, line: Int = #line) {
		NSLog("[\((filename as NSString).lastPathComponent):\(line)] \(function) - %@", message())
	}
#else
	func DLog(_ message:@autoclosure () -> String, filename: String = #file, function: String = #function, line: Int = #line) {
	}
#endif
func ALog(_ message: String, filename: String = #file, function: String = #function, line: Int = #line) {
	NSLog("[\((filename as NSString).lastPathComponent):\(line)] \(function) - %@", message)
}
