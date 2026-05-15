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
  hwdata libglvnd-dev libffi-dev meson ninja-build

LIBS=(
  "xkbcommon,1.11.0,https://github.com/xkbcommon/libxkbcommon"
  "hyprutils,v0.13.1,https://github.com/hyprwm/hyprutils"
  "hyprgraphics,v0.5.1,https://github.com/hyprwm/hyprgraphics"
  "hyprlang,v0.6.7,https://github.com/hyprwm/hyprlang"
  "hyprwayland-scanner,v0.4.1,https://github.com/hyprwm/hyprwayland-scanner"
  "hyprcursor,v0.1.9,https://github.com/hyprwm/hyprcursor"
  "hyprwire,v0.3.1,https://github.com/hyprwm/hyprwire"
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

  # GCC 14 fix: hyprwayland-scanner 0.4 codegen emits zero-length vtable arrays
  # for interfaces with no requests/events, which -Wpedantic rejects.
  # Patch the codegen to always emit at least `nullptr`.
  if [ "$name" = "hyprwayland-scanner" ]; then
    python3 -c "
import re
with open('src/main.cpp') as f:
    content = f.read()
old = '''        for (auto& rq : (clientCode ? iface.events : iface.requests)) {
            const auto REQUEST_NAME = camelize(std::string{\"_\"} + \"C_\" + IFACE_NAME + \"_\" + rq.name);
            SOURCE += std::format(\"    (void*){},\\\n\", REQUEST_NAME);
        }'''
new = '''        {
            const auto& items_rq = (clientCode ? iface.events : iface.requests);
            if (items_rq.empty()) {
                SOURCE += \"    nullptr,\\\n\";
            } else {
                for (auto& rq : items_rq) {
                    const auto REQUEST_NAME = camelize(std::string{\"_\"} + \"C_\" + IFACE_NAME + \"_\" + rq.name);
                    SOURCE += std::format(\"    (void*){},\\\n\", REQUEST_NAME);
                }
            }
        }'''
assert content.count(old) == 1, 'unexpected number of vtable loop matches'
content = content.replace(old, new)
with open('src/main.cpp', 'w') as f:
    f.write(content)
print('Patched hyprwayland-scanner vtable codegen to avoid zero-length arrays')
"
  fi

  # GCC 14.2 in Debian trixie lacks std::vector::append_range (C++23).
  # Patch all source files: vec.append_range(expr) → for (auto&& _c : expr) vec.push_back(_c)
  if [ "$name" = "hyprwire" ]; then
    python3 << 'PYEOF'
import glob

def fix_append_range(text):
    """Replace vec.append_range(expr) with for-loop push_back, handling nested parens."""
    result = []
    i = 0
    while i < len(text):
        idx = text.find('.append_range(', i)
        if idx == -1:
            result.append(text[i:])
            break
        # Find the full expression before '.append_range(' (supports a.b, a->b, a[b], etc.)
        start = idx - 1
        while start >= 0 and (text[start].isalnum() or text[start] in '_>.)]'):
            if text[start] == ')' or text[start] == ']':
                # skip back over matching pair
                pair = {'(': ')', '[': ']'}
                close = text[start]
                open_c = {v: k for k, v in pair.items()}[close]
                depth = 1
                start -= 1
                while start >= 0 and depth > 0:
                    if text[start] == close:
                        depth += 1
                    elif text[start] == open_c:
                        depth -= 1
                    start -= 1
                start += 1  # back to the matching open char
            else:
                start -= 1
        var = text[start+1:idx]
        result.append(text[i:start+1])  # everything before var (whitespace, etc.)
        # Find matching close paren (handling nesting)
        depth = 1
        j = idx + len('.append_range(')
        while j < len(text) and depth > 0:
            if text[j] == '(':
                depth += 1
            elif text[j] == ')':
                depth -= 1
            j += 1
        expr = text[idx + len('.append_range('):j-1]
        result.append(f'for (auto&& _c : {expr}) {var}.push_back(_c)')
        i = j
    return ''.join(result)

for fpath in glob.glob('src/**/*.cpp', recursive=True):
    with open(fpath) as f:
        content = f.read()
    if '.append_range(' not in content:
        continue
    new_content = fix_append_range(content)
    with open(fpath, 'w') as f:
        f.write(new_content)
    print(f'Patched {fpath}')
PYEOF
  fi

  # xkbcommon uses meson, not cmake
  if [ "$name" = "xkbcommon" ]; then
    meson setup build --prefix=/usr --buildtype=release -Denable-x11=false -Denable-docs=false
    ninja -C build
    ninja -C build install
    cd "$BUILD_DIR"
    continue
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
