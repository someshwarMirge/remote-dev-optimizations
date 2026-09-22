# Remote Cloud VM Development — Optimization & Deployment Guide

This toolkit optimizes **any Windows client PC** and **any remote Ubuntu cloud VM** (AWS EC2, Google Cloud Compute Engine, Azure VM, DigitalOcean, private OpenStack, etc.) for rock-solid reliability, low latency, and zero connection drops.

---

## Architecture Overview

```
+-------------------------------------------------+             +-----------------------------------------------+
|             Local Windows Client PC             |             |             Remote Ubuntu Cloud VM            |
|  - Acts as IDE Frontend (VS Code, Antigravity)  |             |  - Heavy Compilation & Language Servers       |
|  - Windows Terminal / SSH Client                |             |  - Docker, Databases, Runtime Execution       |
|  - Local SSH Private Keys (stay on local PC)    |             |  - Persistent tmux Background Sessions        |
+-------------------------------------------------+             +-----------------------------------------------+
                        |                                                               ^
                        |==== SSH (Keepalive + Agent Forwarding + Port Forwarding) =====|
```

---

## Toolkit Directory Structure

```
Remote-Dev-Optimizer/
├── Run-Optimizer-Windows.bat         # 1-Click root launcher for any Windows machine
├── OPTIMIZATION_GUIDE.md             # This comprehensive deployment guide
├── client-windows/
│   ├── Optimize-RemoteDev.bat        # One-click self-elevating Admin launcher
│   ├── optimize-for-remote-dev.ps1   # Core PowerShell optimization engine
│   ├── ssh_config_snippet.txt        # Universal keepalive snippet for ~/.ssh/config
│   └── vscode_settings_snippet.json  # Recommended Remote-SSH settings for VS Code
└── remote-ubuntu/
    └── setup-remote-ubuntu-vm.sh     # Server-side setup script for the Ubuntu VM
```

---

## Part 1: Setting Up a Windows Client PC

### Quick Setup (1 Click)
1. Copy the `Remote-Dev-Optimizer` folder to the target Windows PC (or keep it on a USB drive).
2. Right-click **`Run-Optimizer-Windows.bat`** (or `client-windows\Optimize-RemoteDev.bat`) and select **Run as administrator** (or double-click and click **Yes** on the UAC prompt).
3. The script automatically executes the following 5 phases:
   - **Physical Network Adapters**: Scans all active physical network adapters (Intel, Realtek, Broadcom, Wi-Fi) and disables **Energy Efficient Ethernet (EEE)**, **Ultra Low Power Mode**, and adapter sleep. This stops random 1-2 second link negotiations that cause SSH `Connection reset by peer`.
   - **OpenSSH Authentication Agent**: Configures the Windows `ssh-agent` service to `Automatic` and starts it, allowing key caching and seamless SSH Agent Forwarding.
   - **Windows Update Reboot Suppression**: Enforces `NoAutoRebootWithLoggedOnUsers = 1` in the registry. Windows will never restart your PC for pending updates while you are logged in.
   - **Power Management**: Sets AC standby and hibernate timeouts to `0` (Never). Active terminals and port forwards will never be killed by idle sleep.
   - **Dev Tools Configuration**: Automatically checks and configures `~/.ssh/config` keepalives and VS Code `settings.json`.

---

### Manual Verification on Windows

#### 1. Test SSH Keepalive Resolution
Run this in PowerShell or CMD to verify that any host inherits keepalive packets:
```powershell
ssh -G your-remote-host | findstr -i "serveralive tcpkeepalive ipqos addkeystoagent"
```
*Expected output:*
```
tcpkeepalive yes
serveralivecountmax 5
serveraliveinterval 30
addkeystoagent true
ipqos lowdelay throughput
```

#### 2. Check OpenSSH Agent Service
```powershell
Get-Service ssh-agent | Select-Object Name, Status, StartType
```
*Expected output:* `Status: Running`, `StartType: Automatic`.

#### 3. Load Your Private Key into the Local Agent
```powershell
ssh-add ~\.ssh\id_ed25519
```
*(Once added, you won't need to retype your passphrase when opening new terminals or launching VS Code).*

---

## Part 2: Setting Up the Remote Ubuntu Cloud VM

### Quick Setup (1 Command)
1. Transfer the setup script to the remote Ubuntu VM:
   ```bash
   scp remote-ubuntu/setup-remote-ubuntu-vm.sh user@your-vm-ip:~/
   ```
2. SSH into your VM and run the script with `sudo`:
   ```bash
   ssh user@your-vm-ip
   sudo bash setup-remote-ubuntu-vm.sh
   ```

### What `setup-remote-ubuntu-vm.sh` Does:
1. **Server-Side SSH Keepalives (`/etc/ssh/sshd_config.d/99-reliability.conf`)**:
   - Configures `ClientAliveInterval 30` and `ClientAliveCountMax 5`.
   - Enables `AllowAgentForwarding yes` and `GatewayPorts clientspecified`.
   - The cloud VM actively checks for client responsiveness every 30s.
2. **Inotify & File Watcher Limits (`/etc/sysctl.d/99-vscode-watcher.conf`)**:
   - Increases `fs.inotify.max_user_watches` to `524288` (default is often 8192).
   - Prevents VS Code and language servers (`rust-analyzer`, `gopls`, `pyright`) from erroring out on large workspaces.
3. **Swapfile Setup (OOM Protection)**:
   - Automatically detects available swap. If < 2GB, creates a **4GB swapfile** at `/swapfile`.
   - Prevents the Linux Out-Of-Memory (`oom-killer`) from crashing compilers (`cargo build`, `npm run build`, `clang++`) during peak RAM spikes.
4. **Tmux Terminal Multiplexer**:
   - Installs `tmux` and sets up mouse scrolling (`set -g mouse on`) and 50,000 line scrollback history.

---

## Part 3: Developer Best Practices & Workflows

### 1. Unbreakable Remote Terminal Sessions with `tmux`
Even with perfect keepalive settings, a physical Wi-Fi drop or laptop lid close will disconnect the SSH connection. With `tmux`, processes running on the cloud VM **never stop**:

```bash
# Start a new persistent session named 'dev'
tmux new -s dev

# Run your long-running server, build, or tests:
npm run dev

# Detach from the session safely anytime:
# Press: Ctrl + b, then press d

# Reattach when you reconnect to the VM:
tmux attach -t dev

# List all running sessions:
tmux ls
```

### 2. SSH Agent Forwarding (Safe Git Authentication)
Never copy your personal GitHub/GitLab private SSH keys onto a cloud VM. With Agent Forwarding:
1. On your Windows PC, add your key to `ssh-agent`:
   ```powershell
   ssh-add ~\.ssh\id_ed25519
   ```
2. Connect with Agent Forwarding:
   ```bash
   ssh -A user@your-vm-ip
   ```
   *(Or connect via VS Code Remote-SSH, which has `"remote.SSH.enableAgentForwarding": true` configured).*
3. Inside the remote VM, test GitHub access:
   ```bash
   ssh -T git@github.com
   ```
   Your local Windows key authenticates the cloud VM seamlessly without the private key ever leaving your local machine.

### 3. Automatic Port Forwarding (Local Browser Preview)
When you run a web server inside the VM (e.g. `localhost:3000` or `localhost:8080`), VS Code automatically forwards the port. You can open `http://localhost:3000` in your Windows browser and preview it instantly.

To forward ports manually via SSH:
```bash
ssh -L 3000:localhost:3000 user@your-vm-ip
```

---

## Troubleshooting & FAQ

| Problem | Root Cause | Solution |
| :--- | :--- | :--- |
| **SSH freezes after 5-10 minutes of inactivity** | Intermediate router/NAT drops idle TCP states. | Ensure `ServerAliveInterval 30` is in `~/.ssh/config` on Windows and `ClientAliveInterval 30` is on the Ubuntu VM. |
| **"Connection reset by peer" during bursts** | Intel/Realtek Ethernet EEE entering low-power mode. | Run `Optimize-RemoteDev.bat` to disable Energy Efficient Ethernet on the Windows network adapter. |
| **Windows reboots overnight, killing sessions** | Windows Update installing updates after active hours. | Run `Optimize-RemoteDev.bat` to enforce `NoAutoRebootWithLoggedOnUsers = 1`. |
| **VS Code shows "File watcher limit reached"** | Linux default `fs.inotify.max_user_watches` is too low. | Run `sudo bash setup-remote-ubuntu-vm.sh` on the Ubuntu VM. |
| **Compiler or Language Server randomly dies (SIGKILL)** | Cloud VM ran out of RAM; Linux OOM killer terminated it. | Run `setup-remote-ubuntu-vm.sh` to enable the 4GB swapfile. |
| **ProxyJump / Bastion connections timing out** | Corporate jump host taking >30s for authentication. | Set `"remote.SSH.connectTimeout": 60` in VS Code `settings.json`. |
