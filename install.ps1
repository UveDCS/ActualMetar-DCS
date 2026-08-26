<#
.SYNOPSIS
    Instala/actualiza/desinstala el mod REAL METAR para el Mission Editor de DCS World.

.DESCRIPTION
    Copia los ficheros Lua de este proyecto a <DCS install>\MissionEditor\modules\real_metar\
    y agrega (si no esta ya) un require('real_metar.init') al final de
    <DCS install>\MissionEditor\MissionEditor.lua, delimitado por marcadores propios
    (REAL-METAR-BEGIN/END). No toca ni depende de dcs-sms; ambos pueden convivir.

    Hay que volver a ejecutar este script cada vez que una actualizacion oficial de
    DCS World sobrescriba MissionEditor.lua (lo hace de vez en cuando). Relanzarlo es
    seguro: si el require ya esta, no lo duplica; los ficheros Lua se refrescan siempre.

.PARAMETER DcsPath
    Ruta de instalacion de DCS World. Si se omite, se autodetectan las rutas habituales.

.PARAMETER Uninstall
    Quita el bloque marcado de MissionEditor.lua y borra la carpeta de modulos.

.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -DcsPath "D:\Eagle Dynamics\DCS World"
.EXAMPLE
    .\install.ps1 -Uninstall
#>
param(
    [string]$DcsPath,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$BeginMarker = "-- REAL-METAR-BEGIN (no editar a mano; gestionado por install.ps1)"
$EndMarker   = "-- REAL-METAR-END"

function Find-DcsPath {
    if ($DcsPath) { return $DcsPath }

    # 1) Rutas estandar bajo Program Files, mas la ruta conocida de este equipo.
    $candidates = @(
        "$env:ProgramFiles\Eagle Dynamics\DCS World",
        "$env:ProgramFiles\Eagle Dynamics\DCS World OpenBeta",
        "${env:ProgramFiles(x86)}\Eagle Dynamics\DCS World",
        "${env:ProgramFiles(x86)}\Eagle Dynamics\DCS World OpenBeta",
        "F:\DCS World"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "MissionEditor\MissionEditor.lua")) { return $c }
    }

    # 2) Si dcs-sms ya esta instalado, reaprovecha la ruta que tiene cacheada
    #    (funciona con instalaciones en cualquier unidad, ej. F:\DCS World).
    $dcsSmsConfig = Join-Path $env:APPDATA "dcs-sms\config.toml"
    if (Test-Path $dcsSmsConfig) {
        $line = Select-String -Path $dcsSmsConfig -Pattern '^\s*dcs_install\s*=\s*"([^"]+)"' -ErrorAction SilentlyContinue
        if ($line) {
            $candidate = $line.Matches[0].Groups[1].Value -replace '/', '\'
            if (Test-Path (Join-Path $candidate "MissionEditor\MissionEditor.lua")) { return $candidate }
        }
    }

    # 3) Barrido rapido de "<unidad>:\DCS World" en las unidades fijas.
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $candidate = Join-Path $drive.Root "DCS World"
        if (Test-Path (Join-Path $candidate "MissionEditor\MissionEditor.lua")) { return $candidate }
    }

    return $null
}

function Find-SavedGamesPath {
    param([string]$Dcs)

    # 1) Reaprovecha el valor cacheado de dcs-sms si existe y sigue siendo valido.
    $dcsSmsConfig = Join-Path $env:APPDATA "dcs-sms\config.toml"
    if (Test-Path $dcsSmsConfig) {
        $line = Select-String -Path $dcsSmsConfig -Pattern '^\s*saved_games\s*=\s*"([^"]+)"' -ErrorAction SilentlyContinue
        if ($line) {
            $candidate = $line.Matches[0].Groups[1].Value -replace '\\\\', '\'
            if (Test-Path $candidate) { return $candidate }
        }
    }

    # 2) Adivina segun si la instalacion es OpenBeta.
    $isBeta = $Dcs -match 'openbeta'
    $order = if ($isBeta) { @("DCS.openbeta", "DCS") } else { @("DCS", "DCS.openbeta") }
    foreach ($name in $order) {
        $candidate = Join-Path $env:USERPROFILE "Saved Games\$name"
        if (Test-Path $candidate) { return $candidate }
    }
    return (Join-Path $env:USERPROFILE "Saved Games\$($order[0])")
}

function Install-LuaSec {
    param([string]$Dcs)

    $payload = Join-Path $PSScriptRoot "luasec_payload"
    $libSrc = Join-Path $payload "lib"
    $binSrc = Join-Path $payload "bin"
    if (-not (Test-Path $libSrc) -or -not (Test-Path $binSrc)) {
        Write-Host "AVISO: no se encuentra el paquete LuaSec en luasec_payload\; se omite." -ForegroundColor Yellow
        return
    }

    $savedGames = Find-SavedGamesPath -Dcs $Dcs
    $libDst = Join-Path $savedGames "real-metar\lib"
    New-Item -ItemType Directory -Force -Path $libDst | Out-Null
    Copy-Item -Path (Join-Path $libSrc "*") -Destination $libDst -Recurse -Force
    Write-Host "LuaSec (HTTPS) instalado en: $libDst" -ForegroundColor Green

    $binDirs = @((Join-Path $Dcs "bin"), (Join-Path $Dcs "bin-mt")) | Where-Object { Test-Path $_ }
    foreach ($bd in $binDirs) {
        Copy-Item -Path (Join-Path $binSrc "*") -Destination $bd -Force
    }
    if ($binDirs) {
        Write-Host ("Dependencias de OpenSSL copiadas en: " + ($binDirs -join ", ")) -ForegroundColor Green
    } else {
        Write-Host "AVISO: no se encontraron las carpetas bin\/bin-mt\ de DCS; el fetch por HTTPS puede no funcionar." -ForegroundColor Yellow
    }
}

$dcs = Find-DcsPath
if (-not $dcs) {
    Write-Host "No se encontro DCS World automaticamente." -ForegroundColor Yellow
    Write-Host "Vuelve a ejecutar con -DcsPath, por ejemplo:"
    Write-Host '  .\install.ps1 -DcsPath "D:\Eagle Dynamics\DCS World"'
    exit 1
}

$meLua = Join-Path $dcs "MissionEditor\MissionEditor.lua"
$modulesDir = Join-Path $dcs "MissionEditor\modules\real_metar"
$sourceDir = Join-Path $PSScriptRoot "lua\real_metar"

Write-Host "DCS World: $dcs"

if ($Uninstall) {
    if (Test-Path $meLua) {
        $content = Get-Content -Raw -Path $meLua
        $pattern = [regex]::Escape($BeginMarker) + "(.|\n|\r)*?" + [regex]::Escape($EndMarker)
        if ($content -match $pattern) {
            $newContent = [regex]::Replace($content, $pattern, "")
            Set-Content -Path $meLua -Value $newContent -NoNewline
            Write-Host "Bloque REAL-METAR quitado de MissionEditor.lua." -ForegroundColor Green
        } else {
            Write-Host "MissionEditor.lua no tenia el bloque REAL-METAR (nada que quitar)."
        }
    }
    if (Test-Path $modulesDir) {
        Remove-Item -Recurse -Force $modulesDir
        Write-Host "Carpeta de modulos borrada: $modulesDir" -ForegroundColor Green
    }
    Write-Host "Desinstalado. Reinicia DCS World por completo."
    exit 0
}

if (-not (Test-Path $sourceDir)) {
    Write-Host "No se encuentra la carpeta de origen: $sourceDir" -ForegroundColor Red
    exit 1
}

# 1) Copiar/actualizar los ficheros Lua (siempre, sea instalacion nueva o refresco)
New-Item -ItemType Directory -Force -Path $modulesDir | Out-Null
Copy-Item -Path (Join-Path $sourceDir "*.lua") -Destination $modulesDir -Force
Write-Host "Ficheros Lua copiados a: $modulesDir" -ForegroundColor Green

# 2) Parchear MissionEditor.lua (solo si el marcador no esta ya presente)
if (-not (Test-Path $meLua)) {
    Write-Host "No se encuentra MissionEditor.lua en $meLua" -ForegroundColor Red
    exit 1
}
$content = Get-Content -Raw -Path $meLua
if ($content -notmatch [regex]::Escape($BeginMarker)) {
    $backup = "$meLua.real-metar.bak"
    if (-not (Test-Path $backup)) {
        Copy-Item -Path $meLua -Destination $backup
        Write-Host "Backup creado: $backup"
    }
    $block = "`r`n$BeginMarker`r`nrequire('real_metar.init')`r`n$EndMarker`r`n"
    Add-Content -Path $meLua -Value $block -NoNewline
    Write-Host "MissionEditor.lua parcheado (require agregado)." -ForegroundColor Green
} else {
    Write-Host "MissionEditor.lua ya tenia el require de REAL METAR (no se toca)."
}

Write-Host ""
Install-LuaSec -Dcs $dcs

Write-Host ""
Write-Host "Instalacion completa." -ForegroundColor Green
Write-Host "Reinicia DCS World POR COMPLETO (no solo el Mission Editor) y abre el editor:"
Write-Host "deberia aparecer REAL METAR en la barra de menu superior."
Write-Host ""
Write-Host "Nota: se han copiado unos ficheros de soporte (LuaSec/OpenSSL) en tu instalacion"
Write-Host "de DCS ('bin\' y 'bin-mt\') para que el fetch por HTTPS funcione sin pasos extra."
Write-Host "Vienen de un build de terceros (proyecto dcs-sms, licencias MIT/Apache-2.0), ver"
Write-Host "luasec_payload\ATTRIBUTION.txt. Algunos servidores multijugador con Integrity Check"
Write-Host "estricto podrian, en teoria, marcarlos; no afecta al Mission Editor ni a misiones"
Write-Host "locales/sin conexion."
