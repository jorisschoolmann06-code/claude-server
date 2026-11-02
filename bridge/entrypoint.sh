#!/bin/sh
# Startet die Bridge immer mit dem aktuellen Code aus /app (= /opt/claude-server auf dem Host).
git config --global --add safe.directory /app >/dev/null 2>&1 || true
git -C /app pull --ff-only >/dev/null 2>&1 || echo "git pull nicht möglich – starte mit vorhandenem Code"
pip install -q -r /app/bridge/requirements.txt || true
mkdir -p /data/work
exec python /app/bridge/server.py
