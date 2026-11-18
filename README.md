# Walion

Live stream player for iPhone, iPad and macOS, built with SwiftUI. Radio comes first; video is planned.

## Features

- **Channel list**: search the [radio-browser.info](https://www.radio-browser.info) directory and save stations to your own list.
- **Playback**: tap a channel to play it. When you switch, the old channel keeps playing until the new one has loaded, and keeps playing if the new one fails.
- **Now playing**: the bar at the bottom shows the station logo, a loading indicator, and the current song or show when the station sends it.
- **System controls**: lock screen, Control Center, Dynamic Island and macOS Now Playing show the station, its logo and the current song. Play/stop, plus next/previous to step through your channel list. On iOS, audio keeps playing in the background.

## Requirements

- Xcode 26 or newer
- iOS 18 / macOS 15 or newer

## Run the app

### In Xcode

1. Open `Walion.xcodeproj`.
2. Pick a run destination in the toolbar: **My Mac** or an iPhone/iPad simulator.
3. Press **⌘R**.

To run on your own device, set your team and a bundle identifier of your own under
*Walion target › Signing & Capabilities*.

### From the command line

macOS:

```sh
xcodebuild -project Walion.xcodeproj -scheme Walion -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/Walion.app
```

iOS Simulator:

```sh
xcodebuild -project Walion.xcodeproj -scheme Walion -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
xcrun simctl boot 'iPhone 17 Pro'; open -a DeviceHub
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Walion.app
xcrun simctl launch booted de.emrox.walion
```

Use `xcrun simctl list devices available` to see which simulator names exist on your machine.

## Run the tests

In Xcode press **⌘U**, or from the command line:

```sh
xcodebuild test -project Walion.xcodeproj -scheme Walion -destination 'platform=macOS' -derivedDataPath build
```

The tests need no network: radio-browser is stubbed and the player plays generated silent audio files.
