## Summary

Add a simple blue macOS app icon for QuickMeeting that communicates "conversation plus audio capture" at a glance and remains legible at small Finder and Dock sizes.

## Visual Direction

Use a rounded square blue background with a centered white speech bubble. Place three short vertical waveform bars inside the bubble to suggest recorded meeting audio without introducing small details that blur at 16px and 32px.

## Why This Approach

- Matches the product name and purpose immediately.
- Keeps the silhouette simple enough for macOS icon downscaling.
- Avoids text, initials, or calendar details that become noisy at small sizes.

## Implementation Notes

- Generate a single 1024x1024 source rendering and resize it to the required `AppIcon.appiconset` entries.
- Keep the palette limited to layered blues plus white to preserve contrast.
- Store generated PNGs in the existing `QuickMeeting/Assets.xcassets/AppIcon.appiconset` catalog and update `Contents.json` with explicit filenames.
- Leave the Xcode target using `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

## Testing

- Verify that every required macOS icon slot has a matching PNG file.
- Run a focused Xcode build to confirm the asset catalog compiles successfully.
