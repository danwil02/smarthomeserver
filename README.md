# smarthomeserver

Home lab stack running on a Dell OptiPlex (Ubuntu), with 6TB storage at `/mnt/external_hdd`.
All services are reachable from any Tailscale device without port forwarding.

---

## Quick start

```bash
./setup.sh        # create dirs, symlinks, install packages, copy .env template
# edit .env.local — fill in all values (see reference below)
./start.sh        # bring up all stacks in order
```

To stop or restart:
```bash
./stop.sh
./restart.sh
```

---

## .env.local reference

| Variable | Description |
|---|---|
| `DATADIR` | Fast local storage for container configs (default: `~/docker_data`) |
| `LOCAL_IP` | Server's LAN IP |
| `TAILSCALE_IP` | Server's Tailscale IP — run `tailscale ip -4` |
| `TZ` | Timezone e.g. `Australia/Adelaide` |
| `PUID` / `PGID` | Host user/group ID (run `id` to find yours) |
| `LOKI_URL` | Auto-derived: `http://${LOCAL_IP}:3100/loki/api/v1/push` |
| `INFLUXDB_TOKEN` | InfluxDB read/write token (generate in InfluxDB UI) |
| `MQTT_USER` / `MQTT_PASSWORD` | Mosquitto credentials (see Mosquitto setup below) |
| `OPENWEATHERMAP_API_KEY` | Used by Telegraf for weather metrics |
| `N8N_DB_PASSWORD` | Postgres password for n8n |
| `N8N_ENCRYPTION_KEY` | n8n secrets encryption key (generate once, never change) |

---

## Stack layout

Stacks start in this order — monitoring must be first so the Loki log driver is ready:

| File | Services |
|---|---|
| `docker-compose.infra.yml` | Traefik, dnsmasq, Portainer, Watchtower, Samba |
| `docker-compose.monitoring.yml` | Loki, Promtail, Grafana, InfluxDB, Telegraf |
| `docker-compose.home.yml` | Home Assistant, Homebridge, Mosquitto, Node-RED |
| `docker-compose.media.yml` | Plex, qBittorrent |
| `docker-compose.apps.yml` | n8n, PostgreSQL, Heimdall, Duplicati, Webtop |

---

## Service ports

| Service | Port | Notes |
|---|---|---|
| Traefik | 80 (proxy), 8081 (dashboard) | Routes `*.lab` hostnames |
| Grafana | 3000 | |
| InfluxDB | 8086 | |
| Home Assistant | 8123 | Pinned — do not auto-update |
| Homebridge | 8581 | host network |
| Mosquitto | 1883 | |
| Node-RED | 1880 | |
| Plex | 32400 | host network |
| qBittorrent | 8080 | |
| n8n | 5678 | |
| Portainer | 9444 | |
| Heimdall | 9080 | |
| Duplicati | 8200 | |
| Webtop | 3001 | |
| Loki | 3100 | |
| dnsmasq | 53 | |

---

## Tailscale split DNS (*.lab from any device)

Allows `n8n.lab`, `grafana.lab` etc. to resolve from any Tailnet device.
`start.sh` detects and reminds you if this is not yet configured.

**One-time setup in Tailscale admin:**

1. Go to https://login.tailscale.com/admin/dns
2. **Nameservers → Add nameserver → Custom**
3. Nameserver: your server's Tailscale IP (`tailscale ip -4`)
4. Check **Restrict to domain** → enter `lab`
5. Save

Verify from any Tailnet device:
```bash
dig +short n8n.lab   # should return the server's Tailscale IP
```

---

## Mosquitto — set password

Run once after first start, or when adding a new MQTT user:

```bash
docker compose -f docker-compose.home.yml exec mosquitto \
  mosquitto_passwd -b /mosquitto/config/password.txt <username> <password>
docker compose -f docker-compose.home.yml restart mosquitto
```

Update `MQTT_USER` / `MQTT_PASSWORD` in `.env.local` to match, then `./restart.sh`.

---

## Important caveats

**Home Assistant** — pinned to a specific image tag. Do not change to `latest` and
do not let Watchtower update it (label `com.centurylinklabs.watchtower.enable=false`
is set). Update manually after reading the HA release notes.

**Plex claim token** — `PLEX_CLAIM` in `.env.local` expires 4 minutes after generation.
Get a fresh token at https://plex.tv/claim immediately before first start.
After the server is registered the token is no longer used.

**Telegraf** — uses a custom-built image (`telegraf_fronius`) built from
`./telegraf-exec-fronius/Dockerfile`. Do not replace with the stock `telegraf` image.

**n8n** — capped at 1 CPU and 512MB RAM. Increase in `docker-compose.apps.yml` if
running heavy workflows.

**Host-networked services** (Plex, Homebridge, Samba) cannot be proxied by container
name in Traefik. They are routed via `172.17.0.1` in `configs/traefik/dynamic.yml`.

---

## Network architecture

All bridge-networked containers share the external `homelab` Docker network (created
once by `start.sh`). Services find each other by container/service name.

Exceptions using `network_mode: host` (needed for mDNS / broadcast discovery):
- Plex, Homebridge, Samba
