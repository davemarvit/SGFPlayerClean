#!/bin/zsh
set -e
cd "${0:A:h}"
python3 build.py
open '.build/Physical Go.app'
