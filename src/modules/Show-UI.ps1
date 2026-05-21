<#
.SYNOPSIS
    Anzeige- und Eingabe-Helfer fuer die interaktive Konsolen-Oberflaeche.

.DESCRIPTION
    Hier sind alle "Look & Feel"-Funktionen gebuendelt:
      - Show-Banner       ASCII-Logo beim Start
      - Show-Help         Befehlsuebersicht
      - Read-Command      Shell-Prompt (z.B. "duplichecker$")
      - Read-Input        Frage an den User mit ">"-Prompt
      - Write-Section     Ueberschrift fuer einen Abschnitt
      - Write-Success / Write-ErrorMsg / Write-Info / Write-Warn
      - Show-DuplicateResults / Show-Samples
    Ziel: das Skript wirkt wie eine kleine Terminal-Anwendung.
#>

# Banner mit ASCII-Logo. Single-Quoted Here-String, damit keine
# Sonderzeichen interpretiert werden.
function Show-Banner {
    $banner = @'

================================================================
   ___                      ___
  / __| ___  _ _   __ _    |   \ _  _  _ __
  \__ \/ _ \| ' \ / _` |   | |) | || || '_ \
  |___/\___/|_||_|\__, |   |___/ \_,_|| .__/
                  |___/                |_|

       Song Duplikat-Checker  |  Modul 122  |  Leandro
================================================================
'@
    Write-Host $banner -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Tippe " -NoNewline -ForegroundColor Gray
    Write-Host "'help'" -ForegroundColor Yellow -NoNewline
    Write-Host " fuer alle Befehle, " -NoNewline -ForegroundColor Gray
    Write-Host "'quit'" -ForegroundColor Yellow -NoNewline
    Write-Host " zum Beenden." -ForegroundColor Gray
}

# Befehlsuebersicht (analog zur "help"-Ausgabe in echten Shells).
function Show-Help {
    Write-Host ""
    Write-Host "  Verfuegbare Befehle:" -ForegroundColor Yellow
    Write-Host ""
    $rows = @(
        @('csv',     'CSV-Datei auf Duplikate pruefen'),
        @('spotify', 'Spotify-Playlist auf Duplikate pruefen'),
        @('config',  'Spotify-Credentials einrichten / aendern'),
        @('web',     'Hinweis zum Starten des Webservers anzeigen'),
        @('samples', 'Verfuegbare Beispiel-CSVs auflisten'),
        @('clear',   'Bildschirm leeren'),
        @('help',    'Diese Hilfe anzeigen'),
        @('quit',    'Programm beenden')
    )
    foreach ($r in $rows) {
        Write-Host ("    {0,-9}" -f $r[0]) -ForegroundColor Cyan -NoNewline
        Write-Host $r[1] -ForegroundColor Gray
    }
    Write-Host ""
}

# Shell-Prompt im Stil "name$ ".
function Read-Command {
    param([string]$Prompt = "duplichecker")
    Write-Host ""
    Write-Host $Prompt -ForegroundColor Green -NoNewline
    Write-Host '$ ' -ForegroundColor Green -NoNewline
    return (Read-Host).Trim().ToLower()
}

# Eingabezeile mit gelber Frage und magenta Pfeil.
function Read-Input {
    param([string]$Question)
    Write-Host ""
    Write-Host "  $Question" -ForegroundColor Yellow
    Write-Host "  > " -ForegroundColor Magenta -NoNewline
    return (Read-Host).Trim()
}

# Abschnittsueberschrift mit Linie darunter.
function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "  >> $Text" -ForegroundColor Cyan
    Write-Host ("  " + ('-' * ($Text.Length + 5))) -ForegroundColor DarkGray
}

# Verschiedene Status-Zeilen mit eindeutigen Praefixen.
function Write-Success  { param([string]$Text) Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Text) Write-Host "  [ERR]  $Text" -ForegroundColor Red }
function Write-Info     { param([string]$Text) Write-Host "  [INFO] $Text" -ForegroundColor Gray }
function Write-Warn     { param([string]$Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow }

# Resultate hubsch ausgeben, egal ob aus CSV oder Spotify.
# Hilfsfunktion: einen String auf eine feste Breite bringen.
# Zu kurz -> mit Spaces auffuellen. Zu lang -> mit Ellipse ... abschneiden.
# Macht die Tabelle uebersichtlich (eine Zeile pro Song, kein Umbruch).
function Format-Cell {
    param([string]$Text, [int]$Width)
    if ([string]::IsNullOrEmpty($Text)) { return ' ' * $Width }
    # eventuelle Zeilenumbrueche im Text platt machen, sonst zerlegt sich die Tabelle.
    $clean = $Text -replace "`r", '' -replace "`n", ' '
    if ($clean.Length -le $Width) {
        return $clean.PadRight($Width)
    }
    # Wir kuerzen mit ".." (ASCII, 2 Zeichen) statt Unicode-Ellipse,
    # damit's auf jeder PowerShell-Konsole identisch aussieht.
    return $clean.Substring(0, $Width - 2) + '..'
}

function Show-DuplicateResults {
    param(
        [psobject[]]$Duplicates,
        [int]$TotalSongs
    )
    Write-Host ""
    if (-not $Duplicates -or $Duplicates.Count -eq 0) {
        Write-Success "$TotalSongs Songs geprueft - keine Duplikate gefunden."
        return
    }

    # Statistik fuer den Header
    $maxCount    = ($Duplicates | Measure-Object -Property Count -Maximum).Maximum
    $tripleCount = ($Duplicates | Where-Object { $_.Count -ge 3 }).Count

    Write-Host "  $TotalSongs Songs geprueft, $($Duplicates.Count) Duplikat-Gruppe(n) gefunden." -ForegroundColor Yellow
    if ($tripleCount -gt 0) {
        Write-Host "  Davon $tripleCount Song(s) mit 3+ Vorkommen (max. ${maxCount}x)." -ForegroundColor Magenta
    }
    Write-Host ""

    # Feste Spaltenbreiten - so wickelt sich nichts mehr um.
    # Total ~107 Zeichen, passt in die uebliche Terminalbreite (120).
    $wCount  = 4
    $wTitle  = 40
    $wArtist = 25
    $wAlbum  = 30
    $sep     = '  '

    # Header + ASCII-Trennlinie (kein Unicode-Box-Drawing - ist auf alten
    # Konsolen oft Mist und PowerShell parst [char]0x2500.ToString() falsch).
    $headerLine = ('#x'.PadLeft($wCount)) + $sep +
                  ('Title'.PadRight($wTitle)) + $sep +
                  ('Artist'.PadRight($wArtist)) + $sep +
                  ('Album'.PadRight($wAlbum))
    $rule = '-' * ($wCount + $wTitle + $wArtist + $wAlbum + ($sep.Length * 3))
    Write-Host "  $headerLine" -ForegroundColor DarkGray
    Write-Host "  $rule"       -ForegroundColor DarkGray

    # Datenzeilen mit Farbcode pro Count und Trenner zwischen Gruppen
    $prevCount = $null
    foreach ($d in $Duplicates) {
        # Leerzeile, wenn die Anzahl wechselt (z.B. von 3x auf 2x)
        if ($null -ne $prevCount -and $d.Count -ne $prevCount) {
            Write-Host ''
        }
        $prevCount = $d.Count

        $is3plus     = $d.Count -ge 3
        $countColor  = if ($is3plus) { 'Red' }   else { 'Yellow' }
        $titleColor  = if ($is3plus) { 'White' } else { 'Gray' }

        $countCell  = ("{0}x" -f $d.Count).PadLeft($wCount)
        $titleCell  = Format-Cell -Text $d.Title  -Width $wTitle
        $artistCell = Format-Cell -Text $d.Artist -Width $wArtist
        $albumCell  = Format-Cell -Text $d.Album  -Width $wAlbum

        Write-Host '  '         -NoNewline
        Write-Host $countCell   -NoNewline -ForegroundColor $countColor
        Write-Host $sep         -NoNewline
        Write-Host $titleCell   -NoNewline -ForegroundColor $titleColor
        Write-Host $sep         -NoNewline
        Write-Host $artistCell  -NoNewline -ForegroundColor Cyan
        Write-Host $sep         -NoNewline
        Write-Host $albumCell              -ForegroundColor DarkGray
    }
    Write-Host ''
}

# Spotify-Credentials interaktiv abfragen und in config.json speichern.
# Gibt $true zurueck, wenn erfolgreich gespeichert wurde, sonst $false.
function Save-SpotifyConfig {
    param([Parameter(Mandatory)][string]$ConfigPath)

    Write-Section "Spotify-Credentials einrichten"
    Write-Info "Anleitung: https://developer.spotify.com/dashboard"
    Write-Info "  -> 'Create app' -> Settings -> Client ID & Client Secret kopieren."

    $clientId = Read-Input -Question "Client ID:"
    if ([string]::IsNullOrWhiteSpace($clientId)) {
        Write-ErrorMsg "Client ID darf nicht leer sein. Abgebrochen."
        return $false
    }

    $clientSecret = Read-Input -Question "Client Secret:"
    if ([string]::IsNullOrWhiteSpace($clientSecret)) {
        Write-ErrorMsg "Client Secret darf nicht leer sein. Abgebrochen."
        return $false
    }

    # Hashtable -> JSON. -Depth 5 ist sicher, auch wenn wir nur 2 Ebenen haben.
    $config = @{
        Spotify = @{
            ClientId     = $clientId
            ClientSecret = $clientSecret
        }
    }
    $json = $config | ConvertTo-Json -Depth 5

    # Ohne BOM speichern, damit ConvertFrom-Json es spaeter sauber liest.
    [System.IO.File]::WriteAllText(
        $ConfigPath, $json, [System.Text.UTF8Encoding]::new($false)
    )

    Write-Success "Credentials gespeichert in: $ConfigPath"
    return $true
}

# Beispiel-CSVs anzeigen, damit der User einen Pfad zum Reinkopieren hat.
function Show-Samples {
    param([string]$SamplesDir)
    Write-Section "Beispiel-CSVs"
    if (-not (Test-Path -LiteralPath $SamplesDir)) {
        Write-ErrorMsg "Ordner nicht gefunden: $SamplesDir"
        return
    }
    Get-ChildItem -LiteralPath $SamplesDir -Filter '*.csv' | ForEach-Object {
        Write-Host "    $($_.FullName)" -ForegroundColor Cyan
    }
}
