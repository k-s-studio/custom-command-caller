$installDir = "$env:USERPROFILE\.ccc"

# remove from user PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -like "*$installDir*") {
    $newPath = ($userPath.Split(';') | Where-Object { $_ -ne $installDir }) -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "Removed $installDir from PATH."
} else {
    Write-Host "$installDir was not found in PATH."
}

# delete install directory
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
    Write-Host "Deleted $installDir."
}

Write-Host "Uninstalled."
