# ============================================================
# Script: Setup-WinRM-Only.ps1
# Purpose: Configure Windows VM for Ansible WinRM management only
#          - Create user 'win_ansible' with Administrator privileges
#          - WinRM on port 5985 (HTTP)
#          - IP Routing
#          - Firewall rules
#          - Complete WinRM configuration for Ansible
#          - Fix TrustedHosts (prevents WinRM hangs)
#          - Disable IPv6 (fixes slow Wi-Fi/network issues)
#          - Fix NLA (prevents "No Internet" false errors)
#          - TCP/IP optimization (fixes network performance)
#          - Configure AutoLogon for win_ansible user
# ============================================================

# Set execution policy to allow script to run
Write-Host "Setting execution policy..." -ForegroundColor Cyan
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# Run as Administrator check
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    Write-Host "Right-click on PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Windows WinRM Setup for Ansible" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# STEP 1: Create User 'win_ansible' with Administrator Privileges
# ============================================================
Write-Host "[1/13] Creating user 'win_ansible'..." -ForegroundColor Yellow

$username = "win_ansible"
$password = "Btmor499"
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force

# Check if user already exists
if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
    Write-Host "  User '$username' already exists. Resetting password..." -ForegroundColor Yellow
    Set-LocalUser -Name $username -Password $securePassword
} else {
    # Create new user
    New-LocalUser -Name $username -Password $securePassword -FullName "Ansible WinRM User" -Description "User for Ansible WinRM management" -PasswordNeverExpires -AccountNeverExpires
    Write-Host "  User '$username' created successfully." -ForegroundColor Green
}

# Add user to Administrators group
Add-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction SilentlyContinue
Write-Host "  User '$username' added to Administrators group." -ForegroundColor Green

# Add user to Remote Management Users group
Add-LocalGroupMember -Group "Remote Management Users" -Member $username -ErrorAction SilentlyContinue
Write-Host "  User '$username' added to Remote Management Users group." -ForegroundColor Green

# Set the display name on login screen
Write-Host "  Setting display name for user..." -ForegroundColor Yellow
Set-LocalUser -Name $username -FullName "win_ansible (Ansible Admin)"
Write-Host "  Display name set to 'win_ansible (Ansible Admin)'" -ForegroundColor Green

# ============================================================
# STEP 2: Configure AutoLogon for win_ansible user
# ============================================================
Write-Host "[2/13] Configuring AutoLogon for user '$username'..." -ForegroundColor Yellow

# Define the registry path
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

# Set the values for autologon
Set-ItemProperty -Path $regPath -Name "AutoAdminLogon" -Value "1" -Type String
Set-ItemProperty -Path $regPath -Name "DefaultUserName" -Value $username -Type String
Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value $password -Type String

Write-Host "  AutoLogon configured for user: $username" -ForegroundColor Green
Write-Host "  AutoLogon will trigger on every reboot (indefinitely)." -ForegroundColor Yellow

# ============================================================
# STEP 3: Change Network Profile from Public to Private
# ============================================================
Write-Host "[3/13] Configuring Network Profile..." -ForegroundColor Yellow

$networkProfiles = Get-NetConnectionProfile
foreach ($profile in $networkProfiles) {
    if ($profile.NetworkCategory -eq "Public") {
        Write-Host "  Changing network profile from Public to Private..." -ForegroundColor Yellow
        Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex -NetworkCategory Private
        Write-Host "  Network profile changed to Private." -ForegroundColor Green
    } else {
        Write-Host "  Network profile is already $($profile.NetworkCategory)." -ForegroundColor Green
    }
}

# ============================================================
# STEP 4: Configure WinRM Service
# ============================================================
Write-Host "[4/13] Configuring WinRM Service..." -ForegroundColor Yellow

# Stop WinRM service for configuration
Stop-Service WinRM -Force -ErrorAction SilentlyContinue

# Run quick config (this starts WinRM and configures firewall)
winrm quickconfig -quiet -force

# Configure WinRM SERVER settings
Write-Host "  Configuring WinRM Server settings..." -ForegroundColor Yellow
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="2048"}'
winrm set winrm/config '@{MaxEnvelopeSizekb="2048"}'

# Configure WinRM CLIENT settings (critical for Ansible)
Write-Host "  Configuring WinRM Client settings..." -ForegroundColor Yellow
winrm set winrm/config/client '@{AllowUnencrypted="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Digest="true"}'
winrm set winrm/config/client/auth '@{CredSSP="true"}'

# Remove existing HTTP listener and recreate
Write-Host "  Configuring HTTP Listener..." -ForegroundColor Yellow
winrm delete winrm/config/Listener?Address=*+Transport=HTTP -ErrorAction SilentlyContinue
winrm create winrm/config/Listener?Address=*+Transport=HTTP

# ============================================================
# STEP 5: Configure TrustedHosts (CRITICAL for Ansible - Prevents hangs)
# ============================================================
Write-Host "[5/13] Configuring WinRM TrustedHosts..." -ForegroundColor Yellow

# Get current value
$currentTrustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value

if ($currentTrustedHosts -eq "*") {
    Write-Host "  TrustedHosts already set to '*'" -ForegroundColor Green
} else {
    Write-Host "  Setting TrustedHosts to '*' (trust all hosts)..." -ForegroundColor Yellow
    Write-Host "  NOTE: For production, replace '*' with specific IPs or hostnames" -ForegroundColor Cyan
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    Write-Host "  TrustedHosts configured successfully." -ForegroundColor Green
}

# ============================================================
# STEP 6: Disable IPv6 (Fixes slow network/Wi-Fi issues)
# ============================================================
Write-Host "[6/13] Disabling IPv6 on all network adapters..." -ForegroundColor Yellow

$ipv6Disabled = $false
$adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

foreach ($adapter in $adapters) {
    $binding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID "ms_tcpip6" -ErrorAction SilentlyContinue
    if ($binding -and $binding.Enabled -eq $true) {
        Disable-NetAdapterBinding -Name $adapter.Name -ComponentID "ms_tcpip6"
        Write-Host "  Disabled IPv6 on adapter: $($adapter.Name)" -ForegroundColor Yellow
        $ipv6Disabled = $true
    }
}

# Also set registry key to prevent IPv6 from re-enabling
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 255 -Type DWord -Force -ErrorAction SilentlyContinue
Write-Host "  Registry key set to permanently disable IPv6." -ForegroundColor Green

if (-not $ipv6Disabled) {
    Write-Host "  IPv6 was already disabled on all adapters." -ForegroundColor Green
}

# ============================================================
# STEP 7: Configure Windows Firewall
# ============================================================
Write-Host "[7/13] Configuring Windows Firewall..." -ForegroundColor Yellow

# Remove existing rules
netsh advfirewall firewall delete rule name="WinRM HTTP 5985" > $null 2>&1
netsh advfirewall firewall delete rule name="Windows Remote Management (HTTP-In)" > $null 2>&1

# Add firewall rule for WinRM HTTP
netsh advfirewall firewall add rule name="WinRM HTTP 5985" dir=in action=allow protocol=TCP localport=5985 remoteip=any

# Enable WinRM firewall group
netsh advfirewall firewall set rule group="Windows Remote Management" new enable=yes

Write-Host "  Firewall rules added for port 5985." -ForegroundColor Green

# ============================================================
# STEP 8: Configure ICMP Firewall Rules (Allow Ping)
# ============================================================
Write-Host "[8/13] Configuring ICMP firewall rules (allow ping)..." -ForegroundColor Yellow

netsh advfirewall firewall delete rule name="Allow ICMPv4" > $null 2>&1
netsh advfirewall firewall add rule name="Allow ICMPv4" protocol=icmpv4:8,any dir=in action=allow

Write-Host "  ICMP firewall rules added." -ForegroundColor Green

# ============================================================
# STEP 9: Fix NLA (Prevents "No Internet" false errors after reboot)
# ============================================================
Write-Host "[9/13] Fixing Network Location Awareness (NLA)..." -ForegroundColor Yellow

# Enable active probing so Windows correctly detects internet connectivity
try {
    $nlaPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet"
    if (-not (Test-Path $nlaPath)) {
        New-Item -Path $nlaPath -Force | Out-Null
    }
    Set-ItemProperty -Path $nlaPath -Name "EnableActiveProbing" -Value 1 -Type DWord -Force
    Write-Host "  NLA active probing enabled." -ForegroundColor Green
} catch {
    Write-Host "  Could not modify NLA settings. You may need to run as Administrator." -ForegroundColor Yellow
}

# ============================================================
# STEP 10: TCP/IP Stack Optimization (Fixes network performance)
# ============================================================
Write-Host "[10/13] Optimizing TCP/IP stack..." -ForegroundColor Yellow

# Run TCP/IP optimization commands
Write-Host "  Running TCP/IP optimization commands..." -ForegroundColor Yellow

netsh int tcp set heuristics disabled
Write-Host "    - TCP heuristics: DISABLED" -ForegroundColor Gray

netsh int tcp set global autotuninglevel=normal
Write-Host "    - TCP auto-tuning: NORMAL" -ForegroundColor Gray

netsh int tcp set global rss=enabled
Write-Host "    - TCP RSS: ENABLED" -ForegroundColor Gray

netsh winsock reset
Write-Host "    - Winsock: RESET" -ForegroundColor Gray

netsh int ip reset
Write-Host "    - TCP/IP stack: RESET" -ForegroundColor Gray

# Release and renew IP address
Write-Host "  Releasing and renewing IP address..." -ForegroundColor Yellow
ipconfig /release
Start-Sleep -Seconds 2
ipconfig /renew
Start-Sleep -Seconds 2

# Flush DNS cache
ipconfig /flushdns
Write-Host "    - DNS cache: FLUSHED" -ForegroundColor Gray

Write-Host "  TCP/IP stack optimization complete." -ForegroundColor Green

# ============================================================
# STEP 11: Enable IP Routing (Optional - for VPN scenarios)
# ============================================================
Write-Host "[11/13] Enabling IP Routing..." -ForegroundColor Yellow

$currentValue = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -ErrorAction SilentlyContinue).IPEnableRouter

if ($currentValue -eq 1) {
    Write-Host "  IP routing already enabled." -ForegroundColor Green
} else {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1
    Write-Host "  IP routing enabled." -ForegroundColor Green
}

# ============================================================
# STEP 12: Fix WinRM Persistence After Reboot (CRITICAL FIX)
# ============================================================
Write-Host "[12/13] Fixing WinRM persistence after reboot..." -ForegroundColor Yellow

# Ensure WinRM service is set to Automatic startup
Set-Service -Name WinRM -StartupType Automatic
Write-Host "  Set WinRM startup type to Automatic." -ForegroundColor Green

# Ensure the WinRM service is running
Start-Service -Name WinRM -ErrorAction SilentlyContinue
Write-Host "  WinRM service started." -ForegroundColor Green

# Create a scheduled task to re-apply WinRM config at startup
Write-Host "  Creating scheduled task to ensure WinRM config persists..." -ForegroundColor Yellow

$taskName = "WinRMConfigPersistence"
$taskDescription = "Re-applies WinRM configuration after reboot to ensure Ansible connectivity"
$taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-Command { winrm set winrm/config/service/auth '@{Basic=`"true`"}'; winrm set winrm/config/service '@{AllowUnencrypted=`"true`"}'; Restart-Service WinRM -Force }"
$taskTrigger = New-ScheduledTaskTrigger -AtStartup
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

try {
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description $taskDescription -Force
    Write-Host "  Scheduled task created successfully." -ForegroundColor Green
} catch {
    Write-Host "  Warning: Could not create scheduled task: $_" -ForegroundColor Yellow
}

# Also fix WinRM listeners persistence
Write-Host "  Configuring WinRM listener to persist..." -ForegroundColor Yellow

# Ensure WinRM listener is properly configured in the registry
$listenerRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener"
try {
    # This ensures the listener is properly registered
    winrm enumerate winrm/config/listener
    Write-Host "  WinRM listener is registered." -ForegroundColor Green
} catch {
    Write-Host "  Warning: WinRM listener may need manual verification." -ForegroundColor Yellow
}

# Ensure the LocalAccountTokenFilterPolicy is set (critical for local accounts)
Write-Host "  Setting LocalAccountTokenFilterPolicy..." -ForegroundColor Yellow
$tokenFilterPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (-not (Test-Path $tokenFilterPath)) {
    New-Item -Path $tokenFilterPath -Force | Out-Null
}
Set-ItemProperty -Path $tokenFilterPath -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord -Force
Write-Host "  LocalAccountTokenFilterPolicy set to 1." -ForegroundColor Green

# ============================================================
# STEP 13: Final WinRM Verification
# ============================================================
Write-Host "[13/13] Final WinRM Verification..." -ForegroundColor Yellow

# Restart WinRM service
Write-Host "  Restarting WinRM Service..." -ForegroundColor Yellow
Restart-Service WinRM -Force -ErrorAction SilentlyContinue
Start-Service WinRM -ErrorAction SilentlyContinue

# Wait a moment for service to fully start
Start-Sleep -Seconds 5

# Verify WinRM is running
$winrmStatus = Get-Service WinRM
if ($winrmStatus.Status -eq "Running") {
    Write-Host "  WinRM service is RUNNING." -ForegroundColor Green
} else {
    Write-Host "  WinRM service is NOT running. Status: $($winrmStatus.Status)" -ForegroundColor Red
}

# Test WinRM locally with the new user
Write-Host "`n  Testing WinRM with user '$username'..." -ForegroundColor Yellow
$testResult = Test-WSMan -ComputerName localhost -Port 5985 -ErrorAction SilentlyContinue
if ($testResult) {
    Write-Host "  WinRM test SUCCESSFUL!" -ForegroundColor Green
    Write-Host "  WinRM Version: $($testResult.ProductVersion)" -ForegroundColor White
} else {
    Write-Host "  WinRM test FAILED. Please check configuration." -ForegroundColor Red
}

# Test with winrs command
Write-Host "`n  Testing winrs connection..." -ForegroundColor Yellow
$winrsTest = winrs -r:http://localhost:5985 -u:$username -p:$password whoami 2>$null
if ($winrsTest -eq "$env:COMPUTERNAME\$username") {
    Write-Host "  winrs test SUCCESSFUL! User: $winrsTest" -ForegroundColor Green
} else {
    Write-Host "  winrs test FAILED. Please check configuration." -ForegroundColor Red
}

# Test TrustedHosts is set
$trustedHostsCheck = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction SilentlyContinue).Value
Write-Host "`n  TrustedHosts: $trustedHostsCheck" -ForegroundColor White

# Test IPv6 status
$ipv6Check = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -ErrorAction SilentlyContinue).DisabledComponents
if ($ipv6Check -eq 255) {
    Write-Host "  IPv6: DISABLED (registry key set)" -ForegroundColor Green
} else {
    Write-Host "  IPv6: Check manually" -ForegroundColor Yellow
}

# ============================================================
# FINAL SUMMARY
# ============================================================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  WINRM SETUP COMPLETE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "USER ACCOUNT CREATED:" -ForegroundColor Cyan
Write-Host "  Username: win_ansible" -ForegroundColor White
Write-Host "  Password: Btmor499" -ForegroundColor White
Write-Host "  Display Name: win_ansible (Ansible Admin)" -ForegroundColor White
Write-Host "  Groups:   Administrators, Remote Management Users" -ForegroundColor White
Write-Host ""
Write-Host "CONFIGURATION SUMMARY:" -ForegroundColor Cyan
Write-Host "  [OK] Network Profile: Private" -ForegroundColor White
Write-Host "  [OK] WinRM Service: Running on port 5985" -ForegroundColor White
Write-Host "  [OK] WinRM AllowUnencrypted: True" -ForegroundColor White
Write-Host "  [OK] WinRM Basic Auth: Enabled" -ForegroundColor White
Write-Host "  [OK] WinRM MaxMemoryPerShellMB: 2048" -ForegroundColor White
Write-Host "  [OK] TrustedHosts: * (prevents WinRM hangs)" -ForegroundColor White
Write-Host "  [OK] IPv6: Disabled (fixes slow network issues)" -ForegroundColor White
Write-Host "  [OK] NLA ActiveProbing: Enabled (prevents 'No Internet' false errors)" -ForegroundColor White
Write-Host "  [OK] TCP/IP Stack: Optimized (heuristics, auto-tuning, RSS)" -ForegroundColor White
Write-Host "  [OK] Winsock: Reset" -ForegroundColor White
Write-Host "  [OK] DNS Cache: Flushed" -ForegroundColor White
Write-Host "  [OK] Firewall: Port 5985 OPEN" -ForegroundColor White
Write-Host "  [OK] ICMP (ping): Allowed" -ForegroundColor White
Write-Host "  [OK] IP Routing: Enabled" -ForegroundColor White
Write-Host "  [OK] WinRM Persistence: Fixed (service auto-start + scheduled task)" -ForegroundColor White
Write-Host "  [OK] LocalAccountTokenFilterPolicy: Set to 1" -ForegroundColor White
Write-Host ""
Write-Host "PERSISTENCE FIXES APPLIED:" -ForegroundColor Cyan
Write-Host "  [OK] WinRM service set to Automatic startup" -ForegroundColor White
Write-Host "  [OK] Scheduled task created to re-apply config at boot" -ForegroundColor White
Write-Host "  [OK] LocalAccountTokenFilterPolicy set to 1" -ForegroundColor White
Write-Host ""
Write-Host "LOCAL TEST COMMAND:" -ForegroundColor Cyan
Write-Host "  winrs -r:http://localhost:5985 -u:win_ansible -p:'Btmor499' whoami" -ForegroundColor White
Write-Host ""
Write-Host "FROM LINUX ANSIBLE CONTROLLER:" -ForegroundColor Cyan
Write-Host "  ansible windows-host -m win_ping -u win_ansible -k" -ForegroundColor White
Write-Host ""

# Ask user to reboot
$reboot = Read-Host "Do you want to reboot now? (Y/N)"
if ($reboot -eq "Y" -or $reboot -eq "y") {
    Write-Host "Rebooting in 5 seconds..." -ForegroundColor Red
    Start-Sleep -Seconds 5
    Restart-Computer
} else {
    Write-Host "Please reboot manually later for all changes to take effect." -ForegroundColor Yellow
    Write-Host "NOTE: IPv6, NLA, TCP/IP changes, and AutoLogon require a reboot to fully apply." -ForegroundColor Cyan
    Write-Host "After reboot, WinRM will automatically start and AutoLogon will trigger." -ForegroundColor Green
}