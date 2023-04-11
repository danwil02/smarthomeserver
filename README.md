# Basic setup

```bash
cd ~
mkdir -p docker_data
mkdir -p docker_data/mosquitto/config

ln -s ~/smarthomeserver/configs/loki-config.yaml ~/docker_data/loki-config.yaml
ln -s ~/smarthomeserver/configs/telegraf.conf ~/docker_data/telegraf.conf
ln -s ~/smarthomeserver/configs/mosquitto.conf ~/docker_data/mosquitto/config/mosquitto.conf
```

Make sure to create a .env.local file with keys populated
Then run:
```bash
source .env.local
docker compose build
docker compose up
```

# Mosquitto Set Password

```bash
docker-compose exec mosquitto mosquitto_passwd -b /mosquitto/config/password.txt user password
docker-compose restart
```
