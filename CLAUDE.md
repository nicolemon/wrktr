# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**wrktr** is a zsh-based git worktree management utility that enables sharing local resources (configuration files, Claude settings, etc.) across multiple git worktrees using hardlinks, softlinks, and copies.

Key concept: When working with git worktrees, each worktree typically needs its own copy of gitignored config files. This tool centralizes those files in a `.SHARED` directory and links them into each worktree.

## Installation & Build Commands

```bash
# Create executable from source
make wrktr

# Install to /usr/local/bin
make install

# Uninstall from system
make uninstall

# Clean build artifacts
make clean
```

## Usage

### Initializing a new worktree project
```bash
wrktr init [repo-url] [project-directory]
```

This creates:
- Project directory structure
- `.bare` directory containing the bare git repository
- `.git` file pointing to `.bare`
- `.SHARED` directory for shared resources
- `main` worktree
- Initial `wrktr.conf` configuration file

### Managing worktree links

```bash
# From project root:
wrktr link [worktree-directory]    # Create links to shared resources
wrktr check [worktree-directory]   # Verify links are correct
wrktr cleanup [worktree-directory] # Remove links

# From within a worktree:
wrktr link    # Links shared resources into current worktree
wrktr check   # Checks current worktree
wrktr cleanup # Cleans current worktree
```

## Architecture

### Directory Structure
```
project/
├── .bare/              # Bare git repository
├── .git                # File containing "gitdir: ./.bare"
├── .SHARED/            # Centralized shared resources
│   ├── .claude/        # Claude Code settings/commands
│   └── [other shared files]
├── wrktr.conf          # Configuration defining what to share
├── main/               # First worktree (typically main branch)
└── [other-worktrees]/  # Additional worktrees
```

### Configuration (wrktr.conf)

The `wrktr.conf` file defines three types of shared assets:

- **hardlink_assets**: Individual gitignored files (e.g., `CLAUDE.local.md`, `.claude/settings.local.json`)
  - Multiple directory entries point to same inode
  - Changes in any worktree propagate to all
  - Space-efficient (single copy on disk)

- **softlink_assets**: Gitignored directories (e.g., `.claude/commands`, `.claude/agents`)
  - Symbolic links to shared directory
  - Entire directory structure shared

- **copy_assets**: Files checked into git that need local modifications
  - Copied from .SHARED to worktree
  - Can be restored with `git restore`

### Component Detection

The script auto-detects context using `worktree_component()`:
- **project**: Has `.SHARED` directory (project root)
- **worktree**: Has `.git` directory and `../.SHARED` exists
- **unknown**: Neither (error state)

### Link Verification

- **Hardlinks**: Verified by checking link count (`stat -f %l`) > 1
- **Softlinks**: Verified by testing if path is a symlink (`test -L`)
- **Copies**: Verified by SHA-1 hash comparison with source

## Development Notes

### Script Evolution
- `wrktr-v1`: Original implementation (hardcoded assets, simpler structure)
- `wrktr.sh`: Current version (configuration-driven, more robust error handling)

### Platform-Specific Commands
The script uses macOS-specific `stat` syntax:
- `stat -f %l` (macOS) vs `stat -c %h` (Linux) for link count

### Shell Configuration
- Uses zsh-specific features (arrays, conditionals)
- Sets vim modeline for 4-space soft tabs
