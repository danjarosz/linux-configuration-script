#!/bin/bash
set -euo pipefail

# ─── Colors and Logging ──────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Suppress ANSI codes when NO_COLOR is set or stderr is not a TTY
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
                exit 1
                ;;
        esac
    done
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf "${YELLOW}[dry-run]${NC} %s\n" "$(printf '%q ' "$@")" >&2
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

    DISTRO_ID="$(grep '^ID=' /etc/os-release | cut -d= -f2- | tr -d '"' || echo "unknown")"
    DISTRO_ID_LIKE="$(grep '^ID_LIKE=' /etc/os-release | cut -d= -f2- | tr -d '"' || echo "")"

    log_info "Detected distro: $DISTRO_ID (ID_LIKE: ${DISTRO_ID_LIKE:-none})"

    # Derive distro family
    if [[ "$DISTRO_ID" == "arch" || "$DISTRO_ID_LIKE" == *"arch"* ]]; then
        DISTRO_FAMILY="arch"
    elif [[ "$DISTRO_ID_LIKE" == *"debian"* || "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
        DISTRO_FAMILY="debian"
    elif [[ "$DISTRO_ID_LIKE" == *"fedora"* ]]; then
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
            (( already_absent++ ))
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
    if [[ $# -eq 0 ]]; then return 0; fi
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
    if [[ $# -eq 0 ]]; then return 0; fi
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
