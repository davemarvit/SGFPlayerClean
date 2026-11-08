#!/bin/zsh
set -eu
TASK_ROOT=${0:A:h:h}
SDK=${1:-iphonesimulator}
if [[ "$SDK" != iphoneos && "$SDK" != iphonesimulator ]]; then echo 'Use iphoneos or iphonesimulator'; exit 2; fi
if [[ ! -d "$TASK_ROOT/.build/KataGo/.git" ]]; then
  git clone --depth 1 --branch v1.16.4 https://github.com/lightvector/KataGo.git "$TASK_ROOT/.build/KataGo"
fi
# Pin the tested release. The build fails rather than silently use a different checkout.
[[ $(git -C "$TASK_ROOT/.build/KataGo" rev-parse HEAD) == 4b8de63bea2bd8790db96cd6f8daf86dc87be6f7 ]]
cmake -S "$TASK_ROOT/KataGo" -B "$TASK_ROOT/.build/katago-$SDK" \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$SDK" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
  -DEIGEN_PATH="${EIGEN_PATH:-/opt/homebrew/include/eigen3}"
cmake --build "$TASK_ROOT/.build/katago-$SDK" -j 6
