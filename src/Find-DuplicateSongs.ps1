<#
.SYNOPSIS
    Hauptskript: erkennt doppelte Songs in einer CSV-Datei.

.DESCRIPTION
    Dies ist der Einstiegspunkt für die Konsolen-Version des Tools.
    Ablauf:
      1. CSV einlesen und validieren (Import-SongCsv)
      2. Duplikate suchen (Find-Duplicates)
      3. Ergebnis in der Konsole anzeigen
      4. Ergebnis als CSV + JSON exportieren (Export-Results)

.PARAMETER Path
    Pfad zur CSV-Datei, die geprüft werden soll.

.PARAMETER IncludeAlbum
    Wenn gesetzt, werden Songs nur dann als Duplikat erkannt, wenn auch
    das Album übereinstimmt. Sonst reicht Titel + Künstler.

.PARAMETER OutputDir
    Ordner, in den die Resultate exportiert werden.
    Standard: ../data/results relativ zum Skript.

.EXAMPLE
    .\Find-DuplicateSongs.ps1 -Path ..\data\samples\songs-with-duplicates.csv

.EXAMPLE
    .\Find-DuplicateSongs.ps1 -Path .\meine-liste.csv -IncludeAlbum
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$IncludeAlbum,

    [string]$OutputDir = (Join-Path $PSScriptRoot '..\data\results')
)

# Module per "Dot-Sourcing" einbinden.
# Die Funktionen aus den .ps1-Dateien werden dadurch hier verfügbar.
. (Join-Path $PSScriptRoot 'modules\Import-SongCsv.ps1')
. (Join-Path $PSScriptRoot 'modules\Find-Duplicates.ps1')
. (Join-Path $PSScriptRoot 'modules\Export-Results.ps1')

try {
    # 1. Einlesen + Validierung
    Write-Host "Lese CSV-Datei: $Path" -ForegroundColor Cyan
    $songs = Import-SongCsv -Path $Path -RequiredColumns @('Title', 'Artist')
    Write-Host "  $($songs.Count) Songs eingelesen." -ForegroundColor Green

    # 2. Duplikate suchen
    $modus = if ($IncludeAlbum) { 'Titel + Künstler + Album' } else { 'Titel + Künstler' }
    Write-Host "Suche Duplikate (Modus: $modus)..." -ForegroundColor Cyan
    $duplicates = Find-Duplicates -Songs $songs -IncludeAlbum:$IncludeAlbum

    # 3. Ausgabe in Konsole
    if ($duplicates.Count -eq 0) {
        Write-Host "Keine Duplikate gefunden." -ForegroundColor Green
        exit 0
    }

    Write-Host ""
    Write-Host "$($duplicates.Count) Duplikat-Gruppe(n) gefunden:" -ForegroundColor Yellow
    $duplicates | Format-Table Title, Artist, Album, Count -AutoSize

    # 4. Export in Datei
    $files = Export-Results -Duplicates $duplicates -OutputDir $OutputDir
    Write-Host "Resultate exportiert:" -ForegroundColor Cyan
    Write-Host "  CSV:  $($files.CsvPath)"
    Write-Host "  JSON: $($files.JsonPath)"

    exit 0
}
catch {
    # Eine einzige zentrale Fehlerausgabe - egal was schiefging.
    Write-Host ""
    Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
