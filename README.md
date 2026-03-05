# Linux Configuration Script

Opinionated post-install script for Linux. It installs all packages needed for a development workflow and removes unnecessary packages that ship with a fresh installation.

Currently supports **Arch-based** distros (primary), with detection and stub support for NixOS, Debian, Fedora, Fedora Atomic, and VanillaOS.

## Goals

- **Install** development tools, utilities, and applications required for daily work
- **Remove** bloatware and unused packages from the default installation
- **Update** all installed packages to their latest versions
- **Automate** the setup so a fresh system is ready to use with a single script run

## Supported Distro Families

| Family | Package Manager | Status | Examples |
|--------|----------------|--------|----------|
| **Arch** | `pacman` / `paru` | Supported | Arch, CachyOS, EndeavourOS, Manjaro |
| **NixOS** | `nix` | Stub | NixOS |
| **Debian** | `apt` | Stub | Debian, Ubuntu, Linux Mint, Pop!_OS |
| **Fedora** | `dnf` | Stub | Fedora Workstation, RHEL |
| **Fedora Atomic** | `rpm-ostree` | Stub | Silverblue, Kinoite, Sericea, Onyx |
| **VanillaOS** | `apx` | Stub | VanillaOS 2.x (Orchid) |

## Usage

### Prerequisites

- A fresh Linux installation from a supported distro family (see above)
- `sudo` access — the script installs and removes system packages
- `curl` — required only for remote execution (see below)
- For Arch-based distros: `pacman` must be available (ships by default); `paru` is optional for AUR packages
- For other distros: the corresponding package manager must be available (see table above)

### Quick Start

Clone the repository and run the entrypoint:

```bash
git clone https://github.com/daankh/linux-configuration-script.git
cd linux-configuration-script
sudo ./setup.sh
```

This runs `cleanup-system.sh` first (to remove unwanted packages), then `install-tools.sh`. `update-tools.sh` is **not** run automatically — it is a standalone operation.

### Remote Execution (without cloning)

Run the full setup directly from the remote repository — the script fetches everything it needs into a temporary directory:

```bash
curl -fsSL https://raw.githubusercontent.com/daankh/linux-configuration-script/main/setup.sh | sudo bash
```

When fetching scripts remotely, `setup.sh` automatically:

1. Downloads all scripts in parallel for faster startup
2. Validates each fetched file is non-empty and starts with `#!/bin/bash`
3. Verifies SHA256 checksums if a `SHA256SUMS` file is available (warns and continues if unavailable)

> [!WARNING]
> `REPO_URL` controls where all scripts are fetched from during remote execution. Overriding it redirects downloads to an arbitrary server — only set it if you trust the source (e.g., your own fork or mirror). After assignment, `REPO_URL` is marked `readonly` to prevent runtime re-assignment. SHA256 checksums are verified when a `SHA256SUMS` file is available, but since the checksums are fetched from the same origin as the scripts, this protects against transport corruption (e.g., truncated downloads), not a compromised origin.

```bash
curl -fsSL https://example.com/setup.sh | sudo REPO_URL=https://example.com bash
```

### Remote Execution of Individual Scripts

Each script can also be run standalone from the remote repository — it fetches `lib/common.sh` and `lib/packages.sh` (not the full suite):

```bash
# Install packages only
curl -fsSL https://raw.githubusercontent.com/daankh/linux-configuration-script/main/install-tools.sh | sudo bash

# Remove unwanted packages only
curl -fsSL https://raw.githubusercontent.com/daankh/linux-configuration-script/main/cleanup-system.sh | sudo bash

# Update all installed packages
curl -fsSL https://raw.githubusercontent.com/daankh/linux-configuration-script/main/update-tools.sh | sudo bash
```

Individual scripts use `--ignore-missing` for SHA256SUMS verification, so only the files actually downloaded are checked.

### Dry Run

Preview every command that would be executed, without making any changes to the system:

```bash
./setup.sh --dry-run
```

Dry-run mode skips the root privilege check, so you can preview without `sudo`. Each command that would normally run is printed prefixed with `[DRY-RUN]`.

### Running Individual Scripts

Each script can be run independently:

```bash
sudo ./install-tools.sh        # Install packages only
sudo ./cleanup-system.sh       # Remove unwanted packages only
sudo ./update-tools.sh         # Update all installed packages
```

All support the `--dry-run` flag:

```bash
./install-tools.sh --dry-run
./cleanup-system.sh --dry-run
./update-tools.sh --dry-run
```

### What Each Script Does

| Script | Purpose |
|---|---|
| `setup.sh` | Entrypoint — detects the distro, checks privileges, then runs cleanup + install in order |
| `install-tools.sh` | Installs development tools and utilities from the distro's package manager (and AUR on Arch) |
| `cleanup-system.sh` | Removes unwanted packages that ship with the default installation |
| `update-tools.sh` | Updates all installed packages to their latest versions (`pacman -Syu` + `paru -Sua` on Arch) |

### Customizing Package Lists

All package lists are centralized in **`lib/packages.sh`**, organized by distro family. Each family has its own arrays:

| Array | Purpose |
|-------|---------|
| `INSTALL_PACKAGES_<FAMILY>` | Packages to install via the primary package manager |
| `REMOVE_PACKAGES_<FAMILY>` | Packages to remove |
| `AUR_PACKAGES_ARCH` | AUR packages (Arch only, installed via `paru`) |

`<FAMILY>` uses underscores for multi-word names (e.g., `FEDORA_ATOMIC`).

To add a package, edit the appropriate array in `lib/packages.sh`. One package per line for easy diffing:

```bash
INSTALL_PACKAGES_ARCH=(
    git
    neovim
    btop
)
```

Run `bash scripts/validate-packages.sh` to verify all required arrays are declared.

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
├── setup.sh              # Entrypoint — orchestrates cleanup + install
├── lib/
│   ├── common.sh         # Shared: distro detection, privilege checks, dry-run, logging
│   └── packages.sh       # Centralized package lists for all distro families
├── install-tools.sh      # Package installation
├── cleanup-system.sh     # Package removal (unwanted distro packages)
├── update-tools.sh       # Package updates (pacman -Syu + paru -Sua on Arch)
├── scripts/
│   └── validate-packages.sh  # CI check: verifies all package arrays exist
├── SHA256SUMS            # Checksums for downloaded scripts — verified during remote execution
└── .github/
    └── workflows/
        ├── checksums.yml          # Auto-regenerates SHA256SUMS on push to main
        └── validate-packages.yml  # Validates package array completeness on PRs
```
