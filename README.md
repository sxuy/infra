# foxii Infrastructure

This repository owns the shared public ingress and deployment contract for
`myweb`, `ForVision`, and `ForClass`. It does not own application business
logic or persistent application data.

Read [docs/SERVER_TOPOLOGY.md](docs/SERVER_TOPOLOGY.md) before changing a
route, network, volume, or production deployment. The operational skill under
`skills/aliyun-ecs-ingress/` is the concise runbook for changes on the Aliyun
ECS instance.

## Runtime Layout

The production checkout is `/srv/foxii`.

- `Caddyfile` defines the public sites and imports route fragments.
- `routes/foxii/*.caddy` contains myweb, ForVision, and the retained Apple TV
  compatibility route.
- `routes/forclass/*.caddy` contains the ForClass route.
- `foxii-edge` is the shared external Docker network used by Caddy and all
  publicly proxied application containers.
- `foxii-caddy-data` and `foxii-caddy-config` persist TLS certificates and
  Caddy state.

Application repositories own their route fragments:

- `myweb/deploy/caddy/myweb.caddy`
- `ForVision/server/deploy/caddy/forvision.caddy`
- `ForClass/server/deploy/caddy/forclass.caddy`

## Safe Operations

Never remove the Caddy volumes during an application deployment. Validate
configuration before reload:

```bash
./scripts/bootstrap.sh
./scripts/sync-routes.sh
./scripts/reload.sh
```

Check public health after a reload:

```bash
curl -fsSI https://foxii.cn/
curl -fsS https://foxii.cn/forvision/api/health
curl -fsS https://forclass.foxii.cn/health
```
