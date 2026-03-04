#!/bin/bash
set -euo pipefail

# ─── Colors and Logging ──────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$*"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

log_step() {
    printf "\n${BLUE}${BOLD}==> %s${NC}\n" "$*"
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
                exit 1
                ;;
        esac
    done
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf "${YELLOW}[dry-run]${NC} %s\n" "$*"
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

    # shellcheck source=/dev/null
    source /etc/os-release

    DISTRO_ID="${ID:-unknown}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"

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
    run_cmd sudo pacman -S --needed --noconfirm "$@"
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
    log_info "Installing $# package(s) via paru..."
    run_cmd paru -S --needed --noconfirm "$@"
}

pacman_remove() {
    if [[ $# -eq 0 ]]; then
        log_info "No packages to remove."
        return 0
    fi

    local to_remove=()
    local already_absent=0

    for pkg in "$@"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            to_remove+=("$pkg")
        else
            already_absent=$((already_absent + 1))
        fi
    done

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        log_info "Removing ${#to_remove[@]} package(s)..."
        run_cmd sudo pacman -Rns --noconfirm "${to_remove[@]}"
    fi

    if [[ $already_absent -gt 0 ]]; then
        log_info "$already_absent package(s) already absent, skipped."
    fi

    log_info "Cleanup complete. ${#to_remove[@]} package(s) removed, $already_absent already absent."
}

# ─── Generic Package Dispatchers ────────────────────────────────────────────

pkg_install() {
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
