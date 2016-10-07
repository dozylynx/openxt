#!/bin/bash -e
#
# OpenXT build script.
# Software license: see accompanying LICENSE file.
#
# Copyright (c) 2016 Assured Information Security, Inc.
#
# Contributions by Jean-Edouard Lejosne
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
GIT_OPENXT_SUBMODULE_DIR="submodules-openxt"
BUILD_USER="$(whoami)"
GIT_LOCALHOST_IP=127.0.0.1

# Fetch git mirrors
for i in ${GIT_ROOT_PATH}/${BUILD_USER}/*.git; do
    echo -n "Fetching `basename $i`: "
    cd $i
    git fetch --all > /dev/null 2>&1
    git log -1 --pretty='tformat:%H'
    cd - > /dev/null
done | tee /tmp/git_heads_$BUILD_USER

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

# Ensure OpenXT submodules are fetched for all branches of OpenXT
TMP_OPENXT_DIR="$(mktemp -d -t tmp-fetch.sh-openxt.XXXXX)"
function cleanup {
    rm -rf "${TMP_OPENXT_DIR}"
}
trap cleanup EXIT

cd "$TMP_OPENXT_DIR"
git clone --quiet git://${GIT_LOCALHOST_IP}/${BUILD_USER}/openxt.git
cd openxt
GITMODULES=
BRANCHES="$(git branch --all | sed -n -e '/HEAD/d' -e '/^\s*remotes/p')"
for BRANCH in ${BRANCHES} ; do
    git checkout --quiet "$BRANCH"
    if [ -r .gitmodules ] ; then
        GITMODULES="${GITMODULES:+$GITMODULES }$(sed -ne 's/^\W*url = //p' <.gitmodules)"
    fi
done
cd - >/dev/null
cleanup
trap - EXIT
GITMODULES="$(for GITMODULE in $GITMODULES ; do echo $GITMODULE ; done | sort | uniq)"

# GITMODULES lists all the remote URLs for submodule repositories required

SUBMODULES_DIR="${GIT_ROOT_PATH}/${BUILD_USER}/${GIT_OPENXT_SUBMODULE_DIR}"
mkdir -p "${SUBMODULES_DIR}"
cd "${SUBMODULES_DIR}"
for GITMODULE in ${GITMODULES} ; do
    REPO_DIRNAME="$(echo $GITMODULE | sed 's,^.*/,,')"
    echo -n "Fetching ${REPO_DIRNAME}: "
    if [ -d "${SUBMODULES_DIR}/${REPO_DIRNAME}" ] ; then
        # fetch
        cd "${SUBMODULES_DIR}/${REPO_DIRNAME}"
        git fetch --all > /dev/null 2>&1
    else
        git clone --quiet --mirror ${GITMODULE} ${REPO_DIRNAME}
        cd "${REPO_DIRNAME}"
    fi
    git log -1 --pretty='tformat:%H'
    cd - >/dev/null
done | tee -a /tmp/git_heads_$BUILD_USER
