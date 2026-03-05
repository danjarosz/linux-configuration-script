# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Opinionated post-install script for Linux. Installs required development packages and removes unnecessary default packages so a fresh system is ready for work. Currently supports Arch-based distros, extensible to Debian-based and Fedora-based.

## Target System

- **Distro families:** Arch-based (currently supported), Debian-based and Fedora-based (placeholder)
- **Package managers:** `pacman` / `paru` for Arch; `apt` for Debian; `dnf` for Fedora
- **Shell:** Bash scripts (`#!/bin/bash`)

## Running

```bash
./setup.sh
```

The script requires elevated privileges for package operations.

## Conventions

- All scripts use Bash; use `set -euo pipefail` at the top of each script
- Package lists should be easy to read and modify (one package per line in arrays)
- Separate install and remove operations clearly
- For Arch-based distros: use `pacman` for official repo packages; `paru` for AUR packages
- Use generic `pkg_install` / `pkg_remove` / `pkg_update` dispatchers; add family-specific helpers as needed

## Additional requirements

- always update CLAUDE.md and README.md with the relevant changes when you finish work

## Code Patterns

- **Safe array expansion:** use `${arr[@]+"${arr[@]}"}` idiom for arrays that may be empty (prevents `set -u` crash in Bash < 4.4)
- **Logging to stderr:** all `log_*` functions write to stderr so stdout stays clean for piping
- **NO_COLOR support:** ANSI color vars are cleared when `NO_COLOR` is set or stderr is not a TTY (per [no-color.org](https://no-color.org/))
- **Safe os-release parsing:** read `/etc/os-release` in a single `while IFS='=' read -r` loop — never `source` it (RCE risk); keys are uppercased with `${key^^}` first (normalizes non-standard lowercase keys), then sanitized with `${key//[^A-Z0-9_]/}` (restricted to `[A-Z0-9_]` per the systemd os-release spec); values with `${val//[^[:alnum:]_. -]/}` using bash builtins (zero forks; hyphen last to avoid range interpretation)
- **`printf -v` in run_cmd:** use `printf -v _cmd_str '%q ' "$@"` (no subshell fork) to preserve argument boundaries in dry-run output
- **`REPO_URL` is readonly:** prevents runtime override after assignment (security hardening for `curl | bash`)
- **Privilege management:** `pacman` runs as root (the script already has root); `paru` drops to `$SUDO_USER` since AUR helpers refuse root; `SUDO_USER` is validated against `^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$` to reject `#`-prefixed values that `sudo -u` would interpret as UIDs
- **Associative array for package lookups:** in `pacman_remove()`, parse `pacman -Q` output into a `local -A` associative array for O(1) installed-package checks instead of per-package subshell grep
- **Inline log stubs:** all scripts with remote execution support (`setup.sh`, `install-tools.sh`, `cleanup-system.sh`, `update-tools.sh`) define lightweight `log_info`/`log_warn`/`log_error`/`log_step` functions before `common.sh` is sourced so remote-fetch output uses consistent `[INFO]`/`[WARN]`/`[ERROR]`/`[STEP]` prefixes; overridden when `common.sh` loads
- **Idempotent init guards:** sub-scripts use `[[ -n "${VAR:-}" ]] || init_func` guards so detection runs once when orchestrated by `setup.sh` but still works standalone
- **Self-contained remote execution:** each individual script (`install-tools.sh`, `cleanup-system.sh`, `update-tools.sh`) duplicates the remote-execution boilerplate (log stubs, `REPO_URL`, `validate_fetched_script`, `run_remote`, `run_local`, entrypoint) so it can be piped from `curl` independently; each fetches only `lib/common.sh` (not the full suite) and uses `sha256sum --check --strict --ignore-missing` for partial SHA256SUMS verification
- **`paru -Sua` for AUR updates:** `paru_update()` uses `-Sua` (not `-Syu`) because official repos are already synced by the preceding `pacman_update()` call
