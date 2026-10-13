param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & $Flutter build web --no-pub --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
    $flutterCommand = Get-Command $Flutter -ErrorAction Stop
    $dartPath = Join-Path (Split-Path $flutterCommand.Source) 'cache/dart-sdk/bin/dart.exe'
    if (Test-Path -LiteralPath $dartPath) {
        & $dartPath tool/prepare_offline.dart
    } else {
        & dart tool/prepare_offline.dart
    }
    if ($LASTEXITCODE -ne 0) { throw 'Offline asset preparation failed' }
} finally {
    Pop-Location
}
