#!/bin/bash
set -euo pipefail

# ─── Resolve Script Directory and Source Common Library ───────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    echo "[ERROR] lib/common.sh not found in $SCRIPT_DIR" >&2
    echo "[ERROR] Please run this script from the repository root." >&2
    exit 1
fi

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ─── Parse Arguments ─────────────────────────────────────────────────────────

parse_args "$@"

# ─── Initialization ──────────────────────────────────────────────────────────

detect_distro
require_root
check_package_manager
check_aur_helper

# ─── Package Lists ───────────────────────────────────────────────────────────

INSTALL_PACKAGES=()
AUR_PACKAGES=()

case "$DISTRO_FAMILY" in
    arch)
        INSTALL_PACKAGES=(
            # Packages will be added in a follow-up task
        )
        AUR_PACKAGES=(
            # AUR packages will be added in a follow-up task
        )
        ;;
    debian)
        INSTALL_PACKAGES=(
            # Packages will be added in a follow-up task
        )
        ;;
    fedora)
        INSTALL_PACKAGES=(
            # Packages will be added in a follow-up task
        )
        ;;
    *)
        log_error "No package list defined for distro family '$DISTRO_FAMILY'."
        exit 1
        ;;
esac

# ─── Installation Logic ─────────────────────────────────────────────────────

log_step "Installing packages..."

pkg_install ${INSTALL_PACKAGES[@]+"${INSTALL_PACKAGES[@]}"}

if [[ "$DISTRO_FAMILY" == "arch" ]]; then
    paru_install ${AUR_PACKAGES[@]+"${AUR_PACKAGES[@]}"}
fi

local_total=$(( ${#INSTALL_PACKAGES[@]} + ${#AUR_PACKAGES[@]} ))
log_step "Installation complete."
log_info "$local_total package(s) processed."
