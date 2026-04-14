# Clarity — Local Setup & Demo Guide

This guide walks you through cloning, building, and running the Clarity IRAMP/ATO questionnaire application on your local corporate machine. Following it end-to-end gives you a working app at `http://localhost:3000` with a 13-question questionnaire that submits dry-run records to Archer.

**Audience:** RTX/Collins teammates running on a corporate Windows machine, on the corporate network (VPN or on-site), demoing the application to leadership.

**Time required:** ~30–45 minutes for first-time setup. Most of that is Docker building images.

---

## What you'll have when you're done

- Clarity running locally in Docker containers (frontend, backend, Postgres, Ollama)
- Enterprise SSO login working via your RTX corporate account
- A 13-question questionnaire seeded automatically on first startup
- Ability to fill out a project end-to-end and submit to Archer in dry-run mode
- All five Archer pipeline steps completing successfully (responses saved → payload generated → connected → hardware records created → authorization package created)

---

## Prerequisites

Before you start, make sure you have all of these installed and working. **Do not skip this section** — most setup failures come from missing or misconfigured prerequisites.

### 1. Docker Desktop

- Download from <https://www.docker.com/products/docker-desktop/>
- After install, launch Docker Desktop and wait for the whale icon in the system tray to stop animating (means the engine is running).
- Verify in PowerShell:
  ```powershell
  docker --version
  docker compose version
  ```
  Both should print version numbers without errors.

### 2. Git for Windows

- Download from <https://git-scm.com/download/win> if not already installed.
- Verify:
  ```powershell
  git --version
  ```

### 3. Git LFS (Large File Storage) — **REQUIRED**

The repository uses Git LFS to store the Phi-3 Mini AI model file (~2.4GB). Without LFS, you'll clone a tiny pointer file instead of the actual model and the Ollama container will not work.

- Download from <https://git-lfs.com/> and run the installer.
- After install, open a fresh PowerShell window and initialize LFS for your user account:
  ```powershell
  git lfs install
  ```
  You should see `Git LFS initialized.`
- Verify:
  ```powershell
  git lfs version
  ```

### 4. VS Code (recommended)

- Not strictly required to run the app, but you'll want it for editing `.env` files and inspecting the code.
- Download from <https://code.visualstudio.com/>

### 5. Network access

- You **must** be on the RTX corporate network. Either physically in an office or connected via VPN.
- Required for: cloning the repo from `github-us.utc.com`, reaching the corporate Keycloak SSO server, and Docker pulling base images through the corporate proxy.
- If you're remote, connect to VPN before starting.

### 6. Corporate SSL certificates

- If you've used `npm`, `pip`, or `git` on your corporate machine before, you're already set up.
- If you're brand new to the corporate machine: contact your IT desk to make sure the corporate root certificates are installed. Without them, Docker builds will fail with SSL errors during `npm install` and `pip install` steps.

### 7. Free local ports

These ports must be unused on your machine when Clarity starts. If you have other services running on any of them, stop those services first.

| Port  | Used by             |
|-------|---------------------|
| 3000  | Clarity frontend    |
| 4000  | Clarity backend API |
| 5432  | Postgres            |
| 8080  | Keycloak (local)    |
| 11434 | Ollama (local LLM)  |

To check if a port is in use:
```powershell
netstat -ano | findstr :3000
```
If anything prints, that port is taken. Free it before continuing.

---

## Step 1 — Clone the repository

Open PowerShell and navigate to wherever you keep code (e.g., `C:\Users\<you>\Desktop\repos`).

```powershell
cd C:\Users\<you>\Desktop\repos
git clone https://github-us.utc.com/us-persons-only/GRCAA-Clarity.git
cd GRCAA-Clarity
```

If you get an authentication prompt, use your RTX network credentials or a personal access token from `github-us.utc.com`.

---

## Step 2 — Switch to the working branch

```powershell
git checkout feat/render
```

Verify you're on the right branch:
```powershell
git branch
```
You should see `* feat/render` highlighted.

---

## Step 3 — Pull the Git LFS files

This downloads the Phi-3 Mini model file (~2.4GB) that LFS only fetched as a pointer during clone.

```powershell
git lfs pull
```

This may take several minutes depending on your network speed. When it finishes, verify the model file is real (not a tiny pointer):

```powershell
cd projects\clarity-rewrite
dir backend\models\*.gguf
```

You should see a file that's a couple of GB in size, not a few hundred bytes.

---

## Step 4 — Set up the `.env` files

There are **three** `.env` files you need:

1. `projects/clarity-rewrite/.env` — root-level docker-compose vars
2. `projects/clarity-rewrite/backend/.env` — backend service vars
3. `projects/clarity-rewrite/frontend/.env` — frontend service vars

**You will receive all three `.env` files from your teammate via secure channel** (Slack DM, encrypted email, password manager share, etc.). They contain real credentials for enterprise Keycloak, the database, and Archer connectivity, so they cannot be committed to the repo.

**Do not type them by hand.** Copy the files exactly as you receive them into the three locations above.

After placing them, verify they exist:
```powershell
cd projects\clarity-rewrite
dir .env
dir backend\.env
dir frontend\.env
```

All three should show as files. If any of them are missing, ask your teammate to resend that specific file.

**Important env vars to spot-check** in the files you receive (don't change them, just confirm they're set):

In `projects/clarity-rewrite/.env`:
- `CLARITY_SQL_PASSWORD` — must be set
- `SEED_DATA=true` — required so the questionnaire auto-loads on first startup

In `projects/clarity-rewrite/backend/.env`:
- `AUTH_MODE=keycloak-enterprise`
- `SEED_DATA=true`
- The Keycloak realm/client/server URL vars must all be set

In `projects/clarity-rewrite/frontend/.env`:
- `NUXT_OAUTH_KEYCLOAK_*` vars must all be set, including the redirect URL pointing at `http://localhost:3000/auth/sso/callback`

If any of these look blank or wrong, stop and check with the person who sent you the files.

---

## Step 5 — Build and start the containers

From the `projects/clarity-rewrite` directory:

```powershell
docker compose -f docker-compose.production.yaml up -d --build
```

What this does:
- Builds the backend image (FastAPI + Python + dependencies)
- Builds the frontend image (Nuxt 3 + Node + dependencies)
- Pulls the Postgres 17 and Keycloak base images
- Pulls the Ollama image and loads the Phi-3 model
- Starts all four containers in detached mode (`-d`)

**This will take 10–20 minutes the first time.** Subsequent runs are much faster because Docker caches the layers.

If the build fails partway through with SSL errors, see the **Troubleshooting** section at the bottom.

When it finishes, verify all four containers are running:

```powershell
docker compose -f docker-compose.production.yaml ps
```

You should see four containers with status `Up`:
- `clarity-frontend`
- `clarity-api`
- `clarity-db`
- `clarity-ollama`

If any of them say `Exited` or `Restarting`, check that container's logs:
```powershell
docker compose -f docker-compose.production.yaml logs <container-name>
```

---

## Step 6 — Wait for the backend to finish initializing

The backend takes about 30–60 seconds after startup to:
1. Connect to Postgres
2. Run the schema setup
3. Load the seed data from `backend/seed/data.json` (because `SEED_DATA=true`)
4. Start serving requests on port 4000

Watch the backend logs in real time:

```powershell
docker compose -f docker-compose.production.yaml logs -f clarity-api
```

You're looking for a line like `Application startup complete` or `Uvicorn running on http://0.0.0.0:4000`. When you see it, the backend is ready. Press `Ctrl+C` to stop tailing the logs (this does not stop the container, only the log tail).

---

## Step 7 — Open the application and log in

Open your browser and go to:

```
http://localhost:3000
```

You should be redirected to the Collins Ping enterprise SSO login page. Sign in with your normal RTX corporate credentials.

After successful login, you'll land on the Clarity home page. You should see your name in the top-right corner and a list of any existing projects (likely empty on a fresh install).

**If the SSO redirect fails or you get a "redirect URI not allowed" error:** the Keycloak client `clarity-dev` may need `http://localhost:3000/auth/sso/callback` added to its allowed redirect URIs. Contact Christopher Michael (the enterprise Keycloak admin) to confirm that's already configured. For machines that have run this before, it should already work.

---

## Step 8 — Verify the questionnaire loaded

Click **"Create New Project"** (or whatever the equivalent button is on the home page).

You should see a 13-question questionnaire with these questions in order:
1. Project Name
2. Purpose
3. Boundary Description
4. Information System Owner
5. System Administrator
6. Clara ID
7. RTX Business
8. SBU Organization
9. Entity
10. Information Classification
11. Connectivity
12. Hosting Environment
13. Hardware

If you see all 13 in this order, the seed data loaded successfully. **You're ready to demo.**

If you see fewer questions, or different question titles, the seed loader didn't run correctly. Stop here and check the backend logs for errors related to seeding.

---

## Demo walkthrough — what to click for leadership

This is the happy-path demo that shows Clarity working end-to-end. Practice it once before your actual demo so you're not fumbling for clicks live.

### Setup (do this before leadership joins)

1. Make sure the app is running: open `http://localhost:3000` and confirm you're logged in.
2. Have a clean browser window ready (or use Incognito to avoid past sessions).
3. Have this README open in another tab in case you need to reference anything.

### The demo

**Part 1 — Show the questionnaire structure (1 minute)**

1. Click **Create New Project**.
2. Point at the left sidebar showing all 13 questions organized by subphase (General, Personnel, Information System Details).
3. Mention: "Clarity walks the user through 13 questions across multiple subphases, and the answers get assembled into an Archer authorization package automatically."

**Part 2 — Fill out the questionnaire (3–5 minutes)**

Fill out each question with realistic but fake data. Suggested values:

1. **Project Name:** `LeadershipDemo-001`
2. **Purpose:** `Demonstration of Clarity questionnaire workflow for leadership.`
3. **Boundary Description:** `Single application server hosted in AWS, accessible via VPN.`
4. **Information System Owner:** `c95063223` (or any employee ID format)
5. **System Administrator:** `c95063223` (same format)
6. **Clara ID:** `12345`
7. **RTX Business:** Pick **Raytheon**.
8. **SBU Organization:** ← **THIS IS THE KEY MOMENT.** Mention: "Notice that the SBU options are now Raytheon-specific — Advanced Products & Solutions, Naval Power, etc. If I had picked Collins Aerospace on the previous question, this dropdown would show Avionics, Mission Systems, etc. The cascade logic enforces that you can't pick a P&W SBU under Raytheon." Pick **Naval Power (NP)**.
9. **Entity:** Pick whatever's appropriate.
10. **Information Classification:** Pick **CDI/CUI(DFARS)** to demonstrate a CUI classification.
11. **Connectivity:** Pick **Internal Only**.
12. **Hosting Environment:** Pick **aws**.
13. **Hardware:** Click to add a row. Fill in:
    - FQDN: `demo-server-01.corp.rtx.com`
    - Hardware Name: `Demo Server`
    - Business: `Raytheon`
    - Internal IP Address: `10.0.0.42`
    - Type: `Linux`

**Part 3 — Submit to Archer (1 minute)**

1. After all 13 questions are answered, click **Review Answers**.
2. Show leadership the review screen with all 13 answers and green status dots.
3. Click **Submit for Review**.
4. The "Submitting to Archer" modal opens with a 5-step progress checklist:
   - Saving questionnaire responses
   - Generating Archer payload
   - Connecting to Archer
   - Creating hardware records
   - Creating authorization package
   - Complete
5. All five should turn green within a few seconds.
6. Mention: "This is currently running in dry-run mode, which means the payload was generated and validated against Archer but no actual record was written. Flipping a single environment variable enables live submission."
7. Click **Done**.

**Part 4 — The story (30 seconds)**

Wrap up by saying something like: "What you just saw is a 13-question intake that automatically derives the Baseline Recommendation, looks up the right SBU hierarchy from RTX business data, validates hardware records, and produces a complete Archer authorization package. What used to take an analyst an hour of manual work in Archer is now a 5-minute self-service flow."

---

## Common operations

### Stop the containers (without deleting data)
```powershell
docker compose -f docker-compose.production.yaml stop
```

### Start them again
```powershell
docker compose -f docker-compose.production.yaml start
```

### Stop and delete the containers (data persists in volumes)
```powershell
docker compose -f docker-compose.production.yaml down
```

### Stop, delete, AND wipe all data (start fresh)
```powershell
docker compose -f docker-compose.production.yaml down -v
```
Use this if your seed data got into a weird state and you want a totally clean slate. You'll need to bring everything back up with `up -d --build` after.

### View logs from a specific container
```powershell
docker compose -f docker-compose.production.yaml logs clarity-api
docker compose -f docker-compose.production.yaml logs clarity-frontend
docker compose -f docker-compose.production.yaml logs db
docker compose -f docker-compose.production.yaml logs clarity-ollama
```

Add `-f` to follow logs in real time, or `--tail 100` to show only the last 100 lines.

### Restart a single container after it gets into a bad state
```powershell
docker compose -f docker-compose.production.yaml restart clarity-api
```

### Open a shell inside a container (for debugging)
```powershell
docker compose -f docker-compose.production.yaml exec clarity-api bash
docker compose -f docker-compose.production.yaml exec db psql -U root -d clarity
```

---

## Troubleshooting

### "Cannot connect to the Docker daemon"
Docker Desktop isn't running. Open it from the Start menu and wait for the whale icon in the system tray to stop animating.

### Build fails with SSL certificate errors during `npm install` or `pip install`
The corporate root certificates aren't installed on your machine, or the Docker build context isn't picking them up. Contact your IT desk. As a temporary workaround, the project supports `NODE_TLS_REJECT_UNAUTHORIZED=0` and `PIP_TRUSTED_HOST` env vars during local builds — check with the person who sent you the `.env` files about whether to enable them.

### "Port 3000 is already in use" (or 4000, 5432, 8080, 11434)
Something else on your machine is bound to that port. Find it and stop it:
```powershell
netstat -ano | findstr :3000
```
The last column is the PID. Kill it via Task Manager or:
```powershell
taskkill /F /PID <pid>
```

### Containers start but the frontend page is blank or won't load
Wait another 30 seconds — the frontend takes longer than the backend to be ready. Then hard-refresh the browser (`Ctrl+Shift+R`).

### SSO redirect fails with "redirect URI not allowed"
The Keycloak client `clarity-dev` doesn't have your machine's URL in its allowed redirect list. Confirm with Christopher Michael that `http://localhost:3000/auth/sso/callback` is registered. If not, ask him to add it.

### SSO works but I can't create projects (500 error)
The seed data probably didn't load. Check the backend logs:
```powershell
docker compose -f docker-compose.production.yaml logs clarity-api | findstr -i "seed"
```
If you see errors loading `data.json`, restart the backend:
```powershell
docker compose -f docker-compose.production.yaml restart clarity-api
```
If that doesn't work, do a full reset (`down -v` then `up -d --build`).

### "Submit for Review" fails or hangs
Check that the Ollama container is running:
```powershell
docker compose -f docker-compose.production.yaml ps clarity-ollama
```
If it's not `Up`, check its logs and restart it. The Phi-3 model takes a moment to load on first request.

### Submit succeeds but Archer says "no record created"
That's expected. The default configuration runs in dry-run mode — the Archer payload is generated and validated but not actually written to Archer. The dry-run modal explicitly tells you this. To enable live publishing, set `ARCHER_PUBLISH_ENABLED=true` in `backend/.env` and restart `clarity-api` — but **don't do this for the demo** unless leadership specifically wants to see a live Archer record.

### Browser shows the wrong questionnaire (old questions, missing Q8 SBU Organization, etc.)
The seed data didn't reload. Easiest fix: full reset.
```powershell
docker compose -f docker-compose.production.yaml down -v
docker compose -f docker-compose.production.yaml up -d --build
```
Wait for the backend to come up, then refresh the browser.

### Login works but the page shows my name as "dev@clarity.local"
Your `backend/.env` has `AUTH_MODE=dev` instead of `AUTH_MODE=keycloak-enterprise`. Check the env file and restart `clarity-api`.

---

## Browser recommendation

Use **Microsoft Edge** for the demo. It has the most reliable behavior with corporate SSO and certificate handling on RTX machines. Chrome works too but occasionally prompts for cert acceptance that Edge handles silently.

Avoid Firefox unless you've already configured it for corporate SSO — it doesn't pick up Windows trust store certificates by default.

---

## If something goes wrong during the demo

If the app breaks live, the fastest recovery is:
```powershell
docker compose -f docker-compose.production.yaml restart clarity-api clarity-frontend
```
Then hard-refresh the browser. This takes 10–20 seconds and fixes 90% of mid-demo issues.

If a full reset is needed and you have time:
```powershell
docker compose -f docker-compose.production.yaml down
docker compose -f docker-compose.production.yaml up -d
```
(Note: no `--build` and no `-v`. This restarts containers from existing images and preserves data.)

---

## Who to contact

- **Application questions / demo content:** Michael Cave
- **Enterprise Keycloak / SSO redirect URIs:** Christopher Michael
- **EC2 / production deployment (not local):** Allen Spector
- **Corporate machine setup / certificates / VPN:** RTX IT Help Desk

---

## What this demo proves

For leadership context, this demo specifically shows:

1. **A working IRAMP/ATO intake workflow** — 13 questions covering project metadata, ownership, classification, connectivity, hosting, and hardware.
2. **Cascading question logic** — SBU Organization options dynamically narrow based on RTX Business selection, enforcing data integrity at the form level instead of catching errors downstream in Archer.
3. **End-to-end Archer integration** — the full payload generation, hardware sub-record creation, and authorization package assembly pipeline runs successfully.
4. **Self-service capability** — what historically required an analyst to manually enter data into Archer is now a guided self-service flow that any approved user can complete.
5. **Production-ready architecture** — Docker, Postgres, FastAPI, Nuxt 3, enterprise Keycloak SSO, and a local LLM for AI assistance, all running in a containerized stack that can deploy to AWS or on-prem.
