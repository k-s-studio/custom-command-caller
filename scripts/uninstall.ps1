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

# delete install directory. when 'ccc-router uninstall' runs from the installed
# copy, its own ccc-router.cmd is held open by cmd.exe, so an in-process delete
# fails; fall back to a detached cmd that removes the folder once we have exited.
if (Test-Path $installDir) {
    try {
        Remove-Item $installDir -Recurse -Force -ErrorAction Stop
        Write-Host "Deleted $installDir."
    } catch {
        Start-Process -WindowStyle Hidden cmd -ArgumentList "/c", "ping 127.0.0.1 -n 2 >nul & rmdir /s /q `"$installDir`""
        Write-Host "Scheduled removal of $installDir (completes after this terminal frees it)."
    }
}

Write-Host "Uninstalled."
