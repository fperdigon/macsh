# Changelog

All notable changes to macsh are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **WebDAV / Nextcloud / ownCloud backend.** Mount any WebDAV server; the
  password (use an app password for Nextcloud) is kept in the Keychain and
  passed to rclone through the environment, never written to the config.
- **Google Drive backend.** Sign in through the browser (`rclone authorize drive`);
  choose full, read-only or per-file access, a shared drive or root folder, and
  optionally your own OAuth client ID/secret. Google Docs/Sheets/Slides appear as
  exported Office files (rclone's default).
- **OAuth sign-in framework.** The token is stored in the Keychain, handed to rclone
  through the environment, and any token rclone refreshes while mounted is written
  back to the Keychain when the mount ends.

- **In-app updates with a stable/nightly choice.** Settings -> Updates picks the channel
  (tagged releases, or the per-commit nightly builds) and whether to check once a day;
  "Check for updates..." downloads the DMG for your flavor (macsh or macsh-lite), checks its
  SHA-256, swaps the app in place and relaunches. Builds now embed their commit so a nightly
  knows whether it is current. Updates come from `fperdigon/macsh` releases.
- **SMB / Windows shares (NAS, Samba)** as a backend, with host, port, user, password, optional
  domain and the share name as the folder; also importable from rclone.conf.
- **Test connection.** A button in the Add/Edit window checks the form's values against
  the server (without saving or mounting) and explains failures: wrong password, host
  unreachable, folder or bucket not found, untrusted certificate.
- **Import from rclone.conf.** "Import from rclone…" in the menu reads your existing
  rclone config (SFTP, S3, FTP, WebDAV/Nextcloud, Google Drive), reveals the saved
  passwords once and stores them in the Keychain. S3 remotes ask for a bucket; other types
  (crypt, alias, ...) are listed as not supported yet.
- **Read-only mounts** and an optional **bandwidth limit** per remote (any backend).

### Changed

- **Generic backend model.** New rclone backends are declared as data
  (`BackendDescriptor`) and stored as `Backend.rclone`, so adding one no longer
  needs new `switch` arms in `SessionManager` or a hand-written form.
  Existing SFTP / S3 / FTP remotes and `remotes.json` are unchanged.

### Fixed

- **Nightly builds publish again.** The rolling `nightly` release could not be recreated once
  GitHub's immutable releases were on ("tag_name was used by an immutable release"), so every
  build after the first failed. Each push to `main` now publishes its own
  `nightly-YYYYMMDD-<sha>` pre-release.
- Deleting an S3 remote now also removes its Keychain items.

## [0.1.3] — 2026-10-16

### Added

- **Per-remote performance settings.** Cache mode, read-ahead, buffer size,
  max cache size, directory-cache time and write-back delay can be tuned per
  remote and are validated before saving.
- **Faster NFS.** NFS remotes default to a full read cache with read-ahead and
  a 1s write-back (measured ~2.5 MB/s with `writes` vs ~17 MB/s).
- **GitHub Actions CI** (build, test, coverage report) and a **release
  workflow**: a `v*` tag publishes a release with DMGs and a commit list, and
  every push to `main` refreshes a rolling `nightly` pre-release whose notes
  keep a running change history.
- **Test coverage of `MacshCore` raised from ~13% to ~89%** (SessionManager,
  Mounter, RcloneProcess, HostKeyVerifier, config building and more).

### Changed

- NFS remotes now mount under `~/macsh/<name>` instead of the root-owned
  `/Volumes`.
- Mounting and unmounting no longer block the main thread, so the menu bar
  item stays responsive; a second mount request while one is in flight is
  ignored. rclone gets up to 30s to start listening and is cleaned up on
  failure.
- Editing an SFTP remote shows the saved key file path.

### Fixed

- The SFTP key passphrase is now passed to rclone.
- Mount errors are readable (with the tail of the rclone log) and key files
  are validated up front.
- Unmounting something already unmounted (ejected in Finder, rclone killed) is
  treated as success instead of an error.
- The whole Settings tab button is clickable, not just its label.

## [0.1.1] — 2026-05-04

### Fixed

- **Crash-recovery: no more duplicate `/Volumes/<name>-1`, `<name>-2`
  pileups.** When macsh died ungracefully (SIGKILL, force-quit, crash),
  its child `rclone serve` process and the corresponding `/Volumes/`
  mount survived. On next launch, `autoMountAll` would mount again,
  and NetFS auto-numbered the colliding name. Each subsequent launch
  added another duplicate.

  Startup now reconciles: for each remote, parses `mount` output for an
  existing `/Volumes/<name>` mounted from `http://127.0.0.1:<port>/...`,
  unmounts it, and SIGTERMs the orphan rclone matched by `--addr` port.
  Per-port matching keeps it safe for `macsh-lite` users who may have
  unrelated rclone processes running.

  Verified end-to-end: launch → mount → `kill -9` → relaunch → single
  `/Volumes/<name>`, single rclone child.

## [0.1.0] — 2026-05-04

Initial public release.

### Added

- SFTP/SSH backend: password, existing key file, app-generated ed25519.
- S3-compatible backend: AWS, Cloudflare R2, Backblaze B2, Wasabi,
  MinIO, DigitalOcean Spaces, custom endpoint.
- FTP / FTPS backend: off / explicit / implicit TLS.
- WebDAV mount transport via Apple's `NetFS.framework`
  (`NetFSMountURLSync`). NFS mount transport via `/sbin/mount_nfs`.
  Per-remote toggle plus a global default in Settings.
- Live-updates toggle: when on, rclone serves with
  `--dir-cache-time 10s --vfs-fast-fingerprint` so server-side changes
  appear in ~10 seconds instead of rclone's 5-minute default.
- Edit existing remotes (disabled while mounted). Backend type is
  locked on edit; password fields stay blank with "leave blank to keep"
  semantics.
- Custom rclone path field in Settings — overrides the bundled binary
  for users who want to point at a specific install.
- Login items via `SMAppService.mainApp`. Auto-mount remotes flagged
  `autoMount=true` with exponential backoff (1s → 5s → 30s → 5min cap).
- Host-key TOFU: `ssh-keyscan` on first connect with fingerprint
  confirmation; loud blocking warning if a known key changes.
- Per-remote tailing log window.
- Two build variants from one source tree:
  - `macsh` — bundles `rclone` in `Resources/` (~32 MB DMG).
  - `macsh-lite` — uses `brew install rclone` or any PATH rclone (~600 KB DMG).
- `scripts/build-release.sh` produces both DMGs unsigned, ready to
  upload to GitHub Releases.

### Notes

- Apple Silicon only (arm64). Intel Macs not supported.
- macOS 14 (Sonoma) deployment target.
- Releases are unsigned. First-launch requires
  `xattr -dr com.apple.quarantine /Applications/macsh.app` to clear
  Gatekeeper. Notarized signing is a planned follow-up.

[0.1.1]: https://github.com/AyonPal/macsh/releases/tag/v0.1.1
[0.1.0]: https://github.com/AyonPal/macsh/releases/tag/v0.1.0
