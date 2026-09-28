---
name: forvision-server
description: Work safely on the ForVision Next.js server, including its movie archive, TMDB gateway, admin APIs, image storage, Wallet passes, and deployment boundaries. Use for work under ForVision/server, not ordinary client-only changes.
---

# ForVision Server

Use this skill for implementation, debugging, reviews, or operational work touching `ForVision/server/`.

Read [the server architecture reference](references/architecture.md) before modifying server behavior. It records durable data ownership, API contracts, safety controls, and externally mutating operations that are not obvious from one route alone.

## Working Rules

- Preserve public contracts in the repository-level `contracts/` directory and existing API semantics unless the requested product change explicitly requires a contract revision.
- Treat `DATA_DIRECTORY` as persistent production state. Do not reset, delete, or repurpose it. Keep durable movie archives distinct from the regenerable upstream image cache.
- Do not expose or commit service secrets, signing material, certificate files, `TMDB_READ_TOKEN`, `ADMIN_PASSWORD`, or `PASS_LINK_SECRET`.
- Reuse the existing storage, HTTP, upstream, metadata, curation, and image helpers instead of introducing parallel persistence, validation, or fetch paths.
- Do not weaken image/path validation, identity validation, admin authentication, same-origin checks, or bounded request parsing.
- Do not run the production deployment script or change public ingress unless the user explicitly asks. For Caddy/public routing work, also use the `aliyun-ecs-ingress` skill.
- Read `infra/docs/SERVER_TOPOLOGY.md` before changing a production route, Docker network, or persistent volume. ForVision has no ownership of `80/443`; Caddy runs in the separate `infra` deployment.

## Validation

For relevant server changes, run from `ForVision/server/`:

```bash
npm run check
npm test
```

Run `npm run audit:movie-archives` when a change affects archive creation, curation, compressed media, metadata persistence, or award snapshots and the required TMDB configuration is available.
