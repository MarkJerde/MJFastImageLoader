//
//  Utility.swift
//  MJFastImageLoader
//
//  Created by Mark Jerde on 3/19/18.
//  Copyright © 2018 Mark Jerde. All rights reserved.
//

import Foundation

/// A collection of static utilities.
class Utility {
	// MARK: Various mimeType arrays.
	public static let mimeType_image_x_ms_bmp = ["image/x-ms-bmp","bmp"]
	public static let mimeType_image_psd = ["image/psd","psd"]
	public static let mimeType_image_iff = ["image/iff","iff"]
	public static let mimeType_image_ico = ["image/vnd.microsoft.icon","ico"]
	public static let mimeType_image_jp2 = ["image/jp2","jp2"]
	public static let mimeType_image_gif = ["image/gif","gif"]
	public static let mimeType_image_webp = ["image/webp","webp"]
	public static let mimeType_image_tiff = ["image/tiff","tiff"]
	public static let mimeType_image_jpeg = ["image/jpeg","jpeg"]
	public static let mimeType_image_png = ["image/png","png"]
	public static let mimeType_application_octet_stream = ["application/octet-stream","bin"]

	// MARK: Private characters and patterns.
	private static let char8:UInt8 = String("8").utf8.map{ UInt8($0) }.first!
	private static let charB:UInt8 = String("B").utf8.map{ UInt8($0) }.first!
	private static let charF:UInt8 = String("F").utf8.map{ UInt8($0) }.first!
	private static let charG:UInt8 = String("G").utf8.map{ UInt8($0) }.first!
	private static let charI:UInt8 = String("I").utf8.map{ UInt8($0) }.first!
	private static let charM:UInt8 = String("M").utf8.map{ UInt8($0) }.first!
	private static let charO:UInt8 = String("O").utf8.map{ UInt8($0) }.first!
	private static let charP:UInt8 = String("P").utf8.map{ UInt8($0) }.first!
	private static let charR:UInt8 = String("R").utf8.map{ UInt8($0) }.first!
	private static let charS:UInt8 = String("S").utf8.map{ UInt8($0) }.first!

	private static let jp2:[UInt8] = [0x00, 0x00, 0x00, 0x0c, 0x6a, 0x50, 0x20, 0x20, 0x0d, 0x0a, 0x87, 0x0a]
	private static let ico:[UInt8] = [0x00, 0x00, 0x01, 0x00]
	private static let tif_ii:[UInt8] = [0x49, 0x49, 0x2A, 0x00] // II\00*
	private static let tif_mm:[UInt8] = [0x4D, 0x4D, 0x00, 0x2A] // MM\00*
	private static let png:[UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
	private static let jpg:[UInt8] = [0xff, 0xd8, 0xff]

	/// Determines the MIME type of the contents of the provided Data.
	///
	/// - Parameter data: The data to identify the type of.
	/// - Returns: The MIME type of the provided data.
	static func mimeTypeByGuessingFromData( data: Data ) -> [String] {
		/*const char swf[3] = {'F', 'W', 'S'};
		const char swc[3] = {'C', 'W', 'S'};
		;*/

		let buffer = [UInt8](data.subdata(in: 0..<jp2.count))

		// Divide the possibilities in half for performance.
		if ( buffer[0] < charG ) {
			// These are all pretty boring types, so just check them in sequence.

			if ( charB == buffer[0] && charM == buffer[1] ) {
				return mimeType_image_x_ms_bmp
			}

			if ( char8 == buffer[0] && charB == buffer[1] && charP == buffer[2] && charS == buffer[3] ) {
				return mimeType_image_psd
			}

			if ( charF == buffer[0] && charO == buffer[1] && charR == buffer[2] && charM == buffer[3] ) {
				return mimeType_image_iff
			}

			if ( ico[0] == buffer[0] && ico[1] == buffer[1] && ico[2] == buffer[2] && ico[3] == buffer[3] ) {
				return mimeType_image_ico
			}

			if ( jp2[0] == buffer[0] && jp2[1] == buffer[1] && jp2[2] == buffer[2] && jp2[3] == buffer[3]
				&& jp2[4] == buffer[4] && jp2[5] == buffer[5] && jp2[6] == buffer[6] && jp2[7] == buffer[7]
				&& jp2[8] == buffer[8] && jp2[9] == buffer[9] && jp2[10] == buffer[10] && jp2[11] == buffer[11] ) {
				return mimeType_image_jp2
			}

		}
		else {
			// Divide the possibilities in half (60/40) again for performance.
			if ( buffer[0] <= charS ) {
				if ( charG == buffer[0] && charI == buffer[1] && charF == buffer[2] ) {
					return mimeType_image_gif
				}

				if ( charR == buffer[0] && charI == buffer[1] && charF == buffer[2] && charF == buffer[3] ) {
					return mimeType_image_webp
				}

				if ( tif_ii[0] == buffer[0] && tif_ii[1] == buffer[1] && tif_ii[2] == buffer[2] && tif_ii[3] == buffer[3] ) {
					return mimeType_image_tiff
				}
			}
			else {
				if ( jpg[0] == buffer[0] && jpg[1] == buffer[1] && jpg[2] == buffer[2] ) {
					return mimeType_image_jpeg
				}

				if ( png[0] == buffer[0] && png[1] == buffer[1] && png[2] == buffer[2] && png[3] == buffer[3]
					&& png[4] == buffer[4] && png[5] == buffer[5] && png[6] == buffer[6] && png[7] == buffer[7] ) {
					return mimeType_image_png
				}
			}
		}

		return mimeType_application_octet_stream // default type
	}

}
