# MJFastImageLoader

Provide faster image rendering of large images into UIImageView for improved user experience.

## Purpose
Rendering large images, such as those from the Camera Roll directly into UIImageView produces noticeable slowness that does not provide ideal user experience.  MJFastImageLoader provides faster image rendering by rendering low-resolution initial images and then replacing them with the high-resolution versions once they are available.

Why not just render the images in the background before needing to display them?  MJFastImageLoader was created in response to a scenario where the user could select from numerous image sets and want several random images from the selected set to appear immediately.  Another solution could have been to pre-select and background-process N random images from each image set, but then we are no better off if they pick a set before we get to it in our batch.  MJFastImageLoader abstracts these details away from your code by giving you a way to say "I might need this image" followed by "I need that image right now" with the framework ensuring that you get what you need fast.

## Usage
Add image in Data instance to the FastImageLoader:

```
FastImageLoader.shared.enqueue(image: data, priority: .critical)
```
Configure batching if needed:

```
// Group up to six updates or as many as arrive within half a second of the first.
FastImageLoaderBatch.shared.batchUpdateQuantityLimit = 6
FastImageLoaderBatch.shared.batchUpdateTimeLimit = 0.5
```
Access the processed UIImage from FastImageLoader, registering an update notification:

```
DispatchQueue.main.sync {
	let updater = UIImageViewUpdater(imageView: imageView, batch: FastImageLoaderBatch.shared)
	imageView.image = FastImageLoader.shared.image(image: data, notification: updater)
}
```
Cancel update notification and processing, such as when you want a different image in that UIImageView:

```
updater.cancel()
FastImageLoader.shared.cancel(image: data)
```

## Code Notes
In terms of documentation and architecture, this framework is designed to demonstrate a maximum level of completion and cleanliness.  This level of documentation may not be appropriate for all projects and may feel excessive to some viewers.  It was written this way as a demonstration of a framework with these aspects turned to the max.  As a result, it provides meaningful Quick Help documentation for all methods and properties from private to open.

Code style is intended to follow the Xcode default styling whether I like it or not.  I'd still like to check whitespace consistency for sake of perfection but believe the current state is quite readable.

## Work Items
* There are some "TODO:" notes that should be evaluated.
* It would make sense to have a single method which would enqueue work, set a UIImageView's image, and register notification.
* Adaptive rendering levels based on requested QoS and observed render times would be good.
* A default image to set before the first render would be good.
