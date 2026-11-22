# Troubleshooting xTool Studio LinuxBox

## Setup stops before xTool Studio appears

1. Run `./install.sh --check` and resolve any missing prerequisites.
2. Review `~/.cache/xtool-studio-cachy-box/install.log` or the file you passed to `--log-file`. Start with the first error in the latest attempt.
3. Use the stock Ubuntu image if a custom image build fails. The setup retries a failed container setup once with alternate DNS. If an xTool download or extraction fails, confirm that the installer URL points to the **x64 Windows** release. [xTool release notes](https://support.xtool.com/article/1773)

On Linux, NVIDIA requires a working host driver and Podman CDI configuration. If you use the stock Ubuntu image and WineHQ package installation fails, check access to `dl.winehq.org` and look for errors from Ubuntu's i386 packages. Red `fchownat() … Operation not permitted` lines for host `/dev` nodes can be informational if setup continues successfully.

## App menu entry opens no window

On Linux, launch from a terminal to see Wine output. Replace `xtool-studio` with the container name you installed.

```sh
distrobox enter --no-workdir xtool-studio -- /usr/local/bin/xToolStudio
```

On FreeBSD, run `"$HOME/.local/bin/xToolStudio"`. For app-menu launches on either system, check `~/.cache/xtool-studio-cachy-box/launch.log`.

## xTool Studio 1.9.11 has a blank or clipped first-run window

- Use your NVIDIA, AMD, or Intel graphics option. Software rendering can open a blank country window. Allow about 15 seconds for the dialog to paint.
- Rerun the current LinuxBox installer if you upgraded from an older checkout. The launcher log should show `Wine: wine-10` or later on Linux. Ubuntu's stock Wine 9 can crash when opening this dialog.
- Complete the country, privacy, and improvement-plan dialogs in xTool Studio. If Confirm is clipped, resize or maximize the dialog. LinuxBox applies a window-size workaround on GNOME-family desktops.
- If the Start Page is blank after you select a country, close and reopen xTool Studio. The launcher uses ANGLE GL for the Start Page once a country is saved. If the top of a maximized window is clipped on GNOME, check for `Decorated=N (GNOME-family compositor)` in the launch log.

## xTool Studio cannot find a device

Windows prompts to install RNDIS or CH340 drivers refer to Windows USB helpers. On Linux, device access depends on the host kernel driver, USB permissions, and the xTool model. A device may use Linux modules such as `cdc_ether` or `ch341`. Cameras and network discovery can also behave differently under Wine.

## Report an issue

Include the LinuxBox release tag, your OS and desktop session (X11 or Wayland), GPU, xTool Studio version, and the steps up to the error. For device issues, add the machine model and how it connects. Paste the relevant part of the setup or launch log after removing private paths, device identifiers, and account details. [GitHub issues](https://github.com/sh4un-dot-com/xTool-Studio-LinuxBox/issues)
