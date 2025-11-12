#!/bin/zsh
# Set up a new workspace with links to shared resources

# https://www.tomups.com/posts/git-worktrees/

big_good_char="✓"
big_bad_char="✘"
good_char="✅"
bad_char="❌"
warn_char="❗"
search_char="🔎"
remove_char="✂️"
link_char="🔗"
dir_char="📁"

_help() {
    cat <<EOF
wrktr - Git Worktree Resource Manager
======================================

Share gitignored configuration files across multiple git worktrees using
hardlinks, softlinks, and copies.

PROBLEM: When using git worktrees, each worktree needs its own copy of
gitignored files (like .env, .claude/, IDE settings). This tool centralizes
them in .SHARED/ and links them into each worktree automatically.

COMMANDS
--------

  wrktr init [repo-url] [project-directory]

    Initialize a new worktree-enabled project:
      • Creates project directory structure
      • Clones bare repository to .bare/
      • Sets up .SHARED/ for centralized resources
      • Creates main worktree
      • Generates initial wrktr.conf

    Example:
      wrktr init https://github.com/user/repo.git ~/projects/myapp

  wrktr link [worktree-directory]

    Link shared resources into a worktree.

    From project root:  wrktr link feature-branch/
    From worktree:      wrktr link

    Creates hardlinks, softlinks, and copies based on wrktr.conf

  wrktr check [worktree-directory]

    Verify that shared resources are correctly linked.

    From project root:  wrktr check feature-branch/
    From worktree:      wrktr check

    Shows status of each configured asset

  wrktr cleanup [worktree-directory]

    Remove links to shared resources (before deleting worktree).

    From project root:  wrktr cleanup feature-branch/
    From worktree:      wrktr cleanup

    Unlinks hardlinks/softlinks, restores copied files with git

CONFIGURATION (wrktr.conf)
--------------------------

Define three types of shared assets:

  hardlink_assets=(
    "CLAUDE.local.md"
    ".claude/settings.local.json"
  )
    Individual gitignored files. Multiple worktrees point to same inode.
    Changes in any worktree propagate to all. Space-efficient.

  softlink_assets=(
    ".claude/commands"
    ".claude/agents"
  )
    Gitignored directories. Symbolic link to shared location.
    Entire directory structure is shared.

  copy_assets=(
    ".vscode/settings.json"
  )
    Files checked into git that need local modifications.
    Copied from .SHARED/, can be restored with git.

TYPICAL WORKFLOW
----------------

  1. wrktr init https://github.com/user/repo.git ~/projects/myapp
  2. cd ~/projects/myapp
  3. Edit wrktr.conf to define shared assets
  4. Populate .SHARED/ with your config files
  5. git worktree add feature-xyz
  6. wrktr link feature-xyz/
  7. Work in feature-xyz/ with shared configs

DIRECTORY STRUCTURE
-------------------

  project/
  ├── .bare/              # Bare git repository
  ├── .git                # Points to .bare
  ├── .SHARED/            # Centralized shared resources
  │   ├── .claude/        # Shared Claude Code settings
  │   ├── CLAUDE.local.md
  │   └── .env
  ├── wrktr.conf          # Defines what to share
  ├── main/               # First worktree
  └── feature-xyz/        # Additional worktrees

MORE INFO
---------

  GitHub: https://github.com/nicolemon/worktree-manager

EOF
}

_commands() {
    cat <<EOF
wrktr commands reference
========================

  init [repo-url] [project-directory]         Initialize a new worktree-enabled project
  link [worktree-directory]                   Link shared resources into a worktree; when run from within a worktree, worktree-directory is ignored
  check [worktree-directory]                  Verify that shared resources are correctly linked; when run from within a worktree, worktree-directory is ignored
  cleanup [worktree-directory]                Remove links to shared resources; when run from within a worktree, worktree-directory is ignored
  commands                                    Show this text

EOF
}

init() {
    repo_url=$1
    project_dir=$2

    echo "** creating project shared directory if needed..."
    test -d ${project_dir}/.SHARED || mkdir -p ${project_dir}/.SHARED

    echo "** cloning bare repository to ${project_dir}/.bare..."
    git clone --quiet --bare ${repo_url} ${project_dir}/.bare

    echo "** setting gitdir for project directory..."
    echo "gitdir: ./.bare" > ${project_dir}/.git

    echo "** configuring fetch remote..."
    git -C ${project_dir} config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"

    echo "** fetching..."
    git -C ${project_dir} fetch --quiet

    echo "** cleanup local refs..."
    git -C ${project_dir} branch --list | grep -v '\*\|\+\|ahead' | xargs -n 1 git -C ${project_dir} branch -D --quiet

    echo "** creating main worktree..."
    git -C ${project_dir} worktree add --quiet main

    echo "** setting main upstream..."
    git -C ${project_dir} branch --quiet --set-upstream-to origin/main

    echo "** creating initial wrktr.conf..."
    _write_conf > ${project_dir}/wrktr.conf
}

_write_conf() {
    cat <<EOF
# Add shared files to .SHARED using the directory structure as wanted in the
# worktrees

# individual gitignored files
hardlink_assets=()

# gitignored directories
softlink_assets=()

# files that are checked into the git repository that we want local versions of
copy_assets=()
EOF
}

worktree_component() {
    if test -d .SHARED; then
        printf "project"
    elif test -f .git && test -d ../.SHARED; then
        printf "worktree"
    else
        printf "unknown"
    fi
}

guard() {
    if [ ! $(worktree_component) = "project" ]; then
        echo "${warn_char} you're not in a wrktr workspace" && _exit 1
    elif ! test -d ${worktree}; then
        echo "${warn_char} directory at ${worktree} does not exist" && _exit 1
    fi
}

createHardlink() {
    filename="$1"
    ln -h ${shared}/${filename} ${worktree}/${filename}
}

createSoftlink() {
    filename="$1"
    ln -s ${shared}/${filename} ${worktree}/${filename}
}

createCopy() {
    filename="$1"
    cp -R ${shared}/${filename} ${worktree}/${filename}
}

_verifyExists() {
    filename="$1"
    test -e "${worktree}/${filename}"
}

verifyExists() {
    filename="$1"
    _verifyExists ${filename} && (echo "${big_good_char} FOUND: ${worktree}/${filename}") || (echo "${big_bad_char} MISSING: ${worktree}/${filename}")
}

verifySoftlink() {
    filename="$1"
    test -L "${worktree}/${filename}" && (echo "  ${good_char} softlinked: ${worktree}/${filename}") || (echo "  ${bad_char} not softlinked: ${worktree}/${filename}")
}

verifyHardlink() {
    filename="$1"
    # link_count=$(stat -c %h "${worktree}/${filename}" 2>/dev/null)
    link_count=$(stat -f %l "${worktree}/${filename}" 2>/dev/null)
    [ "${link_count}" -gt 1 ] && (echo "  ${good_char} hardlinked: ${worktree}/${filename}") || (echo "  ${bad_char} not hardlinked: ${worktree}/${filename}")
}

verifyCopy() {
    filename="$1"
    share_sum=$(sha1sum ${shared}/${filename} | awk '{ print $1 }')
    work_sum=$(sha1sum ${worktree}/${filename} | awk '{ print $1 }')
    [ "${share_sum}" = "${work_sum}" ] && (echo "  ${good_char} copy matches: ${worktree}/${filename}") || (echo "  ${bad_char} copy mismatch: ${worktree}/${filename}")
}

check() {
    echo "\n${search_char} Checking for shared local resources in 📁 ${worktree}...\n"
    _check
}

_check() {
    for asset in ${hardlink_assets}; do
        verifyExists ${asset} && verifyHardlink ${asset}
        echo
    done

    for asset in ${softlink_assets}; do
        verifyExists ${asset} && verifySoftlink ${asset}
        echo
    done

    for asset in ${copy_assets}; do
        verifyExists ${asset} && verifyCopy ${asset}
    done
}

link() {
    mkdir -p ${worktree}/.claude

    for asset in ${hardlink_assets}; do
        _verifyExists ${asset} || createHardlink ${asset}
    done

    for asset in ${softlink_assets}; do
        _verifyExists ${asset} || createSoftlink ${asset}
    done

    for asset in ${copy_assets}; do
        createCopy ${asset}
    done

    echo "\n${link_char} Shared local resources linked in ${dir_char} ${worktree}\n"
    _check
}

cleanup() {
    for asset in ${hardlink_assets}; do
        _verifyExists ${asset} && unlink ${worktree}/${asset}
    done

    for asset in ${softlink_assets}; do
        _verifyExists ${asset} && unlink ${worktree}/${asset}
    done

    for asset in ${copy_assets}; do
        _verifyExists ${asset} && cd ${worktree} && git restore ${asset}
    done

    echo "\n${remove_char} Shared local resources unlinked in ${dir_char} ${worktree}\n"
    _check
}

_exit() {
    [ -v project_dir ] && unset project_dir
    [ -v shared ] && unset shared
    [ -v worktree ] && unset worktree
    [ -v hardlink_assets ] && unset hardlink_assets
    [ -v softlink_assets ] && unset softlink_assets
    [ -v copy_assets ] && unset copy_assets
    exit "$1"
}

entrypoint() {

    if [ -z $1 ]; then
        _commands && _exit 0
    fi

    if [ $1 = "help" ]; then
        _help && _exit 0
    fi

    if [ $1 = "commands" ]; then
        _commands && _exit 0
    fi

    if [ $1 = "init" ]; then
        init $2 $3 && _exit 0
    fi

    if [ $(worktree_component) = "project" ] ; then
        project_dir=$(pwd -P)
        worktree="${project_dir}/$2"
        guard  # check for worktree directory
    elif [ $(worktree_component) = "worktree" ]; then
        project_dir="$(realpath $(pwd)/../)"
        worktree=$(pwd -P)
    else
        echo "${warn_char} neither a worktree project nor worktree; run \`wrktr init [repo-url] [project-directory]\`" && _exit 1
    fi

    shared="${project_dir}/.SHARED"
    config_file="${project_dir}/wrktr.conf"
    [ -f ${config_file} ] && source ${config_file} || (echo "config not found at ${config_file}" && _exit 1)
    [ ! -v hardlink_assets ] && echo "hardlink_assets is unset"
    [ ! -v softlink_assets ] && echo "softlink_assets is unset"
    [ ! -v copy_assets ] && echo "copy_assets is unset"

    exec $1
}

entrypoint "$@"

# vim: set et sts=4 ts=4 sw=4:
