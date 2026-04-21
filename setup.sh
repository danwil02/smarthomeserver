#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Creating docker_data directories"
mkdir -p ~/docker_data/mosquitto/config
mkdir -p ~/docker_data/mosquitto/data
mkdir -p ~/docker_data/mosquitto/log
mkdir -p ~/docker_data/qbittorrent

echo "==> Creating config symlinks in docker_data"
ln -sf ~/smarthomeserver/configs/loki-config.yaml     ~/docker_data/loki-config.yaml
ln -sf ~/smarthomeserver/configs/promtail-config.yaml ~/docker_data/promtail-config.yaml
ln -sf ~/smarthomeserver/configs/telegraf.conf        ~/docker_data/telegraf.conf
ln -sf ~/smarthomeserver/configs/mosquitto.conf       ~/docker_data/mosquitto/config/mosquitto.conf
ln -sf ~/smarthomeserver/configs/qbittorrent.crt      ~/docker_data/qbittorrent/qbittorrent.crt
ln -sf ~/smarthomeserver/configs/qbittorrent.key      ~/docker_data/qbittorrent/qbittorrent.key

echo "==> Fixing n8n directory ownership (requires sudo)"
mkdir -p ~/docker_data/n8n
sudo chown -R 1000:1000 ~/docker_data/n8n

echo "==> Installing system packages"
sudo apt-get install -y \
  cockpit sscg samba smartmontools \
  gtop dstat neofetch fzf \
  tailscale python3-pip \
  mosquitto-clients dnsutils

echo "==> Creating .env.local from template (skipped if already exists)"
if [ ! -f .env.local ]; then
  cp .env .env.local
  echo "    Created .env.local — fill in all values before running start.sh"
else
  echo "    .env.local already exists — skipping"
fi

echo ""
echo "==> Setup complete. Next steps:"
echo "    1. Edit .env.local and populate all values (see README.md for reference)"
echo "    2. Run: ./start.sh"
echo "    3. Follow the Tailscale DNS steps in README.md"
