#!/usr/bin/env bash
# Sobe o Piston em Podman rootless com a porta presa a uma interface local.
#
# O entrypoint oficial liga os controladores cgroup cpuset/io, que não existem
# no namespace de um Podman rootless. Este script monta um entrypoint que
# habilita apenas os controladores disponíveis e mantém o resto do sandbox.
#
#   ./runner/start-piston.sh                 # usa o IP da rota padrão
#   ./runner/start-piston.sh 192.168.15.5    # IP explícito da Wi-Fi
set -euo pipefail

BIND_IP="${1:-$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')}"
if [[ -z "$BIND_IP" ]]; then
  echo "Não consegui descobrir o IP local; passe-o como argumento." >&2
  exit 1
fi

PISTON_DIR="${PISTON_DIR:-$HOME/piston}"
IMAGE="ghcr.io/engineer-man/piston"
CONTAINER="piston_api"
PATCHED="$PISTON_DIR/runner-local/entrypoint.sh"

if [[ ! -d "$PISTON_DIR" ]]; then
  git clone --depth 1 https://github.com/engineer-man/piston.git "$PISTON_DIR"
fi

mkdir -p "$PISTON_DIR/data/piston/packages" "$PISTON_DIR/runner-local"

if [[ ! -f "$PATCHED" ]]; then
  cp "$PISTON_DIR/api/src/docker-entrypoint.sh" "$PATCHED"
  python3 - "$PATCHED" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()

root_old = """echo 1 > isolate/cgroup.procs && \\
echo '+cpuset +cpu +io +memory +pids' > cgroup.subtree_control && \\"""
root_new = """echo 1 > isolate/cgroup.procs && \\
for c in cpuset cpu io memory pids; do grep -qw "$c" cgroup.controllers && echo "+$c" > cgroup.subtree_control; done && \\"""

iso_old = """echo 1 > init/cgroup.procs && \\
echo '+cpuset +memory' > cgroup.subtree_control && \\"""
iso_new = """echo 1 > init/cgroup.procs && \\
for c in cpuset memory; do grep -qw "$c" cgroup.controllers && echo "+$c" > cgroup.subtree_control; done && \\"""

source = source.replace("mkdir isolate/ && \\", "mkdir -p isolate && \\")
source = source.replace("mkdir init && \\", "mkdir -p init && \\")
source = source.replace(root_old, root_new).replace(iso_old, iso_new)
path.write_text(source)
PY
  bash -n "$PATCHED"
fi

podman rm -f "$CONTAINER" >/dev/null 2>&1 || true
podman run -d \
  --name "$CONTAINER" \
  --privileged \
  --cgroupns=private \
  --restart=always \
  -p "$BIND_IP:2000:2000" \
  -v "$PISTON_DIR/data/piston/packages:/piston/packages:z" \
  -v "$PATCHED:/piston_api/src/docker-entrypoint.sh:ro,z" \
  --tmpfs /tmp:exec \
  "$IMAGE" >/dev/null

for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 "http://$BIND_IP:2000/api/v2/runtimes" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

install_runtime() {
  local package="$1"
  local version
  version="$(curl -sS --max-time 20 "http://$BIND_IP:2000/api/v2/packages" \
    | python3 -c "
import json, sys
name = sys.argv[1]
for entry in json.load(sys.stdin):
    if entry['language'].lower() == name:
        print(entry['language_version'])
" "$package" | head -1)"
  if [[ -z "$version" ]]; then
    echo "Pacote $package não encontrado no catálogo do servidor." >&2
    return 1
  fi
  curl -sS --max-time 600 -X POST "http://$BIND_IP:2000/api/v2/packages" \
    -H 'Content-Type: application/json' \
    -d "{\"language\":\"$package\",\"version\":\"$version\"}"
  echo
}

# `gcc` fornece a linguagem "c"; o pacote `nasm` fornece "nasm" e "nasm64".
install_runtime gcc
install_runtime nasm

echo
echo "Piston pronto: http://$BIND_IP:2000"
echo "Configure esse endereço em Goose IDE → + → Execução."
