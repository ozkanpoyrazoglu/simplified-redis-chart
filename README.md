# Redis Sentinel Helm Chart

Redis with Sentinel for high availability on Kubernetes, usable both by Sentinel-aware clients and by
clients that only know a single `host:port`.

## Architecture

```
                     ┌──────────────────────────────┐
  Sentinel-aware ───►│ <fullname>-sentinel :26379   │  Sentinel StatefulSet (quorum-based failover)
  clients            └──────────────┬───────────────┘
                                    │ monitors / promotes
                     ┌──────────────▼───────────────┐
                     │ <fullname>-redis-0..N-1      │  one Redis StatefulSet; Sentinel decides
                     │   1 master + N-1 replicas    │  which pod is the master
                     └──────────────▲───────────────┘
                                    │ health check: AUTH + role:master
  Plain clients ────►┌──────────────┴───────────────┐
                     │ <fullname>-redis-dynamic     │  HAProxy, always routes to the current master
                     │   :6379                      │
                     └──────────────────────────────┘
```

- **Redis**: a single StatefulSet. On start, each pod asks Sentinel for the current master (falling back to
  the other pods, then to pod 0 on a fresh install), so a restarted former master rejoins as a replica
  instead of becoming a second master. If Sentinel still names the restarting pod as master, the pod first
  waits (`2 × downAfterMilliseconds + 10s`) for Sentinel to promote a replica, and only starts as master
  when no failover happens.
- **Planned restarts**: a stopping master asks Sentinel for a failover (`preStop`), pauses writes and follows
  the promoted replica, so rolling updates cause a few seconds of errors instead of an unplanned failover.
  A replica only counts as started once its initial sync is done, and a rolling update waits
  `redis.minReadySeconds` before moving on.
- **Sentinel**: on start, each Sentinel learns the current master from its peers or the Redis pods.
  Pods are addressed by hostname, so Sentinel state survives pod IP changes. A small `cleanup` sidecar runs
  `SENTINEL RESET` when IP-addressed leftovers (e.g. from a version that did not announce hostnames) remain
  while every pod is healthy under its hostname.
- **HAProxy** (optional): checks every Redis pod each second and only routes to the one reporting
  `role:master`. Connections to a pod that stops being master are closed, so clients reconnect to the new
  one. No component needs Kubernetes API access.

## Connecting

| Client type | Address |
|---|---|
| Without Sentinel support | `<fullname>-redis-dynamic:6379` (requires `haproxy.enabled`) |
| Sentinel-aware | Sentinel `<fullname>-sentinel:26379`, master set `mymaster` |
| Read-only | `<fullname>-redis:6379` balances across **all** pods, including replicas; writes may fail with `READONLY` |

If all your clients are Sentinel-aware, you can set `haproxy.enabled: false`.

## Quick Start

```bash
git clone https://github.com/ozkanpoyrazoglu/simplified-redis-chart.git
cd simplified-redis-chart

helm install redis-sentinel . --set redis.auth.password='<strong-password>'
```

## Configuration

| Key | Default | Description |
|---|---|---|
| `redis.replicas` | `3` | Total Redis pods (1 master + N-1 replicas) |
| `redis.auth.enabled` / `redis.auth.password` | `true` / `redis-password-123` | Password for the `default` user; stored in a Secret |
| `redis.auth.acl.enabled` / `redis.auth.acl.users` | `false` | Additional ACL users (see below) |
| `redis.configuration` | see `values.yaml` | Extra `redis.conf` lines. Do not put passwords here |
| `redis.persistence.*` | enabled, `8Gi` | PVC per Redis pod |
| `redis.preStopFailoverTimeout` / `terminationGracePeriodSeconds` | `20` / `60` | Time a stopping master waits for the handover / pod grace period |
| `redis.startupTimeoutSeconds` | `600` | Time a replica may take for its initial sync before it is restarted; raise it for large datasets |
| `redis.minReadySeconds` | `15` | Wait between pods during a rolling update |
| `sentinel.replicas` | `3` | Number of Sentinels |
| `sentinel.masterSet` / `sentinel.quorum` | `mymaster` / `2` | Sentinel master set name and quorum |
| `sentinel.downAfterMilliseconds` / `failoverTimeout` / `parallelSyncs` | `5000` / `10000` / `1` | Sentinel failover tuning |
| `sentinel.configuration` | `""` | Extra lines appended to `sentinel.conf` |
| `sentinel.cleanupInterval` | `30` | Seconds between checks of the `cleanup` sidecar |
| `haproxy.enabled` | `true` | Deploy HAProxy and the `<fullname>-redis-dynamic` Service |
| `haproxy.replicas` | `2` | HAProxy pods |
| `haproxy.check.interval` / `fall` / `rise` | `1s` / `2` / `2` | Master health check |
| `haproxy.timeout.client` / `server` | `330s` | Idle connection timeout through HAProxy |
| `podAntiAffinityPreset` | `soft` | Spread each component across nodes: `soft`, `hard` or `""` (ignored when `affinity` is set) |
| `podDisruptionBudget.enabled` / `minAvailable` | `true` / `1` | One PDB per component |
| `clusterDomain` | `cluster.local` | Cluster DNS domain used for pod hostnames |

### ACL users

```yaml
redis:
  auth:
    enabled: true
    password: "<default-user-password>"
    acl:
      enabled: true
      users:
        - username: "app"
          password: "<app-password>"
          keys: "~app:*"
          channels: "&*"
          permissions: "+@all -@dangerous"
```

Users have no key or channel access unless `keys` / `channels` patterns are set. The `default` user is
always defined from `redis.auth.password` and must not be listed. The password must not contain `"`.

## Operations

```bash
# Current master
kubectl exec <fullname>-sentinel-0 -- redis-cli -p 26379 sentinel get-master-addr-by-name mymaster

# Manual failover
kubectl exec <fullname>-sentinel-0 -- redis-cli -p 26379 sentinel failover mymaster

# Scale Redis (HAProxy picks up the new pods automatically)
helm upgrade redis-sentinel . --reuse-values --set redis.replicas=5
```

Keep `sentinel.replicas` odd and `sentinel.quorum` a majority of it.

## Upgrading to 2.0.0

### From the endpoint-controller variant (single `-redis` StatefulSet, `-redis-dynamic` Service)

Upgrade in place with your existing values file:

```bash
helm upgrade <release> . -f your-values.yaml
```

- Resource names, the StatefulSet selectors, `serviceName` and volume claims are unchanged, so data and
  PVCs are kept and the `-redis-dynamic` Service keeps its ClusterIP. Clients need no change.
- The endpoint controller Deployment, Role and RoleBinding are removed; `-redis-dynamic` is now served by
  HAProxy. `service.redis.endpointController.enabled` still works and maps to `haproxy.enabled`; the other
  `endpointController.*` keys and `service.redis.proxy.*` are ignored.
- Redis and Sentinel pods are restarted once (rolling). The old pods have no `preStop` handover, so the
  master is stopped without a planned failover, and Sentinels restart at the same time. Expect up to about
  a minute of write errors on `-redis-dynamic` during this one upgrade; in tests (master on the first pod
  to be replaced, writes every 200ms) no acknowledged write was lost. Later upgrades use the handover.
- Sentinel entries recorded by pod IP are removed automatically by the `cleanup` sidecar once all pods run
  the new version; no manual `SENTINEL RESET` is needed.
- Remove `requirepass` / `masterauth` from `redis.configuration`; the chart now adds them from the Secret,
  and leaving them in values keeps the password in a ConfigMap. Rendering fails if they differ from
  `redis.auth.password`, since the Secret value would silently replace them.

### From 1.x (separate `-redis-master` / `-redis-replica` StatefulSets)

This layout is removed and cannot be upgraded in place (rendering fails if `redis.master` or
`redis.replica` are set). Install 2.0.0 as a new release, copy the data over (for example with
`redis-cli --rdb` from the old master and restoring it into the new pod 0 before the other pods start, or
with `MIGRATE`/replication), switch clients, then uninstall the old release.

## Uninstalling

```bash
helm uninstall redis-sentinel
# PVCs are kept; delete them to remove the data
kubectl delete pvc -l app.kubernetes.io/instance=redis-sentinel
```

## Security Considerations

- Set a strong `redis.auth.password`; passwords are only stored in the chart's Secret.
- Sentinel itself has no password; restrict access to port 26379 with a NetworkPolicy.
- Pods run as non-root with a read-only root filesystem and no service account token.

## License

MIT
