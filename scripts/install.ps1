$installDir = "$env:USERPROFILE\.ccc"
$scriptDir  = $PSScriptRoot

# create install directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

# copy ccc.ps1
Copy-Item "$scriptDir\ccc.ps1" "$installDir\ccc.ps1" -Force

# copy the syntax highlighting vsix (newest version wins, renamed without version suffix)
$vsix = Get-ChildItem "$scriptDir\..\editor\vscode-cccrouter-syntax" -Filter "cccrouter-syntax-*.vsix" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($vsix) {
    Copy-Item $vsix.FullName "$installDir\cccrouter-syntax.vsix" -Force
}

# create ccc.cmd wrapper (allows calling 'ccc' from any terminal)
$cmdWrapper = '@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccc.ps1" %*'
Set-Content "$installDir\ccc.cmd" $cmdWrapper -Encoding ASCII

# add to user PATH if not already present
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$userPath;$installDir", "User")
    Write-Host "Added $installDir to user PATH."
} else {
    Write-Host "$installDir is already in PATH."
}

Write-Host "Installed. Restart your terminal, then use 'ccc' in any project directory."
