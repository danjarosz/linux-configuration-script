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
            log_error "Usage: ./install-tools.sh [--dry-run]"
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
    read -r -n 200 first_line < "$file"
    if [[ "$first_line" != "#!/bin/bash" ]]; then
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
    # _cleanup_install_tmpdir is visible after run_remote() returns. This is intentional:
    # the trap must reference a callable name. The function body references dl_pids,
    # pid_sums, and tmp_dir by name — they are locals of run_remote() and remain
    # accessible as long as run_remote() is on the call stack (which covers all trap
    # scenarios: EXIT fires before run_remote returns, ERR/INT/TERM fire while active).
    _cleanup_install_tmpdir() {
        # Kill any still-running curl background jobs before removing the tmpdir
        kill ${dl_pids[@]+"${dl_pids[@]}"} ${pid_sums:+"$pid_sums"} 2>/dev/null || true
        # Reap only the known curl jobs — avoids blocking on unrelated background children
        wait ${dl_pids[@]+"${dl_pids[@]}"} ${pid_sums:+"$pid_sums"} 2>/dev/null || true
        rm -rf "$tmp_dir"
    }
    trap '_cleanup_install_tmpdir' EXIT ERR INT TERM HUP QUIT

    log_info "Fetching scripts from $REPO_URL ..."

    mkdir -p "$tmp_dir/lib"

    # Download only the files this script needs
    curl -fsSL "$REPO_URL/lib/common.sh" -o "$tmp_dir/lib/common.sh" &
    dl_pids+=($!) dl_names+=("lib/common.sh")
    curl -fsSL "$REPO_URL/lib/packages.sh" -o "$tmp_dir/lib/packages.sh" &
    dl_pids+=($!) dl_names+=("lib/packages.sh")

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

    # Reap SHA256SUMS download separately — it is optional (graceful degradation).
    # 2>/dev/null: curl's stderr is suppressed because a 404 is expected when the
    # remote does not publish checksums; sums_ok=false triggers a warning below.
    local sums_ok=false
    if wait "$pid_sums" 2>/dev/null; then
        sums_ok=true
    fi

    if [[ "$download_failed" == "true" ]]; then
        log_error "One or more script downloads failed. Check your network and REPO_URL."
        exit 1
    fi

    validate_fetched_script "$tmp_dir/lib/common.sh"   "lib/common.sh"   || exit 1
    validate_fetched_script "$tmp_dir/lib/packages.sh" "lib/packages.sh" || exit 1

    # Verify integrity via SHA256SUMS if available (--ignore-missing: only check files
    # present in the tmpdir — individual scripts don't download the full suite).
    # NOTE: Same-origin checksums protect against transport corruption (e.g., truncated
    # downloads, CDN cache poisoning) — not against a compromised origin server, since
    # SHA256SUMS is fetched from the same source as the scripts themselves.
    if [[ "$sums_ok" == "true" ]]; then
        log_info "Verifying script integrity..."
        local verify_out_file="$tmp_dir/sha256sum.out"
        pushd "$tmp_dir" >/dev/null
        if ! sha256sum --check --strict --ignore-missing SHA256SUMS >"$verify_out_file" 2>&1; then
            popd >/dev/null
            log_error "SHA256 checksum verification failed. Scripts may have been tampered with."
            log_error "sha256sum output:"
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

    run_local "$tmp_dir"
}

# ─── Local Execution ─────────────────────────────────────────────────────────

run_local() {
    local base_dir="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

    # shellcheck source=lib/common.sh
    source "$base_dir/lib/common.sh"
    # shellcheck source=lib/packages.sh
    source "$base_dir/lib/packages.sh"

    parse_args ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}

    # ─── Initialization ──────────────────────────────────────────────────────
    # NOTE: This boilerplate is intentionally duplicated so sub-scripts can run standalone.
    # When invoked from setup.sh, the guards skip already-completed detection.

    [[ -n "${DISTRO_FAMILY:-}" ]] || detect_distro
    require_root
    [[ -n "${PKG_MANAGER:-}" ]] || check_package_manager
    [[ -n "${_AUR_HELPER_CHECKED:-}" ]] || check_aur_helper

    # ─── Package Lists ───────────────────────────────────────────────────────
    # Loaded from lib/packages.sh — dispatch to the correct distro family arrays.

    INSTALL_PACKAGES=()
    AUR_PACKAGES=()

    case "$DISTRO_FAMILY" in
        arch)
            INSTALL_PACKAGES=("${INSTALL_PACKAGES_ARCH[@]+"${INSTALL_PACKAGES_ARCH[@]}"}")
            AUR_PACKAGES=("${AUR_PACKAGES_ARCH[@]+"${AUR_PACKAGES_ARCH[@]}"}")
            ;;
        debian)
            INSTALL_PACKAGES=("${INSTALL_PACKAGES_DEBIAN[@]+"${INSTALL_PACKAGES_DEBIAN[@]}"}")
            [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]] || log_warn "Debian package list is not yet populated. No packages will be installed."
            ;;
        fedora)
            INSTALL_PACKAGES=("${INSTALL_PACKAGES_FEDORA[@]+"${INSTALL_PACKAGES_FEDORA[@]}"}")
            [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]] || log_warn "Fedora package list is not yet populated. No packages will be installed."
            ;;
        nixos)
            INSTALL_PACKAGES=("${INSTALL_PACKAGES_NIXOS[@]+"${INSTALL_PACKAGES_NIXOS[@]}"}")
            [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]] || log_warn "NixOS package list is not yet populated. No packages will be installed."
            ;;
        fedora-atomic)
            INSTALL_PACKAGES=("${INSTALL_PACKAGES_FEDORA_ATOMIC[@]+"${INSTALL_PACKAGES_FEDORA_ATOMIC[@]}"}")
            [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]] || log_warn "Fedora Atomic package list is not yet populated. No packages will be installed."
            ;;
        vanilla)
            INSTALL_PACKAGES=("${INSTALL_PACKAGES_VANILLA[@]+"${INSTALL_PACKAGES_VANILLA[@]}"}")
            [[ ${#INSTALL_PACKAGES[@]} -gt 0 ]] || log_warn "VanillaOS package list is not yet populated. No packages will be installed."
            ;;
        *)
            log_error "No package list defined for distro family '$DISTRO_FAMILY'."
            exit 1
            ;;
    esac

    # ─── Installation Logic ─────────────────────────────────────────────────

    log_step "Installing packages..."

    pkg_install ${INSTALL_PACKAGES[@]+"${INSTALL_PACKAGES[@]}"}

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        paru_install ${AUR_PACKAGES[@]+"${AUR_PACKAGES[@]}"}
    fi

    log_step "Installation complete."
}

# ─── Entrypoint ──────────────────────────────────────────────────────────────
# Execution modes:
#   1. Piped from curl (stdin is a pipe) → run_remote fetches lib/common.sh into a tmpdir
#   2. Local clone with lib/common.sh present → run_local uses the repo directly
#   3. Local without lib/common.sh → run_remote

if [[ -p /dev/stdin ]]; then
    run_remote
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [[ -f "$SCRIPT_DIR/lib/common.sh" ]] && [[ -f "$SCRIPT_DIR/lib/packages.sh" ]]; then
        run_local "$SCRIPT_DIR"
    else
        run_remote
    fi
fi
