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
  hwdata libglvnd-dev libffi-dev

LIBS=(
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
  # Replace with equivalent insert(end(), ...) calls.
  if [ "$name" = "hyprwire" ]; then
    python3 << 'PYEOF'
patches = {
    'src/core/message/messages/BindProtocol.cpp': [
        ('''    m_data.append_range(g_messageParser->encodeVarInt(protocol.length()));
    m_data.append_range(protocol);

    m_data.append_range(std::vector<uint8_t>{HW_MESSAGE_MAGIC_TYPE_UINT, 0, 0, 0, 0});''',
         '''    { auto _r = g_messageParser->encodeVarInt(protocol.length()); m_data.insert(m_data.end(), _r.begin(), _r.end()); }
    m_data.insert(m_data.end(), protocol.begin(), protocol.end());

    { auto _r = std::vector<uint8_t>{HW_MESSAGE_MAGIC_TYPE_UINT, 0, 0, 0, 0}; m_data.insert(m_data.end(), _r.begin(), _r.end()); }'''),
    ],
    'src/core/message/messages/FatalProtocolError.cpp': [
        ('''    m_data.append_range(g_messageParser->encodeVarInt(msg.size()));
    m_data.append_range(msg);''',
         '''    { auto _r = g_messageParser->encodeVarInt(msg.size()); m_data.insert(m_data.end(), _r.begin(), _r.end()); }
    m_data.insert(m_data.end(), msg.begin(), msg.end());'''),
    ],
}

for fpath, replacements in patches.items():
    with open(fpath) as f:
        content = f.read()
    for old, new in replacements:
        assert old in content, f'Pattern not found in {fpath}'
        content = content.replace(old, new)
    with open(fpath, 'w') as f:
        f.write(content)
    print(f'Patched {fpath}')
PYEOF
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
