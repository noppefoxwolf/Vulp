# Known Issues

## Lazy image decoding can reach the main thread

`ImageIOImageDeserializer` creates `UIImage` values from ImageIO `CGImage` objects, but this does not by itself guarantee that all pixel data has been decoded. With a valid target size, `ResizeImageProcessor` draws the source into a bitmap context on its `@concurrent` path, which normally materializes the pixels before the image reaches a UI view.

When the target size is invalid, the processor currently returns the original image without rasterizing it. If the image still has deferred decoding work, assigning it to a `UIImageView` can cause that work (including GIF frame decompression such as `DGifDecompress`) to happen during display on the main thread. Similar behavior is possible when a custom processor returns the source image without drawing or otherwise preparing it.

For now, provide a valid target size and use a processor that rasterizes the output. Preparing an image at its original pixel dimensions can also move deferred decoding off the main thread when no resize is requested, but it may allocate a large bitmap. This behavior has not been verified with an Instruments trace for every fallback path.
