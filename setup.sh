#!/bin/bash
set -euo pipefail

# ─── Inline Log Stubs ──────────────────────────────────────────────────────
# Lightweight log functions for use before common.sh is sourced (e.g., during
# remote fetch). These are overridden once common.sh is loaded in run_local().

_log_red='\033[0;31m' _log_yellow='\033[1;33m' _log_green='\033[0;32m'
_log_blue='\033[0;34m' _log_bold='\033[1m' _log_nc='\033[0m'
# Suppress ANSI codes per https://no-color.org — ${NO_COLOR+set} expands to "set"
# if NO_COLOR is defined (even if empty), so NO_COLOR= still triggers suppression.
if [[ "${NO_COLOR+set}" == "set" ]] || [[ ! -t 2 ]]; then
    _log_red='' _log_yellow='' _log_green='' _log_blue='' _log_bold='' _log_nc=''
fi
log_info()  { printf "${_log_green}[INFO]${_log_nc} %s\n" "$*" >&2; }
log_warn()  { printf "${_log_yellow}[WARN]${_log_nc} %s\n" "$*" >&2; }
log_error() { printf "${_log_red}[ERROR]${_log_nc} %s\n" "$*" >&2; }
log_step()  { printf "\n${_log_blue}${_log_bold}[STEP] ==> %s${_log_nc}\n" "$*" >&2; }

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

# Sanity-check only: confirms the server returned a shell script, not an HTTP
# error page or empty response. Actual integrity verification is done by
# sha256sum --check below.
validate_fetched_script() {
    local file="$1"
    local name="$2"

    if [[ ! -s "$file" ]]; then
        log_error "Fetched $name is empty. The download may have failed."
        log_error "Check that REPO_URL is reachable: $REPO_URL"
        return 1
    fi

    local first_line
    # -n 200 counts characters (Unicode code points), not bytes — on multi-byte
    # locales a crafted response could exceed 200 bytes, but the content is
    # further truncated to 120 chars before logging so this is acceptable.
    read -r -n 200 first_line < "$file"
    # Exact match — #!/bin/bash\r (CRLF from a misconfigured server) is intentionally
    # rejected so that Windows-style line endings are caught, not silently accepted.
    if [[ "$first_line" != "#!/bin/bash" ]]; then
        # Strip non-printable bytes (ANSI escapes, terminal control codes) and \r
        # (which [[:print:]] passes in most locales) from server-controlled content
        # before logging. \r alone would move the cursor to column 0, letting a
        # crafted response visually overwrite the error message on the terminal.
        first_line="${first_line//[^[:print:]]/}"
        first_line="${first_line//$'\r'/}"
        log_error "Fetched $name: expected '#!/bin/bash' on line 1, got: '${first_line:0:120}'."
        log_error "The server may have returned an error page instead of the script."
        log_error "Check that REPO_URL is reachable: $REPO_URL"
        return 1
    fi
}

run_remote() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    local dl_pids=() dl_names=()
    local pid_sums=""

    # NOTE: Bash promotes nested function definitions to global scope —
    # _cleanup_setup_tmpdir is visible after run_remote() returns. This is intentional:
    # the trap must reference a callable name. The function body references dl_pids,
    # pid_sums, and tmp_dir by name — they are locals of run_remote() and remain
    # accessible as long as run_remote() is on the call stack (which covers all trap
    # scenarios: EXIT fires before run_remote returns, ERR/INT/TERM fire while active).
    _cleanup_setup_tmpdir() {
        # Kill any still-running curl background jobs before removing the tmpdir
        kill ${dl_pids[@]+"${dl_pids[@]}"} ${pid_sums:+"$pid_sums"} 2>/dev/null || true
        # Reap only the known curl jobs — avoids blocking on unrelated background children
        wait ${dl_pids[@]+"${dl_pids[@]}"} ${pid_sums:+"$pid_sums"} 2>/dev/null || true
        rm -rf "$tmp_dir"
    }
    trap '_cleanup_setup_tmpdir' EXIT ERR INT TERM HUP QUIT

    log_info "Fetching scripts from $REPO_URL ..."

    mkdir -p "$tmp_dir/lib"

    # Parallelize downloads — track PIDs and names for targeted error reporting

    curl -fsSL "$REPO_URL/lib/common.sh" -o "$tmp_dir/lib/common.sh" &
    dl_pids+=($!) dl_names+=("lib/common.sh")
    curl -fsSL "$REPO_URL/install-tools.sh" -o "$tmp_dir/install-tools.sh" &
    dl_pids+=($!) dl_names+=("install-tools.sh")
    curl -fsSL "$REPO_URL/cleanup-system.sh" -o "$tmp_dir/cleanup-system.sh" &
    dl_pids+=($!) dl_names+=("cleanup-system.sh")
    # update-tools.sh is downloaded but NOT executed by setup.sh — it exists here so that
    # sha256sum --check --strict (without --ignore-missing) can verify ALL files listed in
    # SHA256SUMS, ensuring no checksums are silently skipped.
    curl -fsSL "$REPO_URL/update-tools.sh" -o "$tmp_dir/update-tools.sh" &
    dl_pids+=($!) dl_names+=("update-tools.sh")

    # Also attempt to fetch SHA256SUMS (optional — graceful degradation)
    curl -fsSL "$REPO_URL/SHA256SUMS" -o "$tmp_dir/SHA256SUMS" &
    pid_sums=$!

    local download_failed=false
    local i
    for i in "${!dl_pids[@]}"; do
        if ! wait "${dl_pids[$i]}"; then
            log_error "Failed to download ${dl_names[$i]}."
            download_failed=true
        fi
    done

    # Reap SHA256SUMS download once; store the outcome to avoid double-wait
    # (a PID can be recycled between two wait calls, returning wrong status)
    local sums_ok=false
    if wait "$pid_sums" 2>/dev/null; then
        sums_ok=true
    fi

    if [[ "$download_failed" == "true" ]]; then
        log_error "One or more script downloads failed. Check your network and REPO_URL."
        exit 1
    fi

    # Validate fetched scripts are non-empty and start with #!/bin/bash
    validate_fetched_script "$tmp_dir/lib/common.sh"      "lib/common.sh"      || exit 1
    validate_fetched_script "$tmp_dir/install-tools.sh"   "install-tools.sh"   || exit 1
    validate_fetched_script "$tmp_dir/cleanup-system.sh"  "cleanup-system.sh"  || exit 1
    validate_fetched_script "$tmp_dir/update-tools.sh"    "update-tools.sh"    || exit 1

    # Verify integrity via SHA256SUMS if available
    # NOTE: Same-origin checksums protect against transport corruption (e.g., truncated
    # downloads, CDN cache poisoning) — not against a compromised origin server, since
    # SHA256SUMS is fetched from the same source as the scripts themselves.
    if [[ "$sums_ok" == "true" ]]; then
        log_info "Verifying script integrity..."
        local verify_out_file="$tmp_dir/sha256sum.out"
        pushd "$tmp_dir" >/dev/null
        if ! sha256sum --check --strict SHA256SUMS >"$verify_out_file" 2>&1; then
            popd >/dev/null
            log_error "SHA256 checksum verification failed. Scripts may have been tampered with."
            log_error "sha256sum output:"
            # Sanitize server-influenced output: strip non-printable bytes (ANSI escapes,
            # terminal control codes) and \r (passes [[:print:]] in most locales but
            # causes terminal-overwrite when printed). Cap each line at 200 chars, 20 lines max.
            if [[ -s "$verify_out_file" ]]; then
                local _line _count=0
                while IFS= read -r _line && (( _count < 20 )); do
                    _line="${_line//[^[:print:]]/}"
                    _line="${_line//$'\r'/}"
                    printf '%s\n' "${_line:0:200}" >&2
                    (( ++_count )) || true
                done < "$verify_out_file"
            fi
            exit 1
        fi
        popd >/dev/null
        log_info "Integrity verification passed."
    else
        log_warn "SHA256SUMS not available — cannot verify integrity of downloaded scripts."
        log_warn "Continuing will execute unverified root-level code from: $REPO_URL"
    fi

    # update-tools.sh is verified above (SHA256) but intentionally not chmod'd nor
    # called by setup.sh — it is a standalone operation. If you add a call to it
    # here, add it to the chmod line too.
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
    check_package_manager

    log_step "Starting system setup..."

    "$base_dir/cleanup-system.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}
    "$base_dir/install-tools.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}

    log_step "Setup complete!"
    log_info "System is ready."
}

# ─── Entrypoint ──────────────────────────────────────────────────────────────
# Execution modes:
#   1. Piped from curl (stdin is a pipe) → run_remote fetches scripts into a tmpdir
#   2. Local clone with lib/common.sh present → run_local uses the repo directly
#   3. Local without lib/common.sh → run_remote (e.g., only setup.sh was downloaded)

if [[ -p /dev/stdin ]]; then
    run_remote
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
        run_local "$SCRIPT_DIR"
    else
        run_remote
    fi
fi
