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
IP=$(curl -4 -fsS --max-time 8 https://api.ipify.org || hostname -I | awk '{print $1}')
# Port gilt nur als belegt, wenn er auf allen Adressen oder auf der öffentlichen IP lauscht
# (Tailscale auf 100.x stört nicht, weil wir nur an die öffentliche IP binden).
busy(){ ss -ltnH "sport = :$1" | awk '{print $4}' | grep -Eq "^(0\.0\.0\.0|\*|\[::\]|${IP//./\\.}):$1\$"; }

# Bericht über den Server (vor allem anderen, damit Claude ihn sehen kann – ohne Passwörter)
report(){
  echo "Stand: $(date -Is)"; uname -srm; grep -E '^PRETTY_NAME=' /etc/os-release || true
  echo; df -h / | tail -1; free -h | head -2
  echo; echo "# Docker"; (docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || echo "kein Docker")
  echo; echo "# Offene Ports (Prozess)"; ss -ltnpH | awk '{print $4, $6}' | sed 's/users:((//; s/,pid.*//' | sort -u
  echo; echo "# Dienste"; systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}' | grep -Ev '^(systemd|dbus|getty|serial|ssh|cron|rsyslog|polkit|udisks|multipathd|networkd|qemu|unattended|user@)' | head -40
  echo; echo "# Firewall"; (ufw status 2>/dev/null | head -8) || echo "ufw nicht vorhanden"
}

if ! command -v docker >/dev/null; then
  for p in 80 443; do
    if busy "$p"; then
      echo; echo "Port $p ist schon belegt:"; ss -ltnpH "sport = :$p" | awk '{print $4, $6}'
      echo; report
      die "Port $p belegt – ich installiere noch nichts. Bitte Claude ein Foto von diesem Bildschirm schicken."
    fi
  done
fi
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  echo
  echo "Docker (inkl. Compose) ist auf diesem Server noch nicht installiert."
  echo "Ich würde die Ubuntu-Pakete docker.io und docker-compose-v2 installieren."
  echo "JARVIS wird dabei nicht verändert."
  ans="n"
  if [ -r /dev/tty ]; then printf 'Docker jetzt installieren? (j/n): ' > /dev/tty; read -r ans < /dev/tty || true; fi
  case "$ans" in j|J|y|Y|ja|Ja) ;; *) die "Abgebrochen – ohne Docker kann der Claude-Server nicht laufen";; esac
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-compose-v2
  systemctl enable --now docker
fi

say "Code holen"
if [ -d "$DIR/.git" ]; then
  git -C "$DIR" pull --ff-only
else
  rm -rf "$DIR.tmp"; git clone --depth 1 "$REPO" "$DIR.tmp"
  mkdir -p "$DIR"; cp -a "$DIR.tmp/." "$DIR/"; rm -rf "$DIR.tmp"
fi
mkdir -p "$DIR/data/obsidian" "$DIR/data/tiktok" "$DIR/data/studip" "$DIR/data/work"
cd "$DIR"

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
BIND_IP=${IP}
HTTP_PORT=80
HTTPS_PORT=443
EOF
  chmod 600 .env
fi
grep -q '^BIND_IP=' .env || echo "BIND_IP=${IP}" >> .env
set -a; . ./.env; set +a

say "Bericht über den Server schreiben (für Claude, ohne Passwörter)"
report > data/host-report.txt 2>&1 || true

say "Ports 80/443 prüfen"
ours=$(docker ps --filter "label=com.docker.compose.project=claude-server" -q | wc -l)
for p in 80 443; do
  if busy "$p" && [ "$ours" = 0 ]; then
    echo; echo "Port $p ist schon belegt (vermutlich JARVIS oder ein Webserver):"
    ss -ltnpH "sport = :$p" | awk '{print $4, $6}' || true
    die "Port $p belegt – ich ändere nichts an JARVIS. Bitte Claude Bescheid geben, dann passen wir es an."
  fi
done
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; echo "ufw: 80/443 freigegeben"
fi

say "Container bauen und starten (beim ersten Mal 3–6 Minuten)"
mkdir -p data/logs data/sync data/syncthing
docker compose up -d --build --remove-orphans
cat docker-compose.yml Caddyfile bridge/Dockerfile bridge/entrypoint.sh deploy/auto-deploy.sh | sha256sum | cut -c1-16 > data/.deployed

say "Automatische Updates einrichten (alle 5 Minuten aus GitHub)"
cat > /etc/systemd/system/claude-server-deploy.service <<UNIT
[Unit]
Description=Claude-Server: Updates aus GitHub einspielen
[Service]
Type=oneshot
ExecStart=/opt/claude-server/deploy/auto-deploy.sh
UNIT
cat > /etc/systemd/system/claude-server-deploy.timer <<UNIT
[Unit]
Description=Claude-Server: alle 5 Minuten nach Updates schauen
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now claude-server-deploy.timer >/dev/null

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
