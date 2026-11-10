#!/usr/bin/env bash
# 部署前服务器环境巡检：系统/资源/云元数据/Docker/已有业务/端口占用
# 用法: bash inspect.sh <user@host> [port] [私钥路径]
set -euo pipefail

HOST=${1:?用法: inspect.sh <user@host> [port] [私钥路径]}
PORT=${2:-22}
KEY=${3:-$HOME/.ssh/deploy}

ssh -i "$KEY" -p "$PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$HOST" '
  echo "===== 系统 ====="
  grep -E "^PRETTY_NAME" /etc/os-release || true
  echo "nproc=$(nproc)"
  free -m | awk "NR==2{print \"mem: total=\"\$2\"MB used=\"\$3\"MB avail=\"\$7\"MB\"}"
  free -m | awk "NR==3{print \"swap: total=\"\$2\"MB used=\"\$3\"MB\"}"
  df -m / | awk "NR==2{print \"disk_free=\"\$4\"MB\"}"

  echo "===== 云元数据（阿里云） ====="
  curl -s -m 3 http://100.100.100.200/latest/meta-data/region-id 2>/dev/null && echo || echo "(元数据不可达)"

  echo "===== Docker ====="
  docker --version 2>/dev/null || echo "NO_DOCKER"
  docker compose version 2>/dev/null | head -1 || true
  echo "-- daemon.json --"
  cat /etc/docker/daemon.json 2>/dev/null || echo "(无)"
  echo "-- 运行中容器 --"
  docker ps --format "{{.Names}}  {{.Image}}  {{.Status}}" 2>/dev/null | head -10

  echo "===== 内存 TOP5 ====="
  ps aux --sort=-rss | awk "NR<=6{printf \"%-8s %6dMB  %s\n\", \$1, int(\$6/1024), substr(\$0, index(\$0,\$11), 60)}"

  echo "===== 常用端口占用 ====="
  ss -tlnp 2>/dev/null | grep -E ":(80|443|8080|5173|3306|6379|5432|7474|7687|9000)\b" || echo "(80/8080 等均空闲)"
'
