#!/usr/bin/env bash
# Läuft alle 5 Minuten auf dem Host (systemd-Timer). Holt Änderungen aus GitHub und
# startet die Container nur dann neu, wenn sich die Container-Definition geändert hat.
# Fasst nur /opt/claude-server an – JARVIS bleibt unberührt.
set -euo pipefail
cd /opt/claude-server
git pull -q --ff-only || true
sum=$(cat docker-compose.yml Caddyfile bridge/Dockerfile bridge/entrypoint.sh deploy/auto-deploy.sh 2>/dev/null | sha256sum | cut -c1-16)
last=$(cat data/.deployed 2>/dev/null || true)
if [ "$sum" != "$last" ]; then
  echo "$(date -Is) Änderung erkannt – docker compose up" >> data/logs/deploy.log
  docker compose up -d --build --remove-orphans >> data/logs/deploy.log 2>&1
  echo "$sum" > data/.deployed
fi
