# Linux Configuration Script

Opinionated post-install script for **CachyOS**. It installs all packages needed for a development workflow and removes unnecessary packages that ship with a fresh installation.

## Goals

- **Install** development tools, utilities, and applications required for daily work
- **Remove** bloatware and unused packages from the default CachyOS installation
- **Automate** the setup so a fresh system is ready to use with a single script run

## Target Distribution

- [CachyOS](https://cachyos.org/) (Arch-based, uses `pacman` / `paru`)

## Usage

```bash
./setup.sh
```

> Run with elevated privileges when prompted. Review the package lists before executing.
