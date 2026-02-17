#!/bin/bash
# VioMesh Installer
# Usage: curl -sL get.viomesh.net | bash -s -- <key>

set -euo pipefail

KEY="${1:-}"
if [ -z "$KEY" ]; then
    echo "Usage: curl -sL get.viomesh.net | bash -s -- <key>"
    echo "Or:    viomesh join <key>"
    exit 1
fi

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: root access required"
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  BINARY="viomesh_linux_amd64" ;;
    aarch64) BINARY="viomesh_linux_arm64" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

MIRROR="http://dl.viomesh.ir"
REPO="iProxyLLC/VioMesh-Release"
INSTALL_PATH="/usr/local/bin/viomesh"

echo "Installing VioMesh..."

# Try mirror first (works during internet blackouts in Iran)
if curl -sf --connect-timeout 5 -o "${INSTALL_PATH}" "${MIRROR}/${BINARY}" 2>/dev/null; then
    LATEST=$(curl -sf --connect-timeout 5 "${MIRROR}/version.txt" 2>/dev/null || echo "unknown")
    echo "Downloaded ${BINARY} ${LATEST} from mirror"
else
    # Fall back to GitHub
    echo "Mirror unavailable, trying GitHub..."
    LATEST=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" | grep -oP '"tag_name": "\K[^"]+')
    if [ -z "$LATEST" ]; then
        echo "Error: could not determine latest version"
        exit 1
    fi
    echo "Downloading ${BINARY} ${LATEST}..."
    curl -sLo "${INSTALL_PATH}" "https://github.com/${REPO}/releases/download/${LATEST}/${BINARY}"
fi

chmod +x "${INSTALL_PATH}"
echo "Binary installed to ${INSTALL_PATH}"

# Apply kernel optimizations
echo "Applying kernel optimizations..."

# BBR congestion control
if modprobe tcp_bbr 2>/dev/null; then
    sysctl -qw net.core.default_qdisc=fq 2>/dev/null || true
    sysctl -qw net.ipv4.tcp_congestion_control=bbr 2>/dev/null || true
fi

# TCP buffer tuning
sysctl -qw net.core.rmem_max=134217728 2>/dev/null || true
sysctl -qw net.core.wmem_max=134217728 2>/dev/null || true
sysctl -qw net.ipv4.tcp_rmem="4096 87380 134217728" 2>/dev/null || true
sysctl -qw net.ipv4.tcp_wmem="4096 65536 134217728" 2>/dev/null || true
sysctl -qw net.core.netdev_max_backlog=16384 2>/dev/null || true
sysctl -qw net.core.somaxconn=65535 2>/dev/null || true
sysctl -qw net.ipv4.tcp_max_syn_backlog=65535 2>/dev/null || true

# File descriptor limits
sysctl -qw fs.file-max=1048576 2>/dev/null || true

# TCP Fast Open
sysctl -qw net.ipv4.tcp_fastopen=3 2>/dev/null || true

# Persist sysctl settings
cat > /etc/sysctl.d/99-viomesh.conf << 'SYSCTL'
# VioMesh kernel optimizations
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
fs.file-max = 1048576
net.ipv4.tcp_fastopen = 3
SYSCTL

# File descriptor limits
mkdir -p /etc/security/limits.d
cat > /etc/security/limits.d/99-viomesh.conf << 'LIMITS'
* soft nofile 1048576
* hard nofile 1048576
LIMITS

echo "Kernel optimizations applied"

# Join mesh with key (creates systemd service and starts it)
echo "Joining mesh..."
exec "${INSTALL_PATH}" join "$KEY"
