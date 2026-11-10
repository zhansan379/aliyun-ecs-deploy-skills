---
name: aliyun-ecs-access
description: 阿里云及国内云 ECS 服务器首次接入、SSH 登录排查与部署前环境巡检。Use whenever the user wants to SSH into their Aliyun/China-cloud server, reports root password login failing (Permission denied / Authentication method not allowed), asks to deploy anything to their own server, or wants a pre-deployment inspection of region/memory/docker/ports/已有业务. Keywords: 服务器登录、连不上服务器、安全组、免密登录、巡检。
---

# 阿里云 ECS 首次接入与巡检

## 第一条铁律：agent 是非交互终端

`ssh` 密码提示会挂死会话，Windows Git Bash 又没有 sshpass。所以：

- 一切操作走**密钥 + `-o BatchMode=yes`**，绝不走到密码提示；
- 用户在聊天里给了密码 ≠ 能用密码登录（见下），先用它探测认证方式。

## 根因判断：root 密码被拒 ≠ 密码错误

国内云镜像普遍配置 `PermitRootLogin prohibit-password`，root 只能密钥登录。区分方法：

```bash
# 列出服务器允许的认证方式
ssh -o BatchMode=yes -o ConnectTimeout=10 root@<IP> exit 2>&1
# 输出 "Permission denied (publickey,...,password)" → password 在列表里只代表全局允许，
# 是否真放行 root 还要看实际尝试
```

用 Node ssh2 库做密码认证时，日志里出现 **`Authentication method not allowed: password`** = 服务器按方法拒绝（root 被禁密码，与密码对错无关）；如果是"密码错误"，表现是 auth 失败但方法仍在 allowed 列表。Windows 下没有 sshpass 时，用 `npm i ssh2` + 简短脚本做密码引导（`authHandler: ['keyboard-interactive', 'password']`，密码经环境变量传入，不要写进文件）。

## 接入流程

1. **探测端口并写入 known_hosts**（不通 = 安全组没放行，只能用户在控制台加规则，agent 无法代劳）：
   ```bash
   ssh-keyscan -T 8 -p 22 -H <IP> 2>&1 | tee -a ~/.ssh/known_hosts
   ```
2. **生成专用部署密钥**（不复用个人密钥）：
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/<project>-deploy -N "" -C "<project>-deploy"
   ```
3. **安装公钥**——按可行渠道二选一：
   - 用户自己在任何能以 root 进入的渠道执行（推荐让用户粘贴，幂等）：
     ```bash
     mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo '<公钥整行>' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && echo KEY_INSTALLED
     ```
   - 密码登录确实可用时（Node ssh2 引导成功）：远程执行同上命令（`grep -qF` 防重复追加）。
4. **验证**：
   ```bash
   ssh -i ~/.ssh/<project>-deploy -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@<IP> "echo KEY_LOGIN_OK"
   ```

## 部署前巡检（必须做，一条命令打包）

运行本技能自带的巡检脚本：

```bash
bash scripts/inspect.sh root@<IP> [port] [key路径]
```

它输出：系统版本、CPU/内存/swap/磁盘、阿里云 region-id（`100.100.100.200` 元数据）、Docker 与 Compose 版本、daemon.json 镜像源、**已有容器列表**、内存 TOP5 进程、常用端口占用。

看结果时重点判断四件事：

1. **内存水位**：`available` 低于 1G 且 swap 用满 → 服务器上做任何编译都会 OOM，改走产物模式（见 skill `thin-image-docker-deploy`）；
2. **已有业务**：面板类环境（如宝塔的 `/www/server/`）、数据库等容器往往是用户的生产数据——**不重启 dockerd、不占用已监听端口**（80 常被占，新服务用 8080 起）；
3. **同地域判断**：region-id 与 ACR/对象存储地域一致时，拉取走 VPC 内网地址（见 skill `gh-actions-aliyun-acr-cicd`）；
4. **daemon.json**：若已配置镜像源列表，基础镜像拉取慢是列表里大量死源逐个超时导致，用"镜像源引用拉取 + retag"绕过（模板在 thin-deploy 技能里），**不要重启 docker**（会打断用户的容器）。

## 收尾提醒（说给用户，不阻塞流程）

- 密码若在聊天里出现过，建议 `passwd` 更换；
- 服务器已强制密钥登录是好事，保持；
- 安全组只放行必要的 22（限源 IP）与业务端口（8080 等），80 若被现有业务占用不必再放。
