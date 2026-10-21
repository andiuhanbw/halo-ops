#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="/opt/halo-ops"
RELEASE_DIR="${1:?usage: deploy.sh <release-dir>}"
BACKUP_DIR="${BASE_DIR}/.deploy/backups/$(date +%Y%m%d_%H%M%S)"
FILES=(compose.yaml nginx/default.conf)

cd "${BASE_DIR}"
mkdir -p "${BACKUP_DIR}"

for f in "${FILES[@]}"; do
  if [[ -f "${f}" ]]; then
    mkdir -p "${BACKUP_DIR}/$(dirname "${f}")"
    cp -a "${f}" "${BACKUP_DIR}/${f}"
  fi
done

restore() {
  echo "deploy failed; restoring previous files"
  for f in "${FILES[@]}"; do
    if [[ -f "${BACKUP_DIR}/${f}" ]]; then
      mkdir -p "$(dirname "${f}")"
      cp -a "${BACKUP_DIR}/${f}" "${f}"
    fi
  done
  docker compose up -d || true
  docker compose exec -T nginx nginx -s reload || true
}

trap 'restore; exit 1' ERR

for f in "${FILES[@]}"; do
  mkdir -p "$(dirname "${f}")"
  cp -a "${RELEASE_DIR}/${f}" "${f}"
done

docker compose config -q
docker compose pull
docker compose up -d

# Nginx config is bind-mounted; reload it explicitly after config changes.
docker compose exec -T nginx nginx -t
docker compose exec -T nginx nginx -s reload

for _ in {1..30}; do
  if curl -fsS http://127.0.0.1:8080/healthz >/dev/null 2>&1 && \
     curl -fsS http://127.0.0.1:8080/actuator/health/readiness >/dev/null 2>&1; then
    echo "health check passed"
    exit 0
  fi
  sleep 2
done

echo "health check failed"
restore
exit 1
