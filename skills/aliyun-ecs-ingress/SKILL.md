---
name: aliyun-ecs-ingress
description: 将新网站、API 或 Docker 服务接入 foxii.cn 阿里云 ECS 的 Caddy 公网入口，或修改现有路由、网络、证书与安全组时使用。包含当前已验证的生产拓扑和安全约束。
---

# 阿里云 ECS 入口部署

将项目部署到 `foxii.cn` 的 ECS，或修改其域名路由、共享网络、Caddy
证书和安全组时使用本 Skill。先读取并复核实时状态；本文件最后核对于
2026-09-28。

## 已验证资源

- 云厂商：阿里云 ECS，华东 1（杭州）。
- 实例 ID：`i-bp1hrhh2re91a21i7tgs`；主机名：`iZbp1hrhh2re91a21i7tgsZ`。
- 公网 IPv4：`47.99.245.119`；系统：CentOS 7.9 64 位。
- 规格：`2 vCPU / 2 GiB RAM / 40 GiB` 系统盘；公网带宽峰值
  `100 Mbps`，按流量计费。
- 本机 SSH 别名：`foxii`；私钥：`~/.ssh/foxii`；用户：`root`。
- 不要复制、上传、提交或打印私钥内容。

验证：

```bash
ssh -G foxii | sed -n '1,80p'
ssh foxii 'hostname && docker ps --format "{{.Names}}\t{{.Status}}"'
```

## 当前公网入口

公网 `80/tcp` 和 `443/tcp` 只由 `/srv/foxii` 的 `foxii-caddy`
容器占用。不要在宿主机或另一个容器启动 Nginx/Caddy 并绑定这两个端口。

当前路由：

| 公网入口 | Caddy 上游 | 已验证路径 |
| --- | --- | --- |
| `foxii.cn/*` | `foxii-web:3000` | `GET /` 返回 `200` |
| `foxii.cn/forvision*` | `forvision-service:3000` | `/forvision/api/health` |
| `forclass.foxii.cn/*` | `forclass-ai:8000` | `/health` |
| `foxii.cn/apple-tv-ai-subtitles/*` | `appletv-ai-subtitles-web:8080` | 兼容页面 |

应用路由片段由各自仓库维护并同步到 `/srv/foxii/routes/`：

- `myweb/deploy/caddy/myweb.caddy`
- `ForVision/server/deploy/caddy/forvision.caddy`
- `ForClass/server/deploy/caddy/forclass.caddy`

infra 仓库只负责根 `Caddyfile`、共享网络、证书卷和路由装配。不要直接
在服务器上创建不可追踪的长期路由。

## 网络、卷与安全组

`foxii-edge` 是 Caddy 与应用容器共享的外部 Docker 网络。应用容器只暴露
给该网络，通常不发布公网端口。

必须保留的状态卷：

- `foxii-caddy-data`：ACME 证书、私钥和 Caddy 状态。
- `foxii-caddy-config`：Caddy 配置状态。
- `forvision_metadata`、`forvision_images`：ForVision 持久数据与图片缓存。
- `forclass-ai_forclass_ai_redis`：ForClass Redis AOF。

入方向安全组 `sg-bp1hrhh2re91a40dwgv6` 最终只应保留：

- `22/tcp`：SSH。
- `80/tcp`、`443/tcp`：HTTP/HTTPS 入口。

旧 ForConnection Coturn 已下线。`3478/tcp`、`3478/udp`、
`49160-49200/tcp`、`49160-49200/udp` 必须删除；不要新增这些端口或旧
TURN relay 范围。新 Web/API 服务只通过 Docker 网络接入 Caddy。

## 接入新项目

1. 确认目标域名、路径、上游容器名与端口、普通 HTTP/SSE/WebSocket
   需求及健康检查路径。
2. 在阿里云云解析 DNS 添加 A 记录，值为 `47.99.245.119`；先确认根域
   和已有子域没有冲突。
3. 在业务仓库维护 Caddy route fragment。应用容器加入 `foxii-edge`，
   不发布公网端口，并配置健康检查和 `restart: unless-stopped`。
4. 运行 infra 的 `./scripts/sync-routes.sh`，再运行
   `./scripts/reload.sh`。后者必须先在生产容器内执行 `caddy validate`。
5. 用目标域名验证 HTTPS、预期路径、上游健康检查和容器日志。证书签发
   可能需要 DNS 传播完成。

普通 API 示例：

```caddyfile
handle /example* {
    reverse_proxy example-api:8080
}
```

`reverse_proxy` 支持 WebSocket 与 SSE。长连接按应用需求设置超时，不要
套用短请求限制。

## ForClass 大模型代理与限流

只将模型请求转发到外部模型 API；这台 `2 vCPU / 2 GiB` ECS 不应用于
本地模型推理。ForClass 的 FastAPI、Redis 和 Live Activity worker 继续
保留，旧腾讯云 SCF 实现已经删除。

生产并发必须保持在安全范围内。当前实例没有 swap；若出现 OOM，先调整
业务并发，不得删除 Redis 或 ForVision 持久卷。

## 每次操作前后复核

在任何生产变更前后执行：

```bash
ssh foxii '
  cd /srv/foxii &&
  docker compose config >/dev/null &&
  docker compose ps &&
  docker compose exec -T caddy caddy validate \
    --config /etc/caddy/Caddyfile --adapter caddyfile
'

curl -fsSI https://foxii.cn/
curl -fsS https://foxii.cn/forvision/api/health
curl -fsS https://forclass.foxii.cn/health
```

下载或更新共享路由：

```bash
cd /Users/mac038/Documents/GitHub/infra
./scripts/sync-routes.sh
./scripts/reload.sh
```

停止并先请求确认的情形：替换 Caddy，重启或删除现有业务容器，修改安全组
或 DNS，暴露应用端口，写入 API Key/密钥，删除任何持久卷，或健康检查失败。

严禁重新使用 `forconnection-server_internal`、`forconnection-server-caddy-1`、
Signal、Coturn、`signal.foxii.cn` 或 `/root/forconnection-server`。
