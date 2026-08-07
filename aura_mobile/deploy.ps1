# AURA deploy script
#
# Two modes:
#   .\deploy.ps1              -> fast DEBUG build to your own connected phone
#                                (reinstalls over the app, keeps models/data)
#   .\deploy.ps1 -Release     -> signed universal RELEASE APK for sharing
#                                (one file that installs on all ARM phones,
#                                 copied to your Desktop as AURA.apk)
#
# Run from the aura_mobile folder.

param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"

if ($Release) {
    Write-Host "==> Building signed UNIVERSAL release APK (arm64 + armeabi-v7a)..." -ForegroundColor Cyan
    flutter build apk --release

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed." -ForegroundColor Red
        exit 1
    }

    $src = "build\app\outputs\flutter-apk\app-release.apk"
    $dest = Join-Path ([Environment]::GetFolderPath("Desktop")) "AURA.apk"
    Copy-Item $src $dest -Force
    $sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)

    Write-Host ""
    Write-Host "==> Done. Shareable APK on your Desktop:" -ForegroundColor Green
    Write-Host "    $dest  ($sizeMB MB)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Send THIS file (not the x86_64 one)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If a friend gets 'App not installed' (the icon shows but it won't install):" -ForegroundColor Yellow
    Write-Host "  1. Uninstall any older AURA / aura_mobile already on their phone" -ForegroundColor Gray
    Write-Host "     (an older copy signed with a different key blocks the new one)." -ForegroundColor Gray
    Write-Host "  2. Allow install from their file manager / WhatsApp:" -ForegroundColor Gray
    Write-Host "     Settings > Apps > Special access > Install unknown apps." -ForegroundColor Gray
    Write-Host "  3. If 'Blocked by Play Protect' appears: tap 'Install anyway'," -ForegroundColor Gray
    Write-Host "     or temporarily turn off Play Protect scanning in the Play Store." -ForegroundColor Gray
    Write-Host "  4. Make sure they have enough free storage (~300 MB)." -ForegroundColor Gray
    exit 0
}

Write-Host "==> Building debug APK (arm64)..." -ForegroundColor Cyan
flutter build apk --debug --target-platform android-arm64

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit 1
}

Write-Host "==> Reinstalling (keeping app data + models)..." -ForegroundColor Cyan
& $adb install -r "build\app\outputs\flutter-apk\app-debug.apk"

if ($LASTEXITCODE -eq 0) {
    Write-Host "==> Done! Models preserved. Launching app..." -ForegroundColor Green
    & $adb shell monkey -p com.aura.mobile.aura_mobile -c android.intent.category.LAUNCHER 1 | Out-Null
} else {
    Write-Host "Install failed. If signatures conflict, run once: adb uninstall com.aura.mobile.aura_mobile" -ForegroundColor Red
}
