<# : batch part (PowerShell reads this block as a comment)
@echo off
setlocal
rem Downloads the latest Dhoxar Modules release from GitHub and installs it
rem into the WoW AddOns folder. Usage:
rem   Install-DhoxarModules.bat                 (default WoW Forever folder)
rem   Install-DhoxarModules.bat "D:\Games\World of Warcraft\_forever_"
set "DHX_ADDONS=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression (Get-Content -LiteralPath '%~f0' -Raw)"
set "DHX_CODE=%errorlevel%"
echo.
pause
exit /b %DHX_CODE%
#>

# PowerShell part.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads very slow on PowerShell 5

$Repo = 'roarena/DhoxarModules'
$AddonName = 'DhoxarModules'
$DefaultAddOns = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'

function Read-TocVersion([string]$toc) {
    if (-not (Test-Path -LiteralPath $toc)) { return $null }
    $match = Select-String -LiteralPath $toc -Pattern '^##\s*Version:\s*(.+)$' | Select-Object -First 1
    if ($match) { return $match.Matches[0].Groups[1].Value.Trim() }
    return $null
}

# Accepts the AddOns folder itself, or a WoW folder that contains Interface\AddOns.
function Resolve-AddOns([string]$path) {
    if (-not $path) { return $null }
    $path = $path.Trim().Trim('"').TrimEnd('\')
    if (Test-Path -LiteralPath (Join-Path $path 'Interface\AddOns') -PathType Container) {
        return (Join-Path $path 'Interface\AddOns')
    }
    if (Test-Path -LiteralPath $path -PathType Container) { return $path }
    return $null
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $requested = if ($env:DHX_ADDONS) { $env:DHX_ADDONS } else { $DefaultAddOns }
    $addOns = Resolve-AddOns $requested
    while (-not $addOns) {
        Write-Host "AddOns folder not found: $requested"
        $requested = Read-Host 'Paste your WoW folder or its Interface\AddOns folder (empty to cancel)'
        if (-not $requested) { throw 'Cancelled.' }
        $addOns = Resolve-AddOns $requested
    }

    Write-Host "Checking the latest release of $Repo..."
    $headers = @{ 'User-Agent' = 'DhoxarModules-installer'; 'Accept' = 'application/vnd.github+json' }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -like "$AddonName*.zip" } | Select-Object -First 1
    if (-not $asset) { throw "Release $($release.tag_name) has no $AddonName zip attached." }

    $target = Join-Path $addOns $AddonName
    $installed = Read-TocVersion (Join-Path $target "$AddonName.toc")
    $latest = $release.tag_name -replace '^v', ''
    Write-Host ("Latest release: {0}   Installed: {1}" -f $release.tag_name, $(if ($installed) { $installed } else { 'none' }))
    if ($installed -and $installed -eq $latest) {
        $answer = Read-Host 'Already up to date. Reinstall anyway? (y/N)'
        if ($answer -notmatch '^[yY]') { Write-Host 'Nothing to do.'; exit 0 }
    }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ("DhoxarModules-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        $zip = Join-Path $temp $asset.name
        Write-Host "Downloading $($asset.name)..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers $headers -UseBasicParsing
        $extract = Join-Path $temp 'extract'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract
        $source = Join-Path $extract $AddonName
        if (-not (Test-Path -LiteralPath (Join-Path $source "$AddonName.toc"))) {
            throw "The download does not contain $AddonName\$AddonName.toc."
        }

        # Copy next to the old folder first, then swap, so a failed copy
        # never leaves you without the addon.
        $staged = "$target.new"
        $old = "$target.old"
        foreach ($p in @($staged, $old)) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
        }
        Copy-Item -LiteralPath $source -Destination $staged -Recurse
        if (Test-Path -LiteralPath $target) { Rename-Item -LiteralPath $target -NewName "$AddonName.old" }
        Rename-Item -LiteralPath $staged -NewName $AddonName
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force }
    }
    finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Installed $AddonName $($release.tag_name) to $target" -ForegroundColor Green
    Write-Host 'Your settings (WTF folder) are kept.'
    if (Get-Process -Name 'Wow' -ErrorAction SilentlyContinue) {
        Write-Host 'WoW is running: log out and back in to load the new version.' -ForegroundColor Yellow
    }
    exit 0
}
catch {
    Write-Host "Install failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
