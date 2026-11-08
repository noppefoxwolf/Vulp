# 0015. Preserve source aspect ratio when resizing

- Status: Accepted
- Date: 2026-11-09

## Context

Size-aware views pass their bounds as the requested image size. Resizing the source directly into those dimensions distorts images whenever the source and view aspect ratios differ. Display-side fit behavior cannot undo distortion introduced by the processor.

## Decision

- Treat `MediaImageRequest.targetSize` as the target bounding size for the processed image.
- `ResizeImageProcessor` supports `.fit`, which scales uniformly to fit within the bound, and `.fill`, which scales uniformly to cover the bound and center-crops overflow.
- Default to `.fit`.
- Keep request bucketing and cache identity based on the requested bounding size.
- Include the resize mode in cache identity because fit and fill produce different output images.

## Alternatives considered

- Continue stretching to the exact requested dimensions:
  - Benefits: output dimensions always match the request.
  - Costs: images are visibly distorted when source and view aspect ratios differ.
- Rely on UI content modes without changing processor output:
  - Benefits: keeps processing independent from presentation choices.
  - Costs: cannot restore the source aspect ratio after the processor has stretched the pixels.

## Consequences

- Fit output may be smaller than the requested bounding size on one edge. Fill output matches the requested size and crops the source.
- Both modes preserve the source aspect ratio; fill discards overflow instead of distorting it.
- Callers can choose `.fill` when they need exact target dimensions and can accept cropping; `.fit` preserves the full image.
