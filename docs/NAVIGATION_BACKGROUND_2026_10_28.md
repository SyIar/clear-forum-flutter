# Home navigation transition background

The device recording shows a white strip and white corner wedges outside the rounded home page during an interactive return from Downloader. The home wallpaper was attached only to the moving page; its hosting/navigation surfaces retained their default backgrounds.

Keep a shared wallpaper backdrop behind the module host, outside animated page bounds. The home page reuses the same backdrop, with a transparent navigation container. Explicitly clear the outer navigation and hosting view backgrounds. Preserve native transitions, safe areas for controls, cancelled-swipe handling, and Reduce Motion behavior. Both backdrops observe the same cached wallpaper store without additional downloads.

Apple documents [navigation container backgrounds](https://developer.apple.com/documentation/swiftui/view/containerbackground(_:for:)) as filling the parent container, unlike ordinary view backgrounds; the [navigation placement](https://developer.apple.com/documentation/swiftui/containerbackgroundplacement/navigation) is available on iOS 18 and later.

Device acceptance: return to the selector from Downloader, each forum, and Tieba with both a completed and cancelled edge swipe. Check the left edge and all corners throughout slow transitions, light/dark appearance, and the initial gradient before wallpaper loading. Verify ordinary pushed pages still have their normal backgrounds. Compilation and existing unit tests do not verify the composited animation on a physical device.
