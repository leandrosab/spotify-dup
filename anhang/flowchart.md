# Flowcharts
## Song-Duplikat-Checker — Modul 122

> Diagramme im **Mermaid**-Format. Sie werden direkt in GitHub, GitLab und VS Code (mit der Mermaid-Extension) gerendert. Zum Export als PNG/PDF/SVG: einfach den Code-Block auf [mermaid.live](https://mermaid.live) einfügen → Download.

---

## 1. System-Architektur (Komponenten-Übersicht)

Zeigt, wie die Schichten zueinander stehen und welche externen Datenquellen angebunden sind.

```mermaid
flowchart TB
    subgraph User["Benutzer"]
        Person([Anwender:in])
    end

    subgraph Presentation["Präsentations-Schicht"]
        CLI["PowerShell-Shell<br/>Start-DuplicateChecker.ps1"]
        Web["Web-UI<br/>Start-WebServer.ps1"]
        Browser["Browser<br/>HTML + CSS + JS"]
    end

    subgraph Logic["Logik-Module (src/modules)"]
        ImportCsv["Import-SongCsv"]
        FindDup["Find-Duplicates"]
        Export["Export-Results"]
        ShowUI["Show-UI"]
        GetSpotify["Get-SpotifyTracks"]
        ConnectSpotify["Connect-Spotify"]
    end

    subgraph DataSources["Datenquellen"]
        CSVFile[("CSV-Datei")]
        SpotifyAPI{{"Spotify Web API"}}
    end

    Person -->|tippt Befehle| CLI
    Person -->|Browser| Browser
    Browser <-->|HTTP / JSON| Web

    CLI --> ImportCsv
    CLI --> FindDup
    CLI --> Export
    CLI --> ShowUI
    CLI --> GetSpotify
    CLI --> ConnectSpotify

    Web --> ImportCsv
    Web --> FindDup
    Web --> Export
    Web --> GetSpotify
    Web --> ConnectSpotify

    ImportCsv --> CSVFile
    GetSpotify -->|"Client Credentials"| SpotifyAPI
    ConnectSpotify -->|"OAuth 2.0"| SpotifyAPI

    classDef user fill:#1f3b6e,stroke:#58a6ff,color:#fff
    classDef pres fill:#21262d,stroke:#56d364,color:#c9d1d9
    classDef logic fill:#0d1117,stroke:#f0b033,color:#c9d1d9
    classDef data fill:#161b22,stroke:#58a6ff,color:#c9d1d9

    class Person user
    class CLI,Web,Browser pres
    class ImportCsv,FindDup,Export,ShowUI,GetSpotify,ConnectSpotify logic
    class CSVFile,SpotifyAPI data
```

---

## 2. Hauptablauf — CSV-Modus

Der einfachste Datenfluss. Keine Authentifizierung, keine Netzwerk-Calls.

```mermaid
flowchart TD
    Start([Start]) --> Cmd["User tippt 'csv'"]
    Cmd --> AskPath["Pfad eingeben / Beispiel wählen"]
    AskPath --> Validate{"Datei existiert?<br/>Endung .csv?<br/>Pflichtspalten vorhanden?"}
    Validate -->|nein| ErrCsv["[ERR]<br/>klare Fehlermeldung"]
    Validate -->|ja| Import["Import-SongCsv<br/>liest Daten ein"]
    Import --> AskAlbum["Album mitvergleichen?<br/>j/n"]
    AskAlbum --> Find["Find-Duplicates<br/>Group-Object nach<br/>normalisiertem Key"]
    Find --> Show["Show-DuplicateResults<br/>farbige Tabelle, sortiert nach Anzahl"]
    Show --> AskExport["Resultate exportieren?<br/>J/n"]
    AskExport -->|nein| EndN([Ende])
    AskExport -->|ja| ExportRes["Export-Results<br/>schreibt CSV + JSON<br/>mit Zeitstempel"]
    ExportRes --> EndY([Ende])
    ErrCsv --> EndE([Ende])

    classDef start fill:#1f3b6e,stroke:#58a6ff,color:#fff
    classDef proc fill:#0d1117,stroke:#56d364,color:#c9d1d9
    classDef decision fill:#161b22,stroke:#f0b033,color:#c9d1d9
    classDef error fill:#3d1a1a,stroke:#f85149,color:#fff
    classDef endE fill:#21262d,stroke:#8b949e,color:#c9d1d9

    class Start,EndN,EndY,EndE start
    class Cmd,AskPath,Import,Find,Show,ExportRes proc
    class Validate,AskAlbum,AskExport decision
    class ErrCsv error
```

---

## 3. Hauptablauf — Spotify-Modus (eigene Playlists)

Der komplexeste Flow: OAuth-Login, Token-Management, Playlist-Auswahl.

```mermaid
flowchart TD
    Start([Start]) --> SpoCmd["User tippt 'spotify'"]
    SpoCmd --> CfgChk{"config.json<br/>vorhanden?"}
    CfgChk -->|nein| CfgWizard["Setup-Wizard:<br/>Client ID + Secret eingeben"]
    CfgWizard --> Source
    CfgChk -->|ja| Source["Quelle wählen<br/>[1] eigene / [2] URL"]

    Source -->|"[1] eigene"| TokenChk{"Access-Token<br/>vorhanden + gültig?"}
    Source -->|"[2] URL"| AskUrl["URL eingeben"]

    TokenChk -->|nein| RefreshChk{"Refresh-Token<br/>vorhanden?"}
    RefreshChk -->|ja| Refresh["Token<br/>via Refresh-Token<br/>erneuern"]
    RefreshChk -->|nein| OAuth["OAuth Authorization Code Flow:<br/>Browser öffnen → User-Login →<br/>Callback auf 127.0.0.1:8888 →<br/>Code gegen Tokens tauschen"]

    Refresh --> TokenOk["gültiger Access-Token"]
    OAuth --> TokenOk
    TokenChk -->|ja| TokenOk

    TokenOk --> GetMine["Get-MyPlaylists<br/>/v1/me/playlists"]
    GetMine --> ShowList["nummerierte Liste anzeigen<br/>(* = eigene, leer = gefolgte)"]
    ShowList --> PickPl["User wählt Nummer"]
    PickPl --> AskAlb["Album mitvergleichen?<br/>j/n"]
    AskAlb --> GetTracks["Get-PlaylistTracksUser<br/>/v1/playlists/{id}/items"]

    AskUrl --> AskAlb2["Album mitvergleichen?<br/>j/n"]
    AskAlb2 --> GetTracksPublic["Get-SpotifyTracks<br/>Client Credentials Flow"]

    GetTracks --> Find["Find-Duplicates"]
    GetTracksPublic --> Find
    Find --> Show["Show-DuplicateResults"]
    Show --> Hint["Hinweis:<br/>manuell in Spotify-App entfernen"]
    Hint --> End([Ende])

    classDef start fill:#1f3b6e,stroke:#58a6ff,color:#fff
    classDef proc fill:#0d1117,stroke:#56d364,color:#c9d1d9
    classDef decision fill:#161b22,stroke:#f0b033,color:#c9d1d9
    classDef oauth fill:#2d1f1a,stroke:#ff7b72,color:#fff
    classDef endE fill:#21262d,stroke:#8b949e,color:#c9d1d9

    class Start,End endE
    class SpoCmd,CfgWizard,Source,AskUrl,Refresh,TokenOk,GetMine,ShowList,PickPl,AskAlb,AskAlb2,GetTracks,GetTracksPublic,Find,Show,Hint proc
    class CfgChk,TokenChk,RefreshChk decision
    class OAuth oauth
```

---

## 4. Web-Modus — Request/Response-Fluss

Wie ein Browser-Klick eine API-Anfrage auslöst und der PowerShell-Server sie verarbeitet.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Browser as Browser<br/>(app.js)
    participant Server as PowerShell Server<br/>(Start-WebServer.ps1)
    participant Mod as Module<br/>(Find-Duplicates, …)
    participant Spotify as Spotify Web API

    User->>Browser: öffnet http://localhost:8080
    Browser->>Server: GET /
    Server-->>Browser: index.html
    Browser->>Server: GET /style.css, /app.js
    Server-->>Browser: statische Dateien

    Note over Browser: User wählt CSV-Datei und klickt "Run"
    Browser->>Server: POST /api/check (CSV-Body)
    Server->>Mod: Import-SongCsv + Find-Duplicates
    Mod-->>Server: Duplikat-Liste
    Server-->>Browser: JSON { success, total, duplicates }
    Browser->>User: Tabelle rendern

    Note over Browser: alternativ: User wählt Spotify-Tab → Connect
    Browser->>Server: POST /api/spotify/connect
    Server->>Spotify: OAuth-URL öffnen, Callback abwarten
    Spotify-->>Server: Authorization Code
    Server->>Spotify: Code gegen Tokens tauschen
    Spotify-->>Server: Access + Refresh Token
    Server-->>Browser: JSON { success: true }

    Browser->>Server: GET /api/spotify/my-playlists
    Server->>Spotify: GET /v1/me/playlists (Bearer Token)
    Spotify-->>Server: Playlist-Liste
    Server-->>Browser: JSON { success, playlists[] }
    Browser->>User: klickbare Playlist-Liste

    Note over Browser: User klickt eine Playlist
    Browser->>Server: POST /api/spotify/check-by-id
    Server->>Spotify: GET /v1/playlists/{id}/items
    Spotify-->>Server: Tracks
    Server->>Mod: Find-Duplicates
    Mod-->>Server: Duplikat-Liste
    Server-->>Browser: JSON { success, total, duplicates }
    Browser->>User: Tabelle rendern
```

---

## 5. Duplikat-Erkennung — die Kernlogik

Das Herz des Tools. Aus einer Liste roher Songs werden gruppierte Duplikate.

```mermaid
flowchart LR
    Input[/"Liste von Songs<br/>(Title, Artist, Album)"/] --> Loop["Für jeden Song:"]
    Loop --> Norm["Titel + Artist normalisieren<br/>(Trim, Lowercase)"]
    Norm --> Key{"-IncludeAlbum<br/>gesetzt?"}
    Key -->|ja| Key3["Schlüssel:<br/>titel | artist | album"]
    Key -->|nein| Key2["Schlüssel:<br/>titel | artist"]
    Key2 --> Group["Group-Object<br/>nach Schlüssel"]
    Key3 --> Group
    Group --> Filter{"Anzahl pro<br/>Gruppe > 1?"}
    Filter -->|nein| Drop[verwerfen]
    Filter -->|ja| Keep["als Duplikat-Gruppe<br/>aufnehmen"]
    Keep --> Sort["nach Count absteigend<br/>sortieren"]
    Sort --> Output[/"Duplikat-Gruppen<br/>mit Title, Artist, Album, Count"/]

    classDef inout fill:#1f3b6e,stroke:#58a6ff,color:#fff
    classDef proc fill:#0d1117,stroke:#56d364,color:#c9d1d9
    classDef decision fill:#161b22,stroke:#f0b033,color:#c9d1d9
    classDef drop fill:#3d1a1a,stroke:#f85149,color:#fff

    class Input,Output inout
    class Loop,Norm,Key2,Key3,Group,Keep,Sort proc
    class Key,Filter decision
    class Drop drop
```

**Beispiel-Durchlauf** (ohne `IncludeAlbum`):

| Song | Normalisierter Schlüssel |
|---|---|
| `"Imagine"` von `"John Lennon"` | `imagine\|john lennon` |
| `"  imagine  "` von `"John Lennon"` | `imagine\|john lennon` ← **gleicher Key** |
| `"Imagine - Remastered"` von `"John Lennon"` | `imagine - remastered\|john lennon` |
| `"Hey Jude"` von `"The Beatles"` | `hey jude\|the beatles` |

→ `Group-Object` findet 2 Vorkommen von `imagine|john lennon` → eine Duplikat-Gruppe mit Count 2.

---

## 6. OAuth-2.0-Login im Detail

Der genaue Ablauf des Authorization Code Flows mit lokalem Callback-Listener.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant CLI as duplichecker<br/>(PowerShell)
    participant Listener as TcpListener<br/>auf 127.0.0.1:8888
    participant Browser
    participant Spotify

    User->>CLI: tippt 'spotify' → '1'
    CLI->>CLI: Random State generieren<br/>(CSRF-Schutz)
    CLI->>Listener: starten auf 127.0.0.1:8888
    CLI->>Browser: Start-Process<br/>spotify.com/authorize?<br/>client_id=…&scope=…&state=…&show_dialog=true
    Browser->>Spotify: User loggt sich ein,<br/>klickt "Agree"
    Spotify->>Browser: 302 Redirect zu<br/>127.0.0.1:8888/callback?code=…&state=…
    Browser->>Listener: GET /callback?code=…&state=…
    Listener->>Listener: State prüfen (CSRF-Check)
    Listener->>Browser: HTML "Login erfolgreich"<br/>(rohes HTTP über Socket)
    Listener-->>CLI: Authorization Code
    CLI->>Spotify: POST /api/token<br/>grant_type=authorization_code<br/>+ Basic Auth (ID:Secret)
    Spotify-->>CLI: access_token + refresh_token + scope
    CLI->>CLI: Tokens in config.json speichern<br/>+ Scope-Liste anzeigen
    CLI->>User: "Login erfolgreich"
```

---

## 7. Daten-Pipeline (von Eingabe bis Export)

Zusammenfassung des gesamten Datenflusses unabhängig vom Modus.

```mermaid
flowchart LR
    A[("CSV")] -.->|"Import-SongCsv"| Songs
    B[("Spotify-Playlist<br/>per URL")] -.->|"Get-SpotifyTracks"| Songs
    C[("eigene Spotify-<br/>Playlist via OAuth")] -.->|"Get-PlaylistTracksUser"| Songs

    Songs["normalisierte Song-Liste<br/>(Title, Artist, Album)"]
    Songs --> FD["Find-Duplicates"]
    FD --> Groups["Duplikat-Gruppen<br/>(sortiert nach Count)"]
    Groups --> Display["Show-DuplicateResults<br/>(Konsole / Web-Tabelle)"]
    Groups -. optional .-> ExportNode["Export-Results"]
    ExportNode --> CSVOut[("CSV<br/>mit Zeitstempel")]
    ExportNode --> JSONOut[("JSON<br/>mit Zeitstempel")]

    classDef src fill:#1f3b6e,stroke:#58a6ff,color:#fff
    classDef proc fill:#0d1117,stroke:#56d364,color:#c9d1d9
    classDef out fill:#21262d,stroke:#f0b033,color:#c9d1d9

    class A,B,C src
    class Songs,FD,Groups,Display,ExportNode proc
    class CSVOut,JSONOut out
```

---

## Export-Hinweis

Wenn das Diagramm für die Schule als **PDF** oder **eingebettetes Bild** gebraucht wird:

1. Den jeweiligen ```` ```mermaid ```` -Block kopieren
2. Auf [mermaid.live](https://mermaid.live) einfügen
3. Oben rechts **Actions → PNG/SVG/PDF** klicken

Alternativ in VS Code: Extension **„Markdown Preview Mermaid Support"** installieren, dann Markdown-Preview öffnen → Strg+P → *„Markdown PDF: Export"*.
