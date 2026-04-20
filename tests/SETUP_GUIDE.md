# Clarity — Developer Setup Guide

Welcome. This guide walks you through everything you need to install on a Windows corporate RTX machine to run Clarity locally, and exactly which commands to run afterward. Follow it top to bottom on your first day. It assumes you have **never cloned this repo, never run Docker, and have no prior context on the project.**

> **About Clarity:** Clarity is an IRAMP/ATO (Authorization-to-Operate) workflow automation platform. It takes a user through a 13-question intake, enriches the answers with classification logic, resolves Clarity values to Archer GRC IDs via CSV lookups, and hands the resulting payload off to a downstream Archer publisher service. The stack is Nuxt 3 (frontend), FastAPI (backend), PostgreSQL 17 with pgvector (database), Keycloak (authentication), and Ollama with phi-3-mini (optional AI copilot). All services run in Docker containers.

---

## Part 1 — Software to install

Install these in the order listed. Most installers will ask to restart your machine at some point; you can wait and restart once at the end.

### 1.1 Git for Windows
**What:** Version control, plus Git Bash which you'll use as an alternative terminal.
**Install from:** https://git-scm.com/download/win
**Installer prompts:** Accept defaults except for the editor — pick whatever you're comfortable with (Notepad++, VS Code, or the default Vim if you know it).

After install, open **PowerShell** and verify:
```powershell
git --version
```
Should print something like `git version 2.44.0.windows.1`.

### 1.2 Git LFS (Large File Storage)
**What:** Extension to Git that handles large binary files (model weights, CSV data, PDFs). Clarity uses LFS — skipping this step means `git clone` will succeed but LFS-tracked files will be empty pointer stubs, and things will break mysteriously later.

**Install from:** https://git-lfs.com/

After install, open PowerShell and run this **once per machine** (not per repo):
```powershell
git lfs install
```

Verify:
```powershell
git lfs --version
```

> If you already cloned the repo before installing LFS, don't re-clone — just run `git lfs pull` inside the repo after installing, and the stub files will be replaced with their real contents.

### 1.3 Docker Desktop
**What:** Runs the Clarity containers (backend, frontend, database, Keycloak, Ollama).
**Install from:** https://www.docker.com/products/docker-desktop/
**Important:** On install, **enable WSL 2 backend** when prompted. Docker Desktop will refuse to start without it.

You may need to install WSL 2 separately first if your machine doesn't have it:
```powershell
wsl --install
```
Restart your machine after `wsl --install` runs.

After Docker Desktop is installed and running (whale icon in the system tray), verify:
```powershell
docker --version
docker compose version
```

### 1.4 Visual Studio Code
**What:** Code editor.
**Install from:** https://code.visualstudio.com/download
**Recommended extensions** (install from the Extensions panel inside VS Code after launch):
- Vue - Official (for Nuxt/Vue syntax)
- Python (for FastAPI backend)
- Docker (for managing containers visually)
- GitLens (for Git history inside the editor)

### 1.5 Node.js LTS
**What:** Required if you want to run the frontend outside Docker for faster local iteration. Not strictly required for the Docker-only workflow.
**Install from:** https://nodejs.org/en/download (pick the LTS installer, currently Node 22.x)

Verify:
```powershell
node --version
npm --version
```

### 1.6 Python 3.12
**What:** Required if you want to run the backend outside Docker. Not strictly required for Docker-only workflow.
**Install from:** https://www.python.org/downloads/windows/ (pick the 3.12.x installer)
**Important:** On the installer's first screen, **check "Add python.exe to PATH"** at the bottom before clicking Install.

Verify:
```powershell
python --version
```

### 1.7 GitHub CLI (optional but useful)
**What:** Makes authenticating to RTX's internal GitHub easier.
**Install from:** https://cli.github.com/
Verify:
```powershell
gh --version
```

---

## Part 2 — RTX-specific setup

The RTX network has quirks that will bite you if you don't handle them upfront.

### 2.1 Personal Access Token (PAT) for internal GitHub

Clarity lives on `github-us.utc.com`, the internal RTX GitHub Enterprise instance. You cannot clone it with your RTX password directly — you need a PAT.

1. Open https://github-us.utc.com in your browser, sign in with RTX SSO.
2. Click your avatar (top right) → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**.
3. Give it a note like "clarity-dev-local", expiration 90 days, and check the **`repo`** scope (the whole section).
4. Click **Generate token**. **Copy the token immediately** — you cannot see it again after leaving the page.
5. Save it somewhere secure (password manager preferred; at minimum a text file you delete later).

### 2.2 Corporate SSL proxy

RTX intercepts SSL on your machine, which breaks tools that don't trust the corporate certificate. You may need to set these environment variables in PowerShell before running npm/pip/git commands locally (not inside Docker — the containers handle this themselves):

```powershell
$env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
$env:PYTHONHTTPSVERIFY = "0"
```

> **Only use these locally on your host machine. Never commit them. Never set them in Docker images or on EC2** — they disable SSL validation entirely.

For git, if you hit cert errors:
```powershell
git config --global http.sslBackend schannel
```
This tells git to use Windows' certificate store, which already trusts the RTX corporate cert.

### 2.3 Docker Desktop proxy configuration

If Docker Desktop can't pull images (`docker pull` errors about "certificate signed by unknown authority"), go to **Docker Desktop → Settings → Resources → Proxies** and configure the corporate proxy if your RTX machine uses one. Ask your IT helpdesk if you're unsure what the values should be.

---

## Part 3 — Get the code

Open **PowerShell** (not Git Bash for this part).

### 3.1 Create a working directory

```powershell
mkdir $HOME\Desktop\repos
cd $HOME\Desktop\repos
```

### 3.2 Clone the Clarity monorepo

Replace `<YOUR_PAT>` with the token you generated in Part 2.1:

```powershell
git clone https://<YOUR_PAT>@github-us.utc.com/us-persons-only/GRCAA-Clarity.git
cd GRCAA-Clarity\projects\clarity-rewrite
```

If you get a prompt for credentials, your PAT didn't attach — cancel and retry with the token embedded in the URL.

> The clone will be slower than you expect because Git LFS is pulling large binary files (model weights, data files) in addition to the source code. This is normal. If the clone completes but certain files look wrong (tiny `.gguf` or `.csv` files containing text like `version https://git-lfs.github.com/spec/v1`), that means LFS didn't run. Fix with:
> ```powershell
> git lfs pull
> ```

### 3.3 Switch to the active branch

```powershell
git checkout feat/render
git pull
```

### 3.4 Verify repo layout

```powershell
dir
```

You should see: `backend\`, `frontend\`, `keycloak\`, `models\`, `nginx\`, `docker-compose.production.yaml`, `.env`, and various SQL/JSON patch files.

---

## Part 4 — Configure environment variables

Clarity needs two `.env` files — one for the backend, one for the frontend. Both are gitignored, so you won't see them in the repo; you have to create them.

### 4.1 Backend `.env`

```powershell
cd backend
copy .env.example .env
notepad .env
```

Fill in the values marked `CHANGE_ME`. Critical ones:

```dotenv
# Database
DATABASE_URL=postgresql://root:root@db:5432/clarity

# Authentication mode - dev, keycloak, or keycloak-enterprise
AUTH_MODE=keycloak

# Local Keycloak (for AUTH_MODE=keycloak)
KEYCLOAK_URL=http://keycloak:8080/kc
KEYCLOAK_REALM=clarity
KEYCLOAK_CLIENT_ID=clarity-backend
KEYCLOAK_CLIENT_SECRET=<ask a teammate>

# Enterprise Keycloak (for AUTH_MODE=keycloak-enterprise)
CORP_OIDC_ISSUER=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com/realms/DE-Toolchain
CORP_OIDC_CLIENT_ID=clarity-dev
CORP_OIDC_CLIENT_SECRET=<ask Christopher Michael>

# Data seeding - true means auto-populate the questionnaire on first startup
SEED_DATA=true

# AI services (optional)
OLLAMA_HOST=http://ollama:11434
XETA_API_KEY=<optional, ask Michael>
```

Save and close Notepad.

### 4.2 Frontend `.env`

```powershell
cd ..\frontend
copy .env.example .env
notepad .env
```

Minimum required:
```dotenv
NUXT_PUBLIC_API_BASE_URL=/be
NUXT_PUBLIC_AUTH_MODE=keycloak
```

Save and close.

### 4.3 Return to repo root

```powershell
cd ..
```

You should be back in `clarity-rewrite\`.

---

## Part 5 — First run

This is the moment of truth.

### 5.1 Build and start all containers

```powershell
docker compose -f docker-compose.production.yaml up -d --build
```

This command will:
1. Pull base images (Python 3.12, Node 20, Postgres 17, Keycloak 26, Ollama)
2. Build the backend image (installs Python dependencies)
3. Build the frontend image (installs npm packages, builds the Nuxt app)
4. Start all 5 containers: `clarity-api`, `clarity-frontend`, `clarity-db`, `clarity-keycloak`, `clarity-ollama`

First build takes **5-15 minutes** depending on your network speed. Subsequent builds are much faster thanks to Docker's layer cache.

### 5.2 Verify everything is running

```powershell
docker compose -f docker-compose.production.yaml ps
```

All 5 services should say `Up` or `Up (healthy)`. If any say `Restarting` or `Exited`, check its logs:

```powershell
docker compose -f docker-compose.production.yaml logs <service-name>
```

Common service names: `clarity-api`, `clarity-frontend`, `db`, `keycloak`, `ollama`.

### 5.3 Check the API came up cleanly

```powershell
docker compose -f docker-compose.production.yaml logs --tail=50 clarity-api
```

Look for these milestone log lines:
- `Database tables initialized`
- `Loaded N Archer lookup entries from <filename>` (one per CSV, 4 lines total)
- `Uvicorn running on http://0.0.0.0:4000`

If any of those are missing or a traceback appears, stop here and get help from a teammate.

### 5.4 Open the app in your browser

http://localhost:3000

You should see the Clarity login page with the red "US Persons Only" banner at the top. Sign in through Keycloak with your dev credentials (ask a teammate for the test user, or use Christopher Michael's enterprise SSO flow if you've been set up with it).

---

## Part 6 — Daily workflow

Once the initial setup is done, these are the commands you'll use every day.

### 6.1 Start your environment in the morning

```powershell
cd $HOME\Desktop\repos\GRCAA-Clarity\projects\clarity-rewrite
docker compose -f docker-compose.production.yaml up -d
```

No `--build` flag — just spins up the existing containers.

### 6.2 Pull the latest code

```powershell
git pull origin feat/render
```

### 6.3 Rebuild after backend code changes

FastAPI source is baked into the image at build time, so changes require a rebuild:

```powershell
docker compose -f docker-compose.production.yaml up -d --build clarity-api
```

### 6.4 Rebuild after frontend code changes

Nuxt is also built into the image for production mode:

```powershell
docker compose -f docker-compose.production.yaml up -d --build clarity-frontend
```

### 6.5 View logs

```powershell
# Last 50 lines of the backend
docker compose -f docker-compose.production.yaml logs --tail=50 clarity-api

# Follow logs in real time (Ctrl+C to exit)
docker compose -f docker-compose.production.yaml logs -f clarity-api

# Search logs with PowerShell
docker compose -f docker-compose.production.yaml logs clarity-api | Select-String -Pattern "ERROR|Traceback"
```

### 6.6 Open a database shell

```powershell
docker compose -f docker-compose.production.yaml exec db psql -U root -d clarity
```

Inside psql:
- `\d` — list all tables
- `\d project` — describe the project table
- `\q` — quit
- Any SQL statement, e.g. `SELECT id, title, status FROM project;`

### 6.7 Stop everything at the end of the day

```powershell
docker compose -f docker-compose.production.yaml down
```

This stops the containers but **keeps your database data** (stored in a Docker volume). If you want to nuke the database too (start fresh), add `-v`:

```powershell
docker compose -f docker-compose.production.yaml down -v
```

> **Warning:** `down -v` deletes all projects, users, and Keycloak state. Use only when you want a clean slate.

---

## Part 7 — Common problems and fixes

### "502 Bad Gateway" when hitting localhost:3000
Nginx is up but the frontend container isn't serving yet. Wait 30 seconds, then retry. If it persists:
```powershell
docker compose -f docker-compose.production.yaml logs clarity-frontend
```

### "Cannot connect to database"
The `db` container may still be initializing (takes 10-20 seconds on first boot). Check:
```powershell
docker compose -f docker-compose.production.yaml logs db
```

### Keycloak login loop
The local Keycloak realm isn't seeded. Check `clarity-keycloak` logs and verify the realm import ran. If you're trying to use enterprise Keycloak, contact Christopher Michael about the redirect URI registration for your dev hostname.

### Backend won't start, complains about missing columns
The schema auto-migration in `_ensure_*_columns` should handle this, but if you see "column does not exist" errors, run:
```powershell
docker compose -f docker-compose.production.yaml restart clarity-api
```
That triggers a re-init of the schema check functions.

### Port 80 / 3000 / 4000 already in use
Another process on your machine is using one of Clarity's ports. Find it:
```powershell
netstat -ano | findstr ":3000"
```
The last column is the PID. Kill it:
```powershell
taskkill /PID <pid> /F
```

### "Docker Desktop stopped" or containers keep dying
Docker Desktop ran out of resources. Open **Docker Desktop → Settings → Resources** and bump memory to at least 8GB, CPU to at least 4 cores.

### SSL cert errors during `docker build`
The RTX proxy is injecting its cert mid-transit. Check Docker Desktop's proxy settings (Part 2.3). If that doesn't help, ask IT for the corporate CA bundle and mount it into the build.

---

## Part 8 — People to ask when stuck

- **Michael Cave** (you're reading his guide) — Clarity architecture, backend, submission pipeline
- **Allen Spector** — EC2 instance management, infrastructure
- **Christopher Michael** — Enterprise Keycloak, redirect URI configuration
- **Robert Bogan** — Downstream Archer publisher service
- **Linda Ciulla** — Archer field mapping, CSV hierarchy spec

---

## Appendix — File locations cheat sheet

| What | Where |
|------|-------|
| Backend source | `backend\src\clarity\` |
| Frontend source | `frontend\pages\` and `frontend\components\` |
| Docker compose (production) | `docker-compose.production.yaml` |
| Questionnaire seed data | `backend\seed\data.json` |
| Archer ID CSV lookups | `backend\data\lookups\*.csv` |
| Backend Dockerfile | `backend\Dockerfile` |
| Frontend Dockerfile | `frontend\Dockerfile` |
| Nginx config | `nginx\` |
| Keycloak realm config | `keycloak\` |

---

*Last updated: April 2026 — feat/render branch*
