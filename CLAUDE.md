# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Opinionated post-install script for **CachyOS** (Arch-based). Installs required development packages and removes unnecessary default packages so a fresh system is ready for work.

## Target System

- **Distro:** CachyOS (Arch-based)
- **Package managers:** `pacman` (official repos), `paru` (AUR helper)
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
- Use `pacman` for official repo packages; `paru` for AUR packages
