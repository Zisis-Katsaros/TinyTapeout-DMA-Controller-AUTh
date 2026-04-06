#!/bin/sh

set -eu

if [ ! -d tt ]; then
    mkdir tt
    cp -R /ttsetup/tt-support-tools/. tt/
fi

if [ -d tt/.git ]; then
    rm -rf tt/.git
fi
