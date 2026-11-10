# 阿里云 ECS 部署技能包

三个 [Agent Skills](https://code.claude.com/docs/en/skills)（Claude Code / OpenCode 等兼容实现的 `SKILL.md` 格式），把「国内云服务器怎么部署」这件事从踩坑变成流程。

面向的场景：**一台 2G 内存的国内 ECS、80 端口已被占用、跨境网络很慢**——这是绝大多数个人项目和中小企业项目的真实起点。

## 包含什么

| Skill | 解决什么问题 | 关键产出 |
|---|---|---|
| [`aliyun-ecs-access`](aliyun-ecs-access/SKILL.md) | 第一次登上一台陌生服务器；`root` 密码登录报 `Permission denied` / `Authentication method not allowed`；部署前不知道机器能不能跑 | 密钥登录流程、认证方式诊断、`scripts/inspect.sh` 一键巡检（系统/内存/Docker/已有业务/端口占用） |
| [`gh-actions-aliyun-acr-cicd`](gh-actions-aliyun-acr-cicd/SKILL.md) | 想做到 push 就自动上线；纠结 ACR / GHCR / SSH 直传 / Self-hosted Runner 怎么选 | 六种方案的实测对比表 + 可直接改的 `assets/deploy.yml`，全链路约 3 分钟 |
| [`thin-image-docker-deploy`](thin-image-docker-deploy/SKILL.md) | 服务器上 `mvn`/`vite` 一编译就 OOM；`docker pull` 拉不动；前端和 Spring Boot 想合成一个容器 | 产物模式 Dockerfile + compose + `scripts/deploy.sh`，含 Spring Boot 托管前端静态资源的完整踩坑清单 |

## 实测数据

这些数字来自真实机器（2G 内存、ECS 与 ACR 同地域），不是估算：

| 指标 | 结果 |
|---|---|
| GitHub Runner 构建 → 推 ACR → ECS 内网拉取 → 重启 | **约 3 分钟** |
| 跨境 SSH 直传产物 | **约 40 KB/s**，130MB 要 25 分钟 |
| 服务器侧 `mvn package` | 峰值 >1GB，2G 机器 swap 占满后必然 OOM |
| 产物模式镜像组装（纯 COPY） | 秒级，几乎不占内存 |

## 安装

Skill 目录必须是 skills 根目录下的**直接子目录**，不能多层嵌套。

```bash
# 自动安装（自动探测 ~/.claude/skills 或 ~/.agents/skills）
bash install.sh

# 指定位置
bash install.sh ~/.claude/skills
bash install.sh ~/.agents/skills
```

手动安装等价于：

```bash
mkdir -p ~/.claude/skills
cp -r aliyun-ecs-access gh-actions-aliyun-acr-cicd thin-image-docker-deploy ~/.claude/skills/
```

装完新开一个会话，模型会根据任务描述自动加载对应 skill；也可以直接点名，例如「用 thin-image-docker-deploy 帮我把这个 Spring Boot 项目部署上去」。

## 使用前提

- `gh-actions-aliyun-acr-cicd` 需要 GitHub 仓库 + 阿里云 ACR 个人版（免费）；8 个 Secrets 清单见该 skill 的 `SKILL.md`
- `aliyun-ecs-access` 的巡检脚本需要 **密钥登录**（agent 是非交互终端，密码提示会挂死会话）
- 模板里的 `[调整]` 都是需要按自己项目改的占位：镜像仓库名、产物名、健康检查路径、ACR 地域串

## 安全说明

- 仓库内**不含任何真实凭据**：IP、私钥、ACR 实例 ID、账号一律为 `<占位符>` 或走 `${{ secrets.* }}`
- ACR 凭证只用「固定密码」并仅授予镜像仓库读写，不要复用阿里云账号 AK
- 私钥在 workflow 里通过 `env` + `printf` 写入文件，不要写进 `run:` 里直接内插 `secrets`
- 安全组只放行必要端口（22 限源 IP + 业务端口），80 被现有业务占用就不要动

## License

MIT
