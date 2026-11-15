$ErrorActionPreference = 'Stop'
$projectRoot = Join-Path $PSScriptRoot '..'
$envFile = Join-Path $projectRoot '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    throw 'Missing .env. Run scripts/start-db.ps1 first.'
}

$loaded = @{}
foreach ($line in Get-Content -LiteralPath $envFile) {
    if ($line -match '^\s*(WATCHDENCHI_DATABASE_URL|WATCHDENCHI_HTTP_ADDR)=(.+)$') {
        $name = $Matches[1]
        if (-not (Test-Path -LiteralPath "Env:$name")) {
            $loaded[$name] = $true
            Set-Item -LiteralPath "Env:$name" -Value $Matches[2].Trim()
        }
    }
}
Push-Location -LiteralPath (Join-Path $projectRoot 'services/api')
try {
    go run ./cmd/api
    if ($LASTEXITCODE -ne 0) { throw 'Could not run the API.' }
}
finally {
    Pop-Location
    foreach ($name in $loaded.Keys) {
        Remove-Item -LiteralPath "Env:$name"
    }
}
