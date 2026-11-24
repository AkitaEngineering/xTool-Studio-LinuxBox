# Changelog

## Unreleased

- The installer stays on xTool Studio 1.9.11. `--experimental` downloads the newest Windows build, and the 1.9.11 archive patch is not applied to other builds.
- xTool Studio 1.11 launches without the 1.9.11 graphics overrides so its country window can open.

## 1.1.0 · 2026-11-22

- Scripts and configuration are licensed under GPL-3.0-only. Installer behavior is unchanged. The v1.0.0 tag remains under the MIT license. Upstream portions from Sascha Schüller keep the MIT notice in `LICENSES/MIT.txt`.

## 1.0.0 · 2026-11-22

First official Akita Engineering release. The project is now **xTool Studio LinuxBox**, formerly **xTool Studio Cachy Box**.

- Linux setup uses an Ubuntu 24.04 Distrobox with Podman and WineHQ when needed. FreeBSD uses native Wine from `pkg`.
- The launcher includes rendering and window workarounds for xTool Studio 1.9.11 first-run dialogs.
- The Bash and Fish entry points provide help, prerequisite checks, and read-only install and uninstall previews.
- Uninstallation removes the selected container and preserves Wine data by default. Setup and runtime data retain their existing locations for upgrades.
- The release source contains the LinuxBox automation. The installer fetches the xTool Studio Windows build from the vendor.

See the [installation guide](README.md) and [troubleshooting guide](docs/troubleshooting.md).
