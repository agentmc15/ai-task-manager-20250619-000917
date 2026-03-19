#!/usr/bin/env bash
set -euo pipefail
#
# Script 1: Keycloak Auto-Setup
# Creates a realm export JSON and updates docker-compose to auto-import it.
# Run from: ~/desktop/repos/clarity-rewrite
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Create Keycloak realm export JSON ==="

mkdir -p keycloak

cat > keycloak/clarity-realm.json << 'REALMEOF'
{
  "realm": "clarity",
  "enabled": true,
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "sslRequired": "none",
  "roles": {
    "realm": [
      {
        "name": "clarity-user",
        "description": "Standard Clarity application user"
      },
      {
        "name": "clarity-admin",
        "description": "Clarity administrator"
      }
    ]
  },
  "clients": [
    {
      "clientId": "nuxt-frontend",
      "name": "Clarity Nuxt Frontend",
      "enabled": true,
      "publicClient": false,
      "protocol": "openid-connect",
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": true,
      "serviceAccountsEnabled": false,
      "redirectUris": [
        "http://localhost:3001/*",
        "https://clarity.onertx.com/*"
      ],
      "webOrigins": [
        "http://localhost:3001",
        "https://clarity.onertx.com"
      ],
      "attributes": {
        "post.logout.redirect.uris": "http://localhost:3001/*##https://clarity.onertx.com/*"
      },
      "secret": "nEMT2PXHmL9shdQPP8UpQLHeHfrGX1tF",
      "defaultClientScopes": [
        "web-origins",
        "profile",
        "roles",
        "email"
      ]
    },
    {
      "clientId": "clarity-backend",
      "name": "Clarity FastAPI Backend",
      "enabled": true,
      "publicClient": false,
      "protocol": "openid-connect",
      "bearerOnly": true,
      "standardFlowEnabled": false,
      "directAccessGrantsEnabled": false,
      "serviceAccountsEnabled": false,
      "secret": "backend-service-secret-change-me"
    }
  ],
  "users": [
    {
      "username": "dev@clarity.local",
      "email": "dev@clarity.local",
      "emailVerified": true,
      "enabled": true,
      "firstName": "Dev",
      "lastName": "User",
      "credentials": [
        {
          "type": "password",
          "value": "dev123",
          "temporary": false
        }
      ],
      "realmRoles": [
        "clarity-user",
        "clarity-admin"
      ]
    },
    {
      "username": "testuser@clarity.local",
      "email": "testuser@clarity.local",
      "emailVerified": true,
      "enabled": true,
      "firstName": "Test",
      "lastName": "User",
      "credentials": [
        {
          "type": "password",
          "value": "test123",
          "temporary": false
        }
      ],
      "realmRoles": [
        "clarity-user"
      ]
    }
  ],
  "scopeMappings": [
    {
      "client": "nuxt-frontend",
      "roles": [
        "clarity-user"
      ]
    }
  ]
}
REALMEOF

echo "  Created keycloak/clarity-realm.json"

echo ""
echo "=== Step 2: Update docker-compose.yaml — mount realm + import flag ==="

# Back up the original
cp docker-compose.yaml docker-compose.yaml.bak

cat > docker-compose.yaml << 'DCEOF'
# Local development docker-compose
# Usage: docker compose up -d
services:
  db:
    image: postgres:17
    container_name: clarity-db
    environment:
      POSTGRES_DB: ${CLARITY_SQL_DB:-clarity}
      POSTGRES_USER: ${CLARITY_SQL_USER:-clarity}
      POSTGRES_PASSWORD: ${CLARITY_SQL_PASSWORD:-clarity}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - clarity_network
    ports:
      - "5432:5432"

  keycloak:
    image: quay.io/keycloak/keycloak:26.2.1
    container_name: clarity-keycloak
    depends_on:
      - db
    environment:
      - KC_DB=postgres
      - KC_DB_URL=jdbc:postgresql://db:5432/${CLARITY_SQL_DB:-clarity}
      - KC_DB_USERNAME=${CLARITY_SQL_USER:-clarity}
      - KC_DB_PASSWORD=${CLARITY_SQL_PASSWORD:-clarity}
      - KC_BOOTSTRAP_ADMIN_USERNAME=${CLARITY_KC_ADMIN:-admin}
      - KC_BOOTSTRAP_ADMIN_PASSWORD=${CLARITY_KC_ADMIN_PASSWORD:-admin}
      - JAVA_OPTS=-Xms512m -Xmx1024m
      - KC_HTTP_ENABLED=true
      - KC_HTTP_HOST=0.0.0.0
      - KC_HTTP_PORT=8080
      - KC_HTTP_RELATIVE_PATH=/kc
      - KC_PROXY_HEADERS=xforwarded
    command:
      - start-dev
      - --import-realm
    volumes:
      - ./keycloak/clarity-realm.json:/opt/keycloak/data/import/clarity-realm.json:ro
    ports:
      - "8080:8080"
    networks:
      - clarity_network

networks:
  clarity_network:
    driver: bridge

volumes:
  postgres_data:
DCEOF

echo "  Updated docker-compose.yaml (backed up to docker-compose.yaml.bak)"

echo ""
echo "=== Done ==="
echo ""
echo "To apply:"
echo "  1. Stop current containers:  docker compose down"
echo "  2. Delete Keycloak data so it re-imports:  docker compose down -v"
echo "     (WARNING: this also deletes Postgres data — re-seed with SEED_DATA=true)"
echo "  3. Restart:  docker compose up -d"
echo "  4. Keycloak auto-imports the 'clarity' realm on first boot."
echo "  5. Verify at: http://localhost:8080/kc/admin  (admin/admin)"
echo ""
echo "Test users:"
echo "  dev@clarity.local / dev123     (clarity-user + clarity-admin roles)"
echo "  testuser@clarity.local / test123  (clarity-user role only)"
