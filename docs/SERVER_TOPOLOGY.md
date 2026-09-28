# foxii 服务器业务链路与职责

最后核验：2026-09-28。

## 总览

这台阿里云 ECS 是 `2 vCPU / 2 GiB RAM / 40 GiB` 的单一 Docker
宿主机。公网 `80/tcp` 和 `443/tcp` 只由 `foxii-caddy` 容器占用。
应用容器通过外部网络 `foxii-edge` 接入 Caddy，业务代码不负责申请证书，
也不应自行发布公网端口。

职责边界如下：

| 仓库 | 职责 | 生产位置 | 路由归属 |
| --- | --- | --- | --- |
| `infra` | Caddy、共享网络、证书卷、路由装配、部署与回滚文档 | `/srv/foxii` | 全局入口 |
| `myweb` | 公开首页归档轮播、`/movies/tt...` 只读详情 | `/srv/myweb` | `foxii.cn` 默认路由 |
| `ForVision` | APP、管理员、电影归档、TMDB 网关、奖项和 Wallet pass | `/srv/forvision` | `foxii.cn/forvision*` |
| `ForClass` | FastAPI AI 识别代理、Redis 限流/取消队列、Live Activity worker | `/root/forclass-ai` | `forclass.foxii.cn` |

Apple TV AI 字幕页面是 infra 兼容维护的独立路由，不属于以上三个业务仓库。

## 公共入口

| 公网入口 | Caddy 上游 | 验证路径 |
| --- | --- | --- |
| `https://foxii.cn/*` | `foxii-web:3000` | `/`、`/movies/tt0109685` |
| `https://foxii.cn/forvision*` | `forvision-service:3000` | `/forvision/api/health` |
| `https://forclass.foxii.cn/*` | `forclass-ai:8000` | `/health` |
| `https://foxii.cn/apple-tv-ai-subtitles/*` | `appletv-ai-subtitles-web:8080` | 兼容页面 |

路由片段由业务仓库单独维护，infra 的 `scripts/sync-routes.sh` 只负责同步：

```text
myweb/deploy/caddy/myweb.caddy
ForVision/server/deploy/caddy/forvision.caddy
ForClass/server/deploy/caddy/forclass.caddy
```

修改路由后先运行 `./scripts/reload.sh`，它会在生产容器内执行
`caddy validate`，成功后才 reload。

## 容器与网络

| 容器 | 镜像/用途 | 网络 | 持久化 |
| --- | --- | --- | --- |
| `foxii-caddy` | `caddy:2.10.0-alpine` | `foxii-edge` | `foxii-caddy-data`、`foxii-caddy-config` |
| `foxii-web` | `myweb-web` | `foxii-edge` | 无；只读 ForVision 归档 |
| `forvision-service` | `forvision-service:latest` | `foxii-edge` | `forvision_metadata`、`forvision_images` |
| `forclass-ai` | ForClass FastAPI | `foxii-edge`、`forclass-ai-backend` | 挂载 APNs 只读密钥 |
| `forclass-live-activity-worker` | ForClass Live Activity worker | `foxii-edge`、`forclass-ai-backend` | 无 |
| `forclass-ai-redis` | `redis:7-alpine` | `forclass-ai-backend` | `forclass-ai_forclass_ai_redis` |
| `appletv-ai-subtitles-web` | 静态兼容页面 | `foxii-edge` | 无 |

禁止重新创建旧网络 `forconnection-server_internal`，也不要恢复旧
`forconnection-server-caddy-1`、Signal 或 Coturn 容器。

## 持久数据

以下卷属于生产状态，任何部署都不允许执行 `docker compose down -v`：

- `forvision_metadata`：`/data`，电影归档、奖项表和 Wallet pass 输入。
- `forvision_images`：`/images`，可再生的 TMDB 图片缓存。
- `forclass-ai_forclass_ai_redis`：ForClass Redis AOF，包含取消状态、
  限流和 Live Activity 队列。
- `foxii-caddy-data`：ACME 证书、私钥和 Caddy 状态；不得重建。
- `foxii-caddy-config`：Caddy 配置状态。

`myweb` 不保存电影副本。首页和详情在请求时只读调用 ForVision 的
`/api/compat/myweb/*`，不会因为公开访问触发 TMDB 回源或创建归档。

## 部署与发布顺序

1. 应用仓库分别通过 `npm test`、`npm run build`、`pnpm check`、
   `pnpm test` 或 Python 回归测试完成本地验证。
2. 部署 `myweb`、`ForVision` 或 `ForClass` 时只更新各自容器；生产
   环境文件、证书和持久卷留在服务器。
3. 若业务仓库的路由片段有变化，运行 infra 的
   `./scripts/sync-routes.sh`，再运行 `./scripts/reload.sh`。
4. 运行生产健康检查，确认入口、上游容器和关键只读路径均正常。
5. 不使用 `docker compose down -v`，不删除旧镜像回滚标签，不把
   `.env`、APNs 密钥、Wallet 证书或 TMDB token 提交到 Git。

常用检查：

```bash
ssh foxii '
  cd /srv/foxii &&
  docker compose ps &&
  docker compose exec -T caddy caddy validate \
    --config /etc/caddy/Caddyfile --adapter caddyfile
'

curl -fsSI https://foxii.cn/
curl -fsS https://foxii.cn/api/movie-catalog?feed=popular
curl -fsS https://foxii.cn/forvision/api/health
curl -fsS https://forclass.foxii.cn/health
```

## 容量约束

该实例没有 swap。当前正常负载下系统剩余可用内存约 1.1 GiB，但 ForClass
图像识别和 ForVision 图片归档仍应保持并发上限。若再次出现 OOM，优先
调整业务并发，不能通过删除持久卷或牺牲 `/data`、Redis 数据解决。

## 已下线边界

MyServer、旧 ForConnection Signal、Coturn、旧 Caddy 和对应安全组端口
均已从生产链路移除。新服务不得再依赖 `/root/forconnection-server` 或
`signal.foxii.cn`。
