//
//  DataIdentity.swift
//  MJFastImageLoader
//
//  Created by Mark Jerde on 3/6/18.
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

/// An object representation mechanism that uniquely describes an object without consuming much memory, providing Equatable and Hashable protocols.
class DataIdentity : Equatable, Hashable {
	// A simple mechanism to store a representation of a large object in a small space.
	// Uses the hash value of the original object, which has a risk of collision so it
	// stores a secondary hash of a subset of the original content providing 1-in-n-squared
	// probability of a incorrect equality.
	private(set) var hashValue: Int
	private var partialHash: Int

	/// Creates an identity item object describing the provided Data.
	///
	/// - Parameter data: The Data to describe.
	init(data: Data) {
		hashValue = data.hashValue

		// If the data is small, use all except the first byte for the secondary hash.  Otherwise use a middle-ish one tenth of the data.
		let short = data.count < 1000
		let partialStart = short ? 1 : (data.count / 10 * 5)
		let partialEnd = short ? data.count : (data.count / 10 * 6)
		partialHash = data.subdata(in: Range<Data.Index>(partialStart...partialEnd)).hashValue
	}

	static func ==(lhs: DataIdentity, rhs: DataIdentity) -> Bool {
		return lhs.hashValue == rhs.hashValue && lhs.partialHash == rhs.partialHash
	}
}
