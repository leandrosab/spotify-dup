# Projekt-Dokumentation
## Song-Duplikat-Checker — Modul 122

> Diese Dokumentation beschreibt das Projekt aus **technischer und konzeptioneller Sicht** — also Architektur, Entscheidungen, eingesetzte Technologien und Herausforderungen. Für eine Anleitung zur Bedienung siehe `README.md` im Projektstamm.

---

## 1. Einleitung

Musik-Sammlungen wachsen oft über Jahre — und mit ihnen die Wahrscheinlichkeit, dass derselbe Song mehrfach in einer Playlist landet (manuell oder durch importierte Listen). Das manuelle Aufspüren ist mühsam und fehleranfällig. Der **Song-Duplikat-Checker** automatisiert diesen Vorgang: er liest eine Songliste, normalisiert Titel und Künstler, gruppiert identische Einträge und stellt das Ergebnis übersichtlich dar.

Das Projekt wurde im Rahmen des Berufsbildungs-**Moduls 122 (Automatisieren mit Skriptsprachen)** umgesetzt. Der Kern ist daher bewusst eine **PowerShell-Anwendung**. Eine Web-Oberfläche existiert als optionale Zusatzschicht — wird aber ebenfalls vollständig aus PowerShell heraus ausgeliefert (`System.Net.HttpListener`), um den Modulfokus zu wahren.

## 2. Zielsetzung

| Ziel | Umsetzung |
|---|---|
| Duplikate aus einer CSV-Datei finden | `Import-SongCsv` + `Find-Duplicates` |
| Duplikate in einer eigenen Spotify-Playlist finden | OAuth-Login + `Get-PlaylistTracksUser` |
| Duplikate in einer öffentlichen Spotify-Playlist finden | Client-Credentials + `Get-SpotifyTracks` |
| Ergebnis in Konsole anzeigen | `Show-DuplicateResults` |
| Ergebnis exportieren | `Export-Results` (CSV + JSON) |
| Bedienung durch Konsolen-Shell **oder** Web-UI | `Start-DuplicateChecker.ps1` / `Start-WebServer.ps1` |
| Robuste Fehlerbehandlung | Try/Catch + klare Meldungen, strikte Eingabe-Validierung |

## 3. Architektur-Überblick

Die Anwendung ist in **vier Schichten** aufgebaut:

| Schicht | Komponente | Verantwortlichkeit |
|---|---|---|
| **Präsentation (CLI)** | `Start-DuplicateChecker.ps1` | Interaktive Shell, Banner, Menü, Eingabe-Validierung |
| **Präsentation (Web)** | `Start-WebServer.ps1` + `web/*` | HTTP-Server + statische HTML/CSS/JS-Auslieferung + JSON-API |
| **Logik / Module** | `modules/*.ps1` | Datenimport, Duplikat-Erkennung, Export, Spotify-API |
| **Datenquellen** | CSV-Dateien, Spotify Web API | externe Daten |

Beide Präsentations-Schichten greifen auf **dieselben Logik-Module** zu. Die Trennung ist konsequent: kein Logik-Code in den Entry-Points, keine UI-Strings in den Modulen.

## 4. Modul-Struktur

```
M122-Projekt/
├── README.md                           Benutzerdokumentation (How-To)
├── anhang/
│   ├── dokumentation.md                Diese Datei
│   └── flowchart.md                    Detaillierte Ablauf-Diagramme
├── src/
│   ├── Start-DuplicateChecker.ps1      Konsolen-Shell (Entry-Point)
│   ├── Find-DuplicateSongs.ps1         Parameter-basierter Entry-Point
│   ├── Start-WebServer.ps1             HTTP-Server für die Web-UI
│   ├── config.example.json             Vorlage für Spotify-Credentials
│   ├── config.json                     Persönliche Credentials (nicht teilen)
│   ├── modules/
│   │   ├── Import-SongCsv.ps1          CSV einlesen + Spaltenvalidierung
│   │   ├── Find-Duplicates.ps1         Kern-Algorithmus: Gruppierung + Zählung
│   │   ├── Export-Results.ps1          CSV-/JSON-Export mit Zeitstempel
│   │   ├── Get-SpotifyTracks.ps1       Spotify Client Credentials (public)
│   │   ├── Connect-Spotify.ps1         OAuth Authorization Code Flow (eigene)
│   │   └── Show-UI.ps1                 Banner, Help, Prompts, Tabellen-Render
│   └── web/
│       ├── index.html                  Web-Oberfläche (Terminal-Look)
│       ├── style.css                   Dark-Theme + Responsives Layout
│       └── app.js                      UX- und Terminal-Modus im Browser
└── data/
    ├── samples/                        Beispiel-CSVs
    └── results/                        Exportierte Ergebnisse (Laufzeit)
```

## 5. Technologie-Stack

| Technologie | Rolle | Begründung |
|---|---|---|
| **PowerShell 5.1+** | Kern-Laufzeit | Modul-Anforderung; läuft out-of-the-box auf Windows |
| **System.Net.HttpListener** | Web-Server | Teil des .NET-Frameworks, kein zusätzliches NuGet-/Node-Paket |
| **System.Net.Sockets.TcpListener** | OAuth-Callback | Unter Windows benötigt `HttpListener` für `127.0.0.1` eine URL-ACL — `TcpListener` nicht |
| **Spotify Web API** | Datenquelle für Playlists | Industriestandard, dokumentiert, kostenloser Developer-Account |
| **OAuth 2.0 Authorization Code Flow** | Login für eigene Playlists | Spotify-Vorgabe für privaten Inhaltszugriff |
| **HTML / CSS / Vanilla JS** | Web-Frontend | Kein Framework-Overhead; alles statisch ausgelieferbar |
| **JSON** | Datenaustausch + Export | universell lesbar, kompatibel mit Frontend (`fetch().json()`) |

## 6. Wichtige Design-Entscheidungen

### 6.1 Web-UI aus PowerShell ausgeliefert

Statt einer separaten Web-Anwendung (Node.js, Python-Flask etc.) wird die Web-UI **vom PowerShell-Skript selbst** über `HttpListener` ausgeliefert. So bleibt der Modul-122-Fokus auf PowerShell, ohne dass eine zweite Skriptsprache eingezogen werden muss.

### 6.2 Modulare Trennung Logik ↔ Präsentation

`Find-Duplicates` und die Spotify-Module wissen **nichts** über Konsole oder Web. Beide Entry-Points (`Start-DuplicateChecker.ps1`, `Start-WebServer.ps1`) instanziieren die gleichen Funktionen — die Test- und Wartbarkeit profitiert.

### 6.3 Zwei Spotify-Auth-Flows nebeneinander

| Flow | Wofür | Modul |
|---|---|---|
| **Client Credentials** | öffentliche Playlists per URL | `Get-SpotifyTracks.ps1` |
| **Authorization Code** | eigene/private Playlists des Users | `Connect-Spotify.ps1` |

Beide Flows liefern ein **einheitliches Song-Objekt** (`Title`, `Artist`, `Album`, optional `Uri`/`Position`) — `Find-Duplicates` kennt den Unterschied nicht und braucht dadurch keine Sonderlogik.

### 6.4 `TcpListener` statt `HttpListener` für OAuth-Callback

Spotify verbietet seit 2025 `http://localhost` als Redirect-URI — nur HTTPS oder `http://127.0.0.1`. Ein `HttpListener` auf `http://127.0.0.1:8888/` benötigt unter Windows allerdings eine URL-ACL-Reservierung (`netsh`) oder Administratorrechte. Ein `TcpListener` bindet einen einfachen Socket ohne diese Anforderungen. Der HTTP-Header der Callback-Antwort wird daher **manuell zusammengebaut** — ein wenig zusätzlicher Code, aber kein Admin-Zwang.

### 6.5 Strikte Yes/No-Eingabe

Eingaben wie `"v"` oder beliebige Zeichen werden **nicht** stillschweigend als „Nein" interpretiert. `Read-YesNo` akzeptiert nur `j`/`n`/Aliase oder Enter (Default); andere Eingaben lösen einen Fehler aus und das Prompt erscheint erneut. Das vermeidet stillschweigende, unbeabsichtigte Aktionen.

### 6.6 Spotify-Restriktion auf Modify-Operationen

Spotify hat seit Ende 2024 für Apps im *Development Mode* die Endpoints zum **Erstellen** und **Verändern von Playlist-Tracks** mit `HTTP 403 Forbidden` gesperrt — unabhängig von Scopes oder Owner-Status. Da das Tool keine Extended-Quota-Genehmigung hat, wurde die ursprünglich geplante **automatische Lösch-Funktion entfernt**. Stattdessen weist die Anwendung den Nutzer darauf hin, Duplikate manuell in der Spotify-App zu entfernen.

## 7. Herausforderungen & Lösungen

| Problem | Untersuchung | Lösung |
|---|---|---|
| Spotify lehnt `http://localhost` als Redirect-URI ab | Test im Dashboard: rote Fehlermeldung *„not secure"* | Wechsel auf `http://127.0.0.1:8888/callback` |
| `HttpListener` auf 127.0.0.1 verlangt Admin-Rechte | URL-ACL fehlt; nur `localhost` ist freigegeben | Wechsel auf `System.Net.Sockets.TcpListener` |
| `/v1/playlists/{id}/tracks` liefert 403 | Strukturanalyse der API-Antworten zeigte Feld-Umbenennung | Wechsel auf `/v1/playlists/{id}/items?additional_types=track` |
| Item-Wrapper `track` ist boolean, nicht Datenobjekt | Roh-JSON-Dump aus Diagnose-Befehl | Parser nimmt `$Item.item` als primären Datencontainer |
| `Invoke-RestMethod -Method DELETE -Body …` sendet Body unzuverlässig | Vergleich mit `HttpClient` | OAuth- und Modify-Calls über `System.Net.Http.HttpClient` |
| GET `/api/config` und `/api/spotify/my-playlists` lieferten leeren Body | Routing-Reihenfolge: der breite `if ($method -eq 'GET')` fing alle GETs ab | Spezifische Routen vor dem Static-File-Catch-all + Pfad-Filter |
| Spotify gibt nichtssagendes 403 ohne Detail-Message | `WWW-Authenticate`-Header gedumpt, Spotify-Body komplett geloggt | Diagnose-Befehle `diag`, `test-modify`, `test-tracks` (versteckt im Help) |

## 8. Sicherheits-Überlegungen

- **Path Traversal**: Der Static-File-Handler löst angefragte Pfade absolut auf und prüft, dass sie innerhalb von `web/` liegen. `/../../etc/passwd` führt zu `403`.
- **XSS**: Im Frontend werden Songtitel und Album-Namen via `textContent` (nicht `innerHTML`) eingefügt. Boshafter Songtitel kann kein JavaScript injizieren.
- **Credentials**: `config.json` mit Client Secret und OAuth-Refresh-Token liegt **nicht** im Repository. `config.example.json` als Vorlage zeigt nur die Struktur.
- **OAuth State**: Beim Authorization-Code-Flow wird ein zufälliger `state`-Parameter erzeugt und beim Callback geprüft (CSRF-Schutz).
- **Lokales Binding**: HTTP-Server bindet ausschliesslich an `localhost:8080`, der OAuth-Callback an `127.0.0.1:8888` — keine Netzwerk-Exposition.

## 9. Erweiterungsmöglichkeiten

| Idee | Aufwand | Nutzen |
|---|---|---|
| Bash-Variante des CSV-Modus | mittel | demonstriert beide M122-Skriptsprachen |
| Pester-Unit-Tests für `Find-Duplicates` und `Import-SongCsv` | klein | beweist Code-Qualität |
| Fuzzy-Matching (Levenshtein) für „Imagine" vs „Imagine - Remastered" | mittel | erkennt mehr Duplikate |
| Verlauf in `data/results/history.json` | klein | langfristige Statistik pro Lauf |
| Apple-Music / YouTube-Music-Anbindung | gross | Multi-Plattform-Bibliothek |
| Spotify-Lösch-Funktion bei Extended-Quota-Freigabe | klein | Code ist bereits Architecture-ready |

## 10. API-Endpoints (Web-Server)

| Methode | Pfad | Zweck |
|---|---|---|
| `GET` | `/` | `index.html` |
| `GET` | `/style.css`, `/app.js` | Statische Frontend-Dateien |
| `GET` | `/api/config` | Status: Credentials eingerichtet? eingeloggt? |
| `POST` | `/api/config` | Client ID + Secret speichern |
| `POST` | `/api/check` | CSV-Body → Duplikate als JSON |
| `POST` | `/api/spotify` | URL einer öffentlichen Playlist → Duplikate |
| `POST` | `/api/spotify/connect` | OAuth-Flow für eigene Playlists anstossen |
| `GET` | `/api/spotify/my-playlists` | Liste der eigenen Playlists des Users |
| `POST` | `/api/spotify/check-by-id` | Duplikat-Check für eine eigene Playlist (per ID) |

## 11. Verwendete Spotify-API-Scopes

| Scope | Zweck |
|---|---|
| `playlist-read-private` | private eigene Playlists lesen |
| `playlist-read-collaborative` | kollaborative Playlists lesen |
| `user-read-private` | User-Profil + Region (Track Relinking) |

Modify-Scopes wurden bewusst **nicht** angefordert (siehe Abschnitt 6.6).

---

*Erstellt im Rahmen des Schulprojekts Modul 122. Stand der Dokumentation: Mai 2026.*
