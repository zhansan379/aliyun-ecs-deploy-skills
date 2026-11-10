---
name: thin-image-docker-deploy
description: 小内存（≤2G）国内云主机上的 Docker 应用部署：本地/CI 构建产物，服务器只做 COPY 级镜像组装，单容器运行。Use whenever deploying an app (Spring Boot/Vue/Node 全栈或前后端分离) to a small China-cloud ECS, when server-side builds OOM or docker pull 慢/失败, when the user says 部署到服务器/一键部署/docker compose, or asks 前后端能不能合成一个容器. Not for k8s or large clusters.
---

# 产物模式 Docker 部署（小内存服务器）

## 核心原则（为什么这样设计）

1. **服务器只做 COPY 级镜像组装，永不编译**。Maven/Vite 构建峰值 1GB+，2G 内存（swap 常已占满）必然 OOM；COPY 组装秒级、几乎不耗内存。
2. **不动服务器上现有业务**：不重启 dockerd（会打断用户的容器）、不占用已监听端口（80 常被占，用 8080）、数据放命名卷。
3. **单容器优先**：小项目把前端静态资源交给应用进程托管（如 Spring Boot 托管 dist），一个镜像一个进程一个端口，运维面最小。多实例/需要 TLS 时再拆 nginx 前置。

## 前置检查

先跑 skill `aliyun-ecs-access` 的巡检脚本。若结果满足：Docker ≥ 20 且有 compose 插件、available 内存 ≥ 500M（跑 JVM 即可）→ 可以继续。

## 目录与文件（本技能 assets 中的模板）

```
项目根/
├── Dockerfile.artifact        # 薄运行时镜像（assets/Dockerfile.artifact）
├── docker-compose.prod.yml    # 单服务 + healthcheck + 内存上限（assets/docker-compose.prod.yml）
└── scripts/deploy.sh          # 一键部署（scripts/deploy.sh，通用版）
```

约定 staging 目录布局（deploy.sh 的输入，`STAGE_DIR` 可配）：

```
deploy-pkg/
├── app.jar          # 或其他应用产物
├── static/          # 前端构建产物（无前端可省略）
├── Dockerfile.artifact
└── docker-compose.prod.yml
```

流程：先在本地/CI 完成构建并把产物拷进 staging 目录（**这是项目相关步骤，deploy.sh 不负责**），然后：

```bash
bash scripts/deploy.sh root@<IP> [port] [remote_dir]
# 环境变量: DEPLOY_KEY=私钥路径  STAGE_DIR=staging目录  IMAGE_NAME=镜像名
```

脚本做的事：tar 打包 staging → SSH 流式上传 → 服务器 `docker build -f Dockerfile.artifact`（纯 COPY）→ `docker compose up -d --remove-orphans` → **双健康检查**（API 路径 + 首页都要 curl）。

## 国内基础镜像拉取慢/失败的绕法（高频坑）

服务器 daemon.json 里的镜像源列表常有大量死源，`docker pull` 会逐个超时（表现为拉一个小镜像卡 5 分钟+）。绕法：**用镜像源域名作为引用拉取再 retag**，不重启 dockerd：

```bash
base() {
  docker images --format "{{.Repository}}:{{.Tag}}" | grep -qx "$1" && return 0
  docker pull -q "$1" 2>/dev/null && return 0
  for M in docker.1ms.run docker.m.daocloud.io; do
    docker pull -q "$M/library/$1" 2>/dev/null && { docker tag "$M/library/$1" "$1" && return 0; }
  done
  echo "基础镜像 $1 拉取失败" >&2; return 1
}
```

注意：`base()` 这类函数**必须定义在远程命令字符串内部**——本地 shell 函数传不到远端（`command not found` 127 是典型症状）。

## 单容器 Spring Boot 托管前端（全栈项目）

让 Spring Boot 直接托管 dist：加一个 `WebMvcConfigurer` 挂载文件目录 + 显式接管根路径 + gzip。**有三个必踩的坑**，完整代码与逐条解释见 [references/springboot-static.md](references/springboot-static.md)，写代码前先读它：

1. Boot 的 welcome-page 映射只查 classpath，会抢在自定义资源处理器之前把 `/` 404 掉 → 必须 `addViewControllers("/")` 显式 forward；
2. 空路径会被解析成目录资源 → resolver 里把空路径映射为 `index.html` 并做 `isFile()` 检查；
3. 未匹配的 `/api/*` 不能回退到 index.html（破坏 404 语义），且 `NoResourceFoundException` 要单独映射成 404，否则被兜底 500 吞掉。

配置入口：`app.static-dir: ${STATIC_DIR:}`（application.yml 占位符，不要依赖环境变量 relaxed binding——`APP_STATIC_DIR` 不会映射到 `app.static-dir`）。

## 其他必踩坑清单

- **YAML 重复键**：往 application.yml 追加 `server:`/`app:` 块前先确认没有同名顶层键（`DuplicateKeyException` 启动即挂）；
- **.dockerignore 排除了产物**：`dist/`、`app.jar` 必须能进 build context，否则 `COPY` 报 not found（CI 与服务器行为可能不一致，因为服务器上没有 .dockerignore）；
- **`docker build` 找不到 Dockerfile**：产物模式文件名是 `Dockerfile.artifact`，`docker build` 默认只找 `Dockerfile`，必须显式 `-f`；
- **compose 文件要随代码同步到服务器**：CI 只换镜像不同步 compose，服务定义就永远停留在第一次部署的版本；
- **换行符**：仓库加 `.gitattributes`（`*.sh text eol=lf`），否则 Windows 检出 CRLF 后脚本在 Linux 上 `\r` 报错；
- **`--remove-orphans`**：服务改名/收敛后 `compose up` 不会自动删旧容器，显式加。

## 部署后验收（两样都测）

```bash
curl -fsS http://<IP>:8080/<接口路径>     # API 通
curl -fsS http://<IP>:8080/               # 前端页面通（HTML）
```

只在服务器本地 curl 通、外网不通 → 安全组没放行端口（只能用户在控制台加）。
