#!/bin/bash
set -euo pipefail

# ─── Inline Log Stubs ──────────────────────────────────────────────────────
# Lightweight log functions for use before common.sh is sourced (e.g., during
# remote fetch). These are overridden once common.sh is loaded in run_local().

_log_red='\033[0;31m' _log_yellow='\033[1;33m' _log_green='\033[0;32m' _log_nc='\033[0m'
if [[ "${NO_COLOR+set}" == "set" ]] || [[ ! -t 2 ]]; then
    _log_red='' _log_yellow='' _log_green='' _log_nc=''
fi
log_info()  { printf "${_log_green}[INFO]${_log_nc} %s\n" "$*" >&2; }
log_warn()  { printf "${_log_yellow}[WARN]${_log_nc} %s\n" "$*" >&2; }
log_error() { printf "${_log_red}[ERROR]${_log_nc} %s\n" "$*" >&2; }

# ─── Configuration ───────────────────────────────────────────────────────────

# SECURITY WARNING: REPO_URL controls where scripts are fetched from during
# remote execution (curl | bash). Overriding it via the environment redirects
# all downloads to an arbitrary server. This is an intentional power-user
# feature for forks and mirrors, but means you must trust the source.
# The readonly below prevents runtime re-assignment after this point.
readonly REPO_URL="${REPO_URL:-https://raw.githubusercontent.com/daankh/linux-configuration-script/main}"

# ─── Argument Forwarding ─────────────────────────────────────────────────────

FORWARD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            FORWARD_ARGS+=("--dry-run")
            ;;
        *)
            log_error "Unknown argument: $arg"
            log_error "Usage: ./setup.sh [--dry-run]"
            exit 1
            ;;
    esac
done

# ─── Remote Execution Support ────────────────────────────────────────────────

validate_fetched_script() {
    local file="$1"
    local name="$2"

    if [[ ! -s "$file" ]]; then
        log_error "Fetched $name is empty. The download may have failed."
        return 1
    fi

    local first_line
    read -r first_line < "$file"
    if [[ "$first_line" != "#!/bin/bash" ]]; then
        log_error "Fetched $name does not start with #!/bin/bash (got: '$first_line')."
        log_error "The server may have returned an error page instead of the script."
        return 1
    fi
}

run_remote() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT ERR INT TERM

    log_info "Fetching scripts from $REPO_URL ..."

    mkdir -p "$tmp_dir/lib"

    # Parallelize downloads — track PIDs and names for targeted error reporting
    local dl_pids=() dl_names=()

    curl -fsSL "$REPO_URL/lib/common.sh" -o "$tmp_dir/lib/common.sh" &
    dl_pids+=($!) dl_names+=("lib/common.sh")
    curl -fsSL "$REPO_URL/install-tools.sh" -o "$tmp_dir/install-tools.sh" &
    dl_pids+=($!) dl_names+=("install-tools.sh")
    curl -fsSL "$REPO_URL/cleanup-system.sh" -o "$tmp_dir/cleanup-system.sh" &
    dl_pids+=($!) dl_names+=("cleanup-system.sh")

    # Also attempt to fetch SHA256SUMS (optional — graceful degradation)
    local sha256_available=false
    curl -fsSL "$REPO_URL/SHA256SUMS" -o "$tmp_dir/SHA256SUMS" &
    local pid_sums=$!

    local download_failed=false
    local i
    for i in "${!dl_pids[@]}"; do
        if ! wait "${dl_pids[$i]}"; then
            log_error "Failed to download ${dl_names[$i]}."
            download_failed=true
        fi
    done

    if [[ "$download_failed" == "true" ]]; then
        wait "$pid_sums" 2>/dev/null || true
        log_error "One or more script downloads failed. Check your network and REPO_URL."
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
    # NOTE: Same-origin checksums protect against transport corruption (e.g., truncated
    # downloads, CDN cache poisoning) — not against a compromised origin server, since
    # SHA256SUMS is fetched from the same source as the scripts themselves.
    if [[ "$sha256_available" == "true" ]]; then
        log_info "Verifying script integrity..."
        if ! (cd "$tmp_dir" && sha256sum --check --strict SHA256SUMS); then
            log_error "SHA256 checksum verification failed. Scripts may have been tampered with."
            exit 1
        fi
        log_info "Integrity verification passed."
    else
        log_warn "SHA256SUMS not available — skipping integrity verification."
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
# Three execution modes:
#   1. Piped from curl (stdin is a pipe) → run_remote fetches scripts into a tmpdir
#   2. Local clone with lib/common.sh present → run_local uses the repo directly
#   3. Local without lib/common.sh → run_remote (e.g., only setup.sh was downloaded)

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
