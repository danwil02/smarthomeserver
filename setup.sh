#!/bin/bash

cd ~
mkdir -p docker_data
mkdir -p docker_data/mosquitto/config

ln -s ~/smarthomeserver/loki-config.yaml ~/docker_data/loki-config.yaml
ln -s ~/smarthomeserver/telegraf.conf ~/docker_data/telegraf.conf
ln -s ~/smarthomeserver/mosquitto.conf ~/docker_data/mosquitto/config/mosquitto.conf

echo
echo Make sure to create a .env.locl file with keys populated
echo Then run:
echo source .env.local
echo docker compose --env-file .env.local up -d
echo
