<#
.SYNOPSIS
    Exportiert die gefundenen Duplikate in CSV- und JSON-Dateien.

.DESCRIPTION
    Schreibt zwei Dateien in den Ausgabe-Ordner, jeweils mit Zeitstempel:
      - duplicates_yyyyMMdd_HHmmss.csv  -> einfache Tabelle
      - duplicates_yyyyMMdd_HHmmss.json -> komplette Daten inkl. aller Duplikate
    Der Ordner wird automatisch angelegt, falls er noch nicht existiert.

.PARAMETER Duplicates
    Die Duplikat-Gruppen aus Find-Duplicates.

.PARAMETER OutputDir
    Zielordner für die Export-Dateien.

.EXAMPLE
    Export-Results -Duplicates $dups -OutputDir "data/results"
#>
function Export-Results {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject[]]$Duplicates,

        [Parameter(Mandatory)]
        [string]$OutputDir
    )

    # Zielordner anlegen, falls noch nicht vorhanden.
    if (-not (Test-Path -LiteralPath $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Zeitstempel im Dateinamen, damit alte Exporte nicht überschrieben werden.
    $stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csvPath  = Join-Path $OutputDir "duplicates_$stamp.csv"
    $jsonPath = Join-Path $OutputDir "duplicates_$stamp.json"

    # CSV: nur die wichtigsten Felder, eine Zeile pro Duplikat-Gruppe.
    $flat = $Duplicates | Select-Object Title, Artist, Album, Count
    $flat | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    # JSON: kompletter Datensatz inkl. der einzelnen doppelten Einträge.
    $Duplicates |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $jsonPath -Encoding UTF8

    # Pfade zurückgeben, damit das Hauptskript sie anzeigen kann.
    return [pscustomobject]@{
        CsvPath  = $csvPath
        JsonPath = $jsonPath
    }
}
