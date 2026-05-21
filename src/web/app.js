// =====================================================================
//  Frontend-Logik fuer das Web-UI.
//  - Tab-Wechsel zwischen CSV- und Spotify-Modus
//  - CSV: Datei lesen, an /api/check schicken
//  - Spotify: URL an /api/spotify schicken (JSON-Body)
//  - Resultate als Status-Zeilen + Tabelle anzeigen
// =====================================================================

// ---- Tab-Switch ----
const tabs  = document.querySelectorAll('.tab');
const modes = document.querySelectorAll('.mode');

tabs.forEach(tab => {
    tab.addEventListener('click', () => {
        const target = tab.dataset.mode;
        tabs.forEach(t => t.classList.toggle('active', t === tab));
        modes.forEach(m => m.classList.toggle('active', m.id === `${target}-mode`));
        clearOutput();
        if (target === 'spotify') refreshConfigStatus();
    });
});

// ---- Sub-Tabs: meine Playlists vs. URL ----
const subTabs   = document.querySelectorAll('.sub-tab');
const subModes  = document.querySelectorAll('.submode');
subTabs.forEach(tab => {
    tab.addEventListener('click', () => {
        const target = tab.dataset.submode;
        subTabs.forEach(t => t.classList.toggle('active', t === tab));
        subModes.forEach(m => m.classList.toggle('active', m.id === `${target}-submode`));
        clearOutput();
    });
});

// ---- Spotify Credentials- und Login-Status ----
// Pruefen, ob config.json eingerichtet ist UND ob ein Refresh-Token existiert.
// Je nach Status: Badge-Farbe + Settings-Sichtbarkeit + meine-Playlists-Bereich.
async function refreshConfigStatus() {
    const badge   = document.getElementById('cfg-badge');
    const details = document.getElementById('cfg-details');
    const myDisc  = document.getElementById('my-disconnected');
    const myConn  = document.getElementById('my-connected');

    try {
        // cache: 'no-store' = Browser darf nichts caches abrufen, immer frisch.
        const res  = await fetch('/api/config', { cache: 'no-store' });
        const data = await res.json();
        console.log('[duplichecker] /api/config ->', data);

        if (!data.configured) {
            badge.textContent = 'credentials fehlen';
            badge.className   = 'cfg-badge cfg-missing';
            details.open      = true;
            myDisc.style.display = 'block';
            myConn.style.display = 'none';
            return;
        }

        if (data.connected) {
            badge.textContent = 'logged in';
            badge.className   = 'cfg-badge cfg-ok';
            details.open      = false;
            await loadMyPlaylists();
        } else {
            badge.textContent = 'credentials ok (nicht eingeloggt)';
            badge.className   = 'cfg-badge cfg-unknown';
            details.open      = false;
            myDisc.style.display = 'block';
            myConn.style.display = 'none';
        }
    } catch (err) {
        console.error('[duplichecker] refreshConfigStatus failed:', err);
        badge.textContent = 'status unbekannt';
        badge.className   = 'cfg-badge cfg-unknown';
    }
}

// ---- Connect-Button: OAuth-Login starten ----
document.getElementById('btn-connect').addEventListener('click', async () => {
    const btn = document.getElementById('btn-connect');
    btn.disabled = true;
    showProcessing('oeffne spotify-login im browser... (max. 5 minuten warten)');
    try {
        const res  = await fetch('/api/spotify/connect', { method: 'POST' });
        const data = await res.json();
        if (!data.success) {
            showError(data.error || 'Login fehlgeschlagen');
            return;
        }
        appendLine('OK - mit Spotify verbunden.', 'success-line');

        // Wir wissen, dass connect gerade erfolgreich war - kein erneutes
        // /api/config noetig (das hat manchmal Caching-/Race-Probleme direkt
        // nach OAuth). UI hart auf "logged in" setzen.
        const badge = document.getElementById('cfg-badge');
        badge.textContent = 'logged in';
        badge.className   = 'cfg-badge cfg-ok';
        document.getElementById('cfg-details').open = false;

        // Sicher in den "meine Playlists"-Sub-Tab wechseln.
        document.querySelector('.sub-tab[data-submode="my"]').click();

        // Direkt Playlists laden.
        await loadMyPlaylists();
    } catch (err) {
        showError('Netzwerkfehler: ' + err.message);
    } finally {
        btn.disabled = false;
    }
});

// ---- Eigene Playlists vom Backend holen und anzeigen ----
async function loadMyPlaylists() {
    const myDisc = document.getElementById('my-disconnected');
    const myConn = document.getElementById('my-connected');
    const list   = document.getElementById('playlist-list');

    try {
        const res  = await fetch('/api/spotify/my-playlists', { cache: 'no-store' });
        const data = await res.json();
        console.log('[duplichecker] /api/spotify/my-playlists ->', data);
        if (!data.success) {
            myDisc.style.display = 'block';
            myConn.style.display = 'none';
            // Hilfreiche Fehlermeldung in den Output schreiben
            if (data.error) {
                appendLine('Konnte Playlists nicht laden: ' + data.error, 'error-line');
            }
            return;
        }
        myDisc.style.display = 'none';
        myConn.style.display = 'block';

        list.innerHTML = '';
        for (const p of data.playlists) {
            const li = document.createElement('li');
            li.className = 'playlist-item';

            const name = document.createElement('span');
            name.className = 'pl-name';
            name.textContent = p.Name;

            const meta = document.createElement('span');
            meta.className = 'pl-meta';
            meta.textContent = `${p.TrackCount} Tracks - ${p.Owner}`;

            li.appendChild(name);
            li.appendChild(meta);
            li.addEventListener('click', () => runMyPlaylist(p.Id, p.Name));
            list.appendChild(li);
        }
    } catch (err) {
        showError('Konnte Playlists nicht laden: ' + err.message);
    }
}

// ---- Klick auf Playlist: Duplikate suchen ----
// Wir merken uns den Kontext (playlistId + Name), damit wir nach
// dem Anzeigen den "Loeschen"-Button anbieten koennen.
async function runMyPlaylist(playlistId, playlistName) {
    const album = document.getElementById('my-album').checked;
    showProcessing(`processing "${playlistName}"...`);
    try {
        const res  = await fetch('/api/spotify/check-by-id', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ playlistId, album })
        });
        const data = await res.json();
        renderResult(data, { ownedPlaylistId: playlistId, ownedPlaylistName: playlistName, album });
    } catch (err) {
        showError('Netzwerkfehler: ' + err.message);
    }
}

// Speichern-Button im Settings-Bereich.
// Nach erfolgreichem Speichern starten wir DIREKT den Spotify-Login,
// damit der User nicht extra noch auf "Connect" klicken muss.
document.getElementById('cfg-save').addEventListener('click', async () => {
    const clientId     = document.getElementById('cfg-client-id').value.trim();
    const clientSecret = document.getElementById('cfg-client-secret').value.trim();
    if (!clientId || !clientSecret) {
        return showError('Client ID und Client Secret duerfen nicht leer sein.');
    }
    try {
        const res = await fetch('/api/config', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ clientId, clientSecret })
        });
        const data = await res.json();
        if (!data.success) {
            return showError(data.error || 'Speichern fehlgeschlagen.');
        }
        clearOutput();
        appendLine('OK - Credentials gespeichert.', 'success-line');
        document.getElementById('cfg-client-id').value = '';
        document.getElementById('cfg-client-secret').value = '';

        // Status pruefen und ggf. direkt einloggen (auto-flow).
        const cfg = await fetch('/api/config').then(r => r.json()).catch(() => ({}));
        if (cfg && cfg.configured && !cfg.connected) {
            appendLine('Starte Spotify-Login...', 'info-line');
            // Settings-Panel zumachen, damit der User danach Playlists sieht.
            document.getElementById('cfg-details').open = false;
            document.getElementById('btn-connect').click();
        } else {
            await refreshConfigStatus();
        }
    } catch (err) {
        showError('Netzwerkfehler: ' + err.message);
    }
});

// Beim ersten Laden direkt einmal pruefen.
refreshConfigStatus();

// =====================================================================
//  TOP-MODE-Switch: UX (Formular) <-> Terminal (Shell-Eingabe)
// =====================================================================
const topModeBtns = document.querySelectorAll('.top-mode-btn');
const topSections = document.querySelectorAll('.top-section');
topModeBtns.forEach(btn => {
    btn.addEventListener('click', () => {
        const target = btn.dataset.topmode;
        topModeBtns.forEach(b => b.classList.toggle('active', b === btn));
        topSections.forEach(s =>
            s.classList.toggle('active', s.id === `${target}-section`));
        // Beim Wechsel ins Terminal direkt Fokus aufs Eingabefeld.
        if (target === 'term') {
            document.getElementById('term-input').focus();
        }
    });
});

// =====================================================================
//  TERMINAL-MODUS - Shell-aehnliche Befehlszeile im Browser
//  Dieselben Endpoints wie der UX-Modus, aber per Befehl statt per Klick.
// =====================================================================
const termOutput = document.getElementById('term-output');
const termInput  = document.getElementById('term-input');
const termForm   = document.getElementById('term-form');
const termPicker = document.getElementById('term-file-picker');

// Letzte Playlist-Liste merken, damit "play <nr>" funktioniert.
let termPlaylists = [];

// ---- Hilfsfunktionen zum Schreiben ins Terminal ----
function termWrite(text, cls = '') {
    const div = document.createElement('div');
    div.className = 'term-line' + (cls ? ' ' + cls : '');
    div.textContent = text;
    termOutput.appendChild(div);
    div.scrollIntoView({ block: 'end' });
}
function termInfo(t)    { termWrite(t, 'term-info'); }
function termOk(t)      { termWrite(t, 'term-success'); }
function termErr(t)     { termWrite(t, 'term-error'); }
function termWarn(t)    { termWrite(t, 'term-warn'); }
function termEcho(cmd) {
    const div = document.createElement('div');
    div.className = 'term-line term-cmd-line';
    const promptSpan = document.createElement('span');
    promptSpan.className = 'prompt';
    promptSpan.textContent = 'duplichecker$';
    const cmdSpan = document.createElement('span');
    cmdSpan.textContent = ' ' + cmd;
    div.appendChild(promptSpan);
    div.appendChild(cmdSpan);
    termOutput.appendChild(div);
}

// Tabelle mit Duplikaten ins Terminal rendern.
function termRenderDuplicates(data) {
    if (!data.success) {
        termErr('Fehler: ' + (data.error || 'unbekannt'));
        return;
    }
    if (data.duplicates.length === 0) {
        termOk(`OK - ${data.total} Songs geprueft, keine Duplikate gefunden.`);
        return;
    }
    const sorted = [...data.duplicates].sort((a, b) => b.Count - a.Count);
    const triples = sorted.filter(d => d.Count >= 3).length;
    const max = Math.max(...sorted.map(d => d.Count));

    termOk(`OK - ${data.total} Songs geprueft, ${sorted.length} Duplikat-Gruppe(n) gefunden.`);
    if (triples > 0) {
        termWarn(`Davon ${triples} Song(s) mit 3+ Vorkommen (max. ${max}x).`);
    }

    const tbl = document.createElement('table');
    tbl.className = 'term-table';
    tbl.innerHTML = '<thead><tr><th class="col-count">#x</th><th>Title</th>' +
                    '<th>Artist</th><th>Album</th></tr></thead><tbody></tbody>';
    const tbody = tbl.querySelector('tbody');
    for (const d of sorted) {
        const tr = document.createElement('tr');
        if (d.Count >= 3) tr.classList.add('row-triple');
        const c1 = document.createElement('td');
        c1.className = 'col-count';
        c1.textContent = d.Count + 'x';
        const c2 = document.createElement('td'); c2.textContent = d.Title;
        const c3 = document.createElement('td'); c3.textContent = d.Artist;
        const c4 = document.createElement('td'); c4.textContent = d.Album || '';
        tr.append(c1, c2, c3, c4);
        tbody.appendChild(tr);
    }
    termOutput.appendChild(tbl);
}

// Mehrstufige Prompts (1/2-Menue, Playlist-Nummer, j/n etc.).
// Wenn != null, wird die naechste Eingabe NICHT als neuer Befehl interpretiert,
// sondern als Antwort auf den laufenden Prompt. So bekommen wir denselben
// interaktiven Ablauf wie die lokale PowerShell-Shell.
let termPromptState = null;

// ---- Eingabe-Verarbeitung ----
termForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const raw = termInput.value;
    termInput.value = '';
    termEcho(raw);
    await termHandle(raw);
    termInput.focus();
});

async function termHandle(line) {
    line = (line || '').trim();

    // Aktiver Multi-Step-Prompt -> Eingabe als Antwort verarbeiten.
    if (termPromptState) {
        const handler = termPromptState.handler;
        termPromptState = null;
        return await handler(line);
    }

    if (!line) return;
    // ersten Token als Befehl, Rest als Argument.
    const space = line.indexOf(' ');
    const cmd = (space === -1 ? line : line.substring(0, space)).toLowerCase();
    const arg = space === -1 ? '' : line.substring(space + 1).trim();

    switch (cmd) {
        case 'help': case '?':       return termCmdHelp();
        case 'clear': case 'cls':    termOutput.innerHTML = ''; return;
        case 'quit': case 'exit': case 'ui':  return termSwitchToUx();
        case 'spotify':              return termCmdSpotifyStart();
        case 'csv':                  return termCmdCsv();
        case 'config':               return termCmdConfig();
        case 'samples':              return termCmdSamples();
        // Versteckte Diagnose-Helfer (nicht in 'help' gelistet,
        // funktionieren aber fuer Power-User):
        case 'status':               return termCmdStatus();
        case 'connect':              return termCmdConnect();
        case 'mine': case 'playlists': return termCmdMine();
        case 'play':                 return termCmdPlay(arg);
        default:
            termErr(`unbekannter Befehl: '${cmd}' - tippe 'help' fuer eine Liste.`);
    }
}

function termCmdHelp() {
    // Spiegelt die Befehle der lokalen PowerShell-Shell - selbe Namen,
    // dieselbe Reihenfolge, damit es konsistent ist.
    const rows = [
        ['csv',     'CSV-Datei auf Duplikate pruefen'],
        ['spotify', 'Spotify-Playlist auf Duplikate pruefen'],
        ['config',  'Spotify-Credentials einrichten / aendern'],
        ['samples', 'Verfuegbare Beispiel-CSVs auflisten'],
        ['clear',   'Bildschirm leeren'],
        ['help',    'Diese Hilfe anzeigen'],
        ['quit',    'Zurueck in den UX-Modus']
    ];
    termInfo('Verfuegbare Befehle:');
    for (const [c, d] of rows) {
        termWrite('  ' + c.padEnd(10) + '- ' + d, 'term-info');
    }
}

// ---- Multi-Step "spotify"-Befehl - mirror der lokalen Shell ----
// 1) Quelle waehlen (1 = eigene Playlists, 2 = URL)
//   1a) Login pruefen, ggf. anstossen
//   1b) Playlists listen, Nummer waehlen
//   1c) Album-Frage j/n
//   1d) Resultat anzeigen
//   2a) URL eingeben
//   2b) Album-Frage j/n
//   2c) Resultat anzeigen
function termCmdSpotifyStart() {
    termInfo('Quelle waehlen:');
    termInfo('  [1] Eine meiner eigenen Playlists  (Login mit Spotify-Account)');
    termInfo('  [2] Eine oeffentliche Playlist per URL/ID');
    termPromptState = { handler: termSpotifySourcePick };
}

async function termSpotifySourcePick(line) {
    if (line === '1') {
        await termSpotifyMineFlow();
    } else if (line === '2') {
        termInfo('Spotify-Playlist URL oder ID:');
        termPromptState = { handler: termSpotifyUrlEntered };
    } else if (line === '') {
        termInfo('Abgebrochen.');
    } else {
        termErr(`Ungueltige Auswahl: '${line}' (erwartet: 1 oder 2)`);
    }
}

async function termSpotifyMineFlow() {
    // Stellt sicher, dass wir eingeloggt sind. Falls nicht, OAuth anstossen.
    const ok = await termEnsureConnected();
    if (!ok) return;
    await termCmdMine();   // setzt termPlaylists
    if (!termPlaylists || termPlaylists.length === 0) return;
    termInfo('Welche Playlist? (Nummer, Enter zum Abbrechen)');
    termPromptState = { handler: termSpotifyPlaylistPicked };
}

async function termSpotifyPlaylistPicked(line) {
    if (line === '') { termInfo('Abgebrochen.'); return; }
    const idx = parseInt(line, 10) - 1;
    if (isNaN(idx) || idx < 0 || idx >= termPlaylists.length) {
        termErr(`Ungueltige Nummer (1 bis ${termPlaylists.length}).`);
        return;
    }
    const pl = termPlaylists[idx];
    termInfo(`Gewaehlt: ${pl.Name}`);
    termInfo('Album mitvergleichen? (j/N)');
    termPromptState = { handler: (ans) => termSpotifyAlbumForPick(ans, pl) };
}

async function termSpotifyAlbumForPick(ans, pl) {
    const album = termParseYesNo(ans, false);
    if (album === null) {
        termErr(`Ungueltige Eingabe: '${ans}' - bitte 'j' oder 'n'.`);
        termPromptState = { handler: (a) => termSpotifyAlbumForPick(a, pl) };
        return;
    }
    await termRunCheckById(pl.Id, pl.Name, album);
}

async function termSpotifyUrlEntered(line) {
    if (line === '') { termInfo('Abgebrochen.'); return; }
    const url = line;
    termInfo('Album mitvergleichen? (j/N)');
    termPromptState = { handler: (ans) => termSpotifyAlbumForUrl(ans, url) };
}

async function termSpotifyAlbumForUrl(ans, url) {
    const album = termParseYesNo(ans, false);
    if (album === null) {
        termErr(`Ungueltige Eingabe: '${ans}' - bitte 'j' oder 'n'.`);
        termPromptState = { handler: (a) => termSpotifyAlbumForUrl(a, url) };
        return;
    }
    termInfo('Hole Tracks von Spotify...');
    try {
        const res = await fetch('/api/spotify', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ url, album })
        });
        termRenderDuplicates(await res.json());
    } catch (err) {
        termErr('Netzwerkfehler: ' + err.message);
    }
}

async function termRunCheckById(playlistId, playlistName, album) {
    termInfo(`Pruefe "${playlistName}"...`);
    try {
        const res = await fetch('/api/spotify/check-by-id', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ playlistId, album })
        });
        const data = await res.json();
        termRenderDuplicates(data);
        if (data.success && data.duplicates && data.duplicates.length > 0) {
            termInfo('Hinweis: Duplikate manuell in der Spotify-App entfernen.');
        }
    } catch (err) {
        termErr('Netzwerkfehler: ' + err.message);
    }
}

// Falls noch nicht eingeloggt, OAuth-Flow anstossen.
async function termEnsureConnected() {
    let cfg = null;
    try {
        cfg = await fetch('/api/config', { cache: 'no-store' }).then(r => r.json());
    } catch (err) {
        termErr('Status-Pruefung fehlgeschlagen: ' + err.message);
        return false;
    }
    if (!cfg.configured) {
        termWarn('Credentials nicht eingerichtet - tippe "config".');
        return false;
    }
    if (cfg.connected) return true;
    termWarn('Du bist noch nicht mit Spotify verbunden.');
    termInfo('Oeffne Browser fuer Login... (max. 5 Min)');
    try {
        const res = await fetch('/api/spotify/connect', { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            termOk('Login erfolgreich.');
            return true;
        }
        termErr('Login fehlgeschlagen: ' + (data.error || 'unbekannt'));
        return false;
    } catch (err) {
        termErr('Netzwerkfehler: ' + err.message);
        return false;
    }
}

// Yes/No-Parser: identische Liste wie Read-YesNo im PowerShell-CLI.
// Gibt true/false zurueck, oder null bei ungueltiger Eingabe.
function termParseYesNo(s, def) {
    const v = (s || '').trim().toLowerCase();
    if (v === '') return def;
    if (['j','y','ja','yes','1','true'].includes(v))  return true;
    if (['n','nein','no','0','false'].includes(v))    return false;
    return null;
}

// ---- 'config' im Web-Terminal ----
// Hier koennen wir keine Inputs im Terminal selbst entgegennehmen (Client ID
// hat Sonderzeichen und ist lang). Wir leiten den User zum UX-Modus weiter,
// wo der Settings-Panel komfortabel ist.
function termCmdConfig() {
    termInfo('Spotify-Credentials werden im UX-Modus eingegeben:');
    termInfo('  1. Klicke oben rechts auf [UX]');
    termInfo('  2. Tab "[2] Spotify-Playlist"');
    termInfo('  3. "> spotify credentials einrichten / aendern" aufklappen');
}

// ---- 'samples' im Web-Terminal ----
function termCmdSamples() {
    termInfo('Beispiel-CSVs (im Ordner data/samples/):');
    termWrite('  songs-clean.csv             - keine Duplikate', 'term-info');
    termWrite('  songs-with-duplicates.csv   - 3+ Duplikat-Gruppen', 'term-info');
    termWrite('  songs-broken.csv            - fehlende Spalte (Fehlerbehandlung)', 'term-info');
}

function termSwitchToUx() {
    document.querySelector('.top-mode-btn[data-topmode="ux"]').click();
}

async function termCmdStatus() {
    try {
        const cfg = await fetch('/api/config').then(r => r.json());
        if (!cfg.configured) {
            termWarn('Credentials fehlen. Im UX-Modus einrichten (Tab Spotify -> Settings).');
        } else if (cfg.connected) {
            termOk('Status: eingeloggt + Credentials OK.');
        } else {
            termInfo('Credentials OK, aber nicht eingeloggt. Tippe "connect".');
        }
    } catch (err) {
        termErr('Netzwerkfehler: ' + err.message);
    }
}

async function termCmdConnect() {
    termInfo('Oeffne Browser fuer Spotify-Login... (max. 5 Min)');
    try {
        const res  = await fetch('/api/spotify/connect', { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            termOk('Login erfolgreich.');
        } else {
            termErr('Fehler: ' + (data.error || 'unbekannt'));
        }
    } catch (err) {
        termErr('Netzwerkfehler: ' + err.message);
    }
}

async function termCmdMine() {
    try {
        const res  = await fetch('/api/spotify/my-playlists');
        const data = await res.json();
        if (!data.success) {
            termErr('Fehler: ' + (data.error || 'unbekannt'));
            termInfo('Tipp: erst "connect" ausfuehren.');
            return;
        }
        termPlaylists = data.playlists;
        if (termPlaylists.length === 0) {
            termWarn('Keine Playlists gefunden.');
            return;
        }
        termInfo(`Deine Playlists (${termPlaylists.length}):`);
        termPlaylists.forEach((p, i) => {
            const div = document.createElement('div');
            div.className = 'term-line';
            const num = document.createElement('span');
            num.className = 'term-num';
            num.textContent = '[' + (i + 1) + ']';
            const txt = document.createTextNode(
                ` ${p.Name}  (${p.TrackCount} Tracks)`);
            div.append(num, txt);
            termOutput.appendChild(div);
        });
    } catch (err) {
        termErr('Netzwerkfehler: ' + err.message);
    }
}

// Versteckter Power-User-Befehl: direkt eine Playlist aus der letzten 'mine'-
// Liste pruefen (ohne durch das spotify-Menue zu gehen).
async function termCmdPlay(arg) {
    const idx = parseInt(arg, 10) - 1;
    if (isNaN(idx) || idx < 0 || idx >= termPlaylists.length) {
        termErr(`Ungueltige Nummer. Erst "mine" ausfuehren, dann "play 1" bis "play ${termPlaylists.length || '?'}".`);
        return;
    }
    const pl = termPlaylists[idx];
    await termRunCheckById(pl.Id, pl.Name, false);
}

function termCmdCsv() {
    termInfo('Datei-Auswahl wird geoeffnet...');
    termPicker.value = '';   // Reset, damit gleiche Datei wieder triggert.
    termPicker.click();
}

termPicker.addEventListener('change', async () => {
    const file = termPicker.files[0];
    if (!file) return;
    termInfo(`Verarbeite "${file.name}"...`);
    try {
        const text = await file.text();
        const res  = await fetch('/api/check?album=0', {
            method:  'POST',
            headers: { 'Content-Type': 'text/csv; charset=utf-8' },
            body:    text
        });
        termRenderDuplicates(await res.json());
    } catch (err) {
        termErr('Netzwerkfehler: ' + err.message);
    }
});

// ---- CSV-Form ----
document.getElementById('csv-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const file  = document.getElementById('csv-file').files[0];
    const album = document.getElementById('csv-album').checked;
    if (!file) return showError('Bitte eine CSV-Datei waehlen.');

    showProcessing(`processing "${file.name}"...`);
    const text = await file.text();

    try {
        const res = await fetch(`/api/check?album=${album ? '1' : '0'}`, {
            method:  'POST',
            headers: { 'Content-Type': 'text/csv; charset=utf-8' },
            body:    text
        });
        renderResult(await res.json());
    } catch (err) {
        showError('Netzwerkfehler: ' + err.message);
    }
});

// ---- Spotify-Form ----
document.getElementById('spotify-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const url   = document.getElementById('spotify-url').value.trim();
    const album = document.getElementById('spotify-album').checked;
    if (!url) return showError('Bitte eine Playlist-URL oder ID angeben.');

    showProcessing('fetching playlist from spotify api...');

    try {
        const res = await fetch('/api/spotify', {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ url, album })
        });
        renderResult(await res.json());
    } catch (err) {
        showError('Netzwerkfehler: ' + err.message);
    }
});

// ---- Anzeige der Resultate ----
// context kann optional { ownedPlaylistId, ownedPlaylistName, album } enthalten.
// Falls gesetzt, blenden wir am Ende einen "Duplikate aus Playlist entfernen"
// Button ein (nur fuer eigene Spotify-Playlists, nicht fuer CSV oder Public URL).
function renderResult(data, context) {
    if (!data || !data.success) {
        return showError(data && data.error ? data.error : 'Unbekannter Fehler.');
    }

    if (data.duplicates.length === 0) {
        appendLine(`OK - ${data.total} Songs geprueft, keine Duplikate gefunden.`, 'success-line');
        return;
    }

    appendLine(
        `OK - ${data.total} Songs geprueft, ${data.duplicates.length} Duplikat-Gruppe(n) gefunden:`,
        'success-line'
    );

    // 3+ Vorkommen extra hervorheben - das ist meistens das interessanteste.
    const triples = data.duplicates.filter(d => d.Count >= 3);
    if (triples.length > 0) {
        const max = Math.max(...data.duplicates.map(d => d.Count));
        appendLine(`Davon ${triples.length} Song(s) mit 3+ Vorkommen (max. ${max} x).`, 'warn-line');
    }

    // Nach Anzahl absteigend sortieren -> 3x/4x oben.
    const sorted = [...data.duplicates].sort((a, b) => b.Count - a.Count);

    const out = document.getElementById('output');
    const table = document.createElement('table');
    table.innerHTML = `
        <thead><tr><th class="col-count">#x</th><th>Title</th><th>Artist</th><th>Album</th></tr></thead>
        <tbody></tbody>
    `;
    const tbody = table.querySelector('tbody');
    for (const d of sorted) {
        const tr = document.createElement('tr');
        // 3+ Treffer optisch markieren.
        if (d.Count >= 3) tr.classList.add('row-triple');
        // Count zuerst, mit eigener CSS-Klasse fuer kleine Spaltenbreite.
        const countCell = td(String(d.Count) + 'x');
        countCell.className = 'col-count';
        tr.appendChild(countCell);
        // textContent statt innerHTML -> kein XSS durch boese Songtitel.
        tr.appendChild(td(d.Title));
        tr.appendChild(td(d.Artist));
        tr.appendChild(td(d.Album || ''));
        tbody.appendChild(tr);
    }
    out.appendChild(table);

    // Bei eigenen Spotify-Playlists: Hinweis auf manuelles Loeschen einblenden,
    // da Spotify die Modify-API in Development Mode mit 403 sperrt.
    if (context && context.ownedPlaylistId) {
        const hint = document.createElement('p');
        hint.className = 'hint';
        hint.textContent = 'Hinweis: Duplikate manuell in der Spotify-App entfernen ' +
            '(Rechtsklick auf Song -> "Aus Playlist entfernen").';
        out.appendChild(hint);
    }
}

function td(text) {
    const cell = document.createElement('td');
    cell.textContent = text;
    return cell;
}

// ---- kleine Logging-Helfer ----
function clearOutput() {
    document.getElementById('output').innerHTML = '';
}
function appendLine(text, cls) {
    const line = document.createElement('div');
    line.className = `line ${cls}`;
    line.textContent = text;
    document.getElementById('output').appendChild(line);
}
function showProcessing(text) { clearOutput(); appendLine('> ' + text, 'info-line'); }
function showError(text)      { appendLine('ERR: ' + text, 'error-line'); }
