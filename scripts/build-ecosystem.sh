#!/bin/bash
# Build Hyprland ecosystem libraries from source for Debian stable
# Run this ONCE before building Hyprland
# Usage: sudo bash scripts/build-ecosystem.sh
# (runs without sudo inside Docker containers)

set -e

echo "=== Installing system dependencies ==="
apt install -y cmake g++ pkg-config libwayland-dev wayland-protocols \
  libxkbcommon-dev libinput-dev libdrm-dev libgbm-dev libcairo2-dev \
  libpango1.0-dev libgdk-pixbuf-2.0-dev libpixman-1-dev libxcursor-dev \
  libxcb*-dev libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
  glslang-dev glslang-tools uuid-dev liblcms2-dev libre2-dev \
  libmuparser-dev liblua5.4-dev libmagic-dev librsvg2-dev libpugixml-dev \
  libseat-dev libdisplay-info-dev libjxl-dev libheif-dev libzip-dev libtomlplusplus-dev \
  hwdata libglvnd-dev

LIBS=(
  "hyprutils,v0.13.1,https://github.com/hyprwm/hyprutils"
  "hyprgraphics,v0.5.1,https://github.com/hyprwm/hyprgraphics"
  "hyprlang,v0.6.7,https://github.com/hyprwm/hyprlang"
  "hyprwayland-scanner,v0.4.1,https://github.com/hyprwm/hyprwayland-scanner"
  "hyprcursor,v0.1.9,https://github.com/hyprwm/hyprcursor"
  "aquamarine,v0.10.0,https://github.com/hyprwm/aquamarine"
)

BUILD_DIR="/tmp/hyprland-ecosystem"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

for entry in "${LIBS[@]}"; do
  IFS=',' read -r name version url <<< "$entry"
  echo ""
  echo "=== Building $name $version ==="

  if [ -d "$name" ]; then
    rm -rf "$name"
  fi

  git clone --depth 1 --branch "$version" "$url" 2>/dev/null || \
    git clone --depth 1 "$url" "$name"

  cd "$name"

  # GCC 14 fix: hyprcursor v0.1.9 needs explicit #include <fstream>
  if [ "$name" = "hyprcursor" ]; then
    sed -i '1i#include <fstream>' hyprcursor-util/src/main.cpp
  fi

  # GCC 14 + hyprwayland-scanner 0.4 generates zero-length vtable arrays
  # which -Wpedantic treats as error. Add override flag after -Wpedantic.
  if [ "$name" = "aquamarine" ]; then
    sed -i 's/-Wpedantic)/-Wpedantic\n  -Wno-zero-length-array)/' CMakeLists.txt
  fi

  cmake -B build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  cmake --build build -j$(nproc)
  cmake --install build
  cd "$BUILD_DIR"
done

rm -rf "$BUILD_DIR"

echo ""
echo "=== Ecosystem libs installed ==="
echo "Now build Hyprland:"
echo "  cmake -B build -DCMAKE_BUILD_TYPE=Release"
echo "  cmake --build build -j\$(nproc)"
