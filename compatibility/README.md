# YouTube 21.42.4 compatibility for the free YouTube Plus 5.2b4

This fork adds a small open-source compatibility library and a guarded patching
script for a user-supplied, decrypted YouTube **21.42.4** IPA with **YTLite 5.2b4**.
It does not contain YouTube binaries, signing material, or paid tweak features.
The source in the upstream root is older than the distributed 5.2b4 tweak; this
adapter explicitly targets the free release binary rather than claiming to
rebuild that release from the old sources.

## Changes

- Restore `YTPlayerViewController.playerResponse` by forwarding to
  `contentPlayerResponse`. The old selector caused an uncaught exception whenever
  a video opened in 21.42.4.
- Forward the obsolete native-share hook to its original implementation. This
  avoids the removed `YTIShareEntityEndpoint.shareEntityEndpoint` API. The native
  share replacement is disabled; YouTube's original sharing remains available.
- Add a native **YT+** pivot-bar entry immediately after the profile/You item.
  YouTube positions it in the Duo sidebar or compact tab bar. It opens the original
  tweak settings and provides download and PiP commands when a video is available.
- Keep the native vertical sidebar visible on the expanded watch page (outside
  fullscreen). Selecting a destination first collapses the watch page through
  YouTube’s native completion-based transition, then performs normal navigation.
- Put playback speed directly in the player controls, using a speedometer button
  registered with YTVideoOverlay. It follows the player controls’ visibility and
  opens the native speed menu. The duplicate speed action in the home YT+ menu
  is removed.
- Extend the renamed `YTVarispeedSwitchControllerImpl` speed options with 2.5×,
  3×, 3.5×, 4×, and 5×. The old tweak hooked a class name that no longer exists. The player's speed
  action now opens this native client-side menu instead of a server-provided sheet.
- Integrate **YouPiP 1.12.15** and **YTVideoOverlay 2.3.9** for PiP. These are
  separate free projects by PoomSmart, not features of the paid YouTube Plus.

## Build locally on a Mac

You need Xcode's iPhoneOS SDK, Python 3, and
[cyan](https://github.com/asdfzxcvbn/pyzule-rw) with its `insert_dylib` helper.
Obtain the free 5.2b4 DEB from upstream and the YouPiP / YTVideoOverlay DEBs from
[PoomSmart's repository](https://poomsmart.github.io/repo/).

```sh
cyan -i YOUR_DECRYPTED_YOUTUBE_21.42.4.ipa -o patched.ipa -uwef \
  com.dvntm.ytlite_5.2b4_iphoneos-arm.deb \
  com.ps.youpip_1.12.15_iphoneos-arm.deb \
  com.ps.ytvideooverlay_2.3.9_iphoneos-arm.deb
unzip -q patched.ipa -d staging
python3 compatibility/patch_app.py staging/Payload/YouTube.app \
  --insert-dylib /path/to/insert_dylib
```

Sign the app and every nested framework/dylib with your own provisioning profile
and signing identity, then install with Xcode or `devicectl`. Patching invalidates
existing signatures. No credentials should be added to this repository.

The patcher refuses a different YouTube version or an unexpected native-share
function prologue. Reapplying the patch is supported. It does not establish
compatibility with future versions or with the paid 5.2.2 release.

## Validation

```sh
python3 -m unittest discover -s compatibility -p 'test_*.py'
```

The original video-opening crash was reproduced on iOS 27.1. After the getter
bridge, two videos played successfully with audio, confirmed on the device.
Settings were instantiated and displayed successfully. Runtime inspection confirmed
the native speed controller contains options through 5×. The sidebar entry is
inserted at the view and controller levels, and its icon is explicitly kept visible
when YouTube lays out the custom item. The user confirmed the dedicated gear
is visible after installation. Download, PiP, and selecting extended speeds
still require device testing; the unit tests cover binary address mapping,
byte preservation, idempotence, and rejection of unexpected inputs.
