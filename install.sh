#!/usr/bin/env bash

# --- Configuration & Colors ---
BLUE=''
GREEN=''
YELLOW=''
NC=''
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    BLUE='\033[0;34m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# --- CLI options & Logging ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_OS="$(uname -s)"
LOG_DIR="$HOME/.cache/xtool-studio-cachy-box"
SETUP_DIR="$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"
LAST_STEP_FILE="$LOG_DIR/last_failed_step"
CONTAINER_SETUP_SRC="$SCRIPT_DIR/scripts/container-setup.sh"
FREEBSD_SETUP_SRC="$SCRIPT_DIR/scripts/install-freebsd.sh"
PAYLOAD_SRC="$SCRIPT_DIR/scripts/install-payload.sh"
LAUNCHER_SRC="$SCRIPT_DIR/scripts/xtool-studio-launcher.sh"
MAPPER_SRC="$SCRIPT_DIR/scripts/xtool-map-windows.py"

log(){
    local level="$1" timestamp
    shift
    if [ "$DRY_RUN" = true ] || [ "$PRECHECK" = true ]; then
        printf '[%s] %s\n' "$level" "$*"
    else
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        printf '[%s] [%s] %s\n' "$timestamp" "$level" "$*" | tee -a "$LOG_FILE"
    fi
}

has_nvidia_cdi_spec(){
    find /etc/cdi /var/run/cdi -maxdepth 1 -type f \( -iname '*nvidia*.yaml' -o -iname '*nvidia*.json' \) -print -quit 2>/dev/null | grep -q .
}

has_nvidia_container_support(){
    command -v podman &>/dev/null || return 1
    command -v nvidia-smi &>/dev/null || return 1
    has_nvidia_cdi_spec && return 0
    return 1
}

run_logged(){
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: $*"
        return 0
    fi

    "$@" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]:-0}
}

resolve_latest_xtool_url(){
    local latest_response latest_url

    if [ -n "$XTOOL_URL" ]; then
        case "$XTOOL_URL_SOURCE" in
            cli)
                log "INFO" "Using xTool Studio installer URL from CLI: $XTOOL_URL"
                ;;
            environment)
                log "INFO" "Using xTool Studio installer URL from environment: $XTOOL_URL"
                ;;
        esac
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would look up the Windows installer at $XTOOL_RELEASE_NOTES_URL"
        return 0
    fi

    latest_response=$(curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 15 --max-time 60 \
        "$XTOOL_RELEASE_NOTES_URL" 2>>"$LOG_FILE" || true)

    latest_url=$(printf '%s' "$latest_response" | grep -oE 'https://storage\.atomm\.com/[^"[:space:]<>]+/xTool-Studio-x64-[0-9.]+\.exe' | head -n 1)

    if [ -n "$latest_url" ]; then
        XTOOL_URL="$latest_url"
        log "INFO" "Resolved latest xTool Studio Windows installer: $XTOOL_URL"
    else
        XTOOL_URL="$DEFAULT_XTOOL_URL"
        log "WARN" "Unable to resolve the latest xTool Studio release; falling back to $XTOOL_URL"
    fi
}

build_distrobox_create_cmd(){
    local image_name="$1"
    local gpu_flag="$2"
    local additional_flags="$3"

    DBX_CREATE_CMD=(distrobox create --name "$CONTAINER_NAME" --image "$image_name")
    if [ -n "$gpu_flag" ]; then
        DBX_CREATE_CMD+=("$gpu_flag")
    fi
    if [ -n "$additional_flags" ]; then
        DBX_CREATE_CMD+=(--additional-flags "$additional_flags")
    fi
    DBX_CREATE_CMD+=(--yes)
}

# latest-release resolution (can be overridden with XTOOL_URL or --url)
DEFAULT_XTOOL_URL="https://storage.atomm.com/efficacy/atomm-package/prod/packages/109/d7cb892b-c082-4565-803e-5e71b9f8026b/xTool-Studio-x64-1.6.6.exe"
XTOOL_RELEASE_NOTES_URL="https://support.xtool.com/article/1773"
XTOOL_URL="${XTOOL_URL:-}"
XTOOL_URL_SOURCE=""
if [ -n "$XTOOL_URL" ]; then
    XTOOL_URL_SOURCE="environment"
fi

NON_INTERACTIVE=false
DRY_RUN=false
PRECHECK=false
UNINSTALL=false
CONTAINER_NAME="xtool-studio"
gpu_choice=""
img_choice=""

usage(){
    cat <<EOF
xTool Studio LinuxBox installer · Akita Engineering
https://www.akitaengineering.com

Usage
  $0 [options]

Options
  --check                  Check host prerequisites.
  --dry-run                Preview the setup without writing files or downloading.
  --non-interactive, --yes, -y
                           Use defaults for prompts in this script.
  --gpu 1-4                1 Nvidia, 2 AMD, 3 Intel, 4 software rendering.
  --image-source 1-2       Linux only. 1 stock Ubuntu, 2 local image build.
  --container-name NAME    Linux only. Default is xtool-studio.
  --url URL                Override the xTool Studio Windows installer URL.
  --log-file PATH          Write the log to PATH during installation.
  --uninstall              Run the uninstaller. Add --dry-run for a preview.
  --help, -h               Show this help.

Linux uses Distrobox and Podman. FreeBSD installs Wine through pkg.
EOF
}

usage_error(){
    printf 'ERROR: %s\nRun %s --help for usage.\n' "$1" "$0" >&2
    exit 2
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --url|--container-name|--gpu|--image-source|--log-file)
            [[ -n "${2:-}" && "$2" != -* ]] || usage_error "$1 requires a value." ;;
    esac
    case "$1" in
        --non-interactive|--yes|-y)
            NON_INTERACTIVE=true; shift ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --check)
            PRECHECK=true; shift ;;
        --uninstall)
            UNINSTALL=true; shift ;;
        --url)
            XTOOL_URL="$2"; XTOOL_URL_SOURCE="cli"; shift 2 ;;
        --container-name)
            CONTAINER_NAME="$2"; shift 2 ;;
        --gpu)
            gpu_choice="$2"; shift 2 ;;
        --image-source)
            img_choice="$2"; shift 2 ;;
        --log-file)
            LOG_FILE="$2"; shift 2 ;;
        --help|-h)
            usage; exit 0 ;;
        *) usage_error "Unknown option '$1'." ;;
    esac
done

[[ "$CONTAINER_NAME" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] || usage_error "Invalid container name '$CONTAINER_NAME'."
[[ -z "$gpu_choice" || "$gpu_choice" =~ ^[1-4]$ ]] || usage_error "--gpu needs a number from 1 to 4."
[[ -z "$img_choice" || "$img_choice" =~ ^[1-2]$ ]] || usage_error "--image-source needs 1 or 2."

if [ "$UNINSTALL" = true ]; then
    uninstall_args=(--container-name "$CONTAINER_NAME")
    [ "$LOG_FILE" = "$LOG_DIR/install.log" ] || uninstall_args+=(--log-file "$LOG_FILE")
    [ "$NON_INTERACTIVE" = false ] || uninstall_args+=(--yes)
    [ "$DRY_RUN" = false ] || uninstall_args+=(--dry-run)
    exec bash "$SCRIPT_DIR/uninstall.sh" "${uninstall_args[@]}"
fi

if [ "$(id -u)" -eq 0 ] && [ "$DRY_RUN" = false ] && [ "$PRECHECK" = false ]; then
    echo 'Run ./install.sh as your regular user. The installer will ask for elevated privileges only when needed.' >&2
    exit 1
fi

echo "xTool Studio LinuxBox installer · Akita Engineering"
LAST_STEP="init"

fail(){
    local msg="$1"; shift
    echo
    log "ERROR" "$msg"
    if [ "$DRY_RUN" = false ] && [ "$PRECHECK" = false ]; then
        printf '%s\n' "$LAST_STEP" > "$LAST_STEP_FILE"
    fi
    exit 1
}

if [ "$DRY_RUN" = false ] && [ "$PRECHECK" = false ]; then
    mkdir -p "$LOG_DIR" && touch "$LOG_FILE" || {
        printf 'Cannot open %s. Check that its directory exists and is writable.\n' "$LOG_FILE" >&2
        exit 1
    }
fi

case "$HOST_OS" in
    Linux|FreeBSD) ;;
    *) fail "Unsupported host OS: $HOST_OS. Linux (Distrobox + Wine) and FreeBSD (native Wine) are supported." ;;
esac

detect_gpu(){
    detected_gpu="none"
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        detected_gpu="nvidia"
        return 0
    fi

    local pci=""
    if command -v lspci >/dev/null 2>&1; then
        pci="$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' || true)"
    elif command -v pciconf >/dev/null 2>&1; then
        pci="$(pciconf -lv 2>/dev/null || true)"
    fi

    if printf '%s' "$pci" | grep -iq nvidia; then
        detected_gpu="nvidia"
    elif printf '%s' "$pci" | grep -Eiq 'AMD|ATI'; then
        detected_gpu="amd"
    elif printf '%s' "$pci" | grep -iq intel; then
        detected_gpu="intel"
    fi
}

# preflight checks
preflight(){
    log "INFO" "Running preflight checks on $HOST_OS"
    local cmd available
    local cmds missing=()
    if [ "$HOST_OS" = "FreeBSD" ]; then
        cmds=(curl pkg)
    else
        cmds=(distrobox podman curl)
    fi
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log "ERROR" "Install these prerequisites with your host package manager, then run --check again: ${missing[*]}"
        return 1
    fi
    if [ "$HOST_OS" = "FreeBSD" ]; then
        if ! command -v doas &>/dev/null && ! command -v sudo &>/dev/null; then
            log "ERROR" "Configure doas or sudo so the installer can use pkg."
            return 1
        fi
    elif ! podman info >/dev/null 2>&1; then
        log "ERROR" "Podman is unable to start. Run 'podman info' in your terminal for details."
        return 1
    fi
    if [ "$HOST_OS" != "FreeBSD" ] && command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null && ! has_nvidia_container_support; then
        log "WARN" "Nvidia GPU detected but Podman CDI support is not configured. Install nvidia-container-toolkit and generate a CDI spec before using the Nvidia path."
    fi
    # disk space (POSIX df -kP: avail is column 4)
    available=$(df -kP "$HOME" | awk 'NR==2 {print $4}')
    if [ -n "$available" ] && [ "$available" -lt 4194304 ]; then
        log "WARN" "Your home filesystem has less than 4 GiB free for the download and extracted files."
    fi
    log "INFO" "Host prerequisite check passed."
}


# Distrobox 1.7 (Ubuntu/Zorin) eval's the enter command with /bin/sh (dash).
# Never pass multiline scripts or paths with parentheses through this helper.
enter_container(){
    distrobox enter --no-workdir "$CONTAINER_NAME" -- "$@" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]:-0}
}

verify_container_setup(){
    enter_container /usr/bin/test -x /usr/local/bin/xToolStudio || return 1
    enter_container /usr/bin/test -f /usr/share/applications/xToolStudio.desktop || return 1
    log "INFO" "Verified launcher and desktop entry inside container $CONTAINER_NAME"
}

container_exists(){
    distrobox list --no-color | awk -F '|' -v name="$CONTAINER_NAME" '
        { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2) }
        $2 == name { found = 1 }
        END { exit !found }
    '
}

write_setup_env(){
    {
        printf 'XTOOL_URL=%q\n' "$XTOOL_URL"
        printf 'XTOOL_FORCE_SOFTWARE_RENDERING=%q\n' "$XTOOL_FORCE_SOFTWARE_RENDERING"
        printf 'XTOOL_LAUNCHER_SRC=%q\n' "$SETUP_DIR/xtool-studio-launcher.sh"
        printf 'XTOOL_MAPPER_SRC=%q\n' "$SETUP_DIR/xtool-map-windows.py"
        printf 'XTOOL_SETUP_DIR=%q\n' "$SETUP_DIR"
        printf 'XTOOL_PAYLOAD_LIB=%q\n' "$SETUP_DIR/install-payload.sh"
        printf 'XTOOL_DRY_RUN=%q\n' "$DRY_RUN"
    } > "$SETUP_DIR/container-setup.env"
}

prepare_setup(){
    local setup_script="$1"
    if [ ! -f "$setup_script" ] || [ ! -f "$LAUNCHER_SRC" ] || [ ! -f "$PAYLOAD_SRC" ] || [ ! -f "$MAPPER_SRC" ]; then
        fail "Setup files are missing. Download and extract a fresh copy of the release."
    fi

    cp -f "$setup_script" "$LAUNCHER_SRC" "$PAYLOAD_SRC" "$MAPPER_SRC" "$SETUP_DIR/" &&
    write_setup_env
}


# --- Download URL for the latest Windows installer ---
# (may be overridden with --url)

# if --check was given, run preflight and exit
if [ "$PRECHECK" = true ]; then
    preflight
    exit $?
fi

if [ "$DRY_RUN" = false ] && ! command -v curl &>/dev/null; then
    fail "Install curl with your host package manager, then run the installer again."
fi

resolve_latest_xtool_url


# --- GPU Selection ---
# detect hardware and ask the user to choose a driver stack

echo -e "\n${YELLOW}--- Graphics ---${NC}"
detect_gpu

echo -e "Detected Hardware: ${GREEN}$detected_gpu${NC}"

gpu_default="4"
case $detected_gpu in
    "nvidia") gpu_default="1" ;;
    "amd")    gpu_default="2" ;;
    "intel")  gpu_default="3" ;;
esac

if [ "$HOST_OS" = "FreeBSD" ]; then
    echo "1) Nvidia (host nvidia-driver)"
    echo "2) AMD (host drm-kmod / graphics/gpu-firmware-*)"
    echo "3) Intel (host drm-kmod)"
    echo "4) Generic / None / Software Rendering"
else
    echo "1) Nvidia (uses --nvidia flag)"
    echo "2) AMD (uses DRI pass-through)"
    echo "3) Intel (uses DRI pass-through)"
    echo "4) Generic / None / Software Rendering"
fi
if [ -n "$gpu_choice" ]; then
    log "INFO" "Using GPU from CLI: $gpu_choice"
elif [ "$NON_INTERACTIVE" = true ]; then
    gpu_choice=$gpu_default
    log "INFO" "Non-interactive: selecting GPU stack $gpu_choice"
else
    read -r -p "Choose a graphics option [$gpu_default]: " gpu_choice
    gpu_choice=${gpu_choice:-$gpu_default}
fi
[[ "$gpu_choice" =~ ^[1-4]$ ]] || usage_error "Choose a graphics option from 1 to 4."

if [ "$gpu_choice" = "1" ] && [ "$HOST_OS" != "FreeBSD" ] && ! has_nvidia_container_support; then
    echo -e "${YELLOW}Nvidia GPU detected, but Podman GPU support is not configured.${NC}"
    echo "Install nvidia-container-toolkit and generate /etc/cdi/nvidia.yaml to use the Nvidia path."
    if [ "$NON_INTERACTIVE" = true ]; then
        log "WARN" "Nvidia container support is unavailable; falling back to Generic / software rendering."
        gpu_choice=4
    else
        echo "1) Fall back to Generic / None / Software Rendering"
        echo "2) Abort and configure Nvidia container support first"
        read -r -p "Choose how to proceed [1]: " nvidia_fallback_choice
        nvidia_fallback_choice=${nvidia_fallback_choice:-1}
        case "$nvidia_fallback_choice" in
            1) ;;
            2) fail "Configure Nvidia container support, then run the installer again." ;;
            *) usage_error "Choose 1 for software rendering or 2 to exit." ;;
        esac
        log "WARN" "Nvidia container support is unavailable; falling back to Generic / software rendering."
        gpu_choice=4
    fi
fi

GPU_FLAG=""
ADD_FLAGS=""
GPU_TYPE="generic"
CONTAINERFILE="containerfile.amd"
XTOOL_FORCE_SOFTWARE_RENDERING=1

case $gpu_choice in
    1) GPU_FLAG="--nvidia"; GPU_TYPE="nvidia"; CONTAINERFILE="containerfile.nvidia"; XTOOL_FORCE_SOFTWARE_RENDERING=0 ;;
    2) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="amd"; CONTAINERFILE="containerfile.amd"; XTOOL_FORCE_SOFTWARE_RENDERING=0 ;;
    3) ADD_FLAGS="--device /dev/dri:/dev/dri"; GPU_TYPE="intel"; CONTAINERFILE="containerfile.intel"; XTOOL_FORCE_SOFTWARE_RENDERING=0 ;;
    *) GPU_TYPE="generic"; CONTAINERFILE="containerfile.amd" ;;
esac

if [ "$HOST_OS" = "FreeBSD" ]; then
    echo -e "\n${YELLOW}FreeBSD setup uses native Wine from pkg.${NC}"
    LAST_STEP="freebsd:packages"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would install Wine with pkg, set up xTool Studio, and add a desktop entry."
        exit 0
    fi
    log "INFO" "Installing xTool Studio with native Wine. Setup log: $LOG_FILE"
    prepare_setup "$FREEBSD_SETUP_SRC" || fail "Could not prepare the FreeBSD setup files in $SETUP_DIR."
    bash "$SETUP_DIR/install-freebsd.sh" 2>&1 | tee -a "$LOG_FILE"
    freebsd_rc=${PIPESTATUS[0]:-0}
    if [ "$freebsd_rc" -ne 0 ]; then
        fail "FreeBSD Wine setup failed. See $LOG_FILE for details."
    fi
    if [ ! -f "$HOME/.local/share/applications/xToolStudio.desktop" ]; then
        fail "Desktop file was not created. See $LOG_FILE for details."
    fi
    echo -e "${GREEN}Setup complete.${NC}"
    printf 'Open xTool Studio from your app menu or run "%s/.local/bin/xToolStudio".\n' "$HOME"
    printf 'Desktop launch log: %s/launch.log\n' "$LOG_DIR"
    exit 0
fi

# --- Step 2: Image Source ---
echo -e "\n${YELLOW}--- Container image ---${NC}"
echo "1) Ubuntu 24.04 (default)"
echo "2) Build a local image"
if [ -n "$img_choice" ]; then
    log "INFO" "Using image source from CLI: $img_choice"
elif [ "$NON_INTERACTIVE" = true ]; then
    img_choice=1
    log "INFO" "Non-interactive: selecting image source $img_choice"
else
    read -r -p "Choose an image source [1]: " img_choice
    img_choice=${img_choice:-1}
fi
[[ "$img_choice" =~ ^[1-2]$ ]] || usage_error "Choose 1 for Ubuntu or 2 for a local build."

# Inform user what's next and where logs will go
LAST_STEP="start"
if [ "$DRY_RUN" = false ]; then
    log "INFO" "Installing xTool Studio in '$CONTAINER_NAME'. Setup log: $LOG_FILE"
fi

# --- Step 3: Installation Loop with DNS Retry ---
SUCCESS=false
USE_DNS=false

while [ "$SUCCESS" = false ]; do
    CURRENT_ADD_FLAGS="$ADD_FLAGS"
    if [ "$USE_DNS" = true ]; then
        echo -e "${YELLOW}Retrying container setup with alternate DNS (1.1.1.1 and 8.8.8.8).${NC}"
        CURRENT_ADD_FLAGS="$CURRENT_ADD_FLAGS --dns 1.1.1.1 --dns 8.8.8.8"
    fi

    # Host Dependencies
    LAST_STEP="host:deps"
    missing_host_deps=()
    for host_dep in distrobox podman; do
        if ! command -v "$host_dep" &>/dev/null; then
            missing_host_deps+=("$host_dep")
        fi
    done

    if [ ${#missing_host_deps[@]} -eq 0 ]; then
        log "INFO" "Host dependencies already present: distrobox, podman"
    elif [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would install missing host dependencies via system package manager: ${missing_host_deps[*]}"
    else
        log "INFO" "Installing missing host dependencies: ${missing_host_deps[*]}"
        if command -v pacman &> /dev/null; then
            run_logged sudo pacman -S --needed --noconfirm "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        elif command -v apt &> /dev/null; then
            run_logged sudo apt update || fail "Failed to update apt metadata. See $LOG_FILE for details."
            run_logged sudo apt install -y "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        elif command -v dnf &> /dev/null; then
            run_logged sudo dnf install -y "${missing_host_deps[@]}" || fail "Failed to install host dependencies. See $LOG_FILE for details."
        else
            fail "Unknown package manager. Please install these dependencies manually: ${missing_host_deps[*]}"
        fi
    fi

    # Image Preparation
    IMAGE_NAME="docker.io/library/ubuntu:24.04"
    if [ "$img_choice" == "2" ]; then
        [ -f "$SCRIPT_DIR/$CONTAINERFILE" ] || fail "Cannot find $CONTAINERFILE. Download a fresh copy of the release."
        IMAGE_NAME="localhost/xtool-custom-$GPU_TYPE:latest"
        if [ "$USE_DNS" = false ]; then
            log "INFO" "Building local image from $CONTAINERFILE"
            run_logged podman build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/$CONTAINERFILE" "$SCRIPT_DIR" || fail "Image build failed. See $LOG_FILE for details."
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would replace the '$CONTAINER_NAME' container if it exists."
    elif container_exists; then
        LAST_STEP="container:remove"
        log "INFO" "Replacing the existing '$CONTAINER_NAME' container. Files in your home directory are kept."
        run_logged distrobox rm -f "$CONTAINER_NAME" || fail "Could not remove '$CONTAINER_NAME'. See $LOG_FILE for details."
    fi

    echo -e "${BLUE}Creating Distrobox container...${NC}"
    LAST_STEP="container:create"
    build_distrobox_create_cmd "$IMAGE_NAME" "$GPU_FLAG" "$CURRENT_ADD_FLAGS"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would run: ${DBX_CREATE_CMD[*]}"
    else
        run_logged "${DBX_CREATE_CMD[@]}" || fail "Container creation failed. See $LOG_FILE for details."
    fi

    echo -e "\n${YELLOW}Installing basic packages. This might take a few minutes...${NC}"

    LAST_STEP="install:packages"
    log "INFO" "Installing packages and downloading application inside container"
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN: would install Wine and xTool Studio, then add xTool Studio to your app menu."
        exit 0
    else
        prepare_setup "$CONTAINER_SETUP_SRC" || fail "Could not prepare the container setup files in $SETUP_DIR."
        enter_container /bin/bash "$SETUP_DIR/container-setup.sh"
        install_rc=$?
        if [ $install_rc -eq 0 ] && verify_container_setup; then
            SUCCESS=true
        else
            if [ $install_rc -eq 0 ]; then
                install_rc=1
                log "ERROR" "Container setup returned success, but /usr/local/bin/xToolStudio or its desktop entry is missing inside $CONTAINER_NAME"
            fi
            if [ "$USE_DNS" = false ]; then
                log "WARN" "Container setup failed (exit $install_rc). Retrying once with alternate DNS."
                USE_DNS=true
            else
                fail "Installation failed twice. See $LOG_FILE for details."
            fi
        fi
    fi
done

# --- Step 4: Export & Final Fixes ---
echo -e "\n${BLUE}Adding xTool Studio to your app menu...${NC}"
LAST_STEP="export:app"
enter_container distrobox-export --app xToolStudio || fail "Could not export xTool Studio. See $LOG_FILE for details."
desktop_dir="$HOME/.local/share/applications"
desktop_file="$desktop_dir/$CONTAINER_NAME-xToolStudio.desktop"
if [ ! -f "$desktop_file" ]; then
    fail "Distrobox did not create $desktop_file. See $LOG_FILE for details."
fi
sed -i 's|/run/host||' "$desktop_file" || fail "Could not update $desktop_file."
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$desktop_dir" || log "WARN" "Could not refresh the desktop menu database."
fi
echo -e "${GREEN}Setup complete.${NC}"
echo "Open xTool Studio from your app menu."
printf 'For terminal output, run distrobox enter --no-workdir %s -- /usr/local/bin/xToolStudio\n' "$CONTAINER_NAME"
printf 'Desktop launch log: %s/launch.log\n' "$LOG_DIR"
