#!/bin/bash -e
#
# OpenXT build script.
# Software license: see accompanying LICENSE file.
#
# Copyright (c) 2016 Assured Information Security, Inc.
# Copyright (c) 2016 BAE Systems
#
# Contributions by Jean-Edouard Lejosne
# Contributions by Christopher Clark
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

GIT_ROOT_PATH=%GIT_ROOT_PATH%
BUILD_USER="$(whoami)"
GIT_LOCALHOST_IP=127.0.0.1

usage() {
    cat >&2 <<EOF
usage: $0 [-h help] [-b branch]
  -h: Help
  -b: Branch to fetch build dependencies for
EOF
    exit $1
}

BRANCH=

while getopts "hb:" opt; do
    case $opt in
        h) usage 0
            ;;
        b) BRANCH=${OPTARG}
            ;;
        \?) usage 1
            ;;
    esac
done

# Fetch git mirrors of OpenXT repositories
for i in ${GIT_ROOT_PATH}/${BUILD_USER}/*.git; do
    echo -n "Fetching `basename $i`: "
    cd $i
    git fetch --all > /dev/null 2>&1
    git log -1 --pretty='tformat:%H'
    cd - > /dev/null
done | tee /tmp/git_heads_$BUILD_USER

# Fetch git mirrors of submodules of openxt.git
mirror_openxt_submodules() {
    SUBMODULES=
    cd "${GIT_ROOT_PATH}/${BUILD_USER}/openxt.git"
    BRANCHES="${BRANCH}"
    [ ! -z "${BRANCHES}" ] || BRANCHES="$(git branch --all)"
    for BR in ${BRANCHES} ; do
        SUBMODULES="${SUBMODULES:+$SUBMODULES }$(git show "${BR}":.gitmodules 2>/dev/null | sed -ne 's/^\W*url = //p')"
    done
    cd - >/dev/null
    SUBMODULES="$(for SUBMODULE in $SUBMODULES ; do echo $SUBMODULE ; done | sort | uniq)"

    SUBMODULES_DIR="${GIT_ROOT_PATH}/${BUILD_USER}/submodules/openxt"
    mkdir -p "${SUBMODULES_DIR}"
    for SUBMODULE in ${SUBMODULES} ; do
        REPO_DIRNAME="$(echo $SUBMODULE | sed 's,^.*/,,')"
        echo -n "Fetching ${REPO_DIRNAME}: "
        if [ -d "${SUBMODULES_DIR}/${REPO_DIRNAME}" ] ; then
            cd "${SUBMODULES_DIR}/${REPO_DIRNAME}"
            git fetch --all > /dev/null 2>&1
        else
            git clone --quiet --mirror "${SUBMODULE}" "${REPO_DIRNAME}"
            cd "${SUBMODULES_DIR}/${REPO_DIRNAME}"
        fi
        git log -1 --pretty='tformat:%H'
        cd - >/dev/null
    done | tee -a /tmp/git_heads_$BUILD_USER
}
mirror_openxt_submodules

# Populate repo mirror
mirror_repo_repositories() {
    REPO_MIRROR_DIR="${GIT_ROOT_PATH}/${BUILD_USER}/repo"
    mkdir -p "${REPO_MIRROR_DIR}"
    cd "${REPO_MIRROR_DIR}"
    if [ ! -d .repo ] ; then
        # Use the local git mirror for the openxt remote
        mkdir -p "${REPO_MIRROR_DIR}/.repo/local_manifests"
        cat >.repo/local_manifests/git_mirror.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="openxt" fetch="git://${GIT_LOCALHOST_IP}/${BUILD_USER}"/>
</manifest>
EOF
        ~/repo init -u "git://${GIT_LOCALHOST_IP}/${BUILD_USER}/openxt.git" \
                    -m layer-conf/assemble-mirror.xml \
                    ${BRANCH:+-b} ${BRANCH} \
                    --mirror
    fi
    ~/repo sync
    cd - >/dev/null
}
mirror_repo_repositories

# Start the git service if needed
ps -p `cat /tmp/openxt_git.pid 2>/dev/null` >/dev/null 2>&1 || {
    rm -f /tmp/openxt_git.pid
    git daemon --base-path=${GIT_ROOT_PATH} \
               --pid-file=/tmp/openxt_git.pid \
               --detach \
               --syslog \
               --export-all
    chmod 666 /tmp/openxt_git.pid
}
