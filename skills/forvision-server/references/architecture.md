# ForVision Server Architecture

Read this reference before changing code under `server/`. It describes the current service boundaries and the persistent state that must survive deployments.

## Runtime And Commands

- `server/` is a Next.js 16 service running on Node.js.
- The service package is `forvision-service`; server tests are `server/tests/*.test.ts`.
- Run commands from `server/`:

  ```bash
  npm run dev
  npm run check
  npm test
  npm run build
  npm run audit:movie-archives
  ```

- The server's primary helper modules are:
  - `src/lib/storage.ts`: durable JSON writes and in-process serialization.
  - `src/lib/http.ts`: validation-friendly errors, body limits, rate limiting, admin auth.
  - `src/lib/upstream.ts`: TMDB request behavior and response caching.
  - `src/lib/metadata.ts`: IMDb-anchored movie lookup and durable metadata.
  - `src/lib/curation.ts`: selected artwork and movie archive lifecycle.
  - `src/lib/images.ts`: validated TMDB image proxy/cache.
  - `src/lib/awards.ts`: versioned award tables and movie snapshots.
  - `src/lib/passes.ts`: Apple Wallet pass issuance and signed retrieval.

## Persistent State Versus Cache

`DATA_DIRECTORY` defaults to `./data` and is persistent state. In production Docker it is mounted as `/data`. Do not clear it in code, deployments, maintenance scripts, or tests pointed at a real environment.

`storage.ts` writes JSON atomically with restrictive file permissions (`0600`) and serializes concurrent operations in-process. Keep that model for additions that modify the same durable object.

Important durable files include:

- `movies/<imdbID>/object.json`: the versioned movie archive, including language maps, people, ratings, release information, awards, media metadata, and revision.
- `movies/<imdbID>/media-...webp`: compressed selected poster, backdrop, and logos referenced by `object.json`.
- `awards-<event>.json`: editable award tables.
- `pass-<UUID>.json`: immutable issued pass inputs.

`IMAGE_CACHE_DIRECTORY` defaults to `./image-cache` and is `/images` in production. It is an LRU cache of regenerable upstream images, not a movie archive. `IMAGE_CACHE_MAX_BYTES` defaults to 5 GiB; cached entries remain fresh for 30 days. Do not turn all browsed gallery images into permanent assets.

Server-led archive media is different: the server downloads the selected TMDB candidates, compresses them losslessly, and atomically writes only the referenced poster, backdrop, and logos. Posters and logos are capped at 500 KB; backdrops are capped at 1 MB. Replacing an archive removes obsolete media files after the new object is durable.

## Movie Metadata And API Contracts

The client-facing flow is:

- `GET /api/v1/movies/search`
- `GET /api/v1/movies/resolve`
- `GET /api/v1/movies/[imdbID]`

Movie identity is normalized around IMDb IDs. `metadata.ts` verifies TMDB-to-IMDb mappings exactly, including reverse validation when the request starts with TMDB data. Preserve this protection; do not accept a loose or guessed mapping.

Movie details are server-led durable archives, not a TTL cache. `GET /api/v1/movies/[imdbID]` reads `data/movies/<imdbID>/object.json` first and never contacts TMDB when an archive exists. If no archive exists, the route fetches and validates a TMDB draft, returns complete non-media details with `status: "preparing"`, and starts one deduplicated background job. That job downloads and compresses the selected media, then writes the archive atomically. Later requests return `status: "archived"` with disk media URLs.

Ordinary first archiving must not require a client upload secret, upload ticket, or multipart submission. The former `ARCHIVE_UPLOAD_SECRET` client protocol is obsolete. Admin rebuilds use the authenticated admin routes, may replace an existing archive, and still use the same server download/compression path.

Archive text is stored as language maps. Titles and logos preserve `zh-CN` plus the original language; other displayed text prefers `zh-CN` and falls back to the original language. The structure must remain extensible to additional language codes.

`upstream.ts` uses `TMDB_READ_TOKEN` as a Bearer credential. It has deliberate behavior:

- Search/trending TMDB responses are cached for 15 minutes.
- Other TMDB API responses are cached for 24 hours.
- A stale cached response may be used for up to 7 days only when TMDB returns 429, 502, or 503.
- Requests time out after 15 seconds, carefully retry only transient failures, and honor `Retry-After`.

Do not alter caching, retry, stale-response, or identity validation rules without focused tests.

## Artwork And Image Serving

`movie-archive.ts` owns the server-led archive schema, TMDB media download, lossless compression, atomic writes, and archive media responses. The administrator's gallery remains transient.

When changing curation:

- Enforce type, language, orientation, and ownership checks from the existing artwork schema and `artwork-gallery.ts`.
- Do not accept arbitrary image URLs or filenames.
- Keep media downloads bounded by allowlisted TMDB URLs and the established size limits.
- Preserve in-process deduplication, atomic object replacement, and first-archive idempotency.

`images.ts` accepts only allowlisted TMDB sizes and safe image filenames. `/api/v1/images/...` fetches and caches validated TMDB images. `/api/v1/movies/[imdbID]/media/...` serves compressed archive media; legacy archive paths remain readable. Do not weaken the URL/path validation or proxy arbitrary remote content.

## Awards

`awards.ts` owns 13 versioned tables:

`cannes`, `berlin`, `venice`, `oscars`, `sundance`, `toronto`, `locarno`, `iffr`, `biff`, `tokyo`, `golden-horse`, `bafta`, and `golden-globes`.

Award updates are optimistic-concurrency writes and are reflected into movie archive snapshots. The unified administrator API is `/api/admin/awards`; do not restore old per-award mutation routes. Official SVG assets are in `server/public/award-logos/`, with provenance notes in `SOURCES.md`.

## Admin And Service Security

`requireAdmin()` uses Basic authentication with `ADMIN_PASSWORD`; it requires at least 16 characters. Mutating admin routes enforce same-origin checks. `rateLimit()` is process-local, so do not mistake it for distributed-rate-limit protection.

For endpoints:

- Use `jsonBody()` instead of unbounded `request.json()` for request bodies.
- Use `failure()` for sanitized user-facing errors.
- Validate request input with the established Zod schemas.
- Keep mutations behind `requireAdmin()` where the existing domain expects administration.

Never introduce unauthenticated administrator writes, arbitrary remote URL fetching, user-controlled filesystem paths, raw exception responses, or logging of credentials/secrets.

## Wallet Passes

`/api/v1/passes` is explicitly Node runtime. `passes.ts` issues and signs Apple Wallet passes.

Pass signing requires:

```text
PASS_TYPE_IDENTIFIER
APPLE_TEAM_IDENTIFIER
PASS_SIGNER_CERT_PATH
PASS_SIGNER_KEY_PATH
PASS_WWDR_CERT_PATH
```

`PASS_LINK_SECRET` must be at least 32 characters. Signed pass handoff links require a valid HTTPS `PUBLIC_BASE_URL`. Existing pass IDs are immutable: retrying issuance may reproduce the pass, but it must never reschedule or rewrite the saved screening.

## Deployment

`server/scripts/deploy_service.sh` is an externally mutating production deployment. It builds a standalone application, packages it without credentials/certificates, creates a rollback Docker image tag on the host, rsyncs the staged output, then runs `docker compose up -d --build --wait`.

Do not run it without explicit user approval. The service is deployed at `/srv/forvision`, joins the external `foxii-edge` network, and is reached publicly through `/srv/foxii` Caddy as `https://foxii.cn/forvision`.

Changes to the public Caddy ingress or routing use the separate `aliyun-ecs-ingress` skill. Keep environment files, certificates, and persisted `/data` and `/images` out of deployment artifacts and source control. Never run `docker compose down -v`, and never remove the `forvision_metadata` or `forvision_images` volumes.
