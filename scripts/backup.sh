#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/halo-ops"
BACKUP_ROOT="${BASE_DIR}/backups"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
DEST="${BACKUP_ROOT}/${STAMP}"

mkdir -p "${DEST}"
chmod 700 "${DEST}"

cd "${BASE_DIR}"

echo "[$(date '+%F %T')] backup start: ${DEST}"

# PostgreSQL logical backup, custom format for pg_restore.
docker compose exec -T halodb pg_dump -U halo -d halo -Fc > "${DEST}/halo-db.dump"

# Halo state: attachments, themes, plugins, keys. Logs are excluded.
tar -czf "${DEST}/halo-data.tar.gz" \
  --exclude='halo/logs' \
  -C "${BASE_DIR}/data" halo

sha256sum "${DEST}/halo-db.dump" "${DEST}/halo-data.tar.gz" > "${DEST}/SHA256SUMS"

cat > "${DEST}/metadata.txt" <<EOF
backup_time=${STAMP}
host=$(hostname)
halo_image=$(docker inspect --format '{{.Config.Image}}' halo-ops-halo-1)
postgres_image=$(docker inspect --format '{{.Config.Image}}' halo-ops-halodb-1)
db_backup_size=$(du -h "${DEST}/halo-db.dump" | awk '{print $1}')
data_backup_size=$(du -h "${DEST}/halo-data.tar.gz" | awk '{print $1}')
EOF

echo "[$(date '+%F %T')] backup done: ${DEST}"
du -sh "${DEST}"
