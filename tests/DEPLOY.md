# Clarity — AWS EC2 Production Deployment

> Step-by-step guide to deploy Clarity on an EC2 instance at `clarity.onertx.com`.

---

## Prerequisites

- EC2 instance (Amazon Linux 2 / Ubuntu) with:
  - Docker & Docker Compose installed
  - Nginx installed
  - Git installed with access to `github-us.utc.com`
  - Port 80/443 open (Security Group)
  - SSL certificate and key for `clarity.onertx.com`
- VPN access to corporate network (for Keycloak, Archer, GitHub Enterprise)

---

## First-Time Setup (Run Once)

### 1. SSH into the instance

```bash
ssh -J col-bastion-30.bastion.wg1.aws.ray.com ec2-user@<instance-ip>
```

### 2. One-time root setup

These commands require sudo and only need to be run once:

```bash
# Create directories
sudo mkdir -p /etc/clarity
sudo chown $USER:$USER /etc/clarity

# Add yourself to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### 3. Clone the repo

```bash
cd /etc/clarity
git clone https://github-us.utc.com/us-persons-only/GRCAA-Clarity.git
cd GRCAA-Clarity/projects/clarity-rewrite
```

### 4. Create production .env

```bash
cp deploy/.env.production.example /etc/clarity/.env
chmod 600 /etc/clarity/.env
nano /etc/clarity/.env
```

**Edit every `CHANGE_ME` value** with real production credentials:
- PostgreSQL password
- Keycloak admin password
- Keycloak client secrets
- Archer credentials
- Session password (random 32+ char string)
- Model Hub API key

### 5. Run first-time setup

```bash
bash deploy/setup-server.sh
```

This will:
- Symlink `/etc/clarity/.env` into the app
- Install the nginx config (requires sudo for this step only)
- Install the systemd service (requires sudo for this step only)
- Copy Dockerfiles into backend/ and frontend/ if not present
- Build all Docker images
- Start all containers (Postgres, Keycloak, Backend, Frontend)

### 6. Seed the database

Edit `/etc/clarity/.env` and set `SEED_DATA=true`, then restart:

```bash
cd /etc/clarity/GRCAA-Clarity/projects/clarity-rewrite
docker compose -f docker-compose.production.yaml --env-file /etc/clarity/.env restart backend
```

After the backend logs show seed complete, set `SEED_DATA=false` and restart again.

### 7. Verify

```bash
curl -sf https://clarity.onertx.com/auth/ && echo "OK"
docker compose -f docker-compose.production.yaml ps
```

---

## Subsequent Deployments (No Sudo Required)

After the first-time setup, every deploy is:

```bash
cd /etc/clarity/GRCAA-Clarity/projects/clarity-rewrite
git pull origin aws-feat-clarity-rewrite
bash deploy/deploy.sh
```

That's it. The script pulls latest code, rebuilds containers, and restarts services.

---

## Switching Auth Modes

### Local Keycloak (default)
In `/etc/clarity/.env`, set:
```
AUTH_MODE=keycloak
```
Uncomment the local Keycloak NUXT vars, comment out the enterprise ones.

### Enterprise Keycloak (RTX SSO)
In `/etc/clarity/.env`, set:
```
AUTH_MODE=keycloak-enterprise
```
Uncomment the enterprise NUXT vars, comment out the local ones.

Then restart:
```bash
docker compose -f docker-compose.production.yaml --env-file /etc/clarity/.env restart
```

---

## Common Operations

### View logs
```bash
cd /etc/clarity/GRCAA-Clarity/projects/clarity-rewrite
docker compose -f docker-compose.production.yaml logs -f
docker compose -f docker-compose.production.yaml logs -f backend   # backend only
docker compose -f docker-compose.production.yaml logs -f frontend  # frontend only
```

### Restart a single service
```bash
docker compose -f docker-compose.production.yaml --env-file /etc/clarity/.env restart backend
```

### Full restart
```bash
docker compose -f docker-compose.production.yaml --env-file /etc/clarity/.env down
docker compose -f docker-compose.production.yaml --env-file /etc/clarity/.env up -d
```

### Reset database (destructive)
```bash
docker compose -f docker-compose.production.yaml --env-file /etc/clarity/.env down -v
docker compose -f docker-compose.production.yaml --env-file /etc/clarity/.env up -d
# Then set SEED_DATA=true and restart backend
```

### Check service health
```bash
docker compose -f docker-compose.production.yaml ps
curl -sf http://localhost:4000/auth/ && echo "Backend OK"
curl -sf http://localhost:3000 && echo "Frontend OK"
```

---

## File Layout on EC2

```
/etc/clarity/
├── .env                                    ← production secrets (not in git)
└── GRCAA-Clarity/                          ← cloned repo
    └── projects/clarity-rewrite/
        ├── backend/
        │   ├── Dockerfile
        │   ├── requirements.txt
        │   └── src/
        ├── frontend/
        │   ├── Dockerfile
        │   ├── package.json
        │   └── ...
        ├── keycloak/
        │   └── clarity-realm.json
        ├── deploy/
        │   ├── DEPLOY.md                   ← this file
        │   ├── setup-server.sh
        │   ├── deploy.sh
        │   ├── .env.production.example
        │   ├── clarity.service
        │   └── nginx/
        │       └── clarity.conf
        ├── docker-compose.yaml             ← local dev
        └── docker-compose.production.yaml
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Can't connect to Docker | `sudo usermod -aG docker $USER && newgrp docker` |
| Permission denied on /etc/clarity | `sudo chown $USER:$USER /etc/clarity` |
| Container won't start | Check logs: `docker compose -f docker-compose.production.yaml logs <service>` |
| 502 Bad Gateway | Backend not ready yet — wait or check backend logs |
| SSL errors | Verify certs at `/etc/nginx/ssl/clarity.crt` and `.key` |
| Can't reach github-us.utc.com | Connect to VPN |
| SAML error on enterprise KC | Contact Christopher Michael — SAML subject mapping issue |
| Keycloak "Resource not found" | Ensure `/kc` in server URL for local KC |
| Seed data not loading | Check `SEED_DATA=true` in .env, restart backend |
