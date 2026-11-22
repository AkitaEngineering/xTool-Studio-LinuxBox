# xTool Studio LinuxBox

Run the Windows edition of xTool Studio on x86-64 Linux with Wine, Distrobox, and Podman. FreeBSD has a separate native Wine install path.

**xTool Studio LinuxBox is an [Akita Engineering](https://www.akitaengineering.com) project.** xTool publishes and supports xTool Studio for Windows and macOS. LinuxBox provides community compatibility for Linux and FreeBSD. [xTool system requirements](https://support.xtool.com/article/2403)

[Download the latest release](https://github.com/AkitaEngineering/xTool-Studio-LinuxBox/releases/latest) · [Troubleshooting](docs/troubleshooting.md) · [Changelog](CHANGELOG.md)

## Before you install

| Host | What you need |
| --- | --- |
| **Linux x86-64** | Bash, curl, Podman, Distrobox, and an X11 or XWayland desktop session. LinuxBox sets up Wine 10 or newer inside Ubuntu 24.04 and uses WineHQ when it needs to install Wine. |
| **FreeBSD amd64** | Bash, curl, `pkg`, and a working `doas` or `sudo` configuration. Install Bash and curl with `pkg install bash curl` as root, then run LinuxBox as your regular user. FreeBSD uses Wine from `pkg`. |

Allow several GiB of free space for the container, Windows installer, and extracted app. For NVIDIA on Linux, install `nvidia-container-toolkit` and make sure Podman can find an NVIDIA CDI spec under `/etc/cdi` or `/var/run/cdi`. AMD and Intel use the host's graphics drivers. Choose **Software rendering** if you lack GPU access. Some xTool Studio versions render their first-run screens more reliably with a GPU.

## Install and launch

1. Download and extract **Source code (tar.gz)** from the [release page](https://github.com/AkitaEngineering/xTool-Studio-LinuxBox/releases/latest). If you use Git, clone the release with `git clone --branch v1.0.0 https://github.com/AkitaEngineering/xTool-Studio-LinuxBox.git`.
2. From a terminal in the extracted or cloned folder, run the following as your regular user.

   ```sh
   ./install.sh --check
   ./install.sh
   ```

   To preview the setup without any downloads or file changes, run `./install.sh --dry-run --yes`. Fish users can also run `./install.fish` with the same options.

3. Choose your GPU when prompted. On Linux, keep the default **Ubuntu 24.04** image unless you want to build a local image.
4. Open **xTool Studio** from your app menu. Complete xTool's first-run questions in the app. If the Windows installer opens instead, complete it and open **xTool Studio** again.

The installer looks for the newest x64 Windows installer linked in xTool's release notes. If the lookup fails, it uses the bundled fallback URL for xTool Studio 1.6.6. To choose a specific version, get its Windows installer URL from xTool and pass it with `--url` or set `XTOOL_URL`. [xTool release notes](https://support.xtool.com/article/1773)

## Installer options

| Option | What it does |
| --- | --- |
| `--help`, `-h` | Show available options. |
| `--check` | Check host prerequisites. Missing requirements produce a nonzero exit status. |
| `--dry-run` | Preview changes without downloads, file writes, or removals. |
| `--non-interactive`, `--yes`, `-y` | Use the installer defaults unless you supply options. Package tools may still ask for a password. |
| `--gpu 1-4` | Select NVIDIA (1), AMD (2), Intel (3), or software rendering (4). |
| `--image-source 1-2` | Linux only. Use stock Ubuntu (1) or build a local image (2). |
| `--container-name NAME` | Linux only. Choose a container name. The default is `xtool-studio`. Names can differ while the Wine data is shared. |
| `--url URL` | Download a specific x64 Windows installer. Overrides `XTOOL_URL`. |
| `--log-file PATH` | Choose where to write the setup log. The parent directory must exist. |
| `--uninstall` | Run the uninstaller with the selected container name, logging, and preview options. |

Linux terminal launch, using the default container name

```sh
distrobox enter --no-workdir xtool-studio -- /usr/local/bin/xToolStudio
```

FreeBSD terminal launch

```sh
"$HOME/.local/bin/xToolStudio"
```

## Upgrade or remove LinuxBox

Download the new LinuxBox release and rerun `./install.sh` from its folder. On Linux the installer replaces the named container. The Wine prefix and cached installer live in your home directory and carry over from **xTool Studio Cachy Box**.

Run `./uninstall.sh` or `./uninstall.fish` to remove the launcher and setup files. On Linux, this also removes the selected Distrobox container and tries to remove unused LinuxBox images. The uninstaller asks whether to delete the Wine prefix and cached Windows installer. The default is to keep them. Add `--yes` to keep them and skip the question, `--dry-run` to preview removal, or `--container-name NAME` if you used a custom name.

| Location | Contents |
| --- | --- |
| `~/.local/share/xtool-studio/` | Wine prefix, app files, and cached Windows installer. |
| `~/.cache/xtool-studio-cachy-box/` | Setup files and logs. The original directory name is retained for upgrades. |

## Compatibility and support

USB, network discovery, and cameras depend on your xTool model and host configuration. See the [troubleshooting guide](docs/troubleshooting.md) for first-run display issues, device connectivity, logs, and bug reports. The separate [legacy Compose workflow](docs/compose.md) has its own limitations.

LinuxBox's scripts and configuration are MIT-licensed. The Windows installer is downloaded from xTool and is governed by xTool's terms. [License](LICENSE.md) · [Attribution](docs/attribution.md) · [Shouts out](Shouts_Out.md)
