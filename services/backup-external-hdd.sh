#!/usr/bin/env bash
# Mirrors /mnt/external_hdd (media + Time Machine) to the USB backup drive.
set -euo pipefail

SRC="/mnt/external_hdd"
DST="/mnt/backup_hdd"

if ! mountpoint -q "$SRC"; then
    echo "Source $SRC is not mounted, aborting" >&2
    exit 1
fi

if ! mountpoint -q "$DST"; then
    echo "Backup drive $DST is not mounted, aborting" >&2
    exit 1
fi

# Downloading/ is qBittorrent's in-flight staging area — partial/actively-written
# files, not backup-worthy state. Everything else (TV, Movies, Music, timemachine)
# is mirrored.
rsync -a --delete --stats --itemize-changes \
    --exclude 'Downloading/' \
    --exclude 'timemachine/' \
    "$SRC"/ "$DST"/

logger -t backup-external-hdd "Synced $SRC -> $DST"
