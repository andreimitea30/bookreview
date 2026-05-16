#!/usr/bin/env bash

#   http://localhost:8000  Kong         http://localhost:9090  Prometheus
#   http://localhost:8080  Adminer      http://localhost:9000  Portainer
#   http://localhost:3000  Grafana

set -e

REPO_URL="https://github.com/andreimitea30/bookreview.git"
REPO_BRANCH="initial_try"
DOCKER_USERNAME="${DOCKER_USERNAME:-biancasc}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
NETWORK="swarm-net"
NODES=(node1 node2 node3)

dexec_sh() {
  local node="$1"; shift
  docker exec "$node" sh -c "$*"
}

cmd_down() {
  echo ">>> Tearing down cluster"
  for n in "${NODES[@]}"; do
    docker rm -f "$n" >/dev/null 2>&1 && echo "    removed $n" || echo "    $n not present"
  done
  docker network rm "$NETWORK" >/dev/null 2>&1 && echo "    removed network $NETWORK" || true
  echo "Done."
}

cmd_status() {
  echo ">>> Host containers (dind nodes):"
  docker ps --filter "name=node" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo ""
  echo ">>> Swarm nodes (from node1):"
  docker exec node1 docker node ls 2>/dev/null || { echo "    swarm not initialised"; exit 1; }
  echo ""
  echo ">>> Stack services:"
  docker exec node1 docker stack services bookreview 2>/dev/null || echo "    stack not deployed"
  echo ""
  echo ">>> Task placement:"
  docker exec node1 docker stack ps bookreview --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}" 2>/dev/null || true
}

cmd_up() {
  docker version >/dev/null 2>&1 || { echo "ERROR: Docker is not running. Start Docker Desktop first."; exit 1; }

  docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create --driver bridge "$NETWORK" >/dev/null

  if docker ps -a --filter "name=node1" --format "{{.Names}}" | grep -q "^node1$"; then
    echo "    nodes already exist — skip (use --down first to recreate)"
  else
    docker run -d --privileged --name node1 --hostname node1 --network "$NETWORK" \
      -p 8000:8000 -p 8080:8080 -p 3000:3000 -p 9000:9000 -p 9090:9090 \
      docker:24-dind >/dev/null
    docker run -d --privileged --name node2 --hostname node2 --network "$NETWORK" docker:24-dind >/dev/null
    docker run -d --privileged --name node3 --hostname node3 --network "$NETWORK" docker:24-dind >/dev/null
    echo "    waiting 12s for inner dockerd to start..."
    sleep 12
  fi

  N1_IP="$(docker inspect node1 --format "{{(index .NetworkSettings.Networks \"$NETWORK\").IPAddress}}")"
  if docker exec node1 docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
    echo "    swarm already initialised on node1"
  else
    docker exec node1 docker swarm init --advertise-addr "$N1_IP" >/dev/null
    echo "    node1 initialised at $N1_IP"
  fi
  JOIN_TOKEN="$(docker exec node1 docker swarm join-token -q worker)"
  for n in node2 node3; do
    if docker exec "$n" docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
      echo "    $n already in swarm"
    else
      docker exec "$n" docker swarm join --token "$JOIN_TOKEN" "$N1_IP:2377" >/dev/null
      echo "    $n joined as worker"
    fi
  done

  if dexec_sh node1 "test -d /bookreview"; then
    echo "    /bookreview already present — pulling latest"
    dexec_sh node1 "cd /bookreview && git pull --recurse-submodules && git submodule update --init --recursive"
  else
    dexec_sh node1 "apk add --no-cache git >/dev/null"
    dexec_sh node1 "cd / && git clone --recurse-submodules -b $REPO_BRANCH $REPO_URL bookreview >/dev/null 2>&1"
    echo "    repo cloned to /bookreview ($REPO_BRANCH)"
  fi

  dexec_sh node1 "cd /bookreview && export DOCKER_USERNAME=$DOCKER_USERNAME && export IMAGE_TAG=$IMAGE_TAG && docker stack deploy --compose-file docker-stack.yml bookreview" | sed 's/^/    /'

  echo ""
  echo "    Waiting up to 90s for services to converge..."
  for i in $(seq 1 18); do
    sleep 5
    NOT_READY="$(docker exec node1 docker stack services bookreview --format '{{.Replicas}}' | grep -v '/' | wc -l)"
    READY="$(docker exec node1 docker stack services bookreview --format '{{.Replicas}}' | awk -F/ '$1==$2' | wc -l)"
    TOTAL="$(docker exec node1 docker stack services bookreview --format '{{.Replicas}}' | wc -l)"
    echo "    [${i}/18] $READY/$TOTAL services ready"
    [ "$READY" = "$TOTAL" ] && break
  done

  echo "========================================================================"
  echo "  Cluster is up. Open these URLs from your host browser:"
  echo "    Kong (public API):  http://localhost:8000"
  echo "    Adminer:            http://localhost:8080   (server=auth-db|books-db, user=root, pass=rootpassword)"
  echo "    Grafana:            http://localhost:3000   (admin / admin)"
  echo "    Prometheus:         http://localhost:9090"
  echo "    Portainer:          http://localhost:9000"
  echo "========================================================================"
}

case "${1:-up}" in
  up|"")     cmd_up ;;
  down)      cmd_down ;;
  --down)    cmd_down ;;
  status)    cmd_status ;;
  --status)  cmd_status ;;
  -h|--help)
    sed -n '2,20p' "$0"
    ;;
  *)
    echo "Unknown argument: $1"
    echo "Usage: $0 [up|--down|--status]"
    exit 1
    ;;
esac
