#!/usr/bin/env bash
BOOSTNOTE_VERSION=0.15.0

pushd /tmp
wget https://github.com/BoostIO/boost-releases/releases/download/v${BOOSTNOTE_VERSION}/boostnote_${BOOSTNOTE_VERSION}_amd64.deb
sudo dpkg -i boostnote_${BOOSTNOTE_VERSION}_amd64.deb
popd

