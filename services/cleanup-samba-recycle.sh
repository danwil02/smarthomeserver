#!/usr/bin/env bash
# Purges files older than 30 days from the Samba [Media] share's recycle bin
# (vfs_recycle, see configs/smb.conf). recycle:touch=yes keeps each file's
# mtime set to when it was deleted, so -mtime here measures time-in-bin.
set -euo pipefail

RECYCLE_DIR="/mnt/external_hdd/.recycle"
RETENTION_DAYS=30

if ! mountpoint -q /mnt/external_hdd; then
    echo "external_hdd is not mounted, aborting" >&2
    exit 1
fi

if [ ! -d "$RECYCLE_DIR" ]; then
    echo "No recycle bin at $RECYCLE_DIR yet, nothing to clean"
    exit 0
fi

logger -t cleanup-samba-recycle "Purging files older than ${RETENTION_DAYS}d from $RECYCLE_DIR"
deleted=$(find "$RECYCLE_DIR" -mindepth 1 -type f -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
find "$RECYCLE_DIR" -mindepth 1 -type d -empty -delete
logger -t cleanup-samba-recycle "Purged ${deleted} file(s) older than ${RETENTION_DAYS}d from $RECYCLE_DIR"
