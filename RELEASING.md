# Releasing Dict

This document covers how to cut a release that customers receive through Sparkle's auto-update.

## One-time setup (do this before your first release)

Sparkle signs every update with an EdDSA keypair. You generate this **once**, keep the private key in your Keychain, and embed the public key in the app.

### 1. Generate the Sparkle signing keypair

The `generate_keys` tool ships with the Sparkle SPM package. After building the app at least once, you'll find it here:

```
~/Library/Developer/Xcode/DerivedData/Dict-app-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

Run it once:

```bash
# Find the tool (DerivedData path varies per build)
GENERATE_KEYS=$(find ~/Library/Developer/Xcode/DerivedData -name generate_keys -path "*Sparkle*" | head -1)

# Generate the keypair — private key goes into Keychain, public key is printed
"$GENERATE_KEYS"
```

The tool will print something like:

```
A key has been generated and saved in your keychain.
Public key:
abc123XYZ...=
```

**Immediately back up the private key** to 1Password (or wherever you store secrets). You can export it with:

```bash
"$GENERATE_KEYS" -x private_key.txt
# Copy private_key.txt into 1Password, then:
rm private_key.txt
```

If you lose this key and don't have a backup, you cannot sign any future updates — existing users will be stuck on whatever version they're on.

### 2. Add the public key to the app

Open `Dict-app.xcodeproj` in Xcode → select the `Dict-app` target → Build Settings → search for "Info.plist" → find the "Info.plist Values" section. Add a new entry:

- **Key:** `SUPublicEDKey`
- **Value:** the public key printed by `generate_keys`

(Alternatively, edit `Dict-app.xcodeproj/project.pbxproj` directly and add `INFOPLIST_KEY_SUPublicEDKey = "<your-public-key>"` next to `INFOPLIST_KEY_SUFeedURL` in both Debug and Release build configs.)

Commit this change. Until the key is set, Sparkle will still run but will refuse to install any updates (it can't verify signatures).

## Per-release workflow

When you're ready to ship a new version:

### 1. Bump the version

In Xcode → `Dict-app` target → General tab:
- **Version** (`MARKETING_VERSION`) — the user-visible version, e.g. `1.1.0`
- **Build** (`CURRENT_PROJECT_VERSION`) — monotonically increasing integer, e.g. `5`

Sparkle compares builds using `CURRENT_PROJECT_VERSION`, not `MARKETING_VERSION`. **Always bump the build number**, even for small releases.

Commit the version bump.

### 2. Archive and export

In Xcode → Product → Archive. Then in Organizer:

1. Select the new archive
2. Distribute App → **Developer ID**
3. Upload (for notarization) → wait for Apple to notarize
4. Export the notarized `.app`

Or from CLI:

```bash
xcodebuild -scheme Dict-app -configuration Release archive \
    -archivePath build/Dict.xcarchive

xcodebuild -exportArchive \
    -archivePath build/Dict.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist
```

You'll need an `ExportOptions.plist` with `method = developer-id` and the appropriate team ID.

### 3. Package into a DMG

```bash
# Simplest: zip the .app
cd build/export
ditto -c -k --keepParent Dict.app Dict-1.1.0.zip

# Or create a DMG (looks more professional)
# hdiutil create -volname "Dict" -srcfolder Dict.app -ov -format UDZO Dict-1.1.0.dmg
```

Sparkle supports both `.zip` and `.dmg` for the update enclosure.

### 4. Sign the release with Sparkle

The `sign_update` tool lives next to `generate_keys`:

```bash
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -path "*Sparkle*" | head -1)

"$SIGN_UPDATE" Dict-1.1.0.zip
```

It prints something like:

```
sparkle:edSignature="abc123..." length="1234567"
```

Copy that output — you'll paste it into `appcast.xml` in the next step.

### 5. Update `appcast.xml`

Add a new `<item>` to the top of the `<channel>` in `appcast.xml` (newest first):

```xml
<item>
    <title>Version 1.1.0</title>
    <pubDate>Wed, 08 Apr 2026 12:00:00 +0000</pubDate>
    <sparkle:version>5</sparkle:version>
    <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    <description><![CDATA[
        <h2>What's New in 1.1.0</h2>
        <ul>
            <li>Faster transcription</li>
            <li>Fixed a bug with the waveform</li>
        </ul>
    ]]></description>
    <enclosure
        url="https://github.com/mattbirchler/Dict-app/releases/download/v1.1.0/Dict-1.1.0.zip"
        sparkle:edSignature="PASTE_SIGNATURE_HERE"
        length="PASTE_LENGTH_HERE"
        type="application/octet-stream" />
</item>
```

- `sparkle:version` must match `CURRENT_PROJECT_VERSION` from Xcode
- `sparkle:shortVersionString` must match `MARKETING_VERSION`
- `sparkle:edSignature` and `length` come from step 4
- `url` must be the eventual GitHub release asset URL (you'll create the release in step 6)

### 6. Publish the GitHub release

```bash
gh release create v1.1.0 Dict-1.1.0.zip \
    --title "Dict 1.1.0" \
    --notes "See appcast.xml for full release notes"
```

This creates a release tagged `v1.1.0` and uploads the signed `.zip` as an asset. The asset URL matches what you put in `<enclosure url="...">` in step 5.

### 7. Push `appcast.xml`

```bash
git add appcast.xml
git commit -m "release: 1.1.0"
git push
```

**This is the moment customers receive the update.** Until `appcast.xml` is pushed, existing users still see the old version. Once it's pushed, the raw URL Sparkle reads (`https://raw.githubusercontent.com/mattbirchler/Dict-app/main/appcast.xml`) reflects the new release, and users will see the update on their next daily check (or when they click "Check for Updates…" in the menu bar).

## Gotchas

- **Never push `appcast.xml` without first publishing the GitHub release.** Users will try to download a file that doesn't exist and see a confusing error.
- **Always sign with the real private key.** `sign_update` pulls from Keychain — if you're on a new machine, you need to import the private key first (`generate_keys -f private_key.txt`).
- **Bump the build number every release.** Sparkle uses it for version comparison.
- **Test the update flow end-to-end** before your first customer-facing release: build v1.0.0, install it, then build v1.0.1, publish, and verify that v1.0.0 sees the update and installs it cleanly.

## Related files

- `Dict-app/Dict_appApp.swift` — Sparkle updater lives in `AppDelegate`
- `Dict-app/MenuBarPopover.swift` — "Check for Updates…" button
- `Dict-app.xcodeproj/project.pbxproj` — `INFOPLIST_KEY_SUFeedURL` and (eventually) `INFOPLIST_KEY_SUPublicEDKey`
- `appcast.xml` — the feed customers' Sparkle reads
