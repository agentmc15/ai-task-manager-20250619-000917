#!/usr/bin/env bash
set -euo pipefail
#
# Clarity — Production Deployment (no sudo required)
#
# Usage:
#   cd /etc/clarity/GRCAA-Clarity/projects/clarity-rewrite
#   git pull origin aws-feat-clarity-rewrite
#   bash deploy/deploy.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="/etc/clarity/.env"
COMPOSE_FILE="$APP_DIR/docker-compose.production.yaml"

echo ""
echo "=== Clarity Production Deploy ==="
echo ""

# --- Preflight ---
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found. Run setup-server.sh first."
    exit 1
fi

if ! docker info &>/dev/null; then
    echo "ERROR: Cannot connect to Docker."
    exit 1
fi

# --- 1. Ensure .env symlinks ---
echo "  [1/4] Linking .env..."
ln -sf "$ENV_FILE" "$APP_DIR/.env"
ln -sf "$ENV_FILE" "$APP_DIR/backend/.env"
ln -sf "$ENV_FILE" "$APP_DIR/frontend/.env"

# --- 2. Build containers ---
echo "  [2/4] Building containers..."
cd "$APP_DIR"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build

# --- 3. Restart services ---
echo "  [3/4] Restarting services..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

# --- 4. Health check ---
echo "  [4/4] Waiting for services..."
sleep 15

docker compose -f "$COMPOSE_FILE" ps
echo ""
curl -sf http://localhost:4000/auth/ && echo "  Backend:  OK" || echo "  Backend:  not ready yet"
curl -sf http://localhost:3000 > /dev/null 2>&1 && echo "  Frontend: OK" || echo "  Frontend: not ready yet"

echo ""
echo "=== Deploy Complete ==="
echo ""
echo "  Logs: docker compose -f $COMPOSE_FILE logs -f"
echo ""
