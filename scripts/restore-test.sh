#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/halo-ops"
BACKUP_DIR="${1:?usage: restore-test.sh /opt/halo-ops/backups/<timestamp>}"
TEST_DB="halo_restore_test_$(date +%s)"

cd "${BASE_DIR}"

echo "[$(date '+%F %T')] restore test start"
echo "backup: ${BACKUP_DIR}"
echo "test_db: ${TEST_DB}"

docker compose exec -T halodb psql -U halo -d postgres -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE ${TEST_DB};"

docker compose exec -T halodb pg_restore -U halo -d "${TEST_DB}" \
  --no-owner --no-privileges < "${BACKUP_DIR}/halo-db.dump"

TABLE_COUNT="$(docker compose exec -T halodb psql -U halo -d "${TEST_DB}" -Atc \
  "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';")"

echo "restored_public_tables=${TABLE_COUNT}"

tar -tzf "${BACKUP_DIR}/halo-data.tar.gz" | head -n 10

docker compose exec -T halodb psql -U halo -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE ${TEST_DB};"

echo "[$(date '+%F %T')] restore test done"
