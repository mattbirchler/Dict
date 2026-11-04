# Releasing Dict

Dict ships outside the App Store. This repo (the code) is private. The
public repo [mattbirchler/Dict-releases](https://github.com/mattbirchler/Dict-releases)
holds everything people download: the notarized disk image and zip on its
GitHub Releases, `appcast.xml` (the Sparkle feed running copies check),
the public README, and `PRIVACY.md`. `make publish` keeps a clone of it in
`build/releases-repo`.

Sales and license keys are covered in [SELLING.md](SELLING.md).

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
- tags the version commit `v1.1-6` and pushes it here;
- creates the GitHub release `v1.1-6` on Dict-releases with the disk
  image, the zip and your notes;
- adds the version to Dict-releases' `appcast.xml`, commits
  `release: 1.1 build 6`, and pushes it. This push is the moment users see
  the update;
- while this repo still has its own `appcast.xml` (see below), adds the
  version there too and pushes `main`.

`DRY_RUN=1 make publish NOTES=...` does everything except the commits, the
upload, and the push, and leaves the feed it would publish in
`build/publish/appcast.xml`. Run it before the first real release.

## Making this repo private

Copies of Dict 1.0 (build 4 and earlier) check
`raw.githubusercontent.com/mattbirchler/Dict/main/appcast.xml`, which stops
working the moment this repo goes private. Copies built from now on check
Dict-releases instead. So, in this order:

1. Ship the first version with licensing through `make publish` while this
   repo is still public. It lands in both feeds.
2. Wait for those copies to update. Sparkle checks once a day, so most
   update within a week or two. Copies that never update keep working;
   they just won't hear about updates.
3. Delete `appcast.xml` here, commit, and push. `make publish` notices and
   only updates Dict-releases from then on.
4. Make the repo private: `gh repo edit mattbirchler/Dict --visibility private --accept-visibility-change-consequences`.

The old releases on this repo (1.0 build 4) were copied to Dict-releases,
so download links keep working.

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
- **Release created but the push failed.** The zip is up and the feed is
  committed locally. Run `git -C build/releases-repo push origin main` (and
  `git push origin main` here, while the old feed exists).
- **Sparkle says the update can't be verified.** The zip was signed with a
  different key than the `SUPublicEDKey` in the app people have. Don't
  rotate keys; restore the backed-up private key.
- **Never push `appcast.xml` pointing at a release that doesn't exist.**
  `publish.sh` orders the steps so this can't happen on its own.

## Downloads and CI

`make publish` attaches two files to the Dict-releases GitHub release: `Dict-<v>-<b>.dmg`,
the download for people (a disk image with a drag-to-Applications window,
signed and notarized), and `Dict-<v>-<b>.zip`, which only the Sparkle feed
points at. `make dmg` builds an unsigned image of the local Release build
for a look at the window; `scripts/dmg.sh` lays it out with dmgbuild in a
venv under `vendor/`.

Every push to `main` and every pull request builds and runs the unit tests
on GitHub Actions (on a private repo, macOS minutes count against the
account's Actions allowance at 10x) (`.github/workflows/ci.yml`, a `macos-26` runner with
the newest Xcode it has; the one macOS 27 API Dict uses is behind a
Swift version check so Xcode 26 builds it too). The Parakeet end-to-end test and the Apple Speech session test
need a model and a microphone, so CI skips them.
