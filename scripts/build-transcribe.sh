#!/usr/bin/env bash
# Fetches transcribe.cpp (MIT, github.com/handy-computer/transcribe.cpp) at
# the pinned commit and builds it as static libraries with Metal into
# Vendor/transcribe (include/ and lib/). The SottoEngine helper links them.
# Run once before `swift build`, and again after changing the commit.
set -euo pipefail
cd "$(dirname "$0")/.."

commit=5700f127e38dd53c4735ea23ef743b4b538eacd4
source_dir=Vendor/transcribe.cpp
build_dir=Vendor/transcribe-build
install_dir=Vendor/transcribe

if [[ -f "$install_dir/.commit" && "$(cat "$install_dir/.commit")" == "$commit" ]]; then
    echo "transcribe.cpp $commit is already built."
    exit 0
fi

if [[ ! -d "$source_dir/.git" ]]; then
    git clone --quiet https://github.com/handy-computer/transcribe.cpp.git "$source_dir"
fi
git -C "$source_dir" fetch --quiet origin "$commit" || true
git -C "$source_dir" checkout --quiet "$commit"

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
    -DTRANSCRIBE_METAL=ON \
    -DTRANSCRIBE_BUILD_SHARED=OFF \
    -DTRANSCRIBE_BUILD_TESTS=OFF \
    -DTRANSCRIBE_BUILD_EXAMPLES=OFF
cmake --build "$build_dir"
rm -rf "$install_dir"
cmake --install "$build_dir" --prefix "$install_dir"
echo "$commit" > "$install_dir/.commit"
echo "Built transcribe.cpp $commit into $install_dir"
