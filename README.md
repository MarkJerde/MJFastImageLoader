# MJFastImageLoader

Provide faster image rendering of large images into UIImageView for improved user experience.

## Purpose
Rendering large images, such as those from the Camera Roll directly into UIImageView produces noticeable slowness that does not provide ideal user experience.  MJFastImageLoader provides faster image rendering by rendering low-resolution initial images and then replacing them with the high-resolution versions once they are available.

## Code Notes
In terms of documentation and architecture, this framework is designed to demonstrate a maximum level of completion and cleanliness.  This level of documentation may not be appropriate for all projects and may feel excessive to some viewers.  It was written this way as a demonstration of a framework with these aspects turned to the max.  As a result, it provides meaningful Quick Help documentation for all methods and properties from private to open.

## Work Items
* There are some "fixme" notes that should be evaluated.
* It would make sense to have a single method which would enqueue work, set a UIImageView's image, and register notification.
* Adaptive rendering levels based on requested QoS and observed render times would be good.
* A default image to set before the first render would be good.
