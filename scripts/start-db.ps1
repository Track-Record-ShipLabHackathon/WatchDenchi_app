$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath (Join-Path $PSScriptRoot '..')
try {
    if (-not (Test-Path -LiteralPath .env)) {
        Copy-Item -LiteralPath .env.example -Destination .env
    }

    docker compose up -d --wait db
    if ($LASTEXITCODE -ne 0) { throw 'Could not start PostgreSQL.' }

    foreach ($migration in Get-ChildItem -LiteralPath db/migrations -Filter *.sql | Sort-Object Name) {
        Get-Content -Raw -LiteralPath $migration.FullName |
            docker compose exec -T db psql -X -v ON_ERROR_STOP=1 -U watchdenchi -d watchdenchi
        if ($LASTEXITCODE -ne 0) { throw "Migration failed: $($migration.Name)" }
    }
}
finally {
    Pop-Location
}
