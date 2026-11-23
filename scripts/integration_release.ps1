# Pure package metadata helpers: importing this file never starts a service.
function Get-IntegrationRelease {
    param([Parameter(Mandatory)][string]$Root)
    $value = Get-Content -LiteralPath (Join-Path $Root 'integration-release.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (($value.schemaVersion -isnot [int] -and $value.schemaVersion -isnot [long]) -or
        $value.schemaVersion -ne 1 -or $value.version -isnot [string] -or
        $value.version -notmatch '^[1-9][0-9]{0,5}$' -or
        $value.status -notin @('candidate', 'released')) {
        throw 'Revise integration-release.json: identidade de versao invalida.'
    }
    return $value
}

function Get-IntegrationPackageName {
    param([Parameter(Mandatory)]$Release, [Parameter(Mandatory)][ValidateSet('complete', 'update', 'opener')][string]$Kind)
    switch ($Kind) {
        'complete' { return "integracao-edesk-completa-windows-v$($Release.version).zip" }
        'update' { return "atualizacao-integracao-completa-$($Release.version).zip" }
        'opener' { return "abertura-local-windows-v$($Release.version).zip" }
    }
}

function Test-IntegrationPackage {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Release,
          [Parameter(Mandatory)][ValidateSet('complete', 'update', 'opener')][string]$Kind)
    $expected = Get-IntegrationPackageName -Release $Release -Kind $Kind
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        [IO.Path]::GetFileName($Path) -cne $expected) {
        throw "Pacote ausente ou nome divergente: $expected"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $metadata = @($archive.Entries | Where-Object { $_.FullName -ceq 'integration-release.json' })
        if ($metadata.Count -ne 1) { throw "Identidade ausente ou duplicada no pacote: $expected" }
        $reader = New-Object IO.StreamReader($metadata[0].Open())
        try { $inside = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if ($inside.schemaVersion -ne 1 -or $inside.version -isnot [string] -or
            $inside.version -cne $Release.version -or $inside.status -cne $Release.status) {
            throw "Identidade divergente dentro do pacote: $expected"
        }
        if ($Kind -ne 'opener') {
            foreach ($required in @('local_edesk/zendesk_routes.py', 'local_edesk/zendesk_workflow.py',
                    'edesk_bot/edesk_adv.py', 'edesk_bot/edesk_ns_interno.py',
                    'scripts/start_full_integration.ps1', 'scripts/integration_release.ps1')) {
                if (-not $archive.GetEntry($required)) { throw "Modulo ausente no pacote $expected : $required" }
            }
        }
    } finally { $archive.Dispose() }
}
