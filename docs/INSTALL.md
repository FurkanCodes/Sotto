# Installing Sotto

Sotto runs on Macs with Apple silicon (M1 or later) and macOS 26 or later.

Sotto is signed, but not notarized by Apple, so the first time you open it macOS blocks it. You allow it once, below. Updates need the same step.

## The quick way: the install script

In Terminal, run:

```
curl -fsSL https://raw.githubusercontent.com/FurkanCodes/Sotto/main/scripts/install.sh | bash
```

It downloads the latest release, checks it against its SHA-256, and puts `Sotto.app` in Applications, replacing an older version. You can [read the script](../scripts/install.sh) first.

Before installing, it explains Apple's check and asks you to type **yes** or **no**:

- **yes:** Sotto is installed without the "downloaded from the internet" mark, so macOS doesn't block it, and it opens straight away.
- **no:** Sotto keeps the mark. macOS blocks it the first time, and you allow it as in step 3 below.

Then go to step 4. Updates work the same way: run the command again.

## By hand

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

On first launch, Sotto's setup window asks for two permissions, one at a time, and explains each one:

- **Microphone**, to hear you while you hold the dictation key.
- **Accessibility**, to notice when you hold the dictation key and to paste the text into the app you're typing in.

It also downloads its speech model (about 460 MB), once. After that, Sotto never uses the network: your voice and text stay on your Mac.

## Updating

Run the install script again, or quit Sotto, replace `Sotto.app` in Applications with the new one, and repeat step 3. Your permissions and settings carry over, because every release is signed with the same certificate.

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
