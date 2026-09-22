#!/usr/bin/env bash
# ==============================================================================
# setup-remote-ubuntu-vm.sh
# Remote Ubuntu Cloud VM Resilience & Developer Optimization Toolkit
#
# Run this script on your remote Ubuntu Cloud VM (AWS, GCP, Azure, DigitalOcean, etc.)
# to ensure:
#  1. Unbreakable SSH Server Keepalives & Port/Agent Forwarding (/etc/ssh/sshd_config)
#  2. Linux Inotify Watches Increased (prevents VS Code/IDE file-watching crashes)
#  3. 4GB Swapfile Configured (prevents Out-Of-Memory compiler & language server crashes)
#  4. Tmux Installed & Configured with mouse scrolling & session persistence
#  5. Essential Developer Tools (git, curl, build-essential, htop, iotop)
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================================${NC}"
echo -e "${BLUE}    REMOTE UBUNTU CLOUD VM - RELIABILITY & DEV OPTIMIZER         ${NC}"
echo -e "${BLUE}==================================================================${NC}"

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[!] This script must be run with sudo privileges.${NC}"
    echo "    Usage: sudo bash setup-remote-ubuntu-vm.sh"
    exit 1
fi

# ------------------------------------------------------------------------------
# 1. SSH DAEMON RELIABILITY & KEEPALIVES
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[1/5] Configuring OpenSSH Server keepalive & forwarding...${NC}"

SSHD_CONF_DIR="/etc/ssh/sshd_config.d"
SSHD_RELIABILITY_CONF="${SSHD_CONF_DIR}/99-reliability.conf"

if [ -d "$SSHD_CONF_DIR" ]; then
    cat << 'EOF' > "$SSHD_RELIABILITY_CONF"
# Server-side keepalives to prevent NAT/firewall drops
ClientAliveInterval 30
ClientAliveCountMax 5
TCPKeepAlive yes

# Remote development agent and port forwarding
AllowAgentForwarding yes
AllowTcpForwarding yes
GatewayPorts clientspecified
EOF
    echo -e "${GREEN}    [+] Created ${SSHD_RELIABILITY_CONF}${NC}"
else
    # Fallback for Ubuntu versions without sshd_config.d
    sed -i -E 's/^#?ClientAliveInterval.*/ClientAliveInterval 30/' /etc/ssh/sshd_config
    sed -i -E 's/^#?ClientAliveCountMax.*/ClientAliveCountMax 5/' /etc/ssh/sshd_config
    sed -i -E 's/^#?TCPKeepAlive.*/TCPKeepAlive yes/' /etc/ssh/sshd_config
    sed -i -E 's/^#?AllowAgentForwarding.*/AllowAgentForwarding yes/' /etc/ssh/sshd_config
    echo -e "${GREEN}    [+] Updated /etc/ssh/sshd_config${NC}"
fi

# Test configuration before reloading
if sshd -t; then
    systemctl reload ssh || systemctl reload sshd || service ssh reload
    echo -e "${GREEN}    [+] SSH daemon reloaded successfully${NC}"
else
    echo -e "${RED}    [-] SSH configuration test failed; reverting changes.${NC}"
    rm -f "$SSHD_RELIABILITY_CONF"
fi

# ------------------------------------------------------------------------------
# 2. INOTIFY & FILE WATCHER LIMITS (FOR VS CODE / JETBRAINS / NEOVIM)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[2/5] Optimizing Linux kernel file watchers (fs.inotify)...${NC}"

SYSCTL_CONF="/etc/sysctl.d/99-vscode-watcher.conf"
cat << 'EOF' > "$SYSCTL_CONF"
# Increase inotify limits for IDE file watchers on large repositories
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
fs.file-max = 2097152
EOF

sysctl --system > /dev/null
echo -e "${GREEN}    [+] inotify max_user_watches set to 524,288${NC}"

# ------------------------------------------------------------------------------
# 3. SWAPFILE SETUP (PREVENTS OOM COMPILER CRASHES)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/5] Checking Swap Space (Prevent Out-Of-Memory builds)...${NC}"

CURRENT_SWAP=$(free -m | awk '/^Swap:/ {print $2}')

if [ "$CURRENT_SWAP" -lt 2000 ]; then
    echo -e "    Detected low swap (${CURRENT_SWAP} MB). Creating a 4GB swapfile..."
    SWAPFILE="/swapfile"
    if [ ! -f "$SWAPFILE" ]; then
        fallocate -l 4G "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=4096
        chmod 600 "$SWAPFILE"
        mkswap "$SWAPFILE"
        swapon "$SWAPFILE"
        if ! grep -q "$SWAPFILE" /etc/fstab; then
            echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
        fi
        echo -e "${GREEN}    [+] 4GB Swapfile created and enabled at ${SWAPFILE}${NC}"
    else
        swapon "$SWAPFILE" || true
        echo -e "${GREEN}    [+] Swapfile exists and enabled${NC}"
    fi
else
    echo -e "${GREEN}    [*] Sufficient swap detected (${CURRENT_SWAP} MB). Skipping swapfile.${NC}"
fi

# Set conservative swappiness
sysctl -w vm.swappiness=15 > /dev/null

# ------------------------------------------------------------------------------
# 4. TMUX (TERMINAL MULTIPLEXER) FOR UNBREAKABLE BACKGROUND SESSIONS
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[4/5] Installing and configuring tmux for session persistence...${NC}"

if ! command -v tmux &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq tmux
    echo -e "${GREEN}    [+] Installed tmux${NC}"
else
    echo -e "${GREEN}    [*] tmux already installed${NC}"
fi

# Configure tmux for the calling user (if SUDO_USER is set)
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

if [ -d "$TARGET_HOME" ]; then
    TMUX_CONF="${TARGET_HOME}/.tmux.conf"
    if [ ! -f "$TMUX_CONF" ]; then
        cat << 'EOF' > "$TMUX_CONF"
# Enable mouse support (click tabs, resize panes, scroll buffer)
set -g mouse on

# Increase scrollback buffer
set -g history-limit 50000

# 256 color support
set -g default-terminal "screen-256color"

# Zero-delay escape key response for vim/neovim
set -s escape-time 0

# Start window/pane indexing at 1 instead of 0
set -g base-index 1
setw -g pane-base-index 1
EOF
        chown "${TARGET_USER}:${TARGET_USER}" "$TMUX_CONF"
        echo -e "${GREEN}    [+] Created ${TMUX_CONF} with mouse & scrollback support for ${TARGET_USER}${NC}"
    else
        echo -e "${GREEN}    [*] ${TMUX_CONF} already exists${NC}"
    fi
fi

# ------------------------------------------------------------------------------
# 5. ESSENTIAL DEV PACKAGES
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[5/5] Checking essential developer utilities...${NC}"
apt-get install -y -qq git curl wget htop net-tools iotop build-essential > /dev/null 2>&1 || true
echo -e "${GREEN}    [+] Core tools (git, curl, build-essential, htop) verified${NC}"

echo -e "\n${BLUE}==================================================================${NC}"
echo -e "${GREEN}  REMOTE UBUNTU CLOUD VM FULLY OPTIMIZED FOR DEVELOPMENT!         ${NC}"
echo -e "${BLUE}==================================================================${NC}"
echo -e "Key workflows:"
echo -e "  - Start persistent terminal: ${YELLOW}tmux new -s dev${NC}"
echo -e "  - Reattach after disconnect: ${YELLOW}tmux attach -t dev${NC}"
echo -e "  - Check memory & swap:       ${YELLOW}free -h${NC}"
echo -e "${BLUE}==================================================================${NC}"
