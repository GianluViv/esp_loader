# Compila ESP Loader per Windows e raccoglie il bundle nella cartella release.
# Se Enigma Virtual Box e disponibile, crea anche un singolo exe portabile.

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$buildOutput = Join-Path $projectRoot "build\windows\x64\runner\Release"
$releaseDir = Join-Path $projectRoot "release"
$portableExe = Join-Path $projectRoot "release_portable\esp_loader.exe"
$packScript = Join-Path $projectRoot "scripts\pack_portable_exe.ps1"

Write-Host "Compilazione Windows Release..." -ForegroundColor Cyan
& flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows non riuscita (codice $LASTEXITCODE)."
}

$mainExe = Join-Path $buildOutput "esp_loader.exe"
if (-not (Test-Path -LiteralPath $mainExe -PathType Leaf)) {
    throw "Output della build non trovato: $mainExe"
}

if (Test-Path -LiteralPath $releaseDir) {
    Write-Host "Pulizia della cartella release esistente..." -ForegroundColor Cyan
    Remove-Item -LiteralPath $releaseDir -Recurse -Force
}
New-Item -ItemType Directory -Path $releaseDir | Out-Null

Write-Host "Copia del bundle in $releaseDir ..." -ForegroundColor Cyan
Copy-Item -Path (Join-Path $buildOutput "*") -Destination $releaseDir -Recurse -Force
Write-Host "Bundle Windows pronto: $releaseDir" -ForegroundColor Green

# Il bundle resta un risultato valido anche se Enigma Virtual Box non e installato.
& powershell -NoProfile -ExecutionPolicy Bypass -File $packScript `
    -ReleaseDir $releaseDir `
    -MainExeName "esp_loader.exe" `
    -OutputExe $portableExe

if ($LASTEXITCODE -eq 0) {
    Write-Host "Eseguibile portabile pronto: $portableExe" -ForegroundColor Green
}
else {
    Write-Warning "Packaging portabile non eseguito. Il bundle in $releaseDir resta utilizzabile."
}
