# HomeServer

This is the configuration of my Home Server.

It's quite custom, so for the most part will take a fair bit of tinkering in order to run on your own setup.
However, once it's setup, it shouldn't require too much maintenance. It may require several other extra setups
that aren't listed here.

## Running

 1. Clone the repo
 2. `cp .env.example .env`
 3. Edit `.env` with your actual configuration
 4. `./docker.sh pull && ./docker.sh up -d`

### Home Assistant

Home Assistant is set up to run with host networking, as it makes many things much simpler. However, this does
mean that it is much easier to route through traefik using a file provider as opposed to docker labels.

My setup looks something like:
```yaml
http:
  routers:
    homeassistant:
      entrypoints:
        - websecure
      rule: Host(`home.${DOMAIN}`)
      service: homeassistant
      tls:
        certResolver: letsencrypt

  services:
    homeassistant:
      loadBalancer:
        passHostHeader: true
        servers:
          - url: "http://${IP}:8123"
```

Make sure to use the same values for `DOMAIN` and `IP` as you have set in your `.env` file.

#### Home Assistant AI

Many of the images in `docker-compose.ai.yaml` are meant to be used in conjunction with Home Assistant, utilising it's Wyoming protocol integration. That is documented [here](https://community.home-assistant.io/t/year-of-the-voice-chapter-2-lets-talk/565214).

### LocalAI

This is mostly documented by [localai](https://localai.io/howtos/easy-model/). I've been using TheBloke's amethyst mistral model.

### Prometheus/Loki/Promtail/Grafana

Many of the images export prometheus metrics, which can then be consumed via Grafana. Grafana also can be configured to gather logging and such from Loki and Promtail.

Example prometheus config:

```yaml
global:
  scrape_interval: 10s
scrape_configs:
- job_name: 'traefik'
  static_configs:
  - targets: ['traefik:8080']
- job_name: 'jellyfin'
  static_configs:
  - targets: ['watch:8096']
- job_name: 'adguard'
  static_configs:
  - targets: ['adguard-exporter:9617']
- job_name: 'host'
  static_configs:
  - targets: ['node-exporter:9100']
- job_name: 'dnscrypt'
  static_configs:
  - targets: ['dnscrypt:9100']
- job_name: 'authelia'
  static_configs:
  - targets: ['auth:9959']
- job_name: 'todo'
  metrics_path: '/api/v1/metrics'
  static_configs:
    - targets: ['todo:3456']
- job_name: minio
  metrics_path: /minio/v2/metrics/cluster
  scheme: http
  static_configs:
    - targets: ['minio:9000']
- job_name: blackhole
  metrics_path: /api/metrics
  scheme: http
  static_configs:
    - targets: ['blackhole:5000']
- job_name: postgres
  scheme: http
  static_configs:
    - targets: ['postgres-exporter:9187']
- job_name: 'docker'
  static_configs:
    - targets: ['pyxxilated.media:9323']
- job_name: 'promtail'
  static_configs:
    - targets: ['promtail:9080']
- job_name: 'loki'
  static_configs:
    - targets: ['loki:3100']
- job_name: 'speedtest'
  metrics_path: /metrics
  scrape_interval: 30m
  scrape_timeout: 2m
  static_configs:
    - targets: ['speedtest:9798']
- job_name: 'ntfy'
  metrics_path: /metrics
  static_configs:
    - targets: ["ntfy:9090"]
```

Example loki configuration:
```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s
  wal:
    dir: /loki/wal

query_range:
  results_cache:
    cache:
      redis:
        endpoint: redis:6379

schema_config:
  configs:
  - from: 2020-05-15
    store: boltdb-shipper
    object_store: s3
    schema: v11
    index:
      prefix: index_
      period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/index_cache
    resync_interval: 5s
    shared_store: s3
  aws:
    s3: http://user:password@minio.:9000/loki
    s3forcepathstyle: true
    region: local
  index_queries_cache_config:
    redis:
      endpoint: redis:6379

chunk_store_config:
  chunk_cache_config:
    redis:
      endpoint: redis:6379
  write_dedupe_cache_config:
    redis:
      endpoint: redis:6379

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

compactor:
  working_directory: /loki/boltdb-shipper-compactor
  shared_store: aws

analytics:
  reporting_enabled: false
```

Example Promtail configuration:

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
    - targets:
        - localhost
      labels:
        job: containerlogs
        __path__: /var/lib/docker/containers/*/*.log

    pipeline_stages:
      - json:
          expressions:
            output: log
            stream: stream
            attrs:
      - json:
          expressions:
            tag:
          source: attrs
      - regex:
          expression: (?P<image_name>(?:[^|]*[^|])).(?P<container_name>(?:[^|]*[^|])).(?P<image_id>(?:[^|]*[^|])).(?P<container_id>(?:[^|]*[^|]))
          source: tag
      - timestamp:
          format: RFC3339Nano
          source: time
      - labels:
          tag:
          stream:
          image_name:
          container_name:
          image_id:
          container_id:
      - output:
          source: output
```

This also requires properly setting up Minio + Redis.

### Minio/Redis/Postgres

Postgres is setup in such a way that it will allow you to put multiple databases inside one image. This is thanks to the `postgres/docker-postgresql-multiple-databases.sh` script.

Minio is a local server that exposes an S3 endpoint, which many things use (loki, and outline are the main ones). This is a little more complicated to set up than I would have liked, and
unfortunately I didn't document it as I went a long, so it's slightly lost to my knowledge. I'll try to update it here if/when
I remember how to get it up and running properly. Once setup though it's been rather simple.

Redis is mostly simple to setup without much intervention, it just might require some tweaking if you want to have a persistent
redis cache.

### LDAP

LDAP is what's used for an authentication backend for Authelia (as well as several things that don't properly integrate with an auth frontend). It's quite important this is setup properly, because altering later on is a bit of a pain unless you know how to configure LDAP.

Home Assistant auth is done using LDAP, and requires a special integration script. This is found [here](https://github.com/bob1de/ldap-auth-sh).

### Volumes

Most things are all mounted as named volumes inside containers. I currently run all of mine off of a ZFS pool, however feel free to set these up as you like.
