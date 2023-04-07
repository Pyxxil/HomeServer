#!/bin/bash
awk 1 docker-compose.common.yaml   \
    docker-compose.databases.yaml  \
    docker-compose.admin.yaml      \
    docker-compose.dns.yaml        \
    docker-compose.cloud.yaml      \
    docker-compose.media.yaml      \
    docker-compose.metrics.yaml    \
    docker-compose.base.yaml       \
 | docker compose -f - "$@"
