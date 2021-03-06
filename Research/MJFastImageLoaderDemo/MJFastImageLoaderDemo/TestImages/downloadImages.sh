#!/bin/sh

#  downloadImages.sh
#  MJFastImageLoaderDemo
#
#  Created by Mark Jerde on 2/22/18.
#  Copyright © 2018 Mark Jerde.
#
#  This file is part of MJFastImageLoader
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of MJFastImageLoader and associated documentation files (the "Software"), to
#  deal in the Software without restriction, including without limitation the
#  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
#  sell copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in all
#  copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#  SOFTWARE.

# Download 100 random images
for i in {1..100}
do
	wget -O - 'https://picsum.photos/5000/3000/?random' > $(($(ls *.jpg|wc -l|sed 's/ //g')+1)).jpg
	sleep 1
done
