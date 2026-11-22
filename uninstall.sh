#!/usr/bin/env bash
# Copyright (c) 2026 Akita Engineering
# SPDX-License-Identifier: GPL-3.0-only
# Portions copyright (c) 2026 Sascha Schüller, MIT. See LICENSES/MIT.txt.

LOG_DIR="$HOME/.cache/xtool-studio-cachy-box"
LOG_FILE="$LOG_DIR/uninstall.log"
APP_HOME="$HOME/.local/share/xtool-studio"
DESKTOP_DIR="$HOME/.local/share/applications"
CONTAINER_NAME="xtool-studio"
NON_INTERACTIVE=false
DRY_RUN=false
HOST_OS="$(uname -s)"

usage(){
    cat <<HELP
xTool Studio LinuxBox uninstaller · Akita Engineering
https://www.akitaengineering.com

Usage
  $0 [options]

Options
  --dry-run                Preview removal without writing or deleting files.
  --non-interactive, --yes, -y
                           Skip the data removal prompt and keep your Wine data.
  --container-name NAME    Linux only. Default is xtool-studio.
  --log-file PATH          Write the log to PATH during removal.
  --help, -h               Show this help.

By default you can choose whether to delete your Wine data and cached installer
from $APP_HOME.
HELP
}

usage_error(){
    printf 'ERROR: %s\nRun %s --help for usage.\n' "$1" "$0" >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --container-name|--log-file)
            [[ -n "${2:-}" && "$2" != -* ]] || usage_error "$1 requires a value." ;;
    esac
    case "$1" in
        --container-name)
            CONTAINER_NAME="$2"; shift 2 ;;
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --log-file)
            LOG_FILE="$2"; shift 2 ;;
        --help|-h)
            usage; exit 0 ;;
        *) usage_error "Unknown option '$1'." ;;
    esac
done

[[ "$CONTAINER_NAME" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] || usage_error "Invalid container name '$CONTAINER_NAME'."

case "$HOST_OS" in
    Linux|FreeBSD) ;;
    *) printf 'xTool Studio LinuxBox supports Linux and FreeBSD. Detected %s.\n' "$HOST_OS" >&2; exit 1 ;;
esac

if [ "$DRY_RUN" = false ]; then
    if [ "$(id -u)" -eq 0 ]; then
        echo 'Run ./uninstall.sh as the regular user who installed xTool Studio.' >&2
        exit 1
    fi
    mkdir -p "$LOG_DIR" && touch "$LOG_FILE" || {
        printf 'Cannot open %s. Check that its directory exists and is writable.\n' "$LOG_FILE" >&2
        exit 1
    }
fi

log(){
    if [ "$DRY_RUN" = true ]; then
        printf 'DRY RUN: %s\n' "$*"
    else
        printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG_FILE"
    fi
}

run_logged(){
    "$@" 2>&1 | tee -a "$LOG_FILE"
    return "${PIPESTATUS[0]}"
}

echo 'xTool Studio LinuxBox uninstaller · Akita Engineering'

if [ "$HOST_OS" = "Linux" ] && [ "$DRY_RUN" = true ]; then
    log "Would remove the xTool Studio desktop export and '$CONTAINER_NAME' container if present."
    log 'Would try to remove unused LinuxBox Podman images.'
elif [ "$HOST_OS" = "Linux" ]; then
    if command -v distrobox &>/dev/null; then
        if ! containers="$(distrobox list --no-color)"; then
            log "Could not list Distrobox containers. Check Podman, then run the uninstaller again."
            exit 1
        fi
        if printf '%s\n' "$containers" | awk -F '|' -v name="$CONTAINER_NAME" '
            { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2) }
            $2 == name { found = 1 }
            END { exit !found }
        '; then
            log "Removing the xTool Studio desktop export and '$CONTAINER_NAME' container."
            if ! run_logged distrobox enter --no-workdir "$CONTAINER_NAME" -- distrobox-export --app xToolStudio --delete; then
                log 'Distrobox could not remove the export. The uninstaller will remove its desktop entry below.'
            fi
            if ! run_logged distrobox rm -f "$CONTAINER_NAME"; then
                log "Could not remove '$CONTAINER_NAME'. See $LOG_FILE for details."
                exit 1
            fi
        else
            log "No Distrobox container named '$CONTAINER_NAME' was found."
        fi
    else
        log 'Distrobox is unavailable. Check for leftover containers if you reinstall Distrobox.'
    fi

    if command -v podman &>/dev/null && images="$(podman images --format '{{.Repository}}:{{.Tag}}')"; then
        while IFS= read -r image; do
            case "$image" in
                localhost/xtool-custom-nvidia:latest|localhost/xtool-custom-amd:latest|\
                localhost/xtool-custom-intel:latest|localhost/xtool-custom-generic:latest)
                    if ! run_logged podman rmi "$image"; then
                        log "Kept $image. See $LOG_FILE for details."
                    fi ;;
            esac
        done <<< "$images"
    fi
    desktop_files=("$DESKTOP_DIR/$CONTAINER_NAME-xToolStudio.desktop")
else
    desktop_files=("$DESKTOP_DIR/xToolStudio.desktop" "$HOME/.local/bin/xToolStudio" "$HOME/.local/bin/xtool-map-windows.py")
fi

if [ "$DRY_RUN" = true ]; then
    log 'Would remove the launcher files and cached setup scripts.'
else
    log 'Removing launcher files and cached setup scripts.'
    rm -f -- "${desktop_files[@]}" "$LOG_DIR"/{container-setup.env,container-setup.sh,install-freebsd.sh,install-payload.sh,xtool-studio-launcher.sh,xtool-map-windows.py} || {
        log 'Some launcher or setup files could not be removed.'
        exit 1
    }
    if [ -d "$DESKTOP_DIR" ] && command -v update-desktop-database &>/dev/null; then
        run_logged update-desktop-database "$DESKTOP_DIR" || log 'Could not refresh the desktop menu database.'
    fi
fi

cleanup_config=""
if [ "$NON_INTERACTIVE" = false ]; then
    printf 'Local Wine data and the cached Windows installer are in %s.\n' "$APP_HOME"
    printf 'Delete this directory and everything it contains? [y/N] '
    read -r cleanup_config
fi

if [[ "$cleanup_config" = [yY] ]]; then
    if [ "$DRY_RUN" = true ]; then
        log "Would delete $APP_HOME."
    else
        rm -rf -- "$APP_HOME" || { log "Could not remove $APP_HOME."; exit 1; }
        log "Removed $APP_HOME."
    fi
else
    log "Keeping local Wine data and the cached installer in $APP_HOME."
fi

if [ "$DRY_RUN" = true ]; then
    echo 'Preview complete.'
else
    printf 'Removal complete. Log saved to %s\n' "$LOG_FILE"
fi
