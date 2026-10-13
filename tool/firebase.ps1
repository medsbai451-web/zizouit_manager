param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FirebaseArguments)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    $taskNodeDirectory = Get-ChildItem .tools -Directory -Filter 'node-*-win-x64' -ErrorAction SilentlyContinue | Select-Object -First 1
    $taskLocalCli = Join-Path (Get-Location) 'firebase_tests/node_modules/firebase-tools/lib/bin/firebase.js'
    if ($taskNodeDirectory -and (Test-Path -LiteralPath $taskLocalCli)) {
        & (Join-Path $taskNodeDirectory.FullName 'node.exe') $taskLocalCli @FirebaseArguments
    } else {
        & firebase @FirebaseArguments
    }
    if ($LASTEXITCODE -ne 0) { throw "Firebase command failed ($LASTEXITCODE)" }
} finally {
    Pop-Location
}
