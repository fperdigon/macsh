# AGENTS.md

Guidance for anyone working on this repo: people and coding agents (Claude Code, Codex,
Copilot, Cursor, ...). Read it before changing code.

## What this is

macsh is a macOS (14+, Apple Silicon) menu-bar app that mounts remote storage as local
volumes without macFUSE. It wraps [rclone](https://rclone.org): for each remote it starts
`rclone serve webdav|nfs` on localhost and mounts that (WebDAV via NetFS, NFS via
`mount_nfs` under `~/macsh/<name>`). Backends today: SFTP, S3-compatible, FTP/FTPS,
WebDAV/Nextcloud and Google Drive (the generic `Backend.rclone` model; OAuth sign-in via
`OAuthAuthorizer`).

## Layout

- `Sources/MacshCore/` – all logic, no UI. Swift package (tools 5.9, links NetFS/Security).
  - `Models/` backend + remote models, `BackendDescriptor` (declarative backends)
  - `Rclone/` config builder, rclone process management
  - `Mount/` NetFS / `mount_nfs`; `Session/SessionManager` orchestrates mount/unmount
  - `Storage/` Keychain, `remotes.json`; `SSH/` host keys and key generation
- `App/macsh/` – SwiftUI app, generated with xcodegen from `App/project.yml`
  (flavors `macsh` with bundled rclone and `macsh-lite`).
- `Tests/MacshCoreTests/` – unit and integration tests.
- `scripts/` – release build; `scripts/ci/` – servers used by the integration CI jobs.
- `.github/workflows/` – `ci.yml` (build, tests, coverage, integration), `release.yml`.

## Build and test

macOS only (Security, NetFS, SwiftUI); it does not compile on Linux.

```
swift build
swift test                       # unit tests; integration tests skip themselves
swift test --enable-code-coverage
```

Integration tests are gated by `MACSH_IT_*` environment variables and are normally run by
CI (see below). Do not commit changes you could not compile or test; if you work in an
environment without macOS, open a PR and let CI be the judge.

## Ways of working

- Develop on a branch, open a PR against `main` on this repo, and keep CI green.
  CI runs on every PR and on pushes to `main`.
- Every push to `main` refreshes the rolling `nightly` pre-release. A `v*` tag publishes a
  release; the tag must match `CFBundleShortVersionString` in
  `App/macsh/Resources/Info.plist` and `Info-Lite.plist`.
- Update `CHANGELOG.md` (Keep a Changelog format, `[Unreleased]` section) for user-visible
  changes. Update the README when adding a backend.
- Commit messages: short imperative subject, explain the why in the body.
- Keep changes focused; do not refactor unrelated code in a feature PR.

## Code conventions

- Secrets (passwords, keys, tokens) live in the Keychain and reach rclone only through
  `RCLONE_CONFIG_R_<OPTION>` environment variables. They must never be written to the
  temporary rclone config, `remotes.json`, logs or error messages.
- Anything that blocks (rclone start-up, host-key scan, NetFS, `mount_nfs`) runs off the
  main thread; only state changes and dialogs use it.
- New backends are declared as data: add a `BackendDescriptor` (fields, which are secret)
  rather than another `Backend` case plus `switch` arms. See `BackendDescriptor.webdav`.
- Existing `remotes.json` files and Keychain items must keep working: decode tolerantly and
  do not rename stored keys.
- Match the surrounding style, naming and comment density.

## Testing rules

1. **Unit tests for all new logic**, using the helpers in `Tests/MacshCoreTests/TestSupport.swift`
   (`FakeRclone`, `FakeMounter`, temp dirs). Fix tests you break; never skip or delete a
   test to get green.
2. **Every backend must be tested for real in the CI pipeline.** A backend is not done until a
   CI job starts a real server of that kind and an integration test drives macsh's own
   pipeline against it: `SessionManager.add` -> `mount` (real rclone, real `Mounter`) ->
   write a file through the mount -> verify it arrived on the server -> `unmount`. Cover
   both mount protocols (NFS and WebDAV) and every auth method the backend offers (e.g.
   password, key file, generated key). Do not bypass macsh by calling the rclone CLI.
   - Servers are started by scripts in `scripts/ci/` and exported as `MACSH_IT_*`
     variables. Docker/Podman cannot run on Apple Silicon runners (no nested
     virtualization), so run servers natively (PHP for Nextcloud, small Python servers,
     `rclone serve`, ...).
   - Use `IntegrationHarness.roundTrip` and `IntegrationEnv.require` from
     `IntegrationSupport.swift`; tests skip when their variables are unset.
   - Current coverage: SFTP, FTP, S3 (`BackendIntegrationTests`) and Nextcloud/WebDAV
     (`NextcloudIntegrationTests`), plus Google Drive (`GoogleDriveIntegrationTests`, needs the
     `MACSH_IT_GDRIVE_TOKEN` repository secret; they skip without it). Known gaps: FTPS/TLS, passphrase-protected keys, real
     cloud providers (OAuth backends such as Google Drive will need a stand-in server or
     a test-account secret; document the choice in the PR).
3. Keep coverage of `MacshCore` from dropping (it is ~89% lines); the report is in the CI job
   summary.
4. Real-world checks that CI cannot do (Finder behaviour, a real provider account) are
   listed in the PR description as manual steps.

## Things to avoid

- Don't add dependencies without a reason; the core is dependency-free.
- Don't weaken host-key verification or certificate checks to make a test pass.
- Don't push tags or release from automation without the maintainer asking.
- Don't commit secrets, signing material or `.build/`.
