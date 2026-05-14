#!/bin/bash
set -e

REPO="BandiAkarsh/Hyprland-for-debian"
echo "=== Hyprland Installer for Debian 13 / LMDE 7 ==="
echo ""

# Check Debian version
if [ ! -f /etc/debian_version ]; then
    echo "This installer is for Debian-based systems only."
    exit 1
fi

DEBIAN_VER=$(cat /etc/debian_version | cut -d. -f1)
echo "Detected Debian version: $(cat /etc/debian_version)"

# Install system deps
echo ""
echo "[1/4] Installing system dependencies..."
sudo apt update
sudo apt install -y cmake g++ pkg-config wayland-protocols \
    glslang-dev glslang-tools libwayland-dev libxkbcommon-dev \
    libinput-dev libdrm-dev libgbm-dev libcairo2-dev libpango1.0-dev \
    libpixman-1-dev libxcursor-dev libxcb*-dev libgl1-mesa-dev \
    libgles2-mesa-dev libegl1-mesa-dev libuuid-dev liblcms2-dev \
    libre2-dev libmuparser-dev liblua5.4-dev

# Download latest release
echo ""
echo "[2/4] Downloading latest Hyprland release..."
LATEST=$(curl -s https://api.github.com/repos/$REPO/releases/latest \
    | grep "browser_download_url.*deb" | cut -d: -f2,3 | tr -d ' "' )
if [ -z "$LATEST" ]; then
    echo "Failed to find latest release. Falling back to source build."
    git clone https://github.com/$REPO.git /tmp/hyprland-build
    cd /tmp/hyprland-build
    bash scripts/build-ecosystem.sh
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j$(nproc)
    sudo cmake --install build
    echo "Done! Start with: Hyprland"
    exit 0
fi

wget -O /tmp/hyprland.deb "$LATEST"

echo ""
echo "[3/4] Installing Hyprland..."
sudo dpkg -i /tmp/hyprland.deb || sudo apt install -f -y

echo ""
echo "[4/4] Cleaning up..."
rm -f /tmp/hyprland.deb

echo ""
echo "=== Hyprland installed successfully! ==="
echo "Start with: Hyprland"
echo "Or select Hyprland from your display manager session list."
