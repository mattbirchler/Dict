# Releasing Dict

Dict ships outside the App Store. People download a notarized zip from
GitHub Releases, and Sparkle tells running copies about new versions
through `appcast.xml` on this repo's `main` branch.

## Shipping a version

1. Write release notes for people in a Markdown file (for example
   `notes/1.1.md`): what changed and why they'd care. Headings, bullets,
   and paragraphs are supported. They show in Sparkle's update window and
   on the GitHub release.
2. From a clean `main` that matches `origin/main`:

   ```bash
   make publish NOTES=notes/1.1.md VERSION=1.1
   ```

   Leave `VERSION` off to keep the current marketing version and only bump
   the build.

That one command:

- picks the next build number (one past both the project and the live feed)
  and commits it as `1.1 build 6`;
- archives a Release build, exports it signed with Developer ID, sends it
  to Apple for notarization, staples the ticket, and zips it
  (`scripts/notarize.sh`);
- signs the zip with Dict's Sparkle key (keychain account `dict`);
- pushes the version commit and creates the GitHub release `v1.1-6` on it
  with the disk image, the zip and your notes (GitHub makes the tag);
- adds the version to `appcast.xml`, commits `release: 1.1 build 6`, and
  pushes `main`. This push is the moment users see the update.

`DRY_RUN=1 make publish NOTES=...` does everything except the commits, the
upload, and the push, and leaves the feed it would publish in
`build/publish/appcast.xml`. Run it before the first real release.

## One-time setup

- **Notarization credentials.** `fastlane/.env` (gitignored) holds an App
  Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`
  (absolute path to the `.p8`). The same key works for every app on the
  team.
- **Sparkle key.** The private signing key lives in the login keychain
  under the account `dict`; the public half is in `Dict-app/Info.plist`
  as `SUPublicEDKey`. Back the private key up (1Password) with:

  ```bash
  vendor/sparkle/bin/generate_keys --account dict -x ~/Desktop/dict-sparkle-key.txt
  ```

  then delete the file. On a new Mac, import it with
  `generate_keys --account dict -f dict-sparkle-key.txt`. Without this key
  no future update can be signed, and existing users stay where they are.
- **Sparkle tools.** `scripts/sparkle-tools.sh` fetches `sign_update` and
  friends into `vendor/sparkle` (gitignored). `make publish` runs it.

## Other targets

- `make build` and `make test`: Debug build and unit tests. `make test E2E=1`
  also runs the Parakeet end-to-end test, which needs the 500 MB model.
- `make install`: Release build copied to `/Applications/Dict.app`.
- `make notarize`: just the signed, notarized zip in `build/notarized/`,
  without publishing anything.

## If something goes wrong

- **Notarization rejected.** The script prints Apple's log. Usual causes:
  an unsigned helper, or a missing hardened-runtime entitlement. Fix, then
  rerun `make publish` (the version commit from the failed run is still
  there; `git reset --soft HEAD~1` first if you'd rather fold it in).
- **Release created but the push failed.** The zip is up and `appcast.xml`
  is committed locally. Run `git push origin main`.
- **Sparkle says the update can't be verified.** The zip was signed with a
  different key than the `SUPublicEDKey` in the app people have. Don't
  rotate keys; restore the backed-up private key.
- **Never push `appcast.xml` pointing at a release that doesn't exist.**
  `publish.sh` orders the steps so this can't happen on its own.

## Downloads and CI

`make publish` attaches two files to the GitHub release: `Dict-<v>-<b>.dmg`,
the download for people (a disk image with a drag-to-Applications window,
signed and notarized), and `Dict-<v>-<b>.zip`, which only the Sparkle feed
points at. `make dmg` builds an unsigned image of the local Release build
for a look at the window; `scripts/dmg.sh` lays it out with dmgbuild in a
venv under `vendor/`.

Every push to `main` and every pull request builds and runs the unit tests
on GitHub Actions (`.github/workflows/ci.yml`, a `macos-26` runner with
the newest Xcode it has; the one macOS 27 API Dict uses is behind a
Swift version check so Xcode 26 builds it too). The Parakeet end-to-end test and the Apple Speech session test
need a model and a microphone, so CI skips them.
