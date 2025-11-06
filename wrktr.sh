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
    _verifyExists ${filename} && (echo "✅ FOUND: ${worktree}/${filename}") || (echo "❌ MISSING: ${worktree}/${filename}")
}

verifySoftlink() {
    filename="$1"
    test -L "${worktree}/${filename}" && (echo "  ✓ softlinked: ${worktree}/${filename}") || (echo "  ✘ not softlinked: ${worktree}/${filename}")
}

verifyHardlink() {
    filename="$1"
    # link_count=$(stat -c %h "${worktree}/${filename}" 2>/dev/null)
    link_count=$(stat -f %l "${worktree}/${filename}" 2>/dev/null)
    [ "${link_count}" -gt 1 ] && (echo "  ✓ hardlinked: ${worktree}/${filename}") || (echo "  ✘ not hardlinked: ${worktree}/${filename}")
}

verifyCopy() {
    filename="$1"
    share_sum=$(sha1sum ${shared}/${filename} | awk '{ print $1 }')
    work_sum=$(sha1sum ${worktree}/${filename} | awk '{ print $1 }')
    [ "${share_sum}" = "${work_sum}" ] && (echo "  ✓ copy matches: ${worktree}/${filename}") || (echo "  ✘ copy mismatch: ${worktree}/${filename}")
}

check() {
    echo "\n🔎 Checking for shared local resources in 📁 ${worktree}...\n"
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

    echo "\n🔗 Shared local resources linked in 📁 ${worktree}\n"
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

    echo "\n✂️ Shared local resources unlinked in 📁 ${worktree}\n"
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
    if [ $1 = "help" ]; then
        _help && _exit 0
    fi

    if [ -z $1 ]; then
        check . && _exit 0
    fi

    if [ $1 = "init" ]; then
        init $2 $3 && _exit 0
    fi

    [ -f wrktr.conf ]

    if [ $(worktree_component) = "project" ] ; then
        project_dir=$(pwd)
        shared="${project_dir}/.SHARED"
        worktree="${project_dir}/$2"
        guard  # check for worktree directory

        [ -f wrktr.conf ] && source wrktr.conf
        [ ! -v hardlink_assets ] && echo "hardlink_assets is unset"
        [ ! -v softlink_assets ] && echo "softlink_assets is unset"

        exec $1
    elif [ $(worktree_component) = "worktree" ]; then
        project_dir=".."
        shared="../${project_dir}/.SHARED"
        worktree=$(pwd)

        [ -f ../wrktr.conf ] && source ../wrktr.conf
        [ ! -v hardlink_assets ] && echo "hardlink_assets is unset"
        [ ! -v softlink_assets ] && echo "softlink_assets is unset"

        exec $1
    else
        echo "neither a worktree project nor worktree; run \`wrktr init [repo-url] [project-directory]\`" && _exit 1
    fi
}

_help() {
    cat <<EOF
    wrktr init [repo-url] [project-directory]

        1. Create project directory
        2. Clone bare repository into .bare
        3. Create .git in project directory
        4. Configure fetch remote
        5. Add main worktree
        6. Delete local branches

    wrktr link [worktree directory]
    wrktr check [worktree directory]
    wrktr cleanup [worktree directory]

    wrktr.conf:
        hardlink_assets=()
        softlink_assets=()
        copy_assets=()
EOF
}

entrypoint "$@"

# vim: set et sts=4 ts=4 sw=4:
