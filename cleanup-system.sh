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
        log_warn "Debian removal list is not yet implemented. No packages will be removed."
        REMOVE_PACKAGES=(
            # Packages will be added in a follow-up task
        )
        ;;
    fedora)
        log_warn "Fedora removal list is not yet implemented. No packages will be removed."
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

pkg_remove ${REMOVE_PACKAGES[@]+"${REMOVE_PACKAGES[@]}"}

log_step "System cleanup complete."
