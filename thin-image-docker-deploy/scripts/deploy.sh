#!/usr/bin/env bash
# 产物模式一键部署（通用版）：staging 目录 -> 服务器 -> COPY 级组装镜像 -> compose up -> 双健康检查
# 前置：项目构建步骤（mvn/npm 等）已在别处完成，产物已放进 staging 目录：
#   deploy-pkg/
#   ├── app.jar               # 应用产物（命名与 Dockerfile.artifact 的 COPY 对应）
#   ├── static/               # 前端 dist（无前端可省略）
#   ├── Dockerfile.artifact
#   └── docker-compose.prod.yml
# 用法: deploy.sh <user@host> [port] [remote_dir]
# 环境变量: DEPLOY_KEY(默认 ~/.ssh/deploy)  STAGE_DIR(默认 ./deploy-pkg)  IMAGE_NAME(默认 myapp)
set -euo pipefail

HOST=${1:?用法: deploy.sh <user@host> [port] [remote_dir]}
PORT=${2:-22}
REMOTE_DIR=${3:-/opt/myapp}
KEY=${DEPLOY_KEY:-$HOME/.ssh/deploy}
STAGE=${STAGE_DIR:-./deploy-pkg}
IMAGE=${IMAGE_NAME:-myapp}
SSH="ssh -i $KEY -p $PORT -o BatchMode=yes -o StrictHostKeyChecking=accept-new $HOST"

[ -d "$STAGE" ] || { echo "staging 目录不存在: $STAGE（先完成构建并整理产物）"; exit 1; }
[ -f "$STAGE/Dockerfile.artifact" ] || { echo "staging 缺少 Dockerfile.artifact"; exit 1; }

echo "==> [1/4] 上传产物到 $HOST:$REMOTE_DIR"
$SSH "mkdir -p '$REMOTE_DIR'"
tar -C "$STAGE" -czf - . | $SSH "tar -xzf - -C '$REMOTE_DIR'"

echo "==> [2/4] 服务器组装镜像并启动"
$SSH '
  base() {
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -qx "$1" && return 0
    docker pull -q "$1" 2>/dev/null && return 0
    for M in docker.1ms.run docker.m.daocloud.io; do
      docker pull -q "$M/library/$1" 2>/dev/null && { docker tag "$M/library/$1" "$1" && return 0; }
    done
    echo "基础镜像 $1 拉取失败" >&2; return 1
  }
  cd '"$REMOTE_DIR"' || exit 1
  base eclipse-temurin:17-jre \
    && docker build -q -t '"$IMAGE"':latest -f Dockerfile.artifact . \
    && docker compose -f docker-compose.prod.yml up -d --remove-orphans
'

echo "==> [3/4] 健康检查（API + 首页双探）"
for i in $(seq 1 45); do
  if $SSH "curl -fsS http://localhost:8080/ >/dev/null 2>&1"; then
    echo "==> [4/4] 部署成功: http://${HOST#*@}:8080"
    exit 0
  fi
  sleep 2
done
echo "==> 健康检查超时，请上服务器查看: docker compose -f $REMOTE_DIR/docker-compose.prod.yml logs" >&2
exit 1
