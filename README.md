# claude-server

Joris' persönlicher Claude-Server auf Hetzner – läuft **getrennt neben JARVIS** (eigener Ordner `/opt/claude-server`, eigenes Docker-Projekt `claude-server`). JARVIS wird nie verändert.

## Was drin ist
| Dienst | Zweck |
|---|---|
| `bridge` | MCP-Server (Connector für Claude): headless Browser mit dauerhaftem Profil, Dateien unter `/data`, Shell im Container, Zeitpläne (Cron), Selbst-Update |
| `webdav` | WebDAV für den Obsidian-Vault (`/data/obsidian`) – Sync über das Obsidian-Plugin „Remotely Save“ auf Mac, iPhone und PC |
| `caddy` | HTTPS (Let's Encrypt) auf `<IP>.sslip.io` |

## Installation / Update (als root auf dem Server)
```bash
curl -fsSL https://raw.githubusercontent.com/jorisschoolmann06-code/claude-server/main/install.sh | bash
```
Am Ende stehen Connector-URL und WebDAV-Zugang. Geheimnisse liegen nur in `/opt/claude-server/.env` (nie im Git).

## Sicherheit
- Die Connector-URL enthält einen geheimen Schlüssel – nicht teilen.
- Tools arbeiten nur im Container und unter `/data`; kein Docker-Socket, kein Zugriff auf den Host oder JARVIS.
- Zugangsdaten (z. B. Stud.IP) trägt Joris selbst in `.env` ein; Claude sieht sie nie.
