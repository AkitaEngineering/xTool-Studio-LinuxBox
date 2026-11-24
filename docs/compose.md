# Legacy Podman Compose workflow

The [main installer](../README.md#install-and-launch) sets up WineHQ, applies first-run compatibility fixes, and exports an app-menu entry. The Linux-only Compose configuration uses the Ubuntu Wine packages in its containerfile and runs xTool Studio directly in the foreground. xTool Studio 1.9.11 can fail during first run on this older Wine. The configuration uses privileged container access and mounts your home directory read/write. It shares the Wine prefix and download cache used by the main installer.

With Podman, a Compose provider, and a running desktop session, use the following commands from the repository folder.

```sh
podman compose config --quiet
podman compose up --build
```

Set `XTOOL_CONTAINERFILE` and `XTOOL_IMAGE` to select a different local build. The default is `containerfile.amd` with image name `xtool-custom-amd`. With no `XTOOL_URL`, Compose downloads xTool Studio 1.9.11. Set `XTOOL_EXPERIMENTAL=1` to download the newest Windows build instead. That build is experimental and may not start. Set `XTOOL_URL` to an x64 Windows installer URL to choose one version. The first run may show the Windows installation wizard.

Run `podman compose down` from the same folder to stop and remove the container. The Wine prefix and cached installer remain in `~/.local/share/xtool-studio/`. Compose also writes a launcher to `~/.local/bin/xToolStudio`.
