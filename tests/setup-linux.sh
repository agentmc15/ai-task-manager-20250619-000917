#!/usr/bin/env bash
# =============================================================================
# Clarity Rewrite - Linux/AWS Setup
# =============================================================================
# Run: chmod +x scripts/setup-linux.sh && ./scripts/setup-linux.sh
# Prereqs: Docker, Docker Compose, Python 3.12+, Node.js 20+
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_GRAY='\033[0;37m'
C_RESET='\033[0m'

echo ""
echo -e "${C_CYAN}=============================================${C_RESET}"
echo -e "${C_CYAN}  Clarity Rewrite - Linux Setup${C_RESET}"
echo -e "${C_CYAN}=============================================${C_RESET}"
echo ""

# --- 1. Check prerequisites ---
echo -e "${C_YELLOW}[1/8] Checking prerequisites...${C_RESET}"
MISSING=""
command -v docker >/dev/null 2>&1 || MISSING="$MISSING Docker"
command -v python3 >/dev/null 2>&1 || MISSING="$MISSING Python3"
command -v node >/dev/null 2>&1 || MISSING="$MISSING Node.js"
command -v npm >/dev/null 2>&1 || MISSING="$MISSING npm"

if [ -n "$MISSING" ]; then
    echo -e "${C_RED}  MISSING:$MISSING${C_RESET}"
    echo -e "${C_RED}  Install the missing tools and re-run.${C_RESET}"
    exit 1
fi

echo -e "${C_GREEN}  Python:  $(python3 --version 2>&1)${C_RESET}"
echo -e "${C_GREEN}  Node:    $(node --version 2>&1)${C_RESET}"
echo -e "${C_GREEN}  Docker:  $(docker --version 2>&1)${C_RESET}"

if ! docker info >/dev/null 2>&1; then
    echo -e "${C_RED}  Docker daemon is not running.${C_RESET}"
    exit 1
fi
echo -e "${C_GREEN}  Docker:  Running${C_RESET}"

# --- 2. Create .env ---
echo ""
echo -e "${C_YELLOW}[2/8] Setting up environment...${C_RESET}"
if [ ! -f "$ROOT/.env" ]; then
    if [ -f "$ROOT/.env.example" ]; then
        cp "$ROOT/.env.example" "$ROOT/.env"
    else
        cat > "$ROOT/.env" << 'ENVBLOCK'
CLARITY_SQL_DB=clarity
CLARITY_SQL_USER=clarity
CLARITY_SQL_PASSWORD=clarity
CLARITY_SQL_HOST=localhost
CLARITY_SQL_PORT=5432
CLARITY_KC_REALM=clarity
CLARITY_KC_ADMIN=admin
CLARITY_KC_ADMIN_PASSWORD=admin
CLARITY_KC_MGMT_CLIENT_SECRET=
COMP_OIDC_CLIENT_ID=clarity-app
COMP_OIDC_CLIENT_SECRET=
META_OPENAI_URL=
META_OPENAI_KEY=
ARCHER_USERNAME=
ARCHER_PASSWORD=
ARCHER_INSTANCE_NAME=ArcherRTX PROD
ARCHER_BASE_URI=https://archergrc.corp.ray.com
ARCHER_SOAP_SEARCH_URI=
ARCHER_SOAP_GENERAL_URI=
MAPPING_REPORT=
SEED_DATA=true
SEED_RAG=false
NUXT_API_BASE=http://localhost:4000
NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3001/auth/callback
NUXT_SESSION_PASSWORD=clarity-session-password-minimum-32-characters-long
ENVBLOCK
    fi
    echo -e "${C_GREEN}  Created .env${C_RESET}"
else
    echo -e "${C_GREEN}  .env exists, skipping${C_RESET}"
fi

# Export env vars
set -a
source "$ROOT/.env"
set +a

# --- 3. Start Docker (PostgreSQL + Keycloak) ---
echo ""
echo -e "${C_YELLOW}[3/8] Starting PostgreSQL + Keycloak...${C_RESET}"
docker compose up -d db keycloak

echo -e "${C_GRAY}  Waiting for PostgreSQL...${C_RESET}"
for i in $(seq 1 30); do
    if docker exec clarity-db pg_isready -U clarity 2>/dev/null | grep -q "accepting"; then
        echo -e "${C_GREEN}  PostgreSQL ready${C_RESET}"
        break
    fi
    sleep 2
done

echo -e "${C_GRAY}  Waiting for Keycloak (~30s)...${C_RESET}"
sleep 15
for i in $(seq 1 20); do
    if curl -sf http://localhost:8080/kc/health/ready >/dev/null 2>&1; then
        echo -e "${C_GREEN}  Keycloak ready${C_RESET}"
        break
    fi
    sleep 3
done

# --- 4. Python venv + deps ---
echo ""
echo -e "${C_YELLOW}[4/8] Setting up Python backend...${C_RESET}"
BACKEND="$ROOT/backend"

if [ ! -d "$BACKEND/.venv" ]; then
    python3 -m venv "$BACKEND/.venv"
    echo -e "${C_GREEN}  Created venv${C_RESET}"
fi

source "$BACKEND/.venv/bin/activate"
pip install -r "$BACKEND/requirements.txt" --quiet 2>/dev/null
echo -e "${C_GREEN}  Dependencies installed${C_RESET}"

# --- 5. Node.js frontend ---
echo ""
echo -e "${C_YELLOW}[5/8] Setting up Nuxt frontend...${C_RESET}"
FRONTEND="$ROOT/frontend"

if [ ! -d "$FRONTEND/node_modules" ]; then
    cd "$FRONTEND"
    npm install --silent 2>/dev/null
    cd "$ROOT"
    echo -e "${C_GREEN}  npm install complete${C_RESET}"
else
    echo -e "${C_GREEN}  node_modules exists, skipping${C_RESET}"
fi

# --- 6. Seed data ---
echo ""
echo -e "${C_YELLOW}[6/8] Checking seed data...${C_RESET}"
mkdir -p "$BACKEND/src/clarity/seed"
if [ -f "$BACKEND/seed/data.json" ]; then
    cp -n "$BACKEND/seed/data.json" "$BACKEND/src/clarity/seed/data.json" 2>/dev/null || true
    echo -e "${C_GREEN}  Seed data ready${C_RESET}"
else
    echo -e "${C_RED}  WARNING: seed/data.json missing!${C_RESET}"
fi

# --- 7. Fix line endings ---
echo ""
echo -e "${C_YELLOW}[7/8] Ensuring LF line endings...${C_RESET}"
find "$BACKEND" -name "*.py" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
find "$FRONTEND" -name "*.ts" -name "*.vue" -exec sed -i 's/\r$//' {} + 2>/dev/null || true
echo -e "${C_GREEN}  Line endings normalized${C_RESET}"

# --- 8. Create helper scripts ---
echo ""
echo -e "${C_YELLOW}[8/8] Creating helper scripts...${C_RESET}"

cat > "$ROOT/start-backend.sh" << 'STARTBE'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/.env"
source "$ROOT/backend/.venv/bin/activate"
cd "$ROOT/backend"
export SEED_DATA CLARITY_SQL_HOST CLARITY_SQL_PORT CLARITY_SQL_DB CLARITY_SQL_USER CLARITY_SQL_PASSWORD
export CLARITY_KC_REALM CLARITY_KC_MGMT_CLIENT_SECRET COMP_OIDC_CLIENT_ID COMP_OIDC_CLIENT_SECRET
export META_OPENAI_URL META_OPENAI_KEY
export ARCHER_USERNAME ARCHER_PASSWORD ARCHER_INSTANCE_NAME ARCHER_BASE_URI
export ARCHER_SOAP_SEARCH_URI ARCHER_SOAP_GENERAL_URI MAPPING_REPORT
uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload
STARTBE
chmod +x "$ROOT/start-backend.sh"

cat > "$ROOT/start-frontend.sh" << 'STARTFE'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/.env"
cd "$ROOT/frontend"
export NUXT_API_BASE NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL NUXT_SESSION_PASSWORD
npm run dev
STARTFE
chmod +x "$ROOT/start-frontend.sh"

cat > "$ROOT/start-all.sh" << 'STARTALL'
#!/usr/bin/env bash
# Start everything: docker infra + backend + frontend
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting Docker containers..."
docker compose up -d db keycloak
sleep 10

echo "Starting backend..."
"$ROOT/start-backend.sh" &
BACKEND_PID=$!

echo "Starting frontend..."
"$ROOT/start-frontend.sh" &
FRONTEND_PID=$!

echo ""
echo "All services starting..."
echo "  Backend:  http://localhost:4000/docs"
echo "  Frontend: http://localhost:3001"
echo "  Keycloak: http://localhost:8080/kc/admin"
echo ""
echo "Press Ctrl+C to stop all services."

trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; docker compose stop" EXIT INT TERM
wait
STARTALL
chmod +x "$ROOT/start-all.sh"

echo -e "${C_GREEN}  Created start-backend.sh${C_RESET}"
echo -e "${C_GREEN}  Created start-frontend.sh${C_RESET}"
echo -e "${C_GREEN}  Created start-all.sh${C_RESET}"

# --- Done ---
echo ""
echo -e "${C_CYAN}=============================================${C_RESET}"
echo -e "${C_CYAN}  Setup Complete!${C_RESET}"
echo -e "${C_CYAN}=============================================${C_RESET}"
echo ""
echo -e "  PostgreSQL:  localhost:5432"
echo -e "  Keycloak:    http://localhost:8080/kc/  (admin/admin)"
echo ""
echo -e "${C_YELLOW}  To start everything:   ./start-all.sh${C_RESET}"
echo -e "${C_YELLOW}  Or individually:${C_RESET}"
echo -e "${C_YELLOW}    Backend:  ./start-backend.sh${C_RESET}"
echo -e "${C_YELLOW}    Frontend: ./start-frontend.sh  (new terminal)${C_RESET}"
echo ""
echo -e "${C_GREEN}  Frontend:    http://localhost:3001${C_RESET}"
echo -e "${C_GREEN}  Backend API: http://localhost:4000/docs${C_RESET}"
echo -e "${C_GREEN}  Keycloak:    http://localhost:8080/kc/admin${C_RESET}"
echo ""
echo -e "${C_YELLOW}  First run:  SEED_DATA=true  (loads questionnaire)${C_RESET}"
echo -e "${C_YELLOW}  After that: SEED_DATA=false (avoid duplicates)${C_RESET}"
echo ""
