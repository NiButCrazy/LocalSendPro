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

$makepri = Find-WindowsSdkFile @('bin\10.*\x64\makepri.exe')
& $makepri new /pr support\build\msix\content /cf support\build\msix\priconfig.xml /mn support\build\msix\content\AppxManifest.xml /of support\build\msix\content\resources.pri /o
$makeappx = Find-WindowsSdkFile @('bin\10.*\x64\makeappx.exe', 'App Certification Kit\makeappx.exe')
& $makeappx pack /o /d support\build\msix\content /nv /p app\windows\localsend_msix_helper.msix

cd app

fvm flutter clean
fvm flutter pub get
fvm flutter build windows

Remove-Item "D:\inno" -Force  -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "D:\inno"
Copy-Item -Path "build\windows\x64\runner\Release\*" -Destination "D:\inno" -Recurse
Copy-Item -Path "assets\packaging\logo.ico" -Destination "D:\inno"

cd ..

Copy-Item -Path "support\build\windows\x64\*" -Destination "D:\inno" -Recurse
Remove-Item "D:\inno-result" -Force  -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "D:\inno-result"
iscc .\support\scripts\compile_windows_exe-inno.iss

Write-Output 'Generated Windows exe installer!'
