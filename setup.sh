#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/daankh/linux-configuration-script/main}"

# ─── Argument Forwarding ─────────────────────────────────────────────────────

FORWARD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            FORWARD_ARGS+=("--dry-run")
            ;;
        *)
            echo "Error: Unknown argument: $arg" >&2
            echo "Usage: ./setup.sh [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# ─── Remote Execution Support ────────────────────────────────────────────────

run_remote() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    echo "Fetching scripts from $REPO_URL ..."

    mkdir -p "$tmp_dir/lib"

    curl -fsSL "$REPO_URL/lib/common.sh" -o "$tmp_dir/lib/common.sh"
    curl -fsSL "$REPO_URL/install-tools.sh" -o "$tmp_dir/install-tools.sh"
    curl -fsSL "$REPO_URL/cleanup-system.sh" -o "$tmp_dir/cleanup-system.sh"

    chmod +x "$tmp_dir/install-tools.sh" "$tmp_dir/cleanup-system.sh"

    run_local "$tmp_dir"
}

# ─── Local Execution ─────────────────────────────────────────────────────────

run_local() {
    local base_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

    # shellcheck source=lib/common.sh
    source "$base_dir/lib/common.sh"

    # Parse args in setup.sh context for dry-run awareness
    parse_args "${FORWARD_ARGS[@]}"

    detect_distro
    require_root

    log_step "Starting system setup..."

    "$base_dir/cleanup-system.sh" "${FORWARD_ARGS[@]}"
    "$base_dir/install-tools.sh" "${FORWARD_ARGS[@]}"

    log_step "Setup complete!"
    log_info "System is ready."
}

# ─── Entrypoint ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    run_local "$SCRIPT_DIR"
else
    # lib/common.sh not found locally — assume remote execution (curl | bash)
    run_remote
fi
