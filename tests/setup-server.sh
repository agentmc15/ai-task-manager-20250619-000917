#!/usr/bin/env bash
set -euo pipefail
#
# Clarity — First-Time Server Setup
#
# Prerequisites (run once with sudo):
#   sudo mkdir -p /etc/clarity
#   sudo chown $USER:$USER /etc/clarity
#   sudo usermod -aG docker $USER && newgrp docker
#
# Then:
#   cd /etc/clarity/GRCAA-Clarity/projects/clarity-rewrite
#   bash deploy/setup-server.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="/etc/clarity/.env"
COMPOSE_FILE="$APP_DIR/docker-compose.production.yaml"

echo ""
echo "=== Clarity Server Setup ==="
echo ""
echo "  App directory: $APP_DIR"
echo "  Env file:      $ENV_FILE"
echo ""

# --- Preflight checks ---
if ! docker info &>/dev/null; then
    echo "ERROR: Cannot connect to Docker."
    echo "Run:  sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE not found."
    echo ""
    echo "Create it from the template:"
    echo "  cp $SCRIPT_DIR/.env.production.example /etc/clarity/.env"
    echo "  chmod 600 /etc/clarity/.env"
    echo "  nano /etc/clarity/.env"
    echo ""
    echo "Then re-run this script."
    exit 1
fi

# --- 1. Symlink .env into app directories ---
echo "  [1/5] Linking .env..."
ln -sf "$ENV_FILE" "$APP_DIR/.env"
ln -sf "$ENV_FILE" "$APP_DIR/backend/.env"
ln -sf "$ENV_FILE" "$APP_DIR/frontend/.env"

# --- 2. Install nginx config ---
echo "  [2/5] Installing nginx config..."
if [ -f "$SCRIPT_DIR/nginx/clarity.conf" ]; then
    sudo cp "$SCRIPT_DIR/nginx/clarity.conf" /etc/nginx/conf.d/clarity.conf
    sudo nginx -t && sudo systemctl reload nginx
    echo "         nginx config installed and reloaded"
else
    echo "         WARNING: nginx/clarity.conf not found — skipping"
fi

# --- 3. Install systemd service ---
echo "  [3/5] Installing systemd service..."
if [ -f "$SCRIPT_DIR/clarity.service" ]; then
    sudo cp "$SCRIPT_DIR/clarity.service" /etc/systemd/system/clarity.service
    sudo systemctl daemon-reload
    sudo systemctl enable clarity
    echo "         systemd service installed and enabled"
else
    echo "         WARNING: clarity.service not found — skipping"
fi

# --- 4. Build containers ---
echo "  [4/5] Building containers..."
cd "$APP_DIR"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" build

# --- 5. Start services ---
echo "  [5/5] Starting services..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

echo ""
echo "  Waiting for services to start..."
sleep 15

docker compose -f "$COMPOSE_FILE" ps
echo ""
curl -sf http://localhost:4000/auth/ && echo "  Backend:  OK" || echo "  Backend:  not ready yet (check logs)"
curl -sf http://localhost:3000 > /dev/null 2>&1 && echo "  Frontend: OK" || echo "  Frontend: not ready yet (check logs)"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. If first deploy, set SEED_DATA=true in $ENV_FILE and restart:"
echo "     docker compose -f $COMPOSE_FILE --env-file $ENV_FILE restart backend"
echo ""
echo "  2. After seed completes, set SEED_DATA=false and restart again"
echo ""
echo "  3. Verify: curl https://clarity.onertx.com/auth/"
echo ""
echo "  4. Logs:  docker compose -f $COMPOSE_FILE logs -f"
echo ""
