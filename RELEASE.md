# Release Plan (bootstrap + full dist)

Goal: ship a standalone zig bootstrap binary that delegates to a full script
distribution when `sayt.nu` is not colocated, while keeping standalone binaries
for wrappers (`saytw`, `saytw.ps1`).

## Current design

- `sayt` bootstrap checks for `sayt.nu` next to itself (or one directory up).
- If present, it runs `mise tool-stub nu.toml sayt.nu`.
- If not present, it writes an embedded tool-stub into the cache and runs it:
  - Stub points to release assets named:
    - `sayt-linux-x64.tar.gz`
    - `sayt-linux-arm64.tar.gz`
    - `sayt-linux-armv7.tar.gz`
    - `sayt-macos-x64.tar.gz`
    - `sayt-macos-arm64.tar.gz`
    - `sayt-windows-x64.zip`
    - `sayt-windows-arm64.zip`
  - `bin = "sayt"` for non-Windows, `bin = "sayt.exe"` for Windows.
- Version pinning is embedded in:
  - `plugins/sayt/sayt.zig` (`DEFAULT_VERSION`).
  - `plugins/sayt/saytw` and `plugins/sayt/saytw.ps1` (default `SAYT_VERSION`).

## Release assets (GitHub Actions)

Release should publish both:

1) Standalone zig binaries (existing):
   - `sayt-linux-x64`, `sayt-linux-arm64`, `sayt-linux-armv7`
   - `sayt-macos-x64`, `sayt-macos-arm64`
   - `sayt-windows-x64.exe`, `sayt-windows-arm64.exe`

2) Full dist archives (new):
   - `sayt-<os>-<arch>.tar.gz` or `.zip` for Windows.
   - Each archive includes:
     - `sayt` (or `sayt.exe`) bootstrap binary
     - `sayt.nu`, `tools.nu`, `dind.nu`, `config.cue`
     - `nu.toml`, `docker.toml`, `uvx.toml`, `cue.toml`, `.mise.toml`

## Implementation status

- `plugins/sayt/sayt.zig` now embeds the full-dist tool-stub and no longer
  uses a `.version` file.
- `plugins/sayt/.github/workflows/release.yml` builds the full dist archives.
- `saytw` / `saytw.ps1` normalize and export `SAYT_VERSION` (default `v0.0.10`).

## Remaining steps to validate

1) Build locally (if Zig permissions allow):
   - `zig build` in `plugins/sayt`
   - If Homebrew Zig fails with permissions, try:
     - `mise exec zig@0.15.2 -- zig build`

2) Verify runtime flows:
   - With colocated scripts:
     - Use a full dist archive and run `./sayt --help` to ensure it executes
       `sayt.nu` via `mise tool-stub`.
   - Without colocated scripts:
     - Use a standalone binary (downloaded by `saytw`), run `./sayt --help`,
       and verify it pulls the full dist archive and delegates correctly.

3) Tag and release:
   - Create tag `vX.Y.Z`.
   - Confirm release assets include both standalone binaries and full dist
     archives.
