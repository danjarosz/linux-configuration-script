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
- Use generic `pkg_install` / `pkg_remove` dispatchers; add family-specific helpers as needed

## Additional requirements

- always update CLAUDE.md and README.md with the relevant changes when you finish work