FROM telegraf:latest

COPY telegraf-exec-fronius /

RUN apt-get update && apt-get install -y smartmontools nvme-cli
