#!/bin/bash
set -euo pipefail

# ─── Resolve Script Directory and Source Common Library ───────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    echo "Error: lib/common.sh not found in $SCRIPT_DIR" >&2
    echo "Please run this script from the repository root." >&2
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

# ─── Packages to Remove ─────────────────────────────────────────────────────

REMOVE_PACKAGES=()

case "$DISTRO_FAMILY" in
    arch)
        REMOVE_PACKAGES=(
            htop            # Replaced by btop
            vim             # Replaced by neovim
        )
        ;;
    debian)
        REMOVE_PACKAGES=(
            # Packages will be added in a follow-up task
        )
        ;;
    fedora)
        REMOVE_PACKAGES=(
            # Packages will be added in a follow-up task
        )
        ;;
    *)
        log_error "No cleanup list defined for distro family '$DISTRO_FAMILY'."
        exit 1
        ;;
esac

# ─── Removal Logic ──────────────────────────────────────────────────────────

log_step "Cleaning up unwanted packages..."

pkg_remove "${REMOVE_PACKAGES[@]}"

log_step "System cleanup complete."
