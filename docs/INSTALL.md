# Installing Sotto

Sotto runs on Macs with Apple silicon (M1 or later) and macOS 26 or later.

Sotto is signed, but not notarized by Apple, so the first time you open it macOS blocks it. You allow it once, below. Updates need the same step.

## 1. Download and check the file

Download `Sotto-<version>.zip` and `Sotto-<version>.zip.sha256` into the same folder. To check that the download wasn't damaged or changed, open Terminal in that folder and run:

```
shasum -a 256 -c Sotto-0.1.0.zip.sha256
```

It should print `Sotto-0.1.0.zip: OK`. If it prints anything else, don't open the app.

## 2. Move Sotto to Applications

Double-click the zip to unpack it, then drag `Sotto.app` into your Applications folder. Open it from there, not from Downloads.

## 3. Allow Sotto to open

When you first open Sotto, macOS says:

> **"Sotto" Not Opened**
> Apple could not verify "Sotto" is free of malware that may harm your Mac or compromise your privacy.

Click **Done**, not **Move to Trash**. Then allow it in one of two ways.

**In System Settings:** open System Settings → Privacy & Security and scroll down to Security. Next to the message that Sotto was blocked, click **Open Anyway**, confirm, and enter your password if asked.

**In Terminal:** run

```
xattr -dr com.apple.quarantine /Applications/Sotto.app
```

This removes the "downloaded from the internet" mark that makes macOS block the app. Then open Sotto normally.

## 4. Grant permissions

On first launch, Sotto asks for three permissions and explains each one:

- **Microphone**, to hear you while you hold the dictation key.
- **Accessibility**, to paste the text into the app you're typing in.
- **Input Monitoring**, to notice when you press and release the dictation key.

It also downloads its speech model (about 460 MB), once. After that, Sotto never uses the network: your voice and text stay on your Mac.

## Updating

Quit Sotto, replace `Sotto.app` in Applications with the new one, and repeat step 3. Your permissions and settings carry over, because every release is signed with the same certificate.

## Uninstalling

1. Quit Sotto and move `Sotto.app` to the Trash.
2. Delete its data: `~/Library/Application Support/Sotto` (settings, history, extra models) and `~/Library/Application Support/FluidAudio` (the built-in speech model; other apps built on FluidAudio may share it).
3. Optionally, remove its permissions:

   ```
   tccutil reset Microphone com.furkan.sotto
   tccutil reset Accessibility com.furkan.sotto
   tccutil reset ListenEvent com.furkan.sotto
   ```

## For maintainers

`scripts/release.sh` builds the app, refuses an ad-hoc signature, and writes `build/release/Sotto-<version>.zip` with its `.sha256`. Release with the same certificate every time; a different one makes every user grant permissions again. Keep a backup of "Sotto Local Signing" (Keychain Access → export as `.p12` with a password).
