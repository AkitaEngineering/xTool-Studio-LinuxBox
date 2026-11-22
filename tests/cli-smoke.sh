#!/usr/bin/env bash
# Copyright (c) 2026 Akita Engineering
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

export HOME="$scratch/home"
export PATH="$scratch/bin:$PATH"
export XTOOL_TEST_CALLS="$scratch/commands"
export XTOOL_TEST_OS=Linux
unset XTOOL_URL
mkdir -p "$HOME/.local/share/applications" "$scratch/bin"
desktop_file="$HOME/.local/share/applications/xtool-studio-xToolStudio.desktop"
printf 'Exec=/run/host/usr/bin/distrobox-enter\n' > "$desktop_file"
cp "$desktop_file" "$scratch/original.desktop"

cat > "$scratch/bin/distrobox" <<'STUB'
#!/bin/sh
case "$*" in
    'list --no-color')
        printf '%s\n' 'ID | NAME | STATUS | IMAGE' \
            '123 | xtool-studio | Up | ubuntu' \
            '456 | xtool-studio-backup | Up | ubuntu'
        ;;
    *)
        printf 'distrobox %s\n' "$*" >> "$XTOOL_TEST_CALLS"
        [ "${XTOOL_TEST_LIVE:-}" = 1 ]
        ;;
esac
STUB
cat > "$scratch/bin/podman" <<'STUB'
#!/bin/sh
case "$1" in
    info) exit 0 ;;
    images)
        printf '%s\n' localhost/xtool-custom-amd:latest localhost/xtool-custom-intel:latest \
            localhost/xtool-custom-amd-backup:latest
        ;;
    *)
        printf 'podman %s\n' "$*" >> "$XTOOL_TEST_CALLS"
        [ "${XTOOL_TEST_LIVE:-}" = 1 ]
        ;;
esac
STUB
cat > "$scratch/bin/curl" <<'STUB'
#!/bin/sh
printf 'curl %s\n' "$*" >> "$XTOOL_TEST_CALLS"
exit 1
STUB
cat > "$scratch/bin/uname" <<'STUB'
#!/bin/sh
if [ "$1" = -s ]; then
    printf '%s\n' "$XTOOL_TEST_OS"
else
    /usr/bin/uname "$@"
fi
STUB
chmod +x "$scratch/bin/"*

expect_usage_error() {
    local status=0
    timeout 5 "$@" > "$scratch/output" 2>&1 || status=$?
    [ "$status" -eq 2 ]
    grep -Fq -- '--help' "$scratch/output"
}

./install.sh --help > "$scratch/output"
grep -Fq 'xTool Studio LinuxBox' "$scratch/output"
./uninstall.sh --help > "$scratch/output"
grep -Fq 'Akita Engineering' "$scratch/output"

expect_usage_error ./install.sh --gpu
expect_usage_error ./install.sh --gpu 7
expect_usage_error ./install.sh --image-source --yes
expect_usage_error ./install.sh --unexpected
expect_usage_error ./uninstall.sh --log-file
expect_usage_error ./uninstall.sh --container-name 'invalid/name'

./install.sh --check > "$scratch/output"
grep -Fq 'Host prerequisite check passed' "$scratch/output"
./install.sh --dry-run --yes --gpu 4 --log-file "$scratch/install.log" > "$scratch/output"
grep -Fq "would replace the 'xtool-studio' container" "$scratch/output"
grep -Fq 'would look up the Windows installer' "$scratch/output"

./install.sh --uninstall --dry-run --yes --log-file "$scratch/uninstall.log" > "$scratch/output"
grep -Fq "Would remove the xTool Studio desktop export and 'xtool-studio' container" "$scratch/output"
grep -Fq 'Keeping local Wine data' "$scratch/output"
printf 'y\n' | ./uninstall.sh --dry-run > "$scratch/output"
grep -Fq "Would delete $HOME/.local/share/xtool-studio" "$scratch/output"

XTOOL_TEST_OS=FreeBSD ./install.sh --dry-run --yes --gpu 4 > "$scratch/output"
grep -Fq 'would install Wine with pkg' "$scratch/output"
if grep -Fq 'Container image' "$scratch/output"; then
    echo 'The FreeBSD installer unexpectedly offered a container image.' >&2
    exit 1
fi
XTOOL_TEST_OS=FreeBSD ./uninstall.sh --dry-run --yes > "$scratch/output"
if grep -Fq 'Distrobox' "$scratch/output"; then
    echo 'The FreeBSD uninstaller unexpectedly mentioned Distrobox.' >&2
    exit 1
fi

if command -v fish >/dev/null; then
    export XDG_CACHE_HOME="$scratch/fish-cache"
    export XDG_CONFIG_HOME="$scratch/fish-config"
    export XDG_DATA_HOME="$scratch/fish-data"
    ./install.fish --dry-run --yes --gpu 4 > "$scratch/output"
    grep -Fq 'would look up the Windows installer' "$scratch/output"
    ./uninstall.fish --dry-run --yes > "$scratch/output"
    grep -Fq 'Preview complete' "$scratch/output"
fi

cmp "$desktop_file" "$scratch/original.desktop"
for forbidden in "$HOME/.cache" "$scratch/install.log" "$scratch/uninstall.log" "$XTOOL_TEST_CALLS"; do
    [ ! -e "$forbidden" ]
done

cat > "$scratch/bin/id" <<'STUB'
#!/bin/sh
[ "$1" = -u ] && printf '1000\n'
STUB
chmod +x "$scratch/bin/id"
backup_desktop="$HOME/.local/share/applications/xtool-studio-backup-xToolStudio.desktop"
cp "$desktop_file" "$backup_desktop"
mkdir -p "$HOME/.local/share/xtool-studio/prefix"
XTOOL_TEST_LIVE=1 ./install.sh --uninstall --yes --log-file "$scratch/uninstall.log" > "$scratch/output"
grep -Fxq 'distrobox rm -f xtool-studio' "$XTOOL_TEST_CALLS"
grep -Fxq 'podman rmi localhost/xtool-custom-amd:latest' "$XTOOL_TEST_CALLS"
grep -Fxq 'podman rmi localhost/xtool-custom-intel:latest' "$XTOOL_TEST_CALLS"
if grep -Fq 'backup' "$XTOOL_TEST_CALLS"; then
    echo 'The uninstaller attempted to remove an unrelated container or image.' >&2
    exit 1
fi
[ ! -e "$desktop_file" ]
[ -f "$backup_desktop" ]
[ -d "$HOME/.local/share/xtool-studio/prefix" ]
[ -s "$scratch/uninstall.log" ]
echo 'CLI smoke checks passed.'
