#!/bin/zsh
# Set up a new workspace with links to shared resources

# https://www.tomups.com/posts/git-worktrees/

init() {
    repo_url=$1
    project_dir=$2

    test -d ${project_dir} || mkdir ${project_dir}
    git clone --bare ${repo_url} ${project_dir}/.bare
    echo "gitdir: ./.bare" > ${project_dir}/.git
    pushd ${project_dir}

    git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    git fetch
    git worktree add main
    git branch --list | grep -v '\*\|\+\|ahead' | xargs -n 1 git branch -D
    mkdir -p .SHARED/.claude/commands
    mkdir -p .SHARED/.claude/agents
    touch .SHARED/.claude/settings.local.json
    touch .SHARED/gitignore.Makefile
    touch .SHARED/CLAUDE.local.md

    popd && echo "returned to parent directory"
}

worktree_component() {
    if test -d .SHARED; then
        printf "project"
    elif test -d .git && test -d ../.SHARED; then
        printf "worktree"
    else
        printf "unknown"
    fi
}

# files under .SHARED you want hardlinked
hardlink_assets=(
    "gitignore.Makefile"
    "CLAUDE.local.md"
    ".claude/settings.local.json"
)

# directories under .SHARED you want softlinked
softlink_assets=(
    ".claude/commands"
    ".claude/agents"
)

guard() {
    if [ ! $(worktree_component) = "project" ]; then
        echo "❗ you're not in a wrktr workspace" && _exit 1
    elif ! test -d ${worktree}; then
        echo "❗ directory at ${worktree} does not exist" && _exit 1
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

_verifyExists() {
    filename="$1"
    test -e "${worktree}/${filename}"
}

verifyExists() {
    filename="$1"
    _verifyExists ${filename} && (echo "✅ FOUND: ${worktree}${filename}") || (echo "❌ MISSING: ${worktree}${filename}")
}

verifySoftlink() {
    filename="$1"
    test -L "${worktree}/${filename}" && (echo "  ✓ softlinked: ${worktree}${filename}") || (echo "  ✘ not softlinked: ${worktree}${filename}")
}

verifyHardlink() {
    filename="$1"
    # link_count=$(stat -c %h "${worktree}/${filename}" 2>/dev/null)
    link_count=$(stat -f %l "${worktree}/${filename}" 2>/dev/null)
    [ "${link_count}" -gt 1 ] && (echo "  ✓ hardlinked: ${worktree}${filename}") || (echo "  ✘ not hardlinked: ${worktree}${filename}")
}

check() {
    echo "\nChecking for shared local resources in 📁 ${worktree}...\n"
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
}

link() {
    mkdir -p ${worktree}/.claude

    for asset in ${hardlink_assets}; do
        _verifyExists ${asset} || createHardlink ${asset}
    done

    for asset in ${softlink_assets}; do
        _verifyExists ${asset} || createSoftlink ${asset}
    done

    echo "\nShared local resources linked in 📁 ${worktree}\n"
    _check
}

cleanup() {
    for asset in ${hardlink_assets}; do
        _verifyExists ${asset} && unlink ${worktree}/${asset}
    done

    for asset in ${softlink_assets}; do
        _verifyExists ${asset} && unlink ${worktree}/${asset}
    done

    echo "\nShared local resources unlinked in 📁 ${worktree}\n"
    _check
}

_exit() {
    [ -n ${project_dir} ] && unset project_dir
    [ -n ${shared} ] && unset shared
    [ -n ${worktree} ] && unset worktree
    [ -n ${hardlink_assets} ] && unset hardlink_assets
    [ -n ${softlink_assets} ] && unset softlink_assets
    exit "$1"
}

entrypoint() {
    if [ -z $1 ]; then
        check . && exit 0
    fi

    if [ $1 = "init" ]; then
        init $2 $3 && _exit 0
    fi

    if [ $(worktree_component) = "project" ] ; then
        project_dir=$(pwd)
        shared="${project_dir}/.SHARED"
        worktree="${project_dir}/$2"
        guard
        exec $1
    elif [ $(worktree_component) = "worktree" ]; then
        project_dir=".."
        shared="../${project_dir}/.SHARED"
        worktree=$(pwd)
        exec $1
    else
        echo "neither a worktree project nor worktree; run \`wrktr init [repo-url] [project-directory]\`" && exit _1
    fi
}

entrypoint "$@"

# vim: set et sts=4 ts=4 sw=4:
