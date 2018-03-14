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
	// It was observed that it is common for Data objects of equal size to have the same
	// hash value, so a tertiary hash is also performed.
	private(set) var hashValue: Int
	private(set) var partialHash1: Int
	private(set) var partialHash2: Int

	/// Creates an identity item object describing the provided Data.
	///
	/// - Parameter data: The Data to describe.
	init(data: Data) {
		hashValue = data.hashValue

		// If the data is small, use all except the first byte for the secondary hash.  Otherwise use a middle-ish one tenth of the data.
		let maximumSampleSize = 3200
		let short = data.count < maximumSampleSize
		let partial1Start = short ? 1 : (data.count / 100 * 50)
		var partial1End = short ? (data.count - 1) : (data.count / 100 * 51)
		if ( partial1End - partial1Start > maximumSampleSize ) {
			partial1End = partial1Start + maximumSampleSize - 1
		}
		partialHash1 = 0
		// Iterate over the bytes since we already know that .hashValue doesn't do unique so well.
		for i in partial1Start...partial1End {
			// Is there a better way to do this?  Unsafe pointers may provide a good solution that works in larger chunks.
			//let was = partialHash1
			var part = data[i]
			if ( 0 == i % 3 ) {
				// Salt every third with the index.  This because repeating patterns can cause the hash to self-clear otherwise.
				part ^= UInt8(i % 0xFF)
			}
			let shifter = ((i % 8) * 8)
			partialHash1 ^= Int(part) << shifter
		}

		// If the data is small, use all except the first two bytes for the secondary hash.  Otherwise use a early-ish one tenth of the data.
		let partial2Start = short ? 1 : (data.count / 100 * 20)
		var partial2End = short ? (data.count - 1) : (data.count / 100 * 21)
		if ( partial2End - partial2Start > maximumSampleSize ) {
			partial2End = partial2Start + maximumSampleSize - 1
		}
		partialHash2 = 0
		// Iterate over the bytes since we already know that .hashValue doesn't do unique so well.
		for i in partial2Start...partial2End {
			// Is there a better way to do this?  Unsafe pointers may provide a good solution that works in larger chunks.
			var part = data[i]
			if ( 0 == (i + 1) % 3 ) { // Plus one here to un-align with partialHash1
				// Salt every third with the index.  This because repeating patterns can cause the hash to self-clear otherwise.
				part ^= UInt8(i % 0xFF)
			}
			let shifter = ((i % 8) * 8)
			partialHash2 ^= Int(part) << shifter
		}
	}

	static func ==(lhs: DataIdentity, rhs: DataIdentity) -> Bool {
		return lhs.hashValue == rhs.hashValue
			&& lhs.partialHash1 == rhs.partialHash1
			&& lhs.partialHash2 == rhs.partialHash2
	}
}
