# Remote Cloud VM Development — Optimization Toolkit

A portable, production-ready toolkit to optimize **Windows Client PCs** and **Remote Ubuntu Cloud VMs** for unbreakable SSH connections, low latency, and zero connection drops.

---

## Quick Start

### On Any Windows Client Machine:
1. Double-click **`Run-Optimizer-Windows.bat`** (or right-click -> **Run as administrator**).
2. It automatically disables network adapter power-saving glitches (EEE), enables the OpenSSH agent service, blocks unexpected Windows Update restarts, prevents sleep on AC power, and optimizes `~/.ssh/config` and VS Code settings.

### On Any Remote Ubuntu Cloud VM:
1. Copy `remote-ubuntu/setup-remote-ubuntu-vm.sh` to your VM:
   ```bash
   scp remote-ubuntu/setup-remote-ubuntu-vm.sh user@your-vm-ip:~/
   ```
2. Run on the VM:
   ```bash
   sudo bash setup-remote-ubuntu-vm.sh
   ```
3. It sets up server-side keepalives, inotify file watchers for IDEs, a 4GB swapfile to prevent OOM build crashes, and `tmux` with mouse scrolling.

---

## Detailed Documentation
For complete step-by-step instructions, verification commands, tmux workflows, and troubleshooting, read:
👉 **[OPTIMIZATION_GUIDE.md](OPTIMIZATION_GUIDE.md)**
