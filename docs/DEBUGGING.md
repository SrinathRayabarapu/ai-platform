# AI Platform — Debugging playbook

Use this when `./scripts/bootstrap.sh` or `docker compose up` does not leave all services healthy.

## 1. Turn on verbose script logging

```bash
export AI_PLATFORM_DEBUG=1
./scripts/bootstrap.sh
```

- Prints every shell command (`set -x`).
- Writes a timestamped log under `logs/bootstrap-*.log` (path printed at end of bootstrap).

For a single failing step, run it alone:

```bash
./scripts/render-prometheus-config.sh
cat config/prometheus/file_sd/ai-services.json
docker compose config
```

## 2. See why a container exited or is unhealthy

```bash
docker compose ps -a
docker compose logs --tail=200 <service-name>
docker compose logs --tail=50 prometheus grafana kafka postgres redis
```

Replace `<service-name>` with e.g. `ai-lab-grafana`, `ai-lab-kafka`, `ai-lab-prometheus` (prefix matches `COMPOSE_PROJECT_NAME` in `.env`).

Inspect exit code:

```bash
docker inspect "$(docker compose ps -q postgres)" --format '{{.State.ExitCode}} {{.State.Error}}'
```

## 3. Common failures

### Permission denied on Grafana / Prometheus / pgAdmin data dirs (Linux / WSL2)

**Symptom:** Grafana or Prometheus restarts, logs show `permission denied` on `/var/lib/grafana` or TSDB.

**Fix:**

```bash
sudo chown -R 472:472 data/grafana
sudo chmod -R 777 data/prometheus
sudo chown -R 5050:5050 data/pgadmin
docker compose up -d
```

### Prometheus target `ai-services` down

**Symptom:** Prometheus UI → Status → Targets → `ai-services` is down.

**Symptom (Grafana):** dashboards such as **AI Token Usage** show **No data** for `ai_*` metrics even though the app runs — Prometheus is not scraping `/actuator/prometheus`.

**Causes:**

1. Spring Boot not running or not on `management.server.port` (default in repo assumption: **8081**).
2. Wrong host: metrics must be reachable **from inside the Prometheus container**.
   - **App on another machine (typical: Mac runs Spring Boot, Dell runs Docker):** you **must** scrape the dev machine’s **Tailscale (or LAN) IP:8081**, **not** `host.docker.internal`. The latter resolves to the **Docker host** (Dell/WSL), not the Mac; on Linux it may also fail with `lookup host.docker.internal: no such host` if `extra_hosts` was never added (e.g. hand-rolled compose).
   - Set in `.env`:
     - `DEV_MACHINE_IP=100.x.x.x` and `SPRING_ACTUATOR_PORT=8081`, **or**
     - `AI_SERVICES_SCRAPE_TARGET=100.x.x.x:8081`
   - Then run: `./scripts/render-prometheus-config.sh` and `docker compose restart prometheus`.
   - Same machine as Docker: `host.docker.internal:8081` can work **only** if Spring Boot listens on the host and the Prometheus service has `extra_hosts: host.docker.internal:host-gateway` (already in this repo’s `docker-compose.yml`).

3. Actuator not exposed: ensure `management.endpoints.web.exposure.include` includes `prometheus` and app binds `0.0.0.0` for that port if needed.

4. **macOS firewall** blocking inbound 8081 from Tailscale — Dell cannot scrape until the port is allowed (test: `curl` from Dell/WSL to `http://<mac-tailscale-ip>:8081/actuator/prometheus`).

### Kafka container stays `starting` or `unhealthy`

**Symptom:** `docker compose ps` shows Kafka unhealthy.

**Checks:**

```bash
docker compose logs kafka --tail=100
docker exec ai-lab-kafka kafka-broker-api-versions.sh --bootstrap-server localhost:9092
# If that fails, try without .sh or use /opt/kafka/bin/... per your image tag
```

Adjust the `healthcheck` in `docker-compose.yml` if your `apache/kafka` tag uses different binary names or paths.

### Kafka clients cannot connect from another host

**Symptom:** Spring on Mac cannot use `bootstrap-servers` pointing at the lab host.

**Cause:** `KAFKA_ADVERTISED_LISTENERS` EXTERNAL host defaults to `localhost`, which is wrong for remote clients.

**Fix:** In `.env` set `KAFKA_ADVERTISED_EXTERNAL_HOST` to this machine’s **LAN or Tailscale IP**, then:

```bash
docker compose up -d --force-recreate kafka
```

### pgAdmin rejects email

Use a non-reserved TLD, e.g. `admin@ailab.dev`, not `admin@something.local`.

### Extended profile: Loki / Promtail / MinIO fails

**Symptom:** `docker compose --profile extended up` errors on missing file or unhealthy MinIO.

**Checks:**

- `config/loki/loki-config.yml` and `config/promtail/promtail-config.yml` exist (shipped in repo).
- MinIO healthcheck uses `curl` or `wget` inside the container; if both are missing in a future image, remove or replace the `healthcheck` block in `docker-compose.yml` temporarily.
- Loki 3.x may log schema warnings — check `docker compose logs loki` and adjust `loki-config.yml` per current Grafana docs if needed.

### WSL2: ports not reachable from Tailscale

Windows host must forward to WSL; use `scripts/bootstrap-windows.ps1` (Admin) or manually apply `netsh interface portproxy` + firewall rules as in the script.

### `docker compose` vs `docker-compose`

This repo expects **Docker Compose v2** (`docker compose`). Legacy `docker-compose` is not used in scripts.

## 4. Validate Compose file and generated config

```bash
docker compose config
python3 -m json.tool config/prometheus/file_sd/ai-services.json
```

## 5. Migration scripts

- Export writes `backups/export_*/export.log` — always read it if `pg_dumpall` or `docker cp` fails.
- Import writes `import-*.log` inside the backup directory.
- PostgreSQL restore uses `psql -d postgres` because `pg_dumpall` includes global objects.

## 6. Reset and retry (destructive)

```bash
./scripts/reset.sh   # confirms before wiping data/
```

Then `./scripts/bootstrap.sh` again.

## 7. Still stuck

Collect:

```bash
docker compose ps -a > /tmp/ai-platform-ps.txt
docker compose logs --tail=300 > /tmp/ai-platform-logs.txt
uname -a >> /tmp/ai-platform-ps.txt
docker version >> /tmp/ai-platform-ps.txt
```

Attach those files when asking for help (redact `.env` secrets first).
