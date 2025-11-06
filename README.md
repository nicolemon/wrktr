# wrktr - Git Worktree Manager

A zsh utility for managing git worktrees with shared local resources.

## Why wrktr?

Git worktrees let you work on multiple branches simultaneously without switching contexts. However, each worktree typically needs its own copy of gitignored configuration files (`.env`, editor settings, local scripts, etc.). This creates several problems:

- 🔄 **Duplicated effort**: Making the same config change across multiple worktrees
- 💾 **Wasted space**: Storing identical files multiple times
- ⚠️ **Drift risk**: Configurations getting out of sync across worktrees

**wrktr** solves this by centralizing shared resources in a `.SHARED` directory and intelligently linking them into each worktree using hardlinks, softlinks, or copies.

## Installation

```bash
# Clone the repository
git clone <repo-url> worktree-manager
cd worktree-manager

# Install to /usr/local/bin
make install
```

To uninstall:
```bash
make uninstall
```

## Quick Start

### 1. Initialize a new worktree project

```bash
wrktr init https://github.com/user/repo.git my-project
cd my-project
```

This creates:
```
my-project/
├── .bare/           # Bare git repository
├── .git             # Points to .bare
├── .SHARED/         # Shared resources directory
├── wrktr.conf       # Configuration file
└── main/            # First worktree
```

### 2. Configure shared resources

Edit `wrktr.conf` to specify what should be shared:

```bash
# Individual gitignored files (hardlinked)
hardlink_assets=(
    ".env"
    "credentials.json"
    ".claude/settings.local.json"
)

# Gitignored directories (softlinked)
softlink_assets=(
    ".claude/commands"
    ".build-cache"
)

# Versioned files needing local modifications (copied)
copy_assets=(
    "config.local.yaml"
)
```

### 3. Add shared files to .SHARED

Place your shared resources in `.SHARED/` using the same path structure you want in worktrees:

```bash
# Create shared files
echo "SECRET_KEY=abc123" > .SHARED/.env
mkdir -p .SHARED/.claude
cp ~/my-claude-settings.json .SHARED/.claude/settings.local.json
```

### 4. Create a new worktree and link resources

```bash
# Create new worktree for a feature branch
git worktree add feature-x

# Link shared resources into the new worktree
wrktr link feature-x
```

### 5. Verify links

```bash
# Check that all links are correct
wrktr check feature-x
```

Output:
```
🔎 Checking for shared local resources in 📁 /path/to/my-project/feature-x...

✓ FOUND: /path/to/my-project/feature-x/.env
  ✅ hardlinked: /path/to/my-project/feature-x/.env

✓ FOUND: /path/to/my-project/feature-x/.claude/commands
  ✅ softlinked: /path/to/my-project/feature-x/.claude/commands
```

## Usage

### From project root

```bash
wrktr link <worktree-dir>     # Create links to shared resources
wrktr check <worktree-dir>    # Verify links are correct
wrktr cleanup <worktree-dir>  # Remove all links
```

### From within a worktree

```bash
cd feature-x
wrktr link                    # Link shared resources into current worktree
wrktr check                   # Check current worktree
wrktr cleanup                 # Clean current worktree
```

### Getting help

```bash
wrktr help
```

## How It Works

### Three Linking Strategies

**Hardlinks** (for individual files)
- Multiple directory entries point to the same inode
- Changes in any worktree automatically propagate to all others
- Space-efficient (only one copy on disk)
- Perfect for: `.env`, credentials, local configs

**Softlinks** (for directories)
- Symbolic links to shared directory
- Entire directory structure is shared
- Perfect for: `.claude/commands`, build caches, large assets

**Copies** (for versioned files)
- Files copied from `.SHARED` to worktree
- Can be modified locally and restored with `git restore`
- Perfect for: config templates that need branch-specific tweaks

### Directory Structure

```
my-project/
├── .bare/                    # Bare git repository
├── .git                      # File containing "gitdir: ./.bare"
├── .SHARED/                  # Shared resources
│   ├── .env                  # Shared environment variables
│   ├── .claude/
│   │   ├── settings.local.json
│   │   └── commands/         # Shared Claude commands
│   └── credentials.json
├── wrktr.conf                # Configuration
├── main/                     # Main branch worktree
│   ├── .env → hardlink       # Points to .SHARED/.env
│   └── .claude/
│       └── commands → softlink
└── feature-x/                # Feature branch worktree
    ├── .env → hardlink       # Same inode as main/.env
    └── .claude/
        └── commands → softlink
```

## Common Workflows

### Adding a new shared file

```bash
# 1. Add file to .SHARED
echo "NEW_VAR=value" >> .SHARED/.env

# 2. Update wrktr.conf if needed
# (if .env is already in hardlink_assets, skip this step)

# 3. Link into existing worktrees
wrktr link main
wrktr link feature-x
```

### Removing shared resources before switching branches

```bash
cd feature-x
wrktr cleanup               # Remove links
git checkout other-branch   # Switch branches safely
wrktr link                  # Restore links
```

### Checking link integrity

```bash
# Check all worktrees
for worktree in */; do
    wrktr check "$worktree"
done
```

## Configuration Reference

### wrktr.conf

```bash
# Individual files (hardlinked)
# Use for: .env, credentials, small config files
hardlink_assets=(
    "file1.txt"
    "path/to/file2.json"
)

# Directories (softlinked)
# Use for: command directories, build caches
softlink_assets=(
    "directory1"
    "path/to/directory2"
)

# Versioned files (copied)
# Use for: config templates needing local modifications
copy_assets=(
    "config.template.yaml"
)
```

**Important**: Paths in configuration should match the desired structure in worktrees, not absolute paths.

## Use Cases

### Sharing Claude Code settings across worktrees

```bash
# In .SHARED/
.claude/
├── settings.local.json    # Hardlinked (individual preferences)
└── commands/              # Softlinked (shared slash commands)
    ├── commit.sh
    └── review.sh

# In wrktr.conf
hardlink_assets=(
    ".claude/settings.local.json"
)
softlink_assets=(
    ".claude/commands"
)
```

### Sharing development credentials

```bash
# In .SHARED/
.env                       # Hardlinked
.aws/credentials           # Hardlinked
docker-compose.override.yml # Copied (might need tweaks per branch)

# In wrktr.conf
hardlink_assets=(
    ".env"
    ".aws/credentials"
)
copy_assets=(
    "docker-compose.override.yml"
)
```

## Platform Notes

- Requires **zsh** shell
- Uses **macOS-specific** `stat` commands (`stat -f %l`)
- For Linux compatibility, modify stat commands to use `-c %h`

## Troubleshooting

### "neither a worktree project nor worktree" error
You're not in a wrktr-managed project. Run `wrktr init` first.

### Links not being created
- Ensure files exist in `.SHARED/` first
- Check that paths in `wrktr.conf` match your desired worktree structure
- Verify you're running from project root or within a worktree

### Hardlink verification fails
- Hardlinks only work within the same filesystem
- Ensure `.SHARED` and worktrees are on the same volume

## Credits

Inspired by [this article on git worktrees](https://www.tomups.com/posts/git-worktrees/).

## License

MIT License
