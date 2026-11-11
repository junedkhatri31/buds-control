# Install Buds Control

Requires a Mac running macOS 14 or later (Apple Silicon or Intel).

## Install

1. Download **BudsControl.dmg** from the [latest GitHub release](https://github.com/junedkhatri31/buds-control/releases/latest).
2. Double-click the DMG to open it.
3. Drag **Buds Control.app** onto **Applications** in the disk image.
4. Eject the **Buds Control** disk image, then launch the app from Applications.

The ZIP is an alternative: extract it and move **Buds Control.app** to Applications.
No Homebrew, Terminal commands or phone app is needed.

## Allow the first launch in macOS

This release is locally signed and has not been notarized by Apple. macOS may
block the first launch because it cannot verify the developer.

1. Try opening **Buds Control** from Applications and dismiss the warning.
2. Open **Apple menu → System Settings → Privacy & Security**.
3. Under **Security**, find the message for **Buds Control** and choose **Open Anyway**.
4. Confirm with **Open** and follow any macOS confirmation prompts.

Approve the copy downloaded from this repository. The exception applies to this
app; future launches normally work directly from Applications. These steps follow
[Apple's instructions](https://support.apple.com/en-us/102445).

When the app first talks to your earbuds, macOS asks for **Bluetooth** access. Choose **Allow**.

## Connect your earbuds

Pair the earbuds with your Mac in **System Settings → Bluetooth**, then connect them.
Buds Control lives in the menu bar (the earbuds icon) and the Dock. It finds compatible
earbuds automatically and links up whenever they connect to the Mac.

Click the menu-bar icon for battery levels and the dual-connection switch. Choose
**Settings…** (or click the Dock icon) for gestures, connected devices and firmware versions.
To keep the app out of the Dock, turn off **Show in Dock** under **General** in Settings.

## Compatibility

Works with OPPO, OnePlus and realme earbuds that expose their Bluetooth control
service. It was tested on OnePlus Nord Buds 3r. Other models should work, but
which features appear depends on what the earbuds report.
