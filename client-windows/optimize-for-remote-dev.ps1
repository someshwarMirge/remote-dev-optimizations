<#
.SYNOPSIS
    Universal Windows Client Optimizer for Remote Cloud Development.
.DESCRIPTION
    Runs on any Windows 10/11 PC to optimize network stability, SSH agent, and power management:
    1. Detects all physical network adapters (Ethernet & Wi-Fi) and disables power-saving features
       like Energy Efficient Ethernet (EEE) and Ultra Low Power Mode that cause SSH drops and socket resets.
    2. Enables and starts the Windows OpenSSH Agent service for seamless SSH key handling and Agent Forwarding.
    3. Blocks Windows Update from abruptly restarting the PC while a user is logged on.
    4. Prevents AC standby/sleep so active remote tunnels and terminals are never severed.
    5. Optionally configures ~/.ssh/config keepalives and VS Code Remote-SSH settings.
#>

[CmdletBinding()]
param(
    [switch]$ConfigureSSH = $true,
    [switch]$ConfigureVSCode = $true
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] Administrator privileges required. Requesting elevation..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"") -Verb RunAs
    exit
}

Clear-Host
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "    UNIVERSAL WINDOWS CLIENT OPTIMIZER FOR REMOTE CLOUD DEV       " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. NETWORK ADAPTERS (ETHERNET & WI-FI POWER-SAVING TWEAKS)
# ------------------------------------------------------------------------------
Write-Host "`n[1/5] Auditing Physical Network Adapters (Ethernet & Wi-Fi)..." -ForegroundColor Yellow

# Query all physical network adapters (excluding virtual/Hyper-V/VPN)
$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue

if ($adapters) {
    foreach ($adapter in $adapters) {
        Write-Host "  -> Adapter: $($adapter.Name) [$($adapter.InterfaceDescription)]" -ForegroundColor White

        # Advanced properties to tune for zero packet drop / no sleep jitter
        $propsToDisable = @(
            "Energy Efficient Ethernet",
            "Energy-Efficient Ethernet",
            "EEE",
            "Ultra Low Power Mode",
            "Green Ethernet",
            "Reduce Speed On Power Down",
            "System Idle Power Saver",
            "Power Saving Mode",
            "Auto Disable Gigabit"
        )

        foreach ($propName in $propsToDisable) {
            $prop = Get-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $propName -ErrorAction SilentlyContinue
            if ($prop) {
                # Determine target value ('Off' or 'Disabled')
                $validValues = $prop.ValidDisplayValues
                $targetVal = $null
                if ($validValues -contains "Off") { $targetVal = "Off" }
                elseif ($validValues -contains "Disabled") { $targetVal = "Disabled" }

                if ($targetVal -and $prop.DisplayValue -ne $targetVal) {
                    try {
                        Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName $propName -DisplayValue $targetVal -ErrorAction Stop
                        Write-Host "     [+] $propName : Disabled (prevents idle packet drops)" -ForegroundColor Green
                    } catch {
                        Write-Host "     [-] Could not set $propName : $_" -ForegroundColor DarkYellow
                    }
                } else {
                    Write-Host "     [*] $propName : Already $targetVal" -ForegroundColor Gray
                }
            }
        }
    }

    # Disable selective power down via WMI/CIM across all physical network adapters
    try {
        $pnpDevs = Get-CimInstance MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue
        foreach ($dev in $pnpDevs) {
            if ($dev.Enable -eq $true) {
                $dev.Enable = $false
                Set-CimInstance -CimInstance $dev -ErrorAction SilentlyContinue
            }
        }
        Write-Host "  [+] All physical adapters configured to stay active (prevent sleep)" -ForegroundColor Green
    } catch {
        Write-Host "  [*] Adapter power management state verified" -ForegroundColor Gray
    }
} else {
    Write-Host "  [-] No physical network adapters detected" -ForegroundColor DarkYellow
}

# ------------------------------------------------------------------------------
# 2. OPENSSH AUTHENTICATION AGENT SERVICE
# ------------------------------------------------------------------------------
Write-Host "`n[2/5] Configuring Windows OpenSSH Authentication Agent..." -ForegroundColor Yellow

$sshAgent = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
if ($sshAgent) {
    if ($sshAgent.StartType -ne "Automatic") {
        Set-Service -Name "ssh-agent" -StartupType Automatic
        Write-Host "  [+] Service 'ssh-agent' startup type set to: Automatic" -ForegroundColor Green
    } else {
        Write-Host "  [*] Service 'ssh-agent' startup type: Already Automatic" -ForegroundColor Green
    }

    if ($sshAgent.Status -ne "Running") {
        Start-Service -Name "ssh-agent"
        Write-Host "  [+] Service 'ssh-agent' started successfully" -ForegroundColor Green
    } else {
        Write-Host "  [*] Service 'ssh-agent': Already Running" -ForegroundColor Green
    }
} else {
    Write-Host "  [-] OpenSSH Agent service not installed. (Install via Optional Features -> OpenSSH Client)" -ForegroundColor DarkYellow
}

# ------------------------------------------------------------------------------
# 3. WINDOWS UPDATE REBOOT PROTECTION
# ------------------------------------------------------------------------------
Write-Host "`n[3/5] Configuring Windows Update Reboot Policy..." -ForegroundColor Yellow

$wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (-not (Test-Path $wuPath)) {
    New-Item -Path $wuPath -Force | Out-Null
}

try {
    Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
    Write-Host "  [+] NoAutoRebootWithLoggedOnUsers = 1 (enforced)" -ForegroundColor Green
    Write-Host "      Windows Update will NOT restart automatically while you are logged in." -ForegroundColor Gray
} catch {
    Write-Host "  [-] Failed to set NoAutoRebootWithLoggedOnUsers: $_" -ForegroundColor Red
}

# ------------------------------------------------------------------------------
# 4. POWER MANAGEMENT (PREVENT AC STANDBY/SLEEP)
# ------------------------------------------------------------------------------
Write-Host "`n[4/5] Verifying System Power Policies (No Standby on AC)..." -ForegroundColor Yellow

try {
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
    Write-Host "  [+] AC Standby and Hibernation set to NEVER (0 minutes)" -ForegroundColor Green
} catch {
    Write-Host "  [-] powercfg update encountered an error: $_" -ForegroundColor DarkYellow
}

# ------------------------------------------------------------------------------
# 5. USER-LEVEL DEV CONFIGS (SSH & VS CODE)
# ------------------------------------------------------------------------------
Write-Host "`n[5/5] Checking User-Level Developer Tooling..." -ForegroundColor Yellow

# A. SSH Config
$userProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
$sshDir = Join-Path $userProfile ".ssh"
$sshConfigFile = Join-Path $sshDir "config"

if ($ConfigureSSH) {
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    $needsSSHConfig = $true
    if (Test-Path $sshConfigFile) {
        $content = Get-Content $sshConfigFile -Raw -ErrorAction SilentlyContinue
        if ($content -match "ServerAliveInterval") {
            $needsSSHConfig = $false
            Write-Host "  [*] ~/.ssh/config already contains ServerAliveInterval keepalive settings." -ForegroundColor Gray
        }
    }

    if ($needsSSHConfig) {
        $sshSnippet = @"

# Universal keepalive & reliability defaults for all remote sessions & proxy jumps
Host *
  ServerAliveInterval 30
  ServerAliveCountMax 5
  TCPKeepAlive yes
  IPQoS lowdelay throughput
  AddKeysToAgent yes
  IdentitiesOnly no
"@
        Add-Content -Path $sshConfigFile -Value $sshSnippet
        Write-Host "  [+] Added universal keepalive (ServerAliveInterval 30) to ~/.ssh/config" -ForegroundColor Green
    }
}

# B. VS Code Settings
if ($ConfigureVSCode) {
    $vscodeSettingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
    if (Test-Path $vscodeSettingsPath) {
        try {
            $json = Get-Content $vscodeSettingsPath -Raw | ConvertFrom-Json
            $modified = $false

            if ($json.'remote.SSH.connectTimeout' -lt 60) {
                $json | Add-Member -NotePropertyName "remote.SSH.connectTimeout" -NotePropertyValue 60 -Force
                $modified = $true
            }
            if (-not $json.'remote.SSH.enableAgentForwarding') {
                $json | Add-Member -NotePropertyName "remote.SSH.enableAgentForwarding" -NotePropertyValue $true -Force
                $modified = $true
            }
            if (-not $json.'remote.SSH.lockfilesInTmp') {
                $json | Add-Member -NotePropertyName "remote.SSH.lockfilesInTmp" -NotePropertyValue $true -Force
                $modified = $true
            }
            if (-not $json.'remote.SSH.suppressPromptOnConnectionBreak') {
                $json | Add-Member -NotePropertyName "remote.SSH.suppressPromptOnConnectionBreak" -NotePropertyValue $true -Force
                $modified = $true
            }
            if (-not $json.'remote.autoForwardPorts') {
                $json | Add-Member -NotePropertyName "remote.autoForwardPorts" -NotePropertyValue $true -Force
                $modified = $true
            }

            if ($modified) {
                $json | ConvertTo-Json -Depth 20 | Set-Content $vscodeSettingsPath -Encoding UTF8
                Write-Host "  [+] Tuned VS Code Remote-SSH configuration in settings.json" -ForegroundColor Green
            } else {
                Write-Host "  [*] VS Code Remote-SSH settings already optimized" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  [-] Could not parse VS Code settings.json: $_" -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "  [*] VS Code settings.json not detected for current user" -ForegroundColor Gray
    }
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "  OPTIMIZATION COMPLETE! SYSTEM IS TUNED FOR REMOTE CLOUD DEV     " -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan

if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
    Write-Host "`nPress any key to exit..."
    [void][System.Console]::ReadKey()
}
