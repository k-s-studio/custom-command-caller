param(
    [Parameter(Position=0)]
    [string]$Command,
    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

$configFileName = "cccrouter.json"
$installDir = "$env:USERPROFILE\.ccc"
$Repo = "k-s-studio/custom-command-caller"

# installs up to 7f65b23 kept the scripts in the PATH folder itself; the first upgrade from
# one of those runs its old upgrader, which refreshes the scripts in place, and the next
# 'ccc-router upgrade' moves them into lib\.
if ($PSScriptRoot -eq $installDir -and $Command -ne "upgrade") {
    Write-Host "Note: this install still uses the old layout. Run 'ccc-router upgrade' once more to finish moving it."
}

function Show-Usage {
    Write-Host "Usage: ccc-router <command>"
    Write-Host "       ccc-router init        create cccrouter.json in current directory"
    Write-Host "       ccc-router template    edit the shared template in Notepad"
    Write-Host "       ccc-router status      show install status and check for updates"
    Write-Host "       ccc-router upgrade     update the installed scripts from GitHub"
    Write-Host "       ccc-router uninstall   remove the commands (and the beautifier extension)"
    Write-Host "       ccc-router beauty <install|uninstall> --vscode   manage only the beautifier extension"
    Write-Host "       ccc-router --help      show this help"
    Write-Host ""
    Write-Host "Run 'ccc <command> [args]' to route a command through cccrouter.json."
    Write-Host "Already installed - run 'ccc-router upgrade' for the latest, or 'ccc-router status' to check."
}

switch ($Command) {

    { $_ -in @("--help", "-h", "help") } {
        Show-Usage
        exit 0
    }

    "init" {
        $configPath = Join-Path (Get-Location) $configFileName
        if (Test-Path $configPath) {
            Write-Host "cccrouter.json already exists."
            exit 1
        }
        # clone the template that 'ccc-router install' placed in the install dir
        # (sourced from components/cccrouter.json). install always precedes init.
        $templateSrc = Join-Path $installDir $configFileName
        if (-not (Test-Path $templateSrc)) {
            Write-Host "No cccrouter.json template found. Run 'ccc-router install' first."
            exit 1
        }
        Copy-Item $templateSrc $configPath -Force
        Write-Host "Created cccrouter.json"
        if (Test-Path (Join-Path (Get-Location) ".git")) {
            Write-Host "Tip: git detected. Use 'ccc hide' to exclude cccrouter.json from this repo."
        }
        exit 0
    }

    "template" {
        # open the shared template ('ccc-router init' copies it) in Notepad to edit
        $templatePath = Join-Path $installDir $configFileName
        if (-not (Test-Path $templatePath)) {
            Write-Host "No cccrouter.json template found. Run 'ccc-router install' first."
            exit 1
        }
        notepad $templatePath
        exit 0
    }

    "status" {
        & "$PSScriptRoot\status.ps1" @Rest
        exit $LASTEXITCODE
    }

    "install" {
        # 'install' is the repo-level bootstrap (repo ccc-router.bat -> install.ps1) and is
        # never shipped here. reaching it means ccc is already installed, so just say so.
        Write-Host 'ccc-router has been installed. For latest version, run `ccc-router upgrade` or use `ccc-router status` to check.'
        exit 0
    }

    "upgrade" {
        # run the LATEST upgrader from GitHub main, not the installed copy: how an install is
        # laid out, and how older layouts migrate, then ships with the upgrade itself. it runs
        # from a temp file, so it never overwrites the very file it is executing.
        $worker = Join-Path $env:TEMP ("ccc-upgrade-" + [guid]::NewGuid().ToString("N") + ".ps1")
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$Repo/main/scripts/upgrade.ps1" -OutFile $worker -Headers @{ 'User-Agent' = 'ccc-router' } -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "Failed to download the upgrader from GitHub: $($_.Exception.Message)"
            exit 1
        }
        try {
            & $worker @Rest
            $code = $LASTEXITCODE
        } finally {
            Remove-Item $worker -Force -ErrorAction SilentlyContinue
        }
        exit $code
    }

    "uninstall" {
        & "$PSScriptRoot\uninstall.ps1" @Rest
        exit $LASTEXITCODE
    }

    "beauty" {
        # manage ONLY the beautifier extension, leaving the ccc tool untouched:
        #   ccc-router beauty install   --vscode [--local]   install just the extension
        #   ccc-router beauty uninstall --vscode             remove just the extension
        $sub = if ($Rest.Count -ge 1) { $Rest[0] } else { "" }
        switch ($sub) {
            "install" {
                # $Rest is already 'install --vscode [--local]', forward it whole.
                # do NOT slice-and-resplat (e.g. @($Rest[1..])): a single sliced arg
                # gets exploded into characters when this runs via 'pwsh -File'.
                & "$PSScriptRoot\install-highlighter.ps1" @Rest
                exit $LASTEXITCODE
            }
            "uninstall" {
                & "$PSScriptRoot\uninstall.ps1" --beauty
                exit $LASTEXITCODE
            }
            default {
                Write-Host "Usage: ccc-router beauty <install|uninstall> --vscode [--local]"
                exit 1
            }
        }
    }

    default {
        Show-Usage
        if ($Command) { exit 1 }
        exit 0
    }
}
