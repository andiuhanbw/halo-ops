# Runbook

## Service Inventory

| Service | Container | Listen | Exposure |
|---|---|---|---|
| Halo | `halo-ops-halo-1` | `127.0.0.1:8090` | via Nginx only |
| PostgreSQL | `halo-ops-halodb-1` | `5432` inside Docker network | internal only |
| Nginx | `halo-ops-nginx-1` | `0.0.0.0:8080` | public |
| Prometheus | `prometheus` | `127.0.0.1:9090` | localhost |
| Grafana | `grafana` | `127.0.0.1:3000` | SSH tunnel |
| Alertmanager | `alertmanager` | `127.0.0.1:9093` | localhost |
| blackbox_exporter | `blackbox-exporter` | `127.0.0.1:9115` | localhost |
| node_exporter | `node-exporter` | `127.0.0.1:9100` | localhost |

Application paths:

```text
/opt/halo-ops                 application stack
/opt/halo-ops/data/halo       Halo data: attachments, themes, plugins, keys
/opt/halo-ops/backups         local backups
/opt/halo-ops/.deploy         CI/CD releases and pre-deploy backups
/root/prom-stack              existing monitoring stack
```

## Daily Checks

```bash
cd /opt/halo-ops
docker compose ps

curl -sS http://127.0.0.1:8080/healthz
curl -sS http://127.0.0.1:8080/actuator/health/readiness

free -h
df -h /
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
```

Expected:

- Halo, PostgreSQL, Nginx all `Up` and healthy
- `/healthz` returns `ok`
- readiness returns `{"status":"UP"}`
- swap active, disk usage below 85%

## Deploy

Normal path: push to `main`, GitHub Actions runs:

```text
validate -> upload release -> deploy.sh -> nginx -t/reload -> health check
```

If health check fails, `deploy.sh` restores the previous `compose.yaml` and
`nginx/default.conf` and brings the stack back up.

Manual deploy:

```bash
cd /opt/halo-ops
ls -lt .deploy/releases | head
./scripts/deploy.sh /opt/halo-ops/.deploy/releases/<sha>
```

Check the deployment marker:

```bash
curl -sI http://127.0.0.1:8080/healthz | grep -i x-ops-lab
# X-Ops-Lab: halo-ops
```

## Incident: HaloEdgeDown

Meaning: blackbox cannot reach `http://nginx/healthz`.

1. Check Nginx:

```bash
docker compose ps nginx
docker compose logs --tail=100 nginx
```

2. Check config and reload:

```bash
docker compose exec -T nginx nginx -t
docker compose exec -T nginx nginx -s reload
```

3. Check the edge directly:

```bash
curl -sS http://127.0.0.1:8080/healthz
```

4. If Nginx is up but the app is not, check Halo:

```bash
docker compose logs --tail=100 halo
curl -sS http://127.0.0.1:8090/actuator/health/readiness
```

## Incident: HaloAppDown

Meaning: blackbox cannot reach Halo readiness inside the Docker network.

1. Check container and logs:

```bash
docker compose ps halo
docker compose logs --tail=150 halo
```

2. Check database:

```bash
docker compose ps halodb
docker compose logs --tail=80 halodb
docker compose exec -T halodb pg_isready -U halo -d halo
```

3. Check memory and OOM:

```bash
free -h
dmesg -T | grep -i -E 'oom|killed process' | tail
docker stats --no-stream
```

4. Restart only Halo if needed:

```bash
docker compose restart halo
```

## Incident: Disk or Memory Pressure

```bash
df -h /
du -sh /opt/halo-ops/backups /var/lib/docker 2>/dev/null
docker system df
free -h
```

Do not run `docker system prune -a` blindly; confirm what will be removed first.

## Backup and Restore

```bash
/opt/halo-ops/scripts/backup.sh

LATEST=$(ls -1dt /opt/halo-ops/backups/*/ | head -1)
LATEST="${LATEST%/}"
/opt/halo-ops/scripts/restore-test.sh "$LATEST"
```

The restore test uses a temporary database and does not overwrite production.

## SSH and Privilege

- SSH user: `deploy`
- Key: local `~/.ssh/halo_ops_deploy`
- `PermitRootLogin no`
- `PasswordAuthentication no`
- `deploy` is in the `docker` group
- Root recovery: Alibaba Cloud VNC console only

## Known Gaps

- Single host, no high availability
- No public TLS because there is no ICP-filed domain
- Monitoring stack is outside this repository and not deployed by CI/CD
- Prometheus 2.32.1 / Alertmanager 0.23.0 are old and should be upgraded
- Backups are local only; offsite copy is still missing
