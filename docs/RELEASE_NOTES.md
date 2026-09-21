CA Plate Watch is an unofficial macOS menu bar app for watching California personalized auto plates.

- Requires macOS 13 or newer.
- Download `arm64` for Apple Silicon (M-series), or `x86_64` for Intel.
- Unzip and move **CA Plate Watch.app** to Applications before enabling launch at login.

### First launch

These downloads are **ad-hoc signed, not Developer ID signed or notarized**. macOS may block the first launch because Apple cannot verify the developer.

If you trust this download, try opening the app once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. You may need to authenticate. On managed Macs, your organization may prevent this override.

Do not disable Gatekeeper globally. If macOS reports actual malware or a damaged app, do not bypass that warning; re-download and report the issue. See [Apple's instructions](https://support.apple.com/en-us/102445).

The `SHA256SUMS.txt` attachment lets you check downloaded file integrity using `shasum -a 256 -c SHA256SUMS.txt` with both ZIPs in the same folder. Checksums do not replace developer identity verification.

After launching, click the license plate menu bar icon to add plates and enable notifications. Checks run every six hours while the app is running and the Mac is awake. Availability does not reserve a plate.
