---
name: gh-actions-aliyun-acr-cicd
description: 用 GitHub Actions + 阿里云 ACR 实现推代码自动部署到国内 ECS（实测全链路约 3 分钟）。Use whenever setting up CI/CD for an app deployed to a China-cloud server, when the user asks CI/CD 怎么搭/自动部署/流水线, when deciding between ACR/GHCR/SSH直传/Self-hosted Runner/Spot Runner, or when debugging failed GitHub Actions deploy runs. Keywords: GitHub Actions、ACR、镜像仓库、secrets、自动部署。
---

# GitHub Actions + 阿里云 ACR → 国内 ECS 的 CI/CD

## 方案选型（先看表再动手，数据为实测）

| 方案 | 单次端到端 | 额外配置 | 风险面 | 结论 |
|------|-----------|---------|--------|------|
| **Runner 构建镜像 → 推 ACR → ECS VPC 内网拉取** | **~3 分钟** | ACR 个人版（免费）+ 8 个 Secrets | 仅 ACR 登录凭证 | **默认推荐** |
| Runner → SSH 直传产物（22MB） | ~15 分钟 | 无 | 无 | 跨境 SSH 实测仅 ~40KB/s，慢 5 倍，作降级/救急方案 |
| 整镜像 SSH 直传 | 不可用 | 无 | 无 | 130MB 实测 25 分钟传不到一半，放弃 |
| GHCR | 与 SSH 产物直传相当 | — | — | ghcr.io 同样境外，国内拉取无优势 |
| Spot Runner（动态 ECS） | ~7 分钟 | 有 ECS 权限的 RAM AK + 生命周期脚本 | AK 泄露=被刷实例 | 内网秒传的优势被实例启动+注册（2~4 分钟）吃掉，复杂度最高 |
| ECS 常驻 Runner | ~5 分钟 | 需 ≥4G 内存 | Runner 即服务器入口 | 2G 机器跑不动构建，排除 |

关键事实：GitHub 海外 Runner 到国内 ECS 的 **SSH 单流传输 ~40KB/s**；ACR 注册表走并行分块上传（跨境快），ECS 从 **同地域 VPC 地址**拉取走内网（免流量、秒级）。

## 前置步骤（gh CLI 已登录时全自动）

```bash
gh auth setup-git                                   # git 用 gh 凭证推送
gh repo create <name> --private --source . --push   # 建仓并推送（触发首次运行）
gh secret set SSH_HOST --body "<IP>"                # 以下逐个设置
gh secret set SSH_PRIVATE_KEY < ~/.ssh/<project>-deploy
```

## Secrets 清单（8 个）

| Secret | 说明 |
|--------|------|
| `SSH_HOST` / `SSH_USER` / `SSH_PORT` / `SSH_PRIVATE_KEY` | 服务器 SSH（私钥整文件内容，专用部署密钥） |
| `ACR_REGISTRY` | 访问域名，如 `crpi-xxx.cn-beijing.personal.cr.aliyuncs.com` |
| `ACR_NAMESPACE` | 命名空间 |
| `ACR_DOCKER_USERNAME` / `ACR_DOCKER_PASSWORD` | ACR 访问凭证（控制台"访问凭证"页的固定密码） |

**ACR 侧必须先做**：实例 → 创建命名空间 → 创建镜像仓库（个人版推送到不存在的仓库直接失败；catalog API 对个人版不开放列举，别试图用 API 探测，让用户看控制台）。凭证验证用服务器上 `docker login`（curl 直连 `/v2/` 永远 401——ACR 是 token 认证，curl 不做 token 交换）。

## 工作流模板

用 assets/deploy.yml（实战验证版），要点逐条：

1. **guard 步骤**：Secrets 未配齐时输出 `skip=true` 跳过部署——首次推送（还没配 Secrets）也保持绿色；
2. `setup-java`/`setup-node` + **`working-directory`**（Monorepo 子目录构建，漏了就 "no POM in this directory"）；
3. `docker build` **必须显式 `-f Dockerfile.artifact`**（默认只找名为 Dockerfile 的文件；产物 staging 目录里没有这个名字）；
4. 双 tag 推送：`:app`（latest 语义）+ `:app-${GITHUB_SHA::8}`（回滚用；第二 tag 复用已传层，成本极低）；
5. 服务器侧：用 metadata（`http://100.100.100.200/latest/meta-data/region-id`）判断与 ACR 同地域 → 换 `-vpc.` 内网域名拉取；`docker tag` 回本地镜像名后 `docker compose -f docker-compose.prod.yml up -d --remove-orphans`；
6. **compose 文件随仓库同步到服务器**（`cat docker-compose.prod.yml | ssh "cat > ..."`）——只换镜像不同步 compose，服务定义会永远停在第一次部署的版本；
7. **健康检查双探**：API 路径 + 首页都要 curl（单容器托管静态后，只测 API 测不出前端问题）；
8. `concurrency.group` 固定 + `cancel-in-progress: false`：连续 push 排队串行部署，避免并发写服务器。

## 调试失败运行

```bash
gh run list --limit 1                                # 找 run id
gh run view <id> --json status,conclusion,jobs --jq '...'   # 各步骤结论
gh run view <id> --log-failed | tail -30             # 只看失败步骤日志
gh run cancel <id>                                   # 取消卡住的传输
```

高频失败原因速查：no POM（缺 working-directory）/ no such dockerfile（缺 -f）/ COPY not found（.dockerignore 排除了产物）/ command not found（本地函数被放进远程命令）/ Invalid CORS request（同源部署不需要 CORS 配置，删掉遗留白名单）/ 401 catalog（个人版不开放，正常）。

## 安全

- ACR 凭证只限镜像仓库登录，不含云资源权限；提醒用户不要与服务器密码复用；
- secrets 在 Actions 日志中自动打码，但 `run:` 里展开 secrets 的命令行会显示（打码后为 ***），写私钥用 `env` + `printf '%s\n' "$VAR"` 而非 `${{ secrets.* }}` 直接内插；
- 仓库默认建私有。

## 降级路径

ACR 不可用时，退回 skill `thin-image-docker-deploy` 的产物直传 deploy.sh（手动救急可用，接受 ~10 分钟传输）。
