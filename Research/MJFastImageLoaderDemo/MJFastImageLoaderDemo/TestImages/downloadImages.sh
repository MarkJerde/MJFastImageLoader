#!/bin/sh

#  downloadImages.sh
#  MJFastImageLoaderDemo
#
#  Created by Mark Jerde on 2/22/18.
#  Copyright © 2018 Mark Jerde. All rights reserved.

# Download 100 random images
for i in {1..100}
do
	wget -O - 'https://picsum.photos/5000/3000/?random' > $(($(ls *.jpg|wc -l|sed 's/ //g')+1)).jpg
	sleep 1
done
