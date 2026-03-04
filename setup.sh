#!/bin/bash
set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────

readonly REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/daankh/linux-configuration-script/main}"

# ─── Argument Forwarding ─────────────────────────────────────────────────────

FORWARD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            FORWARD_ARGS+=("--dry-run")
            ;;
        *)
            echo "[ERROR] Unknown argument: $arg" >&2
            echo "Usage: ./setup.sh [--dry-run]" >&2
            exit 1
            ;;
    esac
done

# ─── Remote Execution Support ────────────────────────────────────────────────

validate_fetched_script() {
    local file="$1"
    local name="$2"

    if [[ ! -s "$file" ]]; then
        echo "[ERROR] Fetched $name is empty. The download may have failed." >&2
        return 1
    fi

    local first_line
    first_line="$(head -n 1 "$file")"
    if [[ "$first_line" != "#!/bin/bash" ]]; then
        echo "[ERROR] Fetched $name does not start with #!/bin/bash (got: '$first_line')." >&2
        echo "[ERROR] The server may have returned an error page instead of the script." >&2
        return 1
    fi
}

run_remote() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT ERR INT TERM

    echo "Fetching scripts from $REPO_URL ..."

    mkdir -p "$tmp_dir/lib"

    # Parallelize downloads
    curl -fsSL "$REPO_URL/lib/common.sh" -o "$tmp_dir/lib/common.sh" &
    local pid_common=$!
    curl -fsSL "$REPO_URL/install-tools.sh" -o "$tmp_dir/install-tools.sh" &
    local pid_install=$!
    curl -fsSL "$REPO_URL/cleanup-system.sh" -o "$tmp_dir/cleanup-system.sh" &
    local pid_cleanup=$!

    # Also attempt to fetch SHA256SUMS (optional — graceful degradation)
    local sha256_available=false
    curl -fsSL "$REPO_URL/SHA256SUMS" -o "$tmp_dir/SHA256SUMS" &
    local pid_sums=$!

    local download_failed=false
    wait "$pid_common" || download_failed=true
    wait "$pid_install" || download_failed=true
    wait "$pid_cleanup" || download_failed=true

    if [[ "$download_failed" == "true" ]]; then
        echo "[ERROR] One or more script downloads failed. Check your network and REPO_URL." >&2
        exit 1
    fi

    # Check if SHA256SUMS was fetched successfully
    if wait "$pid_sums" 2>/dev/null; then
        sha256_available=true
    fi

    # Validate fetched scripts are non-empty and start with #!/bin/bash
    validate_fetched_script "$tmp_dir/lib/common.sh" "lib/common.sh"
    validate_fetched_script "$tmp_dir/install-tools.sh" "install-tools.sh"
    validate_fetched_script "$tmp_dir/cleanup-system.sh" "cleanup-system.sh"

    # Verify integrity via SHA256SUMS if available
    if [[ "$sha256_available" == "true" ]]; then
        echo "Verifying script integrity..."
        if ! (cd "$tmp_dir" && sha256sum --check --strict SHA256SUMS); then
            echo "[ERROR] SHA256 checksum verification failed. Scripts may have been tampered with." >&2
            exit 1
        fi
        echo "Integrity verification passed."
    else
        echo "[WARN] SHA256SUMS not available — skipping integrity verification." >&2
    fi

    chmod +x "$tmp_dir/install-tools.sh" "$tmp_dir/cleanup-system.sh"

    run_local "$tmp_dir"
}

# ─── Local Execution ─────────────────────────────────────────────────────────

run_local() {
    local base_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

    # shellcheck source=lib/common.sh
    source "$base_dir/lib/common.sh"

    # Parse args in setup.sh context for dry-run awareness
    parse_args ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}

    detect_distro
    require_root

    log_step "Starting system setup..."

    "$base_dir/cleanup-system.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}
    "$base_dir/install-tools.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}

    log_step "Setup complete!"
    log_info "System is ready."
}

# ─── Entrypoint ──────────────────────────────────────────────────────────────

if [[ -p /dev/stdin ]] || [[ ! -t 0 && "${BASH_SOURCE[0]:-}" != "$0" ]]; then
    run_remote
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
        run_local "$SCRIPT_DIR"
    else
        run_remote
    fi
fi
