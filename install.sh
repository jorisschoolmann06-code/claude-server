#!/usr/bin/env bash
# Installiert bzw. aktualisiert Joris' Claude-Server neben JARVIS.
# Aufruf als root:  curl -fsSL https://raw.githubusercontent.com/jorisschoolmann06-code/claude-server/main/install.sh | bash
# JARVIS wird dabei nicht angefasst: eigener Ordner (/opt/claude-server) und eigenes Docker-Projekt.
set -euo pipefail

REPO="https://github.com/jorisschoolmann06-code/claude-server.git"
DIR=/opt/claude-server
say(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die(){ printf '\n\033[1;31mFEHLER: %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" = 0 ] || die "Bitte als root ausführen (vorher: sudo -i)"
command -v git >/dev/null || { apt-get update -qq && apt-get install -y -qq git; }
command -v docker >/dev/null || die "Docker ist nicht installiert"
docker compose version >/dev/null 2>&1 || die "Das Docker-Compose-Plugin fehlt (apt-get install docker-compose-plugin)"

say "Code holen"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull --ff-only; else git clone --depth 1 "$REPO" "$DIR"; fi
mkdir -p "$DIR/data/obsidian" "$DIR/data/tiktok" "$DIR/data/studip" "$DIR/data/work"
cd "$DIR"

IP=$(curl -4 -fsS --max-time 8 https://api.ipify.org || hostname -I | awk '{print $1}')

if [ ! -f .env ]; then
  say "Zugangsdaten erzeugen"
  TOKEN=$(openssl rand -hex 12)
  DAVPASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16)
  DOMAIN_DEFAULT="$(echo "$IP" | tr . -).sslip.io"
  SU=""; SP=""
  if [ -r /dev/tty ]; then
    printf '\nStud.IP-Benutzername (Uni-Account, Enter = später eintragen): ' > /dev/tty
    read -r SU < /dev/tty || true
    if [ -n "$SU" ]; then
      printf 'Stud.IP-Passwort (wird nicht angezeigt): ' > /dev/tty
      read -rs SP < /dev/tty || true; echo > /dev/tty
      case "$SP$SU" in *"'"*) echo "Hinweis: Zeichen ' wird nicht unterstützt – bitte später in $DIR/.env eintragen." > /dev/tty; SU=""; SP="";; esac
    fi
  fi
  umask 077
  cat > .env <<EOF
# Joris' Claude-Server – nur auf diesem Server gespeichert, nie im Git.
DOMAIN=${DOMAIN_DEFAULT}
BRIDGE_TOKEN=${TOKEN}
DAV_USER=joris
DAV_PASS=${DAVPASS}
STUDIP_USER='${SU}'
STUDIP_PASS='${SP}'
HTTP_PORT=80
HTTPS_PORT=443
EOF
  chmod 600 .env
fi
set -a; . ./.env; set +a

say "Bericht über den Server schreiben (für Claude, ohne Passwörter)"
{
  echo "Stand: $(date -Is)"; echo "IP: $IP"; uname -srm; grep -E '^(PRETTY_NAME)=' /etc/os-release || true
  echo; df -h / | tail -1; free -h | head -2
  echo; echo "# Docker-Container (nur Namen/Images/Ports)"; docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
  echo; echo "# Offene Ports"; ss -ltnH | awk '{print $4}' | sort -u
  echo; echo "# Firewall"; (ufw status 2>/dev/null | head -5) || echo "ufw nicht vorhanden"
} > data/host-report.txt 2>&1 || true

say "Ports 80/443 prüfen"
ours=$(docker ps --filter "label=com.docker.compose.project=claude-server" -q | wc -l)
for p in 80 443; do
  if ss -ltnH "sport = :$p" | grep -q . && [ "$ours" = 0 ]; then
    echo; echo "Port $p ist schon belegt (vermutlich JARVIS oder ein Webserver):"
    ss -ltnpH "sport = :$p" || true
    die "Port $p belegt – ich ändere nichts an JARVIS. Bitte Claude Bescheid geben, dann passen wir es an."
  fi
done
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; echo "ufw: 80/443 freigegeben"
fi

say "Container bauen und starten (beim ersten Mal 3–6 Minuten)"
docker compose up -d --build

say "Auf HTTPS-Zertifikat warten"
ok=0
for i in $(seq 1 40); do
  if curl -fsS --max-time 5 "https://${DOMAIN}/health" >/dev/null 2>&1; then ok=1; break; fi
  sleep 5
done

echo
echo "════════════════════════════════════════════════════════════════"
if [ "$ok" = 1 ]; then
  echo "  ✅ Claude-Server läuft"
else
  echo "  ⚠️  Container laufen, aber https://${DOMAIN} antwortet noch nicht."
  echo "     Häufigster Grund: Hetzner-Firewall blockiert Port 80/443."
  echo "     Log: docker compose -f $DIR/docker-compose.yml logs caddy | tail"
fi
echo
echo "  Connector-URL für Claude (Einstellungen → Connectors → eigenen hinzufügen):"
echo
echo "     https://${DOMAIN}/${BRIDGE_TOKEN}/mcp"
echo
echo "  Obsidian (Plugin „Remotely Save“, WebDAV):"
echo "     Adresse:  https://${DOMAIN}/dav/"
echo "     Benutzer: ${DAV_USER}"
echo "     Passwort: ${DAV_PASS}"
echo
echo "  Diese Angaben stehen auch in $DIR/.env  (anzeigen: cat $DIR/.env)"
echo "════════════════════════════════════════════════════════════════"
