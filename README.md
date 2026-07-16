# KeyHaptic

Minimal macOS menu bar utility that plays Force Touch trackpad haptics when you type, and Alarm Clock–style picker ticks when you scroll.

**Repository:** [github.com/EugeneKrokhmal/KeyHaptic](https://github.com/EugeneKrokhmal/KeyHaptic)

## Requirements

- macOS 13+
- Force Touch trackpad (MacBook or Magic Trackpad)
- **Input Monitoring** and **Accessibility** permissions

## Build & run (direct / Developer ID)

```bash
./scripts/build.sh
```

This installs `/Applications/KeyHaptic.app`, resets TCC for the ad-hoc signed binary, and opens System Settings. Then:

1. Enable **KeyHaptic** under Input Monitoring  
2. Enable **KeyHaptic** under Accessibility  
3. Choose **Quit & Reopen**

Menu bar → **Intensities…** for key/scroll strength and picker notch size.

## Distribution notes (important)

| Path | Haptic backend | Apple acceptance |
|------|----------------|------------------|
| **Direct download / notarized Developer ID** | MultitouchSupport actuator (strong) | Gatekeeper via notarization |
| **Mac App Store** | Public `NSHapticFeedbackManager` only | Required — private MultitouchSupport is rejected |

The default build uses the strong Multitouch actuator (same approach as open-source tools like HapticKey). That API is **private** and **will not pass Mac App Store review**.

### App Store build (weaker haptics)

```bash
swift build -c release -Xswiftc -DAPPSTORE
# then package with sandbox entitlements in Resources/KeyHaptic.AppStore.entitlements
```

You still need a full Xcode archive, App Store Connect listing, and screenshots. Expect much weaker feedback than the direct build.

### Notarization (recommended for public releases)

1. Apple Developer Program membership  
2. **Developer ID Application** certificate (not only “Apple Development”)  
3. Sign with hardened runtime + notarize (`notarytool`)  
4. Staple the ticket to the `.app` / `.dmg`

## Privacy

KeyHaptic listens for keyboard and scroll events **on-device only** to trigger haptics. No key contents, text, or analytics are collected or transmitted.

## License

MIT — see [LICENSE](LICENSE).
