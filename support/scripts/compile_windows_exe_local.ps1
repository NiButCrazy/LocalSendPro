# Builds a Windows installer with loose MSIX registration (no code signing).
# Installs per-user, so the Share menu entry is registered for the installing user without UAC.
# Usage: pwsh support/scripts/compile_windows_exe_local.ps1 [-Version 1.18.2-Pro-1.0.0]
param(
    [string]$Version = '1.18.2-Pro-1.0.0'
)

$ErrorActionPreference = 'Stop'

# Locates a Windows SDK tool through the installed KitsRoot10 (the SDK may live on any drive),
# falling back to the default location on C:.
function Find-WindowsSdkFile([string[]]$RelativePaths) {
    $roots = @()
    $kitsRoot = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue).KitsRoot10
    if ($kitsRoot) {
        $roots += $kitsRoot
    }
    $roots += 'C:\Program Files (x86)\Windows Kits\10\'

    foreach ($root in $roots) {
        foreach ($relativePath in $RelativePaths) {
            $match = Get-ChildItem (Join-Path $root $relativePath) -ErrorAction SilentlyContinue | Select-Object -Last 1
            if ($match) {
                return $match.FullName
            }
        }
    }
    throw "Windows SDK tool not found: $($RelativePaths -join ', ') (KitsRoot10: $kitsRoot)"
}

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$payload = Join-Path $env:TEMP 'localsend-inno'
$result = Join-Path $root 'app\build\windows\x64\installer'
$content = Join-Path $root 'support\build\msix\content'
$helper = Join-Path $root 'app\windows\localsend_msix_helper.msix'

# CMake installs this file next to the exe, so it must exist before `flutter build windows`.
if (-not (Test-Path $helper)) {
    $makepri = Find-WindowsSdkFile @('bin\10.*\x64\makepri.exe')
    $makeappx = Find-WindowsSdkFile @('bin\10.*\x64\makeappx.exe', 'App Certification Kit\makeappx.exe')
    & $makepri new /pr $content /cf (Join-Path $root 'support\build\msix\priconfig.xml') /mn (Join-Path $content 'AppxManifest.xml') /of (Join-Path $content 'resources.pri') /o
    & $makeappx pack /o /d $content /nv /p $helper
}

Push-Location (Join-Path $root 'app')
try {
    # MSVC compiles the Rust plugin with code page 936 by default; force UTF-8 sources.
    $env:CL = '-utf-8'
    fvm flutter build windows --release
} finally {
    Pop-Location
}

Remove-Item $payload, $result -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $payload, $result | Out-Null

Copy-Item (Join-Path $root 'app\build\windows\x64\runner\Release\*') $payload -Recurse
Copy-Item (Join-Path $root 'app\assets\packaging\logo.ico') $payload
Copy-Item (Join-Path $root 'support\build\windows\x64\*') $payload -Recurse

# Loose registration payload: manifest, logos and PRI must sit next to localsend_app.exe.
Copy-Item (Join-Path $content 'AppxManifest.xml') $payload
Copy-Item (Join-Path $content 'Images') $payload -Recurse
Copy-Item (Join-Path $content 'resources*.pri') $payload

$iscc = $null
$isccCommand = Get-Command iscc.exe -ErrorAction SilentlyContinue
if ($isccCommand) {
    $iscc = $isccCommand.Source
}
if (-not $iscc) {
    $candidates = @(
        'C:\Program Files\Inno Setup 7\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe',
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
    )
    $iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) {
    throw 'Inno Setup not found. Install it with: winget install --id JRSoftware.InnoSetup -e'
}

& $iscc /DSkipSignTool /DSkipMsixHelper /DLooseRegister "/DPayloadDir=$payload" "/DResultDir=$result" (Join-Path $root 'support\scripts\compile_windows_exe-inno.iss')
if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE"
}

$target = Join-Path $result "LocalSend-$Version-windows-x86-64.exe"
Remove-Item $target -Force -ErrorAction SilentlyContinue
Move-Item (Join-Path $result 'localsend.exe') $target -Force

Write-Output "Installer: $target"
