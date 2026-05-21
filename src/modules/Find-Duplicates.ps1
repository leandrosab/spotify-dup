<#
.SYNOPSIS
    Sucht doppelte Songs in einer Liste.

.DESCRIPTION
    Kernlogik des Projekts. Ablauf:
      1. Pro Song wird ein "Vergleichsschlüssel" gebaut.
         Standard: Titel + Künstler. Mit -IncludeAlbum: Titel + Künstler + Album.
      2. Der Schlüssel wird normalisiert (klein, ohne Leerzeichen am Rand),
         damit "Imagine" und " imagine " als gleicher Song erkannt werden.
      3. Songs werden nach Schlüssel gruppiert. Gruppen mit mehr als
         einem Eintrag = Duplikate.

.PARAMETER Songs
    Liste der Song-Objekte (z.B. aus Import-SongCsv).

.PARAMETER IncludeAlbum
    Wenn gesetzt, wird auch das Album in den Vergleich einbezogen.

.EXAMPLE
    $songs = Import-SongCsv -Path "songs.csv"
    Find-Duplicates -Songs $songs
#>
function Find-Duplicates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject[]]$Songs,

        [switch]$IncludeAlbum
    )

    # Kleine Hilfsfunktion: macht aus einem String einen sauberen Vergleichswert.
    # null/leer -> '', sonst getrimmt und kleingeschrieben.
    function Get-NormalizedString {
        param([string]$Value)
        if ([string]::IsNullOrEmpty($Value)) { return '' }
        return $Value.Trim().ToLower()
    }

    # Schritt 1+2: Schlüssel pro Song berechnen.
    # Wir uebernehmen optional auch Uri+Position, falls die Daten von
    # der Spotify-API kommen - das brauchen wir spaeter zum Loeschen.
    $keyed = foreach ($song in $Songs) {
        $title  = Get-NormalizedString $song.Title
        $artist = Get-NormalizedString $song.Artist

        # Album ist optional - prüfen, ob die Spalte überhaupt existiert.
        $album = ''
        if ($song.PSObject.Properties['Album']) {
            $album = Get-NormalizedString $song.Album
        }

        # Schlüssel mit "|" als Trenner. Album wird nur einbezogen,
        # wenn der User das per Switch verlangt hat.
        $key = if ($IncludeAlbum) { "$title|$artist|$album" } else { "$title|$artist" }

        # Hashtable bauen und nur Spotify-spezifische Felder dranhaengen,
        # wenn sie tatsaechlich existieren (CSV hat keine Uri/Position).
        $obj = [ordered]@{
            Key    = $key
            Title  = $song.Title
            Artist = $song.Artist
            Album  = if ($song.PSObject.Properties['Album']) { $song.Album } else { '' }
        }
        if ($song.PSObject.Properties['Uri'])      { $obj['Uri']      = $song.Uri }
        if ($song.PSObject.Properties['Position']) { $obj['Position'] = $song.Position }
        [pscustomobject]$obj
    }

    # Schritt 3: Gruppieren und nur Gruppen mit mehr als einem Treffer behalten.
    $groups = $keyed | Group-Object -Property Key | Where-Object { $_.Count -gt 1 }

    # Hübsches Ergebnis-Objekt pro Duplikat-Gruppe zurückgeben.
    $result = foreach ($g in $groups) {
        [pscustomobject]@{
            Title      = $g.Group[0].Title
            Artist     = $g.Group[0].Artist
            Album      = $g.Group[0].Album
            Count      = $g.Count
            Duplicates = $g.Group   # alle Originale dieser Gruppe (für Detailausgabe)
        }
    }

    # Nach Anzahl absteigend sortieren - so stehen 3x-, 4x-Duplikate immer oben.
    # @() garantiert: immer ein Array zurueck, nie $null.
    return @($result | Sort-Object -Property Count -Descending)
}
