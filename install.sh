#!/usr/bin/env bash
# 把三个 skill 安装到 agent 的 skills 根目录（必须是根目录的直接子目录）。
# 用法: bash install.sh [目标目录]
#   不给参数时自动探测 ~/.claude/skills 或 ~/.agents/skills
set -euo pipefail

SKILLS=(aliyun-ecs-access gh-actions-aliyun-acr-cicd thin-image-docker-deploy)
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_target() {
  if [ -d "$HOME/.claude/skills" ]; then
    echo "$HOME/.claude/skills"
  elif [ -d "$HOME/.agents/skills" ]; then
    echo "$HOME/.agents/skills"
  else
    echo "$HOME/.claude/skills"
  fi
}

TARGET=${1:-$(detect_target)}
mkdir -p "$TARGET"

echo "==> 源目录:   $SRC_DIR"
echo "==> 目标目录: $TARGET"

for s in "${SKILLS[@]}"; do
  if [ ! -f "$SRC_DIR/$s/SKILL.md" ]; then
    echo "缺少 $s/SKILL.md，请在仓库根目录运行本脚本" >&2
    exit 1
  fi
  rm -rf "$TARGET/$s"
  cp -r "$SRC_DIR/$s" "$TARGET/$s"
  echo "    [ok] $s"
done

echo "==> 安装完成，新开会话生效。触发示例：「帮我把这个项目部署到阿里云 ECS」"
