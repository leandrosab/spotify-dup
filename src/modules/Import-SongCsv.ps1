<#
.SYNOPSIS
    Liest eine CSV-Datei mit Songs ein und prüft, ob sie korrekt formatiert ist.

.DESCRIPTION
    Diese Funktion ist die "Türsteher"-Funktion des Projekts:
    Bevor das Hauptskript Duplikate sucht, stellen wir hier sicher, dass:
      1. die Datei überhaupt existiert
      2. die Datei eine .csv-Endung hat
      3. die CSV nicht leer ist
      4. alle Pflichtspalten (z.B. Title, Artist) vorhanden sind
    Falls etwas nicht stimmt, wirft die Funktion eine klare Fehlermeldung,
    sodass der Benutzer genau weiss, was zu tun ist.

.PARAMETER Path
    Pfad zur CSV-Datei, die eingelesen werden soll.

.PARAMETER RequiredColumns
    Liste der Spalten, die in der CSV vorhanden sein müssen.
    Standard: Title und Artist.

.EXAMPLE
    Import-SongCsv -Path "data/samples/songs-clean.csv"
#>
function Import-SongCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$RequiredColumns = @('Title', 'Artist')
    )

    # 1. Existiert die Datei?
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Datei nicht gefunden: $Path"
    }

    # 2. Ist es überhaupt eine CSV-Datei?
    if ([System.IO.Path]::GetExtension($Path).ToLower() -ne '.csv') {
        throw "Datei ist keine CSV-Datei (.csv erwartet): $Path"
    }

    # 3. CSV einlesen. @(...) sorgt dafür, dass das Ergebnis IMMER ein Array ist,
    #    auch wenn nur eine einzige Zeile drin steht.
    try {
        $songs = @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    }
    catch {
        throw "CSV konnte nicht gelesen werden: $($_.Exception.Message)"
    }

    # 4. Ist die Datei leer (nur Header oder gar nichts)?
    if ($songs.Count -eq 0) {
        throw "CSV-Datei enthält keine Datenzeilen."
    }

    # 5. Sind alle Pflichtspalten da?
    #    PSObject.Properties.Name liefert die Spaltennamen der ersten Zeile.
    $actualColumns = $songs[0].PSObject.Properties.Name
    $missing = $RequiredColumns | Where-Object { $_ -notin $actualColumns }
    if ($missing) {
        throw ("Fehlende Pflichtspalten: {0}. Vorhandene Spalten: {1}" -f `
            ($missing -join ', '), ($actualColumns -join ', '))
    }

    # Alles gut: gib die Songs zurück.
    return $songs
}
