#!/bin/bash
set -euo pipefail

# ─── Package Configuration ──────────────────────────────────────────────────
# Sourced by install-tools.sh, cleanup-system.sh — not executed directly.
# The shebang and set -euo pipefail above are required so that
# validate_fetched_script() accepts this file during remote execution
# (curl | bash). They are idempotent when sourced by a script that
# already sets them.
#
# Central package list for all supported distro families.
#
# Naming convention:
#   INSTALL_PACKAGES_<FAMILY>  — packages to install via the primary package manager
#   AUR_PACKAGES_<FAMILY>      — AUR packages (Arch only, installed via paru)
#   REMOVE_PACKAGES_<FAMILY>   — packages to remove
#
# FAMILY uses underscores for multi-word names (e.g., FEDORA_ATOMIC).
# One package per line for easy diffing. Comments describe the reason.
#
# To add a new package: add it to the appropriate array for each distro family.
# Run scripts/validate-packages.sh to verify structural completeness.

# ─── Arch Linux (pacman + AUR) ──────────────────────────────────────────────

INSTALL_PACKAGES_ARCH=(
    # Packages will be added in a follow-up task
)

AUR_PACKAGES_ARCH=(
    # AUR packages will be added in a follow-up task
)

REMOVE_PACKAGES_ARCH=(
    htop            # Replaced by btop
    vim             # Replaced by neovim
)

# ─── Debian / Ubuntu (apt) ──────────────────────────────────────────────────

INSTALL_PACKAGES_DEBIAN=(
    # Stub — to be populated
)

REMOVE_PACKAGES_DEBIAN=(
    # Stub — to be populated
)

# ─── Fedora (dnf) ───────────────────────────────────────────────────────────

INSTALL_PACKAGES_FEDORA=(
    # Stub — to be populated
)

REMOVE_PACKAGES_FEDORA=(
    # Stub — to be populated
)

# ─── NixOS (nix) ────────────────────────────────────────────────────────────

INSTALL_PACKAGES_NIXOS=(
    # Stub — to be populated
    # Use nix package names here; the install script handles the nix-specific invocation.
)

REMOVE_PACKAGES_NIXOS=(
    # Stub — to be populated
)

# ─── Fedora Atomic (rpm-ostree) ─────────────────────────────────────────────

INSTALL_PACKAGES_FEDORA_ATOMIC=(
    # Stub — to be populated
)

REMOVE_PACKAGES_FEDORA_ATOMIC=(
    # Stub — to be populated
)

# ─── VanillaOS (apx) ────────────────────────────────────────────────────────

INSTALL_PACKAGES_VANILLA=(
    # Stub — to be populated
    # VanillaOS uses apx (container-based package manager via Podman/Distrobox).
)

REMOVE_PACKAGES_VANILLA=(
    # Stub — to be populated
)
