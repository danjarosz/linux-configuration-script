# Linux Configuration Script

Opinionated post-install script for Linux. It installs all packages needed for a development workflow and removes unnecessary packages that ship with a fresh installation.

Currently supports **Arch-based** distros, with a structure ready for Debian-based and Fedora-based support.

## Goals

- **Install** development tools, utilities, and applications required for daily work
- **Remove** bloatware and unused packages from the default installation
- **Automate** the setup so a fresh system is ready to use with a single script run

## Supported Distro Families

- **Arch** — `pacman` / `paru` (Arch, EndeavourOS, Manjaro, etc.)
- **Debian** — placeholder, not yet implemented
- **Fedora** — placeholder, not yet implemented

## Usage

### Prerequisites

- A fresh Linux installation from a supported distro family (see above)
- `sudo` access — the script installs and removes system packages
- `curl` — required only for remote execution (see below)
- For Arch-based distros: `pacman` must be available (ships by default); `paru` is optional for AUR packages

### Quick Start

Clone the repository and run the entrypoint:

```bash
git clone https://github.com/daankh/linux-configuration-script.git
cd linux-configuration-script
sudo ./setup.sh
```

This runs `cleanup-system.sh` first (to remove unwanted packages), then `install-tools.sh`.

### Remote Execution (without cloning)

Run directly from the remote repository — the script fetches everything it needs into a temporary directory:

```bash
curl -fsSL https://raw.githubusercontent.com/daankh/linux-configuration-script/main/setup.sh | sudo bash
```

When fetching scripts remotely, `setup.sh` automatically:

1. Downloads all scripts in parallel for faster startup
2. Validates each fetched file is non-empty and starts with `#!/bin/bash`
3. Verifies SHA256 checksums if a `SHA256SUMS` file is available (warns and continues if unavailable)

> **Note:** `REPO_URL` is `readonly` after initial assignment. It defaults to this repository's GitHub raw URL and can only be overridden via environment variable before the script starts:

```bash
curl -fsSL https://example.com/setup.sh | sudo REPO_URL=https://example.com bash
```

### Dry Run

Preview every command that would be executed, without making any changes to the system:

```bash
./setup.sh --dry-run
```

Dry-run mode skips the root privilege check, so you can preview without `sudo`. Each command that would normally run is printed prefixed with `[dry-run]`.

### Running Individual Scripts

Each script can be run independently:

```bash
sudo ./install-tools.sh        # Install packages only
sudo ./cleanup-system.sh       # Remove unwanted packages only
```

Both support the `--dry-run` flag:

```bash
./install-tools.sh --dry-run
./cleanup-system.sh --dry-run
```

### What Each Script Does

| Script | Purpose |
|---|---|
| `setup.sh` | Entrypoint — detects the distro, checks privileges, then runs cleanup + install in order |
| `install-tools.sh` | Installs development tools and utilities from the distro's package manager (and AUR on Arch) |
| `cleanup-system.sh` | Removes unwanted packages that ship with the default installation |

### Customizing Package Lists

Package lists are defined as arrays inside each script, organized by distro family. To add or remove packages, edit the relevant `case` block:

- **`install-tools.sh`** — `INSTALL_PACKAGES` and `AUR_PACKAGES` (Arch only)
- **`cleanup-system.sh`** — `REMOVE_PACKAGES`

Each array uses one package per line for easy reading and diffing:

```bash
INSTALL_PACKAGES=(
    git
    neovim
    btop
)
```

> Review the package lists before executing. Always run with `--dry-run` first to preview what will happen.

### NO_COLOR Support

All log output respects the [NO_COLOR](https://no-color.org/) convention. ANSI color codes are suppressed when:

- The `NO_COLOR` environment variable is set (any value), or
- stderr is not a TTY (e.g., output is piped or redirected)

```bash
NO_COLOR=1 sudo ./setup.sh              # No colors
sudo ./setup.sh 2>&1 | tee setup.log    # No colors (piped)
```

## Project Structure

```
.
├── setup.sh              # Entrypoint — orchestrates install + cleanup
├── lib/
│   └── common.sh         # Shared: distro detection, privilege checks, dry-run, logging
├── install-tools.sh      # Package installation (placeholder — packages added in follow-up)
├── cleanup-system.sh     # Package removal (unwanted distro packages)
├── SHA256SUMS            # Checksums for integrity verification during remote execution
└── .github/
    └── workflows/
        └── checksums.yml # Auto-regenerates SHA256SUMS on push to main
```
