#!/usr/bin/env bash
set -euo pipefail

MYWEB_DIR="${MYWEB_DIR:-/Users/mac038/Documents/GitHub/myweb}"
FORVISION_DIR="${FORVISION_DIR:-/Users/mac038/Documents/GitHub/ForVision}"
FORCLASS_DIR="${FORCLASS_DIR:-/Users/mac038/Documents/GitHub/ForClass}"
REMOTE="${REMOTE:-foxii:/srv/foxii/routes}"

rsync -az --delete routes/ "$REMOTE/"
rsync -az "$MYWEB_DIR/deploy/caddy/myweb.caddy" "$REMOTE/foxii/myweb.caddy"
rsync -az "$FORVISION_DIR/server/deploy/caddy/forvision.caddy" "$REMOTE/foxii/forvision.caddy"
rsync -az "$FORCLASS_DIR/server/deploy/caddy/forclass.caddy" "$REMOTE/forclass/forclass.caddy"
