#!/bin/bash
set -euo pipefail

# ─── Colors and Logging ──────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Suppress ANSI codes per https://no-color.org — ${NO_COLOR+set} expands to "set"
# if NO_COLOR is defined (even if empty), so NO_COLOR= still triggers suppression.
if [[ "${NO_COLOR+set}" == "set" ]] || [[ ! -t 2 ]]; then
    RED='' YELLOW='' GREEN='' BLUE='' BOLD='' NC=''
fi

log_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$*" >&2
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$*" >&2
}

log_step() {
    printf "\n${BLUE}${BOLD}[STEP] ==> %s${NC}\n" "$*" >&2
}

# ─── Dry-Run Support ─────────────────────────────────────────────────────────

# DRY_RUN is intentionally inheritable from the environment so that setup.sh
# can propagate dry-run mode to child sub-scripts via the process environment,
# in addition to passing --dry-run on the command line. parse_args() overrides
# this value when --dry-run is passed as an argument.
DRY_RUN="${DRY_RUN:-false}"

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                log_info "Dry-run mode enabled. No changes will be made."
                ;;
            *)
                log_error "Unknown argument: $arg"
                log_error "Usage: <script> [--dry-run]"
                log_error "Options:"
                log_error "  --dry-run    Preview all commands without making any changes"
                exit 1
                ;;
        esac
    done
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        local _cmd_str
        printf -v _cmd_str '%q ' "$@"
        printf "${YELLOW}[DRY-RUN]${NC} %s\n" "$_cmd_str" >&2
    else
        "$@"
    fi
}

# ─── Distro Detection ────────────────────────────────────────────────────────

DISTRO_ID=""
DISTRO_ID_LIKE=""
DISTRO_VARIANT_ID=""
DISTRO_FAMILY=""

detect_distro() {
    log_step "Detecting distribution..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect distribution: /etc/os-release not found."
        exit 1
    fi

    # Single-pass read — avoids 6 child processes (two grep|cut|tr chains) and
    # sanitizes both keys and values to strip ANSI escapes or other control characters.
    # Keys are restricted to [A-Z0-9_] per the systemd os-release spec.
    # Values keep alphanumerics, underscore, dot, space, and hyphen (hyphen last to
    # avoid range interpretation in the character class).
    local key val
    while IFS='=' read -r key val; do
        key="${key^^}"
        key="${key//[^A-Z0-9_]/}"
        val="${val#\"}"
        val="${val%\"}"
        val="${val//[^[:alnum:]_. -]/}"
        case "$key" in
            ID)         DISTRO_ID="$val" ;;
            ID_LIKE)    DISTRO_ID_LIKE="$val" ;;
            # VARIANT_ID gets a second, tighter pass: dots and spaces are valid for
            # ID/ID_LIKE (e.g., "Debian GNU/Linux") but not for variant identifiers
            # like "silverblue" or "kinoite" that are used as exact-match tokens.
            VARIANT_ID) DISTRO_VARIANT_ID="${val//[^[:alnum:]_-]/}" ;;
        esac
    done < /etc/os-release

    log_info "Detected distro: $DISTRO_ID (ID_LIKE: ${DISTRO_ID_LIKE:-none}, VARIANT_ID: ${DISTRO_VARIANT_ID:-none})"

    # Derive distro family — order matters: check specific/immutable distros before
    # their parent families so derivatives are not misclassified.
    if [[ "$DISTRO_ID" == "nixos" ]]; then
        DISTRO_FAMILY="nixos"
    elif [[ "$DISTRO_ID" == "vanilla" ]]; then
        # VanillaOS is immutable (Debian Sid-based) — must not fall through to debian
        DISTRO_FAMILY="vanilla"
    elif [[ "$DISTRO_ID" == "fedora" && "$DISTRO_VARIANT_ID" =~ ^(silverblue|kinoite|sericea|onyx)$ ]]; then
        # Fedora Atomic desktops use rpm-ostree, not dnf — separate from regular Fedora.
        # Known variants only — new spins require adding to this list. As a fallback,
        # check_package_manager() will detect rpm-ostree even if VARIANT_ID is unrecognized.
        DISTRO_FAMILY="fedora-atomic"
    elif [[ "$DISTRO_ID" == "arch" || "$DISTRO_ID_LIKE" == *"arch"* ]]; then
        DISTRO_FAMILY="arch"
    elif [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID_LIKE" == *"debian"* || "$DISTRO_ID_LIKE" == *"ubuntu"* ]]; then
        DISTRO_FAMILY="debian"
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID_LIKE" == *"fedora"* ]]; then
        # Fallback: detect Fedora Atomic spins with unknown VARIANT_ID by checking
        # for rpm-ostree — works on live systems but not in CI-like environments.
        if command -v rpm-ostree &>/dev/null; then
            DISTRO_FAMILY="fedora-atomic"
        else
            DISTRO_FAMILY="fedora"
        fi
    else
        DISTRO_FAMILY="unknown"
        log_warn "Unknown distro family for '$DISTRO_ID'. Some features may not work."
    fi

    log_info "Distro family: $DISTRO_FAMILY"
}

# ─── Privilege Check ─────────────────────────────────────────────────────────

require_root() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping root check (dry-run mode)."
        return 0
    fi

    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script requires root privileges."
        log_error "Please run with: sudo $0"
        exit 1
    fi
}

# ─── Package Manager Checks ──────────────────────────────────────────────────

PKG_MANAGER=""
PARU_AVAILABLE=false
_AUR_HELPER_CHECKED=""

check_package_manager() {
    # rpm-ostree must be probed before dnf — Fedora Atomic ships both, and dnf
    # would shadow rpm-ostree, causing the wrong package manager to be selected.
    if command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    elif command -v apt &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v rpm-ostree &>/dev/null; then
        PKG_MANAGER="rpm-ostree"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v nix &>/dev/null; then
        PKG_MANAGER="nix"
    elif command -v apx &>/dev/null; then
        PKG_MANAGER="apx"
    else
        log_error "No supported package manager found (pacman, apt, rpm-ostree, dnf, nix, apx)."
        exit 1
    fi
    log_info "Package manager: $PKG_MANAGER"
}

check_aur_helper() {
    if [[ "$PKG_MANAGER" != "pacman" ]]; then
        _AUR_HELPER_CHECKED=true
        return 0
    fi

    if command -v paru &>/dev/null; then
        PARU_AVAILABLE=true
        log_info "AUR helper: paru"
    else
        PARU_AVAILABLE=false
        log_warn "'paru' (AUR helper) is not installed. AUR packages will be skipped."
    fi
    _AUR_HELPER_CHECKED=true
}

# ─── SUDO_USER Validation ────────────────────────────────────────────────────

[[ -v _SUDO_USER_RE ]] || readonly _SUDO_USER_RE='^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$'
[[ -v _SUDO_USER_VALIDATED ]] || _SUDO_USER_VALIDATED=""

_validate_sudo_user() {
    # Return immediately if already validated in this session — SUDO_USER is
    # immutable during execution (set by sudo(8)), so the result never changes.
    [[ -n "${_SUDO_USER_VALIDATED:-}" ]] && return 0

    # Trust boundary: SUDO_USER is set by sudo(8) and cannot be forged by
    # unprivileged callers, but is empty when running as direct root login.
    if [[ -z "${SUDO_USER:-}" ]]; then
        log_error "Cannot run paru as root without SUDO_USER (direct root login detected)."
        log_error "Please run this script via sudo."
        return 1
    fi
    # Reject invalid usernames — e.g., SUDO_USER=#0 would cause sudo -u to
    # resolve UID 0 (root), defeating the intended privilege drop for AUR ops.
    # NOTE: $_SUDO_USER_RE must be unquoted — in [[ =~ ]], quoting the RHS
    # forces literal string comparison instead of regex matching.
    if [[ ! "$SUDO_USER" =~ $_SUDO_USER_RE ]]; then
        # Strip non-printable chars before logging — SUDO_USER could contain ANSI
        # escape sequences that manipulate terminal output.
        local _safe_user="${SUDO_USER//[^[:print:]]/}"
        _safe_user="${_safe_user//$'\r'/}"
        _safe_user="${_safe_user//$'\t'/}"
        log_error "SUDO_USER contains invalid characters: '${_safe_user:0:64}'. Refusing to proceed."
        return 1
    fi
    readonly _SUDO_USER_VALIDATED=true
    return 0
}

# ─── Package Operation Helpers ────────────────────────────────────────────────

pacman_install() {
    if [[ $# -eq 0 ]]; then
        log_info "No pacman packages to install."
        return 0
    fi
    log_info "Installing $# package(s) via pacman..."
    run_cmd pacman -S --needed --noconfirm "$@"
}

paru_install() {
    if [[ $# -eq 0 ]]; then
        log_info "No AUR packages to install."
        return 0
    fi
    if [[ "$PARU_AVAILABLE" != "true" ]]; then
        log_warn "Skipping AUR packages (paru not available)."
        return 0
    fi
    _validate_sudo_user || return 1
    log_info "Installing $# package(s) via paru..."
    # paru must be in SUDO_USER's PATH — sudo -u preserves the user's environment
    run_cmd sudo -u "$SUDO_USER" paru -S --needed --noconfirm "$@"
}

pacman_remove() {
    if [[ $# -eq 0 ]]; then
        log_info "No packages to remove."
        return 0
    fi

    # In dry-run mode, skip the live package database query
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would check and remove $# package(s)..."
        run_cmd pacman -Rns --noconfirm "$@"
        return 0
    fi

    # Parse installed packages into an associative array for O(1) lookups
    local -A installed_set=()
    local to_remove=()
    local already_absent=0
    local line pkg_name
    while IFS= read -r line; do
        pkg_name="${line%% *}"
        installed_set["$pkg_name"]=1
    done < <(pacman -Q "$@" 2>/dev/null || true)

    for pkg in "$@"; do
        if [[ -v "installed_set[$pkg]" ]]; then
            to_remove+=("$pkg")
        else
            already_absent=$(( already_absent + 1 ))
        fi
    done

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        log_info "Removing ${#to_remove[@]} package(s)..."
        run_cmd pacman -Rns --noconfirm "${to_remove[@]}"
    fi

    if [[ $already_absent -gt 0 ]]; then
        log_info "$already_absent package(s) already absent, skipped."
    fi

    log_info "Cleanup complete. ${#to_remove[@]} package(s) removed, $already_absent already absent."
}

# ─── Generic Package Dispatchers ────────────────────────────────────────────

pkg_install() {
    if [[ $# -eq 0 ]]; then
        log_info "No packages to install."
        return 0
    fi
    case "$DISTRO_FAMILY" in
        arch)
            pacman_install "$@"
            ;;
        debian|fedora|nixos|fedora-atomic|vanilla)
            log_warn "pkg_install is not yet populated for distro family '$DISTRO_FAMILY'. Skipping."
            return 0
            ;;
        *)
            log_error "pkg_install is not supported for distro family '$DISTRO_FAMILY'."
            exit 1
            ;;
    esac
}

pkg_remove() {
    if [[ $# -eq 0 ]]; then
        log_info "No packages to remove."
        return 0
    fi
    case "$DISTRO_FAMILY" in
        arch)
            pacman_remove "$@"
            ;;
        debian|fedora|nixos|fedora-atomic|vanilla)
            log_warn "pkg_remove is not yet populated for distro family '$DISTRO_FAMILY'. Skipping."
            return 0
            ;;
        *)
            log_error "pkg_remove is not supported for distro family '$DISTRO_FAMILY'."
            exit 1
            ;;
    esac
}

# ─── Package Update Helpers ─────────────────────────────────────────────────

pacman_update() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would update all official packages via pacman..."
    else
        log_info "Updating all official packages via pacman..."
    fi
    if ! run_cmd pacman -Syu --noconfirm; then
        log_error "pacman -Syu failed. Try running 'pacman -Syu' manually to see the full error output."
        return 1
    fi
}

paru_update() {
    if [[ "$PARU_AVAILABLE" != "true" ]]; then
        log_warn "Skipping AUR update (paru not available)."
        return 0
    fi
    _validate_sudo_user || return 1
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would update AUR packages via paru..."
        run_cmd sudo -u "$SUDO_USER" paru -Sua --noconfirm
        return 0
    fi
    log_info "Updating AUR packages via paru..."
    # -Sua updates only AUR packages — official repos already synced by pacman_update()
    if ! run_cmd sudo -u "$SUDO_USER" paru -Sua --noconfirm; then
        # SUDO_USER is safe to log here — _validate_sudo_user confirmed it matches [a-zA-Z0-9_.-]
        log_error "paru -Sua failed. Try running 'paru -Sua' as $SUDO_USER to see the full error output."
        return 1
    fi
}

pkg_update() {
    case "$DISTRO_FAMILY" in
        arch)
            # pacman -Syu must complete first: AUR builds link against updated official libs.
            pacman_update || return 1
            paru_update   || return 1
            ;;
        debian|fedora|nixos|fedora-atomic|vanilla)
            log_warn "pkg_update is not yet populated for distro family '$DISTRO_FAMILY'. Skipping."
            return 0
            ;;
        *)
            log_error "pkg_update is not supported for distro family '$DISTRO_FAMILY'."
            exit 1
            ;;
    esac
}
