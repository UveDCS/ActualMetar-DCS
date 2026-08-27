<#
.SYNOPSIS
    Builds the two OvGME-ready distribution zips (ES/EN) for ACTUAL METAR.

.DESCRIPTION
    Assembles, per language, a folder that mirrors the DCS World install
    tree (MissionEditor\modules\actual_metar\, bin\, bin-mt\) plus a
    version.txt and the manual-step instructions (OVGME_LEEME.txt /
    OVGME_README.txt), then zips it so the top-level folder name inside the
    zip matches the zip filename without extension — the naming rule OvGME
    requires. Used both by CI (.github/workflows/build.yml) and for local
    testing before a release.

.PARAMETER Version
    Version string written to version.txt inside each package.

.PARAMETER OutDir
    Where to write the two .zip files. Defaults to the repo root.

.EXAMPLE
    .\ovgme\build_ovgme_packages.ps1 -Version 0.2.1
#>
param(
    [string]$Version = "dev",
    [string]$OutDir = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = "Stop"
$repoRoot = Join-Path $PSScriptRoot ".."
$staging = Join-Path $PSScriptRoot "staging"

if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Build-Package {
    param([string]$Name, [string]$LuaSourceDir, [string]$ReadmeFile)

    $pkgRoot = Join-Path $staging $Name
    $modulesDir = Join-Path $pkgRoot "MissionEditor\modules\actual_metar"
    New-Item -ItemType Directory -Force -Path $modulesDir | Out-Null

    Copy-Item -Path (Join-Path $repoRoot "$LuaSourceDir\*.lua") -Destination $modulesDir -Force

    $libDst = Join-Path $modulesDir "lib"
    New-Item -ItemType Directory -Force -Path $libDst | Out-Null
    Copy-Item -Path (Join-Path $repoRoot "luasec_payload\lib\*") -Destination $libDst -Recurse -Force

    foreach ($binName in @("bin", "bin-mt")) {
        $binDst = Join-Path $pkgRoot $binName
        New-Item -ItemType Directory -Force -Path $binDst | Out-Null
        Copy-Item -Path (Join-Path $repoRoot "luasec_payload\bin\*") -Destination $binDst -Force
    }

    Set-Content -Path (Join-Path $pkgRoot "version.txt") -Value $Version -NoNewline
    Copy-Item -Path (Join-Path $PSScriptRoot $ReadmeFile) -Destination $pkgRoot -Force

    $zipPath = Join-Path $OutDir "$Name.zip"
    if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
    Compress-Archive -Path $pkgRoot -DestinationPath $zipPath
    Write-Host "Built: $zipPath" -ForegroundColor Green
}

Build-Package -Name "ActualMetar-ES-OvGME" -LuaSourceDir "lua\actual_metar" -ReadmeFile "OVGME_LEEME.txt"
Build-Package -Name "ActualMetar-EN-OvGME" -LuaSourceDir "lua_en\actual_metar" -ReadmeFile "OVGME_README.txt"

Remove-Item -Recurse -Force $staging
