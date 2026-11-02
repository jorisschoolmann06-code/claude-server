# CLAUDE.md – claude-server

Eigener MCP-Server („Joris Server“) auf Joris' Hetzner-Server, dazu Datei-Sync, WebDAV und das Dashboard.
Antworten und Commit-Texte auf Deutsch.

## Architektur
- Server: Hetzner CX23 (Ubuntu 24.04), Code liegt in `/opt/claude-server`, Docker-Compose-Projekt `claude-server`.
- Container (siehe `docker-compose.yml`):
  - `bridge` – Python-MCP-Server (`bridge/server.py`, Paket `mcp` ≥ 2.3, Streamable HTTP, stateless, JSON-Antworten). Alle Tools sind hier.
  - `webdav` – rclone WebDAV für `/data/obsidian` unter `/dav/`.
  - `syncthing` – Datei-Sync, Ordner-ID `joris-ablage` („Server-Ablage“) ↔ `/data/sync`.
  - `caddy` – HTTPS (Let's Encrypt) und Weiterleitung, siehe `Caddyfile`.
- Daten liegen unter `./data` (im Container `/data`), nie im Repo.
- `.env` (nicht im Repo) enthält Domain, Bridge-Token, WebDAV-Zugang usw.
- Zugangsdaten, die Joris über die Einrichtungsseite `/{TOKEN}/setup` einträgt, liegen in `/data/.secrets.json` (chmod 600). `secret(name)` liest erst dort, dann aus der Umgebung.

## Deploy
- Push auf `main` reicht: der systemd-Timer `claude-server-deploy.timer` macht alle 5 Minuten `git pull` (`deploy/auto-deploy.sh`) und startet Container neu, wenn sich Container-Dateien geändert haben.
- Nur Python-Änderungen an `bridge/`: Tool `self_update` aufrufen (git pull + Neustart der Bridge).
- `bridge/entrypoint.sh` zieht beim Start den aktuellen Stand und installiert `bridge/requirements.txt`.

## Regeln (wichtig)
- **JARVIS niemals verändern.** JARVIS läuft als eigene systemd-Dienste auf dem Host (127.0.0.1:8787). Nur eigene Container daneben.
- Port 443 ist auf der Tailscale-IP belegt → Caddy bindet nur an die öffentliche IP (`BIND_IP`).
- Keine Zugangsdaten auslesen oder ausgeben; `.secrets.json` ist für `files_read`/`files_write` gesperrt.
- Datei-Tools dürfen nur unter `/data` arbeiten.
- Mail-Tools (`gmx_*`) lesen und verschieben nur, nie endgültig löschen, nie senden.
- Fehler, die der Nutzer sehen soll, als `ToolError` werfen.
- Neue Tools mit klarer deutscher Beschreibung (die sieht Claude als Tool-Doku).
- Connector-URL bzw. Token nie in Code, README oder Commits schreiben.

## Tools (Überblick)
server_status, files_list/read/write/move/delete, shell, http_fetch, browser_open/screenshot/script/download/login,
studip_login, pdf_text, sync_status, sync_add_device, gmx_accounts/folders/list/read/move/create_folder/overview,
jobs_list/set/remove/log/run_now (eigener Cron, Europe/Berlin), self_update,
wetter (Open-Meteo), oepnv_verbindung / oepnv_abfahrten (Transitous, VBN-Fahrplan). Gespeicherte Orte (zuhause, uni …) liegen in `/data/dashboard/orte.json`, nie im Repo.

## Kurzbefehl-Zugang (iPhone)
- `POST /q/todo` (Text oder JSON `{text, faellig?, bereich?}`) legt ein To-do in `dashboard/todos.json` an, `GET /q/todo` liefert offene To-dos als Text.
- Header `X-Key` = Inhalt von `/data/.quick_key` (chmod 600, für Datei-Tools gesperrt). Max. 30 Anfragen/Minute. Kann nichts anderes.

## Dashboard (`apps/dashboard/index.html`)
- iPhone-first, iOS-Design (Large Titles, Inset-Grouped-Listen, Tab-Leiste, System-Farben, hell/dunkel).
- Läuft derzeit als Claude-Artefakt „Joris · Dashboard“ mit der `mcp`-Fähigkeit (Joris Server, Google Calendar, Gmail).
- Datenbausteine auf dem Server unter `/data/dashboard/`:
  - `briefing.json` – `{datum, zusammenfassung, punkte[], wichtig}` (schreibt der Morgen-Überblick)
  - `todos.json` – `{todos:[{id, text, bereich, erledigt, faellig?}]}` (abhaken im Dashboard per `files_write`)
  - `status.json` – Projekte, Business-Ideen, Fahrplan, Automatisierungen
  - `uni.json` – Kurse, Fristen, Neues auf Stud.IP (schreibt der Studium-Wochenabschluss)
  - `fitness.json` – Ziele, `heute` (Protein/kcal), Gewichtsverlauf
- Geplant: als eigene Web-App (PWA) direkt vom Server ausliefern, dann mit eigenen API-Routen in der Bridge statt über Claude-Connectoren.
