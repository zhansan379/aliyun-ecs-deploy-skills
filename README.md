# 阿里云 ECS 部署技能包

> **一句话**：这是一份写给 AI 编程助手（Claude Code / OpenCode 等）看的「说明书」——让它能照着把你本地的项目，一路部署到国内那台小内存云服务器上，并且做到 push 代码就自动上线。

> 懒得读文档？直接跳到 [一键让 AI 带你部署](#一键让-ai-带你部署复制下面整段)，复制那段提示词即可。

三个 [Agent Skills](https://code.claude.com/docs/en/skills)，把「国内云服务器怎么把项目部署上线」这件事从反复踩坑变成固定流程。

面向的场景：**一台 2G 内存的国内 ECS、80 端口已被占用、跨境网络很慢**——这是绝大多数个人项目和中小企业项目的真实起点。

---

## 它到底做了什么

```mermaid
flowchart LR
    subgraph 本地["你的电脑"]
        A[git push] --> B[GitHub]
    end

    subgraph GH["GitHub Actions"]
        B --> C[build jar / dist]
        C --> D[docker build 产物镜像]
        D --> E[推送阿里云 ACR]
    end

    subgraph 云["阿里云"]
        E --> F[(ACR 镜像仓库)]
        F -->|VPC 内网, 秒级| G[ECS docker pull]
        G --> H[compose up -d]
        H --> I[健康检查: API + 首页]
    end

    I --> J([用户访问 :8080])

    style 云 fill:#fff5f0,stroke:#ff6a00
    style GH fill:#f2f6ff,stroke:#4a7bd0
```

关键点在于**服务器上永远不编译**：Maven/Vite 的构建峰值会吃掉 1GB+ 内存，2G 机器必然 OOM。产物在 GitHub Runner 上构建好，服务器只做 COPY 级镜像组装。

跑起来就是这样一个绿色的 run，从 push 到上线约 2 分钟（`build-and-deploy` 本身 1 分 58 秒）：

![GitHub Actions 运行成功](images/actions-run.png)

## 一键让 AI 带你部署（复制下面整段）

不想逐字读文档的话，把下面这段原样粘给 Claude Code / OpenCode / Cursor 等能读文件、能跑命令的 AI，它会先把这个技能包装到本机，然后一步一步问你的情况、带你走完全流程。

```text
你是我的部署助手。请按下面流程，一步一步带我把自己的项目部署到阿里云 ECS 上。
每一步只做一件事，做完先把结果讲给我，等我确认再继续。

【第 1 步 · 安装技能包】
把 https://github.com/zhansan379/aliyun-ecs-deploy-skills 装到本机：
  git clone --depth 1 https://github.com/zhansan379/aliyun-ecs-deploy-skills /tmp/aliyun-deploy-skills
  bash /tmp/aliyun-deploy-skills/install.sh
装完确认 ~/.claude/skills 或 ~/.agents/skills 下出现 aliyun-ecs-access、
gh-actions-aliyun-acr-cicd、thin-image-docker-deploy 三个目录，
然后完整读一遍这三个 SKILL.md 再动手。

【第 2 步 · 摸清现状】
一次性问我这几个问题（不要一个个挤牙膏）：
  1) 服务器配置：内存多大、是否已装 Docker、有没有 swap
  2) 我的项目技术栈与目录结构（Spring Boot / Vue / Node / Monorepo？）
  3) 服务器上有没有已有业务占着 80、8080 等端口
问完先用 aliyun-ecs-access 的巡检脚本跑一遍，把内存水位、已有容器、端口占用讲给我听，
并明确告诉我这台机器该不该在服务器上编译。

【第 3 步 · SSH 免密】
带我生成专用部署密钥（ed25519，不复用日常 id_rsa）、把公钥装到服务器，
最后用 ssh -i <key> -o BatchMode=yes <user>@<ip> "echo OK" 验证通过。
注意：不要让我把私钥内容贴进对话。

【第 4 步 · 准备 8 个参数】
按 README「需要你准备哪些参数」逐条带我取：
  SSH_HOST / SSH_USER / SSH_PORT / SSH_PRIVATE_KEY
  ACR_REGISTRY / ACR_NAMESPACE / ACR_DOCKER_USERNAME / ACR_DOCKER_PASSWORD
每拿到一个就说明它来自控制台哪一页、后面填到哪里。
我如果贴出敏感值，请提醒我撤回并改用本地文件方式传。

【第 5 步 · 配好 CI/CD】
用 gh-actions-aliyun-acr-cicd 的模板生成 .github/workflows/deploy.yml，
按我的项目改掉所有 [调整] 处（产物名、镜像仓库名、健康检查路径、ACR 地域串），
再用 gh secret set 把 8 个值写进仓库 Secrets。

【第 6 步 · 首次部署与验收】
push 触发部署，失败就用 gh run view <id> --log-failed 看日志并直接给出修法；
成功后登录服务器做双探测（API + 首页），
最后告诉我安全组该放行哪些端口、以及回滚该怎么做。

【硬性约束】
- 服务器上永远不编译，走 thin-image-docker-deploy 的产物模式
- 不重启 dockerd、不占用别人已在监听的端口
- 任何要提交进仓库的文件都不能含真实 IP / 私钥 / 账号 / 实例 ID
- 每步结束用一句话总结：现在状态 / 下一步做什么 / 需要我提供什么
```

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
| GitHub Runner 构建 → 推 ACR → ECS 内网拉取 → 重启 | **约 2–3 分钟**（下方截图这次是 2m03s） |
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

---

## 需要你准备哪些参数

整套流程一共 **8 个值**，全部存在 GitHub 仓库的 Secrets 里（Settings → Secrets and variables → Actions → New repository secret），代码里只引用 `${{ secrets.XXX }}`，不会出现在任何文件或日志中。

先看总表，再按下面的步骤逐个拿：

| # | 名称 | 从哪获取 | 难度 |
|---|---|---|---|
| 1 | `SSH_HOST` | ECS 控制台 → 实例列表 → 公网 IP | 1 分钟 |
| 2 | `SSH_USER` | 一般就是 `root`（阿里云镜像）或 `ecs-user` | 10 秒 |
| 3 | `SSH_PORT` | 默认 `22`，改过端口才需要填 | 10 秒 |
| 4 | `SSH_PRIVATE_KEY` | 本地 `ssh-keygen` 生成，公钥装到服务器 | 5 分钟 |
| 5 | `ACR_REGISTRY` | ACR 个人版 → 实例概览 → 访问域名 | 2 分钟 |
| 6 | `ACR_NAMESPACE` | ACR 个人版 → 命名空间 → 自己创建一个 | 1 分钟 |
| 7 | `ACR_DOCKER_USERNAME` | ACR 个人版 → 访问凭证 → 阿里云账号全名 | 1 分钟 |
| 8 | `ACR_DOCKER_PASSWORD` | ACR 个人版 → 访问凭证 → 设置固定密码 | 1 分钟 |

### 第 1 步：准备服务器 SSH 访问（对应 1–4）

**① 拿到公网 IP（`SSH_HOST`）**

[ECS 实例列表控制台](https://ecs.console.aliyun.com/)（注意先在左上角把地域切成你服务器所在的地域）→ 找到实例 → 复制「公网 IP」或「弹性 IP」那一列。

![在 ECS 实例详情里找公网 IP](images/ecs-instance-ip.png)

不方便开控制台时，登进服务器执行：

```bash
curl -s ifconfig.me    # 输出公网出口 IP
```

> 如果这台机器走 NAT 网关出网，`ifconfig.me` 拿到的是 NAT 的 IP，不是入站地址——以控制台为准。

**② 决定登录用户（`SSH_USER` / `SSH_PORT`）**

阿里云 Linux 镜像默认是 `root`（密码登录）或 `ecs-user`（部分新镜像）。端口没改过就是 `22`。两个值都只在改过默认值时才需要特别确认。

**③ 生成专用部署密钥（`SSH_PRIVATE_KEY`）**

```bash
# 不要复用你日常的 id_rsa，每个项目一把
ssh-keygen -t ed25519 -f ~/.ssh/myapp-deploy -N "" -C "myapp-deploy"
cat ~/.ssh/myapp-deploy.pub      # 公钥，装到服务器
```

**④ 把公钥装到服务器**

最简单的做法是用阿里云 Workbench（控制台里的「远程连接」）登录后粘贴：

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo 'ssh-ed25519 AAAA... myapp-deploy' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

**⑤ 验证免密登录**

```bash
ssh -i ~/.ssh/myapp-deploy -o BatchMode=yes root@<你的IP> "echo OK"
```

输出 `OK` 就对了。**如果出现 `Permission denied (publickey)`**，先看 [`aliyun-ecs-access/SKILL.md`](aliyun-ecs-access/SKILL.md)——里面区分了「密码认证被禁用」和「公钥没装上」两种完全不同的原因。

**⑥ 把私钥写进 Secret**

```bash
gh secret set SSH_HOST --body "1.2.3.4"
gh secret set SSH_USER --body "root"
gh secret set SSH_PORT --body "22"
gh secret set SSH_PRIVATE_KEY < ~/.ssh/myapp-deploy
```

> 私钥文件是**整段内容**（含 `-----BEGIN OPENSSH PRIVATE KEY-----` 两行），不是路径。

### 第 2 步：准备阿里云 ACR 镜像仓库（对应 5–8）

ACR = 容器镜像服务，个人版免费。它的作用是当「中转站」：GitHub 构建好镜像推上去，ECS 从内网拉，比跨境直传快几十倍。

**① 进控制台建个人版实例**

[容器镜像服务控制台](https://cr.console.aliyun.com/)（**先在左上角切到你服务器所在地域**）→ 左侧「实例列表」→ 首次进入会提示开通「个人版实例」，**地域必须选成和你 ECS 同一个**（例如都在 `cn-beijing`）。开通后得到形如 `crpi-xxxxxxxx.cn-beijing.personal.cr.aliyuncs.com` 的域名，这就是 `ACR_REGISTRY`。

![ACR 个人版实例概览：公网/专有网络访问域名](images/acr-registry-domain.png)

> 为什么强调同地域：`deploy.yml` 会读服务器元数据判断地域，同地域时自动把域名换成 `-vpc.` 版本，走内网拉取（免流量、秒级）；跨地域只能走公网，慢且计费。

**② 创建命名空间（`ACR_NAMESPACE`）**

个人版实例详情页 → 左侧「仓库管理 > 命名空间」→ 创建，例如 `myteam`。相当于镜像的目录分组。

**③ 创建镜像仓库**

命名空间内 →「创建镜像仓库」→ 仓库名填 `myapp`（要和 `deploy.yml` 里 `ACR_IMAGE` 的仓库名一致，默认就是 `myapp`）→ 类型选**私有**。

**④ 设置固定密码（`ACR_DOCKER_USERNAME` / `ACR_DOCKER_PASSWORD`）**

个人版实例详情页 → 左侧「仓库管理 > 访问凭证」→ 在「访问凭证」页点「设置固定密码」。

![访问凭证页：设置固定密码 + docker login 命令示例](images/acr-credentials.png)

- 用户名：**阿里云账号全名**（形如 `your_account@example.com`，或 RAM 子账号名），不是昵称
- 密码：刚才设置的固定密码。**这是独立于阿里云登录密码的另一套凭证**，只对镜像仓库有效

> 选项里的「临时密码」有效期只有 1 小时，CI 里绝不能用。

官方文档（个人版）：[创建个人版实例](https://help.aliyun.com/zh/acr/user-guide/create-a-container-registry-personal-edition-instance) ｜ [管理命名空间](https://help.aliyun.com/zh/acr/user-guide/manage-namespaces) ｜ [推送和拉取镜像（含「访问凭证 → 设置固定密码」截图步骤）](https://help.aliyun.com/zh/acr/user-guide/use-a-container-registry-personal-edition-instance-to-push-and-pull-images)

```bash
gh secret set ACR_REGISTRY --body "crpi-xxxxxxxx.cn-beijing.personal.cr.aliyuncs.com"
gh secret set ACR_NAMESPACE --body "myteam"
gh secret set ACR_DOCKER_USERNAME --body "your_account@example.com"
gh secret set ACR_DOCKER_PASSWORD --body "你设置的固定密码"
```

### 第 3 步：放行端口（部署完访问不了，99% 是这里）

[ECS 控制台](https://ecs.console.aliyun.com/)（左上角切地域）→ 左侧「网络与安全 > 安全组」→ 点目标安全组 ID → 入方向 → 手动添加：

| 授权策略 | 协议类型 | 端口范围 | 授权对象 | 用途 |
|---|---|---|---|---|
| 允许 | 自定义 TCP | `22/22` | **你的固定 IP**/32 | SSH，别用 `0.0.0.0/0` |
| 允许 | 自定义 TCP | `8080/8080` | `0.0.0.0/0` | 应用对外访问 |

官方文档：[使用安全组](https://help.aliyun.com/zh/ecs/user-guide/start-using-security-groups)

> 80 端口常被服务器上已有的面板/nginx 占用，新服务一律从 8080 起，不要去抢 80。

### 一次性核对

```bash
gh secret list          # 应该正好 8 条
```

![GitHub 仓库 Secrets 列表（值不可见，天然安全）](images/gh-secrets.png)

漏了也不至于炸：`deploy.yml` 里有一个 `guard` 步骤，Secrets 没配齐时直接跳过部署并打印提示，仓库不会一上来就飘红。

### 可选参数

以下不是 Secret，按需在 `deploy.yml` / `deploy.sh` 里改：

| 参数 | 默认值 | 说明 |
|---|---|---|
| `REMOTE_DIR` | `/opt/myapp` | 服务器上的部署目录 |
| `STAGE_DIR` | `./deploy-pkg` | 本地 staging 目录（`deploy.sh` 用） |
| `DEPLOY_KEY` | `~/.ssh/deploy` | 本地部署私钥路径 |
| `IMAGE_NAME` | `myapp` | 本地镜像名，要和 compose 里的 `image:` 一致 |

## 安全说明

- 仓库内**不含任何真实凭据**：IP、私钥、ACR 实例 ID、账号一律为 `<占位符>` 或走 `${{ secrets.* }}`
- ACR 凭证只用「固定密码」，不要复用阿里云账号 AK（AK 泄露 = 可被刷机器）
- 私钥在 workflow 里通过 `env` + `printf` 写入文件，不直接内插进 `run:` 命令行
- 安全组只放行必要端口（22 限源 IP + 业务端口），80 被现有业务占用就不要动
- 密码如果曾在聊天/文档里出现过，部署完 `passwd` 改一次

## License

MIT
