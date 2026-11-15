# Walion

Live stream player for iPhone, iPad and macOS, built with SwiftUI. Radio stations are found via [radio-browser.info](https://www.radio-browser.info).

## Requirements

- Xcode 26 or newer
- iOS 18 / macOS 15 or newer

## Run the app

### In Xcode

1. Open `Walion.xcodeproj`.
2. Pick a run destination in the toolbar: **My Mac** or an iPhone/iPad simulator.
3. Press **⌘R**.

To run on a real device, first set your team and a unique bundle identifier under
*Walion target › Signing & Capabilities* (the default `com.example.Walion` is a placeholder).

### From the command line

macOS:

```sh
xcodebuild -project Walion.xcodeproj -scheme Walion -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Walion.app
```

iOS Simulator:

```sh
xcodebuild -project Walion.xcodeproj -scheme Walion -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
xcrun simctl boot 'iPhone 17 Pro'; open -a Simulator
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Walion.app
xcrun simctl launch booted com.example.Walion
```

Use `xcrun simctl list devices available` to see which simulator names exist on your machine.
