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
| `AUTHELIA_SESSION_SECRET` / `AUTHELIA_STORAGE_ENCRYPTION_KEY` / `AUTHELIA_OIDC_HMAC_SECRET` / `AUTHELIA_RESET_PASSWORD_JWT_SECRET` | SSO secrets — `openssl rand -hex 32` each |
| `GRAFANA_OIDC_CLIENT_SECRET` | Grafana's SSO client secret (plaintext here; the hash Authelia checks against lives in `configs/authelia/configuration.yml`) |

---

## Stack layout

Stacks start in this order — auth must be up before anything that depends on it for
SSO, monitoring must be up before the Loki log driver is needed:

| File | Services |
|---|---|
| `docker-compose.infra.yml` | Traefik, dnsmasq, Portainer, Watchtower, Samba |
| `docker-compose.auth.yml` | Authelia, Redis (session store) — SSO |
| `docker-compose.monitoring.yml` | Loki, Promtail, Grafana, InfluxDB, Telegraf |
| `docker-compose.home.yml` | Home Assistant, Homebridge, Mosquitto, Node-RED |
| `docker-compose.media.yml` | Plex, Jellyfin, qBittorrent, and the rest of the *arr stack |
| `docker-compose.apps.yml` | n8n, PostgreSQL, Heimdall, Duplicati, Webtop |

---

## Service ports

| Service | Port | Notes |
|---|---|---|
| Traefik | 80 (proxy), 8081 (dashboard) | Routes `*.lab`/`*.svc.lab` hostnames |
| Authelia | — | No published host port — reached only via Traefik/internal network |
| Grafana | 3000 | grafana.lab |
| InfluxDB | 8086 | influx.svc.lab (SSO-gated) |
| Home Assistant | 8123 | homeassistant.lab — pinned, do not auto-update, not SSO-gated |
| Homebridge | 8581 | host network |
| Mosquitto | 1883 | |
| Node-RED | 1880 | node-red.svc.lab (SSO-gated) |
| Plex | 32400 | host network, plex.lab, not SSO-gated |
| Jellyfin | 8096 | jellyfin.lab, not SSO-gated |
| qBittorrent | 8080 | qbittorrent.svc.lab (SSO-gated) |
| n8n | 5678 | n8n.svc.lab (SSO-gated editor UI; `/webhook*` bypasses SSO) |
| Portainer | 9444 | portainer.svc.lab (SSO-gated) |
| Heimdall | 9080 | heimdall.svc.lab (SSO-gated) |
| Duplicati | 8200 | duplicati.svc.lab (SSO-gated) |
| Webtop | 3001 | not currently deployed |
| Loki | 3100 | |
| dnsmasq | 53 | |

---

## Tailscale split DNS (*.lab from any device)

Allows `grafana.lab`, `heimdall.svc.lab` etc. to resolve from any Tailnet device — the
wildcard covers both the plain `.lab` and two-label `.svc.lab` (SSO-gated) hostnames.
`start.sh` detects and reminds you if this is not yet configured.

**One-time setup in Tailscale admin:**

1. Go to https://login.tailscale.com/admin/dns
2. **Nameservers → Add nameserver → Custom**
3. Nameserver: your server's Tailscale IP (`tailscale ip -4`)
4. Check **Restrict to domain** → enter `lab`
5. Save

Verify from any Tailnet device:
```bash
dig +short grafana.lab       # should return the server's Tailscale IP
dig +short heimdall.svc.lab  # two-label subdomains resolve the same way
```

---

## HTTPS / TLS (internal CA)

Every `*.lab` service is served over HTTPS (HTTP requests to `:80` redirect to `:443`
automatically). Trust comes from a private root CA generated for this homelab — not a
public CA — so each personal device needs that root CA installed once. After that,
every current *and future* `.lab` service is trusted automatically; no per-service
install is needed.

Cert files live in `configs/traefik/certs/` (gitignored — `ca.key`/`lab.key` never
leave the server):
- `ca.crt` / `ca.key` — root CA, 10-year validity. Install `ca.crt` on your devices once.
- `lab.crt` / `lab.key` — leaf cert Traefik actually presents, 825-day validity
  (expires 2028-11-28), lists every `.lab` hostname explicitly (not a real wildcard — see below).

### Adding a new service

The cert has no true wildcard — `*.lab` is rejected by OpenSSL/browsers as too broad
for a single-label domain (treated the same as `*.com` would be). Any new `.lab`
Traefik router needs its hostname added to the cert:

```bash
./configs/traefik/regen-cert.sh
docker compose --env-file .env.local -f docker-compose.infra.yml restart traefik
```

The script re-scans all compose files + `dynamic.yml` for `.lab` hostnames and reissues
`lab.crt` automatically — no manual hostname list to maintain. No action needed on any
client device; they already trust the CA that signs the new cert.

View what's currently covered:
```bash
openssl x509 -in configs/traefik/certs/lab.crt -noout -ext subjectAltName
```

### Installing the root CA on your devices (one-time per device)

First, get **`ca.crt` only** onto the device — never serve the whole `certs/`
directory, it also contains `ca.key`/`lab.key`. Copy just the one file into an
isolated folder before serving it:
```bash
mkdir -p /tmp/ca-export && cp ~/smarthomeserver/configs/traefik/certs/ca.crt /tmp/ca-export/
cd /tmp/ca-export && python3 -m http.server 8765
```
Then, from the device's browser, go to `http://<TAILSCALE_IP>:8765/ca.crt` and download
it. Stop the server (`Ctrl+C`) once every device is done — it's an unauthenticated file
server for as long as it's running.

**macOS (Terminal — recommended):** the Keychain Access double-click flow is prone to
a cryptic `Error: -25294` if you're not careful (easy to click the wrong file, or the
GUI import just fails for no clear reason). The `security` CLI does the import *and*
sets "Always Trust" in one step, reliably:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/ca.crt
```
Enter your Mac password when prompted. Verify it landed:
```bash
security find-certificate -c "smarthomeserver Local CA" /Library/Keychains/System.keychain
```

**macOS (Keychain Access GUI — alternative):** if you prefer the GUI, double-check
you're importing **`ca.crt`**, not `lab.crt` — Keychain Access will show the cert's
name as **smarthomeserver Local CA**; if it instead shows **smarthomeserver.lab**,
you grabbed the wrong file (that's the leaf cert, not the root).
1. Double-click `ca.crt` — Keychain Access opens and imports it (login keychain).
2. Find **smarthomeserver Local CA**, double-click it.
3. Expand **Trust**, set **When using this certificate** to **Always Trust**.
4. Close the dialog and enter your Mac password to confirm.

Firefox uses its own trust store on both platforms, not the system one — if you use
it, also import via Settings → Privacy & Security → Certificates → View Certificates →
Authorities → Import.

**iOS:**
1. In Safari, go to `http://<TAILSCALE_IP>:8765/ca.crt` — iOS prompts to download a
   configuration profile. Allow it.
2. Go to **Settings → General → VPN & Device Management**, tap the downloaded profile,
   **Install** (enter passcode), **Install** again to confirm.
3. **Required extra step** (easy to miss): go to **Settings → General → About →
   Certificate Trust Settings**, and toggle **full trust** on for
   **smarthomeserver Local CA**. Installing the profile alone is not enough — iOS
   keeps new root CAs untrusted for websites until this is switched on.

---

## SSO (Authelia)

Most admin UIs share one login, via passkey — no password to type day-to-day. A handful
of services are deliberately left out (see below) because they have their own native
apps that a login gate would break.

**Why some services are on `X.svc.lab` and others stayed on `X.lab`:** sharing one login
across services needs one session cookie, and cookie domains need at least two labels —
`lab` alone isn't valid for that (same underlying reason the TLS wildcard cert above
needed real hostnames instead of `*.lab`). Only the services actually behind the SSO
gate moved to a `service.svc.lab` hostname; nothing else changed and no DNS
reconfiguration was needed (the existing `*.lab` wildcard in dnsmasq/Tailscale already
covers two-label subdomains too).

**Not SSO-gated, on purpose:** Plex, Jellyfin, and Home Assistant all have native
mobile/TV/companion apps that log in with their own tokens, not through a browser — an
SSO gate would lock those apps out with no way to complete the login. They keep their
own separate logins, unchanged. **Grafana** is also not behind the gate, but for a
different reason: it talks to Authelia directly (native SSO login button), rather than
sitting behind the same checkpoint as everything else.

### First-time passkey setup

1. Go to `https://auth.svc.lab` directly, or just visit any SSO-gated service
   (e.g. `heimdall.svc.lab`) — you'll be redirected there automatically.
2. Register your passkey when prompted (Face ID / Touch ID / security key, depending on
   your device).
3. You're now logged in across every SSO-gated service — no separate login per service,
   and no re-prompt until the session expires (8 hours, or 30 days if you use "remember
   me").

There's no backup recovery code configured (a deliberate choice) — if the device holding
your passkey is ever lost, direct server access is the only way back in. Using a passkey
that syncs across your own devices (e.g. iCloud Keychain) avoids this being a
single-device risk.

### Signing into Grafana with SSO

Grafana keeps its own local login as a fallback (`grafana.lab`, "Sign in" in the
corner) alongside a **"Sign in with Authelia"** option. If you're already logged in via
SSO elsewhere, that button logs you in with no extra prompt. Note: authentication and
permissions are separate — your SSO login only grants Grafana **Admin** if your Authelia
account is in the `admins` group (`configs/authelia/users_database.yml`); everyone else
lands as Viewer.

### Adding a new service to the SSO gate

```bash
# 1. Rename its Host() rule to <name>.svc.lab, and add the auth middleware label:
#      traefik.http.routers.<name>.middlewares=authelia@file
# 2. Regenerate the TLS cert for the new hostname (same as any new service):
./configs/traefik/regen-cert.sh
docker compose --env-file .env.local -f docker-compose.infra.yml restart traefik
# 3. Recreate the service so its new labels take effect:
docker compose --env-file .env.local -f <its-compose-file>.yml up -d <service>
```

Before gating a service, check whether it has its own native mobile/TV/desktop app that
logs in independently of a browser (like Plex/Jellyfin/Home Assistant) — if so, it
probably shouldn't go behind the SSO gate at all.

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
