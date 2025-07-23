@echo off
powershell -NoLogo -NoProfile -Command "New-Item -ItemType File -Path $PROFILE -Force"
echo PowerShell profile created (or already exists).
pause
