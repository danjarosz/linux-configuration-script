#!/bin/bash
set -euo pipefail

# ─── Colors and Logging ──────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Suppress ANSI codes per https://no-color.org — ${NO_COLOR+set} expands to "set"
# if NO_COLOR is defined (even if empty), so NO_COLOR= still triggers suppression.
if [[ "${NO_COLOR+set}" == "set" ]] || [[ ! -t 2 ]]; then
    RED='' YELLOW='' GREEN='' BLUE='' BOLD='' NC=''
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$*" >&2
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

log_step() {
    printf "\n${BLUE}${BOLD}[STEP] ==> %s${NC}\n" "$*" >&2
}

# ─── Dry-Run Support ─────────────────────────────────────────────────────────

# DRY_RUN is intentionally inheritable from the environment so that setup.sh
# can propagate dry-run mode to child sub-scripts via the process environment,
# in addition to passing --dry-run on the command line. parse_args() overrides
# this value when --dry-run is passed as an argument.
DRY_RUN="${DRY_RUN:-false}"

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                log_info "Dry-run mode enabled. No changes will be made."
                ;;
            *)
                log_error "Unknown argument: $arg"
                log_error "Usage: <script> [--dry-run]"
                log_error "Options:"
                log_error "  --dry-run    Preview all commands without making any changes"
                exit 1
                ;;
        esac
    done
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        local _cmd_str
        printf -v _cmd_str '%q ' "$@"
        printf "${YELLOW}[DRY-RUN]${NC} %s\n" "$_cmd_str" >&2
    else
        "$@"
    fi
}

# ─── Distro Detection ────────────────────────────────────────────────────────

DISTRO_ID=""
DISTRO_ID_LIKE=""
DISTRO_FAMILY=""

detect_distro() {
    log_step "Detecting distribution..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect distribution: /etc/os-release not found."
        exit 1
    fi

    # Single-pass read — avoids 6 child processes (two grep|cut|tr chains) and
    # sanitizes both keys and values to strip ANSI escapes or other control characters.
    # Keys are restricted to [A-Z0-9_] per the systemd os-release spec.
    # Values keep alphanumerics, underscore, dot, space, and hyphen (hyphen last to
    # avoid range interpretation in the character class).
    local key val
    while IFS='=' read -r key val; do
        key="${key^^}"
        key="${key//[^A-Z0-9_]/}"
        val="${val#\"}"
        val="${val%\"}"
        val="${val//[^[:alnum:]_. -]/}"
        case "$key" in
            ID)      DISTRO_ID="$val" ;;
            ID_LIKE) DISTRO_ID_LIKE="$val" ;;
        esac
    done < /etc/os-release

    log_info "Detected distro: $DISTRO_ID (ID_LIKE: ${DISTRO_ID_LIKE:-none})"

    # Derive distro family — check DISTRO_ID directly first (vanilla Debian/Fedora
    # set ID without ID_LIKE), then fall back to ID_LIKE for derivatives.
    if [[ "$DISTRO_ID" == "arch" || "$DISTRO_ID_LIKE" == *"arch"* ]]; then
        DISTRO_FAMILY="arch"
    elif [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID_LIKE" == *"debian"* || "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
        DISTRO_FAMILY="debian"
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID_LIKE" == *"fedora"* ]]; then
        DISTRO_FAMILY="fedora"
    else
        DISTRO_FAMILY="unknown"
        log_warn "Unknown distro family for '$DISTRO_ID'. Some features may not work."
    fi

    log_info "Distro family: $DISTRO_FAMILY"
}

# ─── Privilege Check ─────────────────────────────────────────────────────────

require_root() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping root check (dry-run mode)."
        return 0
    fi

    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script requires root privileges."
        log_error "Please run with: sudo $0"
        exit 1
    fi
}

# ─── Package Manager Checks ──────────────────────────────────────────────────

PKG_MANAGER=""
PARU_AVAILABLE=false

check_package_manager() {
    if command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    elif command -v apt &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        log_error "No supported package manager found (pacman, apt, dnf)."
        exit 1
    fi
    log_info "Package manager: $PKG_MANAGER"
}

check_aur_helper() {
    if [[ "$PKG_MANAGER" != "pacman" ]]; then
        return 0
    fi

    if command -v paru &>/dev/null; then
        PARU_AVAILABLE=true
        log_info "AUR helper: paru"
    else
        PARU_AVAILABLE=false
        log_warn "'paru' (AUR helper) is not installed. AUR packages will be skipped."
    fi
}

# ─── Package Operation Helpers ────────────────────────────────────────────────

pacman_install() {
    if [[ $# -eq 0 ]]; then
        log_info "No pacman packages to install."
        return 0
    fi
    log_info "Installing $# package(s) via pacman..."
    run_cmd pacman -S --needed --noconfirm "$@"
}

paru_install() {
    if [[ $# -eq 0 ]]; then
        log_info "No AUR packages to install."
        return 0
    fi
    if [[ "$PARU_AVAILABLE" != "true" ]]; then
        log_warn "Skipping AUR packages (paru not available)."
        return 0
    fi
    # Trust boundary: SUDO_USER is set by sudo(8) and cannot be forged by
    # unprivileged callers, but is empty when running as direct root login.
    if [[ -z "${SUDO_USER:-}" ]]; then
        log_error "Cannot run paru as root without SUDO_USER. Please run this script via 'sudo' (not as direct root login)."
        return 1
    fi
    # Reject invalid usernames — e.g., SUDO_USER=#0 would cause sudo -u to
    # resolve UID 0 (root), defeating the intended privilege drop for AUR ops.
    if [[ ! "$SUDO_USER" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$ ]]; then
        log_error "SUDO_USER contains invalid characters: '$SUDO_USER'. Refusing to proceed."
        return 1
    fi
    log_info "Installing $# package(s) via paru..."
    # paru must be in SUDO_USER's PATH — sudo -u preserves the user's environment
    run_cmd sudo -u "$SUDO_USER" paru -S --needed --noconfirm "$@"
}

pacman_remove() {
    if [[ $# -eq 0 ]]; then
        log_info "No packages to remove."
        return 0
    fi

    # In dry-run mode, skip the live package database query
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would check and remove $# package(s)..."
        run_cmd pacman -Rns --noconfirm "$@"
        return 0
    fi

    # Parse installed packages into an associative array for O(1) lookups
    local -A installed_set=()
    local to_remove=()
    local already_absent=0
    local line pkg_name
    while IFS= read -r line; do
        pkg_name="${line%% *}"
        installed_set["$pkg_name"]=1
    done < <(pacman -Q "$@" 2>/dev/null || true)

    for pkg in "$@"; do
        if [[ -v "installed_set[$pkg]" ]]; then
            to_remove+=("$pkg")
        else
            already_absent=$(( already_absent + 1 ))
        fi
    done

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        log_info "Removing ${#to_remove[@]} package(s)..."
        run_cmd pacman -Rns --noconfirm "${to_remove[@]}"
    fi

    if [[ $already_absent -gt 0 ]]; then
        log_info "$already_absent package(s) already absent, skipped."
    fi

    log_info "Cleanup complete. ${#to_remove[@]} package(s) removed, $already_absent already absent."
}

# ─── Generic Package Dispatchers ────────────────────────────────────────────

pkg_install() {
    if [[ $# -eq 0 ]]; then
        log_info "No packages to install."
        return 0
    fi
    case "$DISTRO_FAMILY" in
        arch)
            pacman_install "$@"
            ;;
        *)
            log_error "pkg_install is not implemented for distro family '$DISTRO_FAMILY'."
            exit 1
            ;;
    esac
}

pkg_remove() {
    if [[ $# -eq 0 ]]; then
        log_info "No packages to remove."
        return 0
    fi
    case "$DISTRO_FAMILY" in
        arch)
            pacman_remove "$@"
            ;;
        *)
            log_error "pkg_remove is not implemented for distro family '$DISTRO_FAMILY'."
            exit 1
            ;;
    esac
}
