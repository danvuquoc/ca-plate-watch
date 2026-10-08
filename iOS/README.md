# CA Plate Watch for iPhone

This is the iOS companion to the macOS menu bar app. It uses the same plate catalog, validation, and DMV client. Each device keeps its own watchlist; there is no account, cloud sync, or server.

## Build on your iPhone

1. Install Xcode with an iOS SDK and device support for iOS 18.7 or later.
2. Open `CAPlateWatchiOS.xcodeproj` in Xcode and select the **CAPlateWatchiOS** scheme.
3. Select the app target's **Signing & Capabilities** tab, choose your personal development team, and replace `local.CAPlateWatch.iOS` with a bundle identifier available to that team if Xcode asks.
4. Select an iPhone running iOS 18.7 or later and press **Run**. Xcode may ask you to enable Developer Mode or trust the signing identity on the iPhone.

The deployment target is iOS 18.7. Xcode expresses this at the major/minor level, so it also covers iOS 18.7.10.

The checked-in Xcode project is generated from `project.yml` with XcodeGen. XcodeGen is needed only if you change the project specification and want to regenerate the project; it is not needed to open or build the checked-in project.

## How checks work

The home screen shows your watched plates as scrollable status cards. The **+** icon opens a dedicated Add a plate page with a plate entry prompt and Add button. The refresh icon checks now, and the gear icon opens a separate Settings page for intervals and notification settings.

Adding a plate checks it immediately. The app checks overdue plates when opened, while active, and when iOS grants a background app refresh. The refresh button checks every saved plate immediately. The interval determines when a plate becomes eligible, but iOS chooses when to run background refresh and may delay it by hours. Enable **Background App Refresh** in iOS Settings for the best chance of background checks. If you force quit the app, reopen it to resume checks.

The app sends a local notification only after a DMV response confirms a transition to available. An unrecognized response or network failure preserves the last confirmed status and is shown as an error. Notifications require permission. Availability is not a reservation or final DMV approval.

A newly available plate shows **NEW** for the current app run. The marker clears automatically the next time the app launches.

The watchlist is stored in this app's private Application Support directory. It does not read or sync the Mac's `watchlist.json` file. Plate queries go directly to the California DMV over HTTPS.

## Verification

Run offline shared-core checks from the repository root:

```sh
swift run CAPlateWatchCoreTests
```

GitHub Actions also builds the iPhone scheme for a generic iOS simulator on pushes and pull requests. That build checks compilation without launching the app or exercising background refresh.

For iOS, build and run the scheme in Xcode on a simulator with an iOS 18.7+ runtime or on a device. Verify a plate can be added and survives relaunch; manual refresh updates its status; notifications are shown on an available transition; and network errors preserve the last confirmed status. Background launch and expiration need a physical device for meaningful validation because iOS controls their timing.
