#!/bin/bash
set -euo pipefail

# ─── Package Configuration Validator ─────────────────────────────────────────
#
# Validates that lib/packages.sh defines all required package arrays for every
# supported distro family. Run locally or in CI to catch missing arrays early.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Derive repo root from SCRIPT_DIR without a second subshell fork
REPO_ROOT="${SCRIPT_DIR%/*}"

if [[ ! -f "$REPO_ROOT/lib/packages.sh" ]]; then
    printf "ERROR: lib/packages.sh not found at %s/lib/packages.sh\n" "$REPO_ROOT" >&2
    exit 1
fi

# shellcheck source=../lib/packages.sh
source "$REPO_ROOT/lib/packages.sh"

# ─── Expected Arrays ──────────────────────────────────────────────────────────

FAMILIES=(ARCH DEBIAN FEDORA NIXOS FEDORA_ATOMIC VANILLA)

# Every family must have INSTALL and REMOVE arrays
REQUIRED_PREFIXES=(INSTALL_PACKAGES REMOVE_PACKAGES)

# Arch has an additional AUR array
ARCH_EXTRA=(AUR_PACKAGES_ARCH)

# ─── Validation ───────────────────────────────────────────────────────────────

errors=0

for family in "${FAMILIES[@]}"; do
    for prefix in "${REQUIRED_PREFIXES[@]}"; do
        var_name="${prefix}_${family}"
        # declare -p output begins with "declare -a" for indexed arrays.
        # Checking this prefix ensures the variable is an array, not a plain
        # string that happens to share a name (e.g., an env var exported before
        # this script ran).
        if ! declare -p "$var_name" 2>/dev/null | grep -q '^declare -a '; then
            printf "ERROR: %s is not declared as an indexed array in lib/packages.sh\n" "$var_name" >&2
            (( ++errors )) || true
        fi
    done
done

for var_name in "${ARCH_EXTRA[@]}"; do
    if ! declare -p "$var_name" 2>/dev/null | grep -q '^declare -a '; then
        printf "ERROR: %s is not declared as an indexed array in lib/packages.sh\n" "$var_name" >&2
        (( ++errors )) || true
    fi
done

# ─── Result ───────────────────────────────────────────────────────────────────

if [[ $errors -gt 0 ]]; then
    printf "\nValidation FAILED: %d missing array(s).\n" "$errors" >&2
    exit 1
fi

printf "Validation passed: all package arrays are declared.\n" >&2
