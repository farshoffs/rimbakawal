$ErrorActionPreference = 'Stop'

Write-Host 'Checking Flutter...'
flutter --version

if (Test-Path '.\patrol_nfc') {
    throw 'A .\patrol_nfc folder already exists. Rename/remove it first, or copy the starter files manually.'
}

Write-Host 'Creating Flutter mobile project...'
flutter create --platforms=android,ios patrol_nfc

Copy-Item -Path '.\lib' -Destination '.\patrol_nfc\lib' -Recurse -Force
Copy-Item -Path '.\pubspec.yaml' -Destination '.\patrol_nfc\pubspec.yaml' -Force

$manifestPath = '.\patrol_nfc\android\app\src\main\AndroidManifest.xml'
$manifest = Get-Content $manifestPath -Raw

if ($manifest -notmatch 'android.permission.NFC') {
    $manifest = $manifest -replace '<manifest xmlns:android="http://schemas.android.com/apk/res/android">', @'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.NFC" />
    <uses-feature android:name="android.hardware.nfc" android:required="false" />
'@
    Set-Content -Path $manifestPath -Value $manifest -Encoding UTF8
}

Push-Location '.\patrol_nfc'
try {
    flutter pub get
    Write-Host ''
    Write-Host 'Project ready.' -ForegroundColor Green
    Write-Host 'Connect an Android NFC phone with USB debugging enabled, then run:'
    Write-Host '  flutter devices'
    Write-Host '  flutter run'
    Write-Host ''
    Write-Host 'For mock mode instead:'
    Write-Host '  flutter run --dart-define=USE_MOCK_NFC=true'
}
finally {
    Pop-Location
}
