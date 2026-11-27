#!/usr/bin/env python3
# Copyright (c) 2026 Akita Engineering
# SPDX-License-Identifier: GPL-3.0-only
"""Exercise payload upgrades and launchers without installing Wine or containers."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
GATE_SUFFIX = "movable:!0,webPreferences:{nodeIntegration:!0,contextIsolation:!1,webSecurity:!1}"
HIDDEN_GATE = "show:!1,frame:!1," + GATE_SUFFIX
SHOWN_GATE = "show:!0,frame:!0," + GATE_SUFFIX
WINDOW_CODE = "\n".join([
    HIDDEN_GATE,
    HIDDEN_GATE,
    "Start Page - xTool Studio`,frame:!1",
    "resizable:!1,transparent:!0,roundedCorners:!1",
])


def make_asar(version, source=WINDOW_CODE):
    package = json.dumps({"name": "xtool-studio", "version": version}).encode()
    script = source.encode()
    header = json.dumps({"files": {
        "package.json": {"size": len(package), "offset": "0"},
        "main.js": {"size": len(script), "offset": str(len(package))},
    }}).encode()
    padded = header + b"\0" * (-len(header) % 4)
    header_size = 8 + len(padded)
    return struct.pack("<4I", 4, header_size, header_size - 4, len(header)) + padded + package + script


TOOL_STUB = r'''
import json
import os
from pathlib import Path
import shutil
import sys
import time

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["XTOOL_TEST_CALLS"], "a") as log:
    log.write(json.dumps({"tool": tool, "args": args,
                          "winearch": os.environ.get("WINEARCH"),
                          "overrides": os.environ.get("WINEDLLOVERRIDES")}) + "\n")
if tool == "wine":
    if args == ["--version"]:
        print(os.environ.get("XTOOL_TEST_WINE_VERSION", "wine-11.0"))
    elif args[:1] == ["start"]:
        sys.exit(int(os.environ.get("XTOOL_TEST_LAUNCH_STATUS", "0")))
elif tool == "wineboot":
    sys.exit(int(os.environ.get("XTOOL_TEST_WINEBOOT_STATUS", "0")))
elif tool == "curl":
    destination = Path(args[args.index("-o") + 1])
    destination.write_bytes(b"partial" if os.environ.get("XTOOL_TEST_FAIL_DOWNLOAD") else b"installer")
    pause = os.environ.get("XTOOL_TEST_PAUSE_DOWNLOAD")
    while pause and Path(pause).exists():
        time.sleep(0.02)
    sys.exit(22 if os.environ.get("XTOOL_TEST_FAIL_DOWNLOAD") else 0)
elif tool == "7z":
    destination = Path(next(arg[2:] for arg in args if arg.startswith("-o")))
    if os.environ.get("XTOOL_TEST_FAIL_EXTRACT"):
        destination.mkdir(parents=True, exist_ok=True)
        sys.exit(2)
    if Path(args[2]).name == "app-64.7z":
        shutil.copytree(os.environ["XTOOL_TEST_PAYLOAD"], destination, dirs_exist_ok=True)
    else:
        archive = destination / "$PLUGINSDIR/app-64.7z"
        archive.parent.mkdir(parents=True)
        archive.write_bytes(b"archive")
elif tool == "pgrep":
    sys.exit(1)
elif tool == "id":
    print("1000" if args == ["-u"] else "tester")
elif tool == "uname":
    print(os.environ.get("XTOOL_TEST_OS", "Linux") if args == ["-s"] else "x86_64")
elif tool == "mv":
    if os.environ.get("XTOOL_TEST_FAIL_PROMOTE") and Path(args[-2]).name == "app":
        sys.exit(1)
    os.execv(os.environ["XTOOL_TEST_REAL_MV"], ["mv", *args])
elif tool == "distrobox":
    state = Path(os.environ["XTOOL_TEST_STATE"])
    if args == ["list", "--no-color"]:
        print("ID | NAME | STATUS | IMAGE")
        if state.exists():
            print("123 | xtool-studio | Up | ubuntu")
    elif args[:1] == ["create"]:
        state.touch()
    elif args[:1] == ["rm"]:
        state.unlink(missing_ok=True)
    elif args[:1] == ["enter"]:
        command = args[args.index("--") + 1:]
        if command[:1] == ["/bin/bash"]:
            attempt = state.with_suffix(".attempt")
            if os.environ.get("XTOOL_TEST_FAIL_SETUP_ONCE") and not attempt.exists():
                attempt.touch()
                sys.exit(1)
        elif command[:1] == ["distrobox-export"]:
            desktop = Path(os.environ["HOME"]) / ".local/share/applications/xtool-studio-xToolStudio.desktop"
            desktop.parent.mkdir(parents=True, exist_ok=True)
            desktop.write_text("[Desktop Entry]\nExec=/run/host/usr/bin/distrobox-enter -n xtool-studio -- /usr/local/bin/xToolStudio\nIcon=/run/host/icon.png\n")
elif tool == "podman":
    if args[:1] == ["images"]:
        print("localhost/xtool-custom-amd:latest")
'''


class RuntimeChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="xtool-runtime-")
        self.addCleanup(self.temp.cleanup)
        self.scratch = Path(self.temp.name)
        self.user_home = self.scratch / "home with spaces"
        self.bin = self.scratch / "bin"
        self.bin.mkdir()
        self.user_home.mkdir()
        self.calls_file = self.scratch / "calls.jsonl"
        self.env = dict(os.environ, HOME=str(self.user_home), USER="tester",
                        PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        DISPLAY="", XTOOL_TEST_CALLS=str(self.calls_file),
                        XTOOL_TEST_STATE=str(self.scratch / "container"),
                        XTOOL_TEST_REAL_MV=shutil.which("mv"))
        for key in ("XTOOL_URL", "XTOOL_FORCE_SOFTWARE_RENDERING", "WINEDLLOVERRIDES", "WINEARCH"):
            self.env.pop(key, None)
        for tool in ("wine", "wineboot", "wineserver", "curl", "7z", "pgrep", "id", "uname", "mv", "distrobox", "podman"):
            path = self.bin / tool
            path.write_text(f"#!{sys.executable}\n" + TOOL_STUB)
            path.chmod(0o755)
        self.app_home = self.user_home / ".local/share/xtool-studio"
        self.app = self.app_home / "prefix/drive_c/users/tester/AppData/Local/Programs/xTool Studio"
        self.fixture = self.scratch / "payload"
        self.write_app(self.fixture, "1.9.11")
        self.env["XTOOL_TEST_PAYLOAD"] = str(self.fixture)

    def write_app(self, destination, version):
        (destination / "resources").mkdir(parents=True, exist_ok=True)
        (destination / "xTool Studio.exe").write_bytes(b"exe-" + version.encode())
        (destination / "resources/app.asar").write_bytes(make_asar(version))

    def run_command(self, *args, **env):
        return subprocess.run(args, env=dict(self.env, **env), cwd=ROOT,
                              capture_output=True, text=True, timeout=15)

    def calls(self, tool):
        if not self.calls_file.exists():
            return []
        return [call for line in self.calls_file.read_text().splitlines()
                if (call := json.loads(line))["tool"] == tool]

    def install(self, **env):
        return self.run_command("bash", "-c", 'set -euo pipefail; source "$1"; xtool_install_payload',
                                "_", str(SCRIPTS / "install-payload.sh"),
                                XTOOL_URL="https://example.invalid/new.exe", **env)

    def seed_installation(self):
        self.write_app(self.app, "1.6.6")
        (self.app / ".linuxbox-source-url").write_text("https://example.invalid/old.exe\n")
        (self.app_home / "downloads").mkdir()
        (self.app_home / "downloads/xTool-Studio-setup.exe").write_bytes(b"old-installer")
        (self.app_home / "last-download-url").write_text("https://example.invalid/old.exe\n")

    def test_patch_is_idempotent_and_preserves_asar_version_and_size(self):
        archive = self.fixture / "resources/app.asar"
        before = archive.read_bytes()
        command = ("bash", "-c", 'source "$1"; xtool_patch_electron_startup "$2"',
                   "_", str(SCRIPTS / "install-payload.sh"), str(archive))
        result = self.run_command(*command)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        after = archive.read_bytes()
        self.assertEqual(len(before), len(after))
        self.assertEqual(after.count(SHOWN_GATE.encode()), 2)
        self.assertNotIn(HIDDEN_GATE.encode(), after)
        self.assertEqual(self.run_command(*command).returncode, 0)
        self.assertEqual(archive.read_bytes(), after)
        result = self.run_command("perl", str(SCRIPTS / "xtool-asar-version.pl"), str(archive))
        self.assertEqual(result.stdout.strip(), "1.9.11")

    def test_other_version_with_matching_window_signatures_is_preserved(self):
        self.write_app(self.fixture, "1.11.9")
        archive = self.fixture / "resources/app.asar"
        before = archive.read_bytes()
        result = self.run_command("bash", "-c", 'source "$1"; xtool_patch_electron_startup "$2"',
                                  "_", str(SCRIPTS / "install-payload.sh"), str(archive))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(archive.read_bytes(), before)

    def test_asar_reader_rejects_truncated_and_oversized_headers(self):
        archive = self.scratch / "invalid.asar"
        for contents in (b"invalid", make_asar("1.9.11")[:20], struct.pack("<4I", 4, 2**30, 2**30 - 4, 8)):
            with self.subTest(contents=contents):
                archive.write_bytes(contents)
                result = self.run_command("perl", str(SCRIPTS / "xtool-asar-version.pl"), str(archive))
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(result.stdout)

    def test_launcher_selects_flags_using_archive_version(self):
        for version in ("1.9.11", "1.11.9", "1.6.6"):
            with self.subTest(version=version):
                self.write_app(self.app, version)
                self.calls_file.unlink(missing_ok=True)
                result = self.run_command(str(SCRIPTS / "xtool-studio-launcher.sh"), "drawing with spaces.xcs")
                self.assertEqual(result.returncode, 0, result.stderr)
                start = next(call for call in self.calls("wine") if call["args"][:1] == ["start"])
                self.assertEqual(start["args"][-1], "drawing with spaces.xcs")
                self.assertEqual("--use-gl=angle" in start["args"], version == "1.9.11")
                self.assertEqual(start["winearch"], "win64")

    def test_old_wine_is_rejected_before_start(self):
        self.write_app(self.app, "1.9.11")
        result = self.run_command(str(SCRIPTS / "xtool-studio-launcher.sh"), XTOOL_TEST_WINE_VERSION="wine-9.0")
        self.assertEqual(result.returncode, 3)
        self.assertFalse(any(call["args"][:1] == ["start"] for call in self.calls("wine")))

    def test_launcher_preserves_explicit_dll_overrides(self):
        self.write_app(self.app, "1.6.6")
        for overrides, expected in (
            ("d3d11=n;mscoree=n;mshtml=n", "d3d11=n;mscoree=n;mshtml=n"),
            ("mscoree=n", "mscoree=n;mshtml="),
            ("mshtml=n", "mshtml=n;mscoree="),
            ("*MSCOREE,*mshtml=n,b", "*MSCOREE,*mshtml=n,b"),
        ):
            with self.subTest(overrides=overrides):
                self.calls_file.unlink(missing_ok=True)
                result = self.run_command(str(SCRIPTS / "xtool-studio-launcher.sh"), WINEDLLOVERRIDES=overrides)
                self.assertEqual(result.returncode, 0, result.stderr)
                start = next(call for call in self.calls("wine") if call["args"][:1] == ["start"])
                self.assertEqual(start["overrides"], expected)

    def test_prefix_setup_preserves_explicit_dll_overrides(self):
        result = self.install(WINEDLLOVERRIDES="*mscoree,*mshtml=n,b")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls("wineboot")[-1]["overrides"], "*mscoree,*mshtml=n,b")

    def test_download_and_extraction_failures_preserve_previous_installation(self):
        self.seed_installation()
        for failure in ("XTOOL_TEST_FAIL_DOWNLOAD", "XTOOL_TEST_FAIL_EXTRACT", "XTOOL_TEST_WINEBOOT_STATUS"):
            with self.subTest(failure=failure):
                result = self.install(**{failure: "1"})
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual((self.app / "xTool Studio.exe").read_bytes(), b"exe-1.6.6")
                self.assertEqual((self.app_home / "downloads/xTool-Studio-setup.exe").read_bytes(), b"old-installer")
                self.assertEqual((self.app_home / "last-download-url").read_text().strip(), "https://example.invalid/old.exe")
                self.assertFalse(list(self.app_home.glob(".install.??????")))

    def test_failed_promotion_restores_previous_app_and_can_be_retried(self):
        self.seed_installation()
        result = self.install(XTOOL_TEST_FAIL_PROMOTE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.app / "xTool Studio.exe").read_bytes(), b"exe-1.6.6")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.app / "xTool Studio.exe").read_bytes(), b"exe-1.9.11")

    def test_upgrade_and_cached_rerun(self):
        self.seed_installation()
        result = self.install(WINEARCH="win32")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls("wineboot")[-1]["winearch"], "win64")
        self.assertEqual((self.app / "xTool Studio.exe").read_bytes(), b"exe-1.9.11")
        self.assertEqual((self.app_home / "last-extracted-url").read_text().strip(), "https://example.invalid/new.exe")
        self.calls_file.unlink()
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.calls("curl"))
        self.assertFalse(self.calls("7z"))

    def test_concurrent_installation_cannot_mutate_shared_payload(self):
        self.seed_installation()
        with (self.app_home / ".install.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.install()
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse(self.calls("curl"))
            self.assertEqual((self.app / "xTool Studio.exe").read_bytes(), b"exe-1.6.6")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_payload_lock_lasts_until_the_installation_exits(self):
        self.seed_installation()
        pause = self.scratch / "pause-download"
        pause.touch()
        env = dict(self.env, XTOOL_URL="https://example.invalid/new.exe", XTOOL_TEST_PAUSE_DOWNLOAD=str(pause))
        process = subprocess.Popen(["bash", "-c", 'source "$1"; xtool_install_payload',
                                    "_", str(SCRIPTS / "install-payload.sh")], cwd=ROOT, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not self.calls("curl") and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(self.calls("curl"), "The first installer did not reach its download")
            result = self.install()
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((self.app / "xTool Studio.exe").read_bytes(), b"exe-1.6.6")
        finally:
            pause.unlink(missing_ok=True)
            output, error = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, output + error)
        self.assertEqual((self.app / "xTool Studio.exe").read_bytes(), b"exe-1.9.11")

    def compose_service(self):
        if not shutil.which("docker"):
            self.skipTest("Docker Compose is required for the legacy configuration checks")
        if self.run_command("docker", "compose", "version").returncode:
            self.skipTest("Docker Compose is unavailable")
        result = self.run_command("docker", "compose", "config", "--format", "json")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)["services"]["xtool-studio"]

    def test_compose_download_failure_preserves_the_shared_installer(self):
        self.seed_installation()
        command = self.compose_service()["command"][2].replace("$$", "$")
        result = self.run_command("bash", "-c", command, XTOOL_URL="https://example.invalid/new.exe",
                                  XTOOL_TEST_FAIL_DOWNLOAD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.app_home / "downloads/xTool-Studio-setup.exe").read_bytes(), b"old-installer")
        self.assertEqual((self.app_home / "last-download-url").read_text().strip(), "https://example.invalid/old.exe")
        self.assertFalse(list((self.app_home / "downloads").glob(".xtool-download.*")))

    def test_compose_cache_and_generated_launcher(self):
        self.seed_installation()
        command = self.compose_service()["command"][2].replace("$$", "$")
        result = self.run_command("bash", "-c", command, XTOOL_URL="https://example.invalid/new.exe")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        launcher = self.user_home / ".local/bin/xToolStudio"
        self.assertTrue(launcher.is_file())
        self.assertEqual(self.run_command("sh", "-n", str(launcher)).returncode, 0)
        self.assertEqual((self.app_home / "downloads/xTool-Studio-setup.exe").read_bytes(), b"installer")
        self.calls_file.unlink()
        result = self.run_command("bash", "-c", command, XTOOL_URL="https://example.invalid/new.exe")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.calls("curl"))

    def test_compose_supports_x11_and_maps_the_host_user(self):
        self.env.pop("WAYLAND_DISPLAY", None)
        self.env.pop("XDG_RUNTIME_DIR", None)
        self.env["XAUTHORITY"] = str(self.scratch / "session-cookie")
        service = self.compose_service()
        self.assertEqual(service["userns_mode"], "keep-id:uid=1001,gid=1001")
        auth_mount = next(volume for volume in service["volumes"] if volume["target"] == "/tmp/xtool-Xauthority")
        self.assertEqual(auth_mount["source"], self.env["XAUTHORITY"])
        self.assertTrue(auth_mount["read_only"])
        self.assertFalse(auth_mount["bind"]["create_host_path"])
        self.assertFalse(any(volume["source"] == "/wayland-0" for volume in service["volumes"]))

    def test_installer_retries_container_setup_and_cleans_temporary_files(self):
        result = self.run_command(str(ROOT / "install.sh"), "--yes", "--gpu", "4", "--url", "https://example.invalid/new.exe",
                                  XTOOL_TEST_FAIL_SETUP_ONCE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        creates = [call for call in self.calls("distrobox") if call["args"][:1] == ["create"]]
        self.assertEqual(len(creates), 2)
        self.assertIn("--dns 1.1.1.1 --dns 8.8.8.8", creates[-1]["args"][-2])
        desktop = self.user_home / ".local/share/applications/xtool-studio-xToolStudio.desktop"
        self.assertIn("Exec=/usr/bin/distrobox-enter", desktop.read_text())
        self.assertIn("Icon=/run/host/icon.png", desktop.read_text())
        self.assertFalse(list((self.user_home / ".cache/xtool-studio-cachy-box").glob("setup.*")))


if __name__ == "__main__":
    unittest.main()
