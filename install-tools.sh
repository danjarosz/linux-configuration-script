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
# NOTE: This boilerplate is intentionally duplicated so sub-scripts can run standalone.
# When invoked from setup.sh, the guards skip already-completed detection.

[[ -n "${DISTRO_FAMILY:-}" ]] || detect_distro
require_root
[[ -n "${PKG_MANAGER:-}" ]] || check_package_manager
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
        log_warn "Debian package list is not yet implemented. No packages will be installed."
        INSTALL_PACKAGES=(
            # Packages will be added in a follow-up task
        )
        ;;
    fedora)
        log_warn "Fedora package list is not yet implemented. No packages will be installed."
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

local_count=${#INSTALL_PACKAGES[@]}
aur_count=${#AUR_PACKAGES[@]}
total_packages=$(( local_count + aur_count ))

log_step "Installation complete."
if [[ $total_packages -gt 0 ]]; then
    log_info "$total_packages package(s) requested for installation."
else
    log_info "No packages to process (package lists are empty)."
fi
