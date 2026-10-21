# Incident Report: HaloEdgeDown Drill

## Summary

A controlled failure drill was performed by stopping the Nginx container. The
external edge probe failed while the Halo application probe stayed healthy. The
alert fired, was delivered to ntfy, and resolved after Nginx was restored.

## Impact

- External access on `:8080` was unavailable during the drill
- Halo itself remained running
- No data loss

## Detection

- `probe_success{job="blackbox", service="halo-edge"}` dropped to `0`
- `probe_success{job="blackbox", service="halo-app"}` stayed at `1`
- `HaloEdgeDown` entered `firing` after the configured `for: 1m`
- Alertmanager delivered a firing notification to ntfy

## Timeline

| Time (CST) | Event |
|---|---|
| 15:42 | `HaloEdgeDown` firing notification received |
| 15:43 | Nginx restored, `HaloEdgeDown` resolved notification received |
| 15:45 | Grafana showed `halo-edge` back at `1`, HTTP `200` |

The first attempt at 15:33 did not fire because Prometheus could not read the
rules directory. That was a monitoring configuration issue, not an application
failure. The rules directory was root-only while Prometheus runs as a non-root
user; `chmod 755` fixed it and the rule reloaded successfully.

## Root Cause

Nginx container was stopped intentionally to simulate an edge failure.

## Recovery

```bash
cd /opt/halo-ops
docker compose start nginx
```

The edge probe returned to `1` and Alertmanager sent a resolved notification.

## What Went Well

- Blackbox distinguished edge failure from application failure
- Alert grouping and resolved notification worked
- Dashboard clearly showed `halo-app=1` and `halo-edge=0`
- The failure was detected without checking logs manually

## Follow-ups

- [x] Fix Prometheus rules directory permissions
- [x] Add a runbook for edge and application failures
- [ ] Upgrade Prometheus and Alertmanager from the old `latest` images
- [ ] Add an external dead-man's switch for the monitoring host itself
- [ ] Format Alertmanager webhook payloads before sending to ntfy

## Evidence

- Grafana `Halo Ops / Probe`: `halo-edge` red `0`, `halo-app` green `1`
- ntfy: `HaloEdgeDown` firing and resolved messages
- Prometheus: alert state transition from inactive to firing to inactive
