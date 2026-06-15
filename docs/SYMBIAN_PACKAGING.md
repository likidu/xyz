Symbian packaging and device verification
========================================

Prerequisites
- Symbian Qt SDK installed (Qt 4.7.4 toolchain). Default path assumed by scripts: C:\Symbian\QtSDK
- Symbian SDK root (example): C:\Symbian\QtSDK\Symbian\SDKs\SymbianSR1Qt474
- RVCT 4.0 toolchain (used by build-symbian.ps1).
- Device: a Symbian Belle handset (e.g. Nokia C7 / X7) with the Qt runtime installed.

Build + package (one step)
   pwsh scripts/build-sis.ps1 -Config Release -Arch armv5
Runs the build and packaging stages below and writes the self-signed SIS to
build-symbian\armv5-release\Xyz_selfsigned.sis. Useful flags:
- -Clean  : force a clean rebuild. Use this after editing QML — rcc does not
            retrigger on .qml/.qrc/svg changes alone, so a stale UI gets baked in
            otherwise (see docs/DEVICE_NOTES.md).
- -Force  : regenerate the self-signed certificate.

Build + package (separate stages)
1. Build the binaries:
   pwsh scripts/build-symbian.ps1 -Config Release -Arch armv5
   Output is staged into build-symbian\armv5-release.
2. Confirm Xyz_template.pkg has the package UID and version you want.
   - The default UID is in the self-signed test range (0xE0000000-0xEFFFFFFF).
3. Create the SIS:
   pwsh scripts/package-symbian.ps1 -Config Release -Arch armv5
   Outputs (in build-symbian\armv5-release):
   - Xyz_selfsigned.sis  (install this on the device)
   - Xyz_unsigned.sis    (intermediate)
   - Xyz_local.pkg       (generated from Xyz_template.pkg with local paths)
   The self-signed cert/key are generated once under build-symbian\certs\.

Install on device
- Transfer Xyz_selfsigned.sis to the phone over Bluetooth (open it from the
  Messaging inbox to install), or via USB mass storage / Nokia Suite.
- Allow untrusted installs first: Settings > Application manager > Installation
  settings > Software installation = All, and Online certificate check = Off.

Troubleshooting
- QML/UI edits not appearing on device: editing only .qml/.qrc/svg files does not
  retrigger rcc; rebuild with -Clean (see docs/DEVICE_NOTES.md).
- Xyz.rsc or Xyz_reg.rsc missing: rebuild and confirm the Symbian SDK path is correct.
- Network requests fail with a capability error: add NetworkServices to the Symbian
  capabilities in Xyz.pro and rebuild.
- App won't launch (missing Qt libraries): install the Qt runtime for Symbian Belle.

Manual smoke test (current build: M2 - auth + Updates / Subscriptions)
- Self-test page (app menu > Self-test): TLS, SQLite round-trip, live RAM, and
  audio playback each report pass.
- Login: tap the phone field -> the on-screen keyboard appears; Get Code; enter the
  4-digit SMS code; Sign in.
- After login the content area fills the screen, with the bottom tab bar pinned to
  the bottom edge.
- Updates feed loads real episodes (covers, titles, meta row).
- My Subscriptions loads; the grid <-> list toggle both render.
