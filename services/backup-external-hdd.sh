#!/usr/bin/env bash
# Mirrors /mnt/external_hdd (media + Time Machine) to the USB backup drive.
set -euo pipefail

SRC_EXT_HDD="/mnt/external_hdd"
SRC_HOME_WILL="/home/will"

DST="/mnt/backup_hdd"
DST_EXT_HDD="$DST/backup-external_hdd"
DST_HOME_WILL="$DST/backup-home_will"

if ! mountpoint -q "$SRC_EXT_HDD"; then
    echo "Source $SRC_EXT_HDD is not mounted, aborting" >&2
    exit 1
fi

if ! mountpoint -q "$DST"; then
    echo "Backup drive $DST is not mounted, aborting" >&2
    exit 1
fi

mkdir -p "$DST_EXT_HDD"
mkdir -p "$DST_HOME_WILL"

logger -t backup-external-hdd "Syncing $SRC_EXT_HDD -> $DST_EXT_HDD"
ext_status=0
rsync -a --delete --stats --itemize-changes \
    --exclude 'Downloading/' \
    --exclude 'timemachine/' \
    --exclude 'WpSystem/' \
    "$SRC_EXT_HDD"/ "$DST_EXT_HDD"/ || ext_status=$?
logger -t backup-external-hdd "Syncing $SRC_EXT_HDD -> $DST_EXT_HDD done (exit $ext_status)"

logger -t backup-external-hdd "Syncing $SRC_HOME_WILL -> $DST_HOME_WILL"
home_status=0
rsync -a --delete --stats --itemize-changes \
    --exclude '.vscode-server/' \
    --exclude '.cache/' \
    --exclude 'go/' \
    "$SRC_HOME_WILL"/ "$DST_HOME_WILL"/ || home_status=$?
logger -t backup-external-hdd "Syncing $SRC_HOME_WILL -> $DST_HOME_WILL done (exit $home_status)"

logger -t backup-external-hdd "Completed syncing  $SRC_HOME_WILL -> $DST_HOME_WILL and $SRC_EXT_HDD -> $DST_EXT_HDD"

if (( ext_status != 0 || home_status != 0 )); then
    logger -t backup-external-hdd "One or more syncs failed (ext=$ext_status, home=$home_status)"
    exit 1
fi
