#!/usr/bin/env bash
# ============================================================
# Clarity AWS .env Setup — Copy and paste this entire block
# Run from: /etc/clarity/GRCAA-Clarity/projects/clarity-rewrite
# ============================================================

# --- Backend .env ---
cat > backend/.env << 'BACKEND_EOF'
# === Auth Mode ===
# 'dev'                = No login, mock user (dev@clarity.local)
# 'keycloak'           = Local Keycloak (Docker, localhost:8080)
# 'keycloak-enterprise' = RTX enterprise Keycloak (shared instance)
AUTH_MODE=keycloak-enterprise

# === PostgreSQL ===
CLARITY_SQL_DB=clarity
CLARITY_SQL_USER=root
CLARITY_SQL_PASSWORD=claritySqlAdminPassword
CLARITY_SQL_HOST=localhost
CLARITY_SQL_PORT=5432

# === Local Keycloak (used when AUTH_MODE=keycloak) ===
CLARITY_KC_HOST=localhost
CLARITY_KC_PORT=8080
CLARITY_KC_REALM=clarity
CLARITY_KC_ADMIN=admin
CLARITY_KC_ADMIN_PASSWORD=admin
CLARITY_KC_MGMT_CLIENT_SECRET=PE1JjykdiIq0XAg8W68u0MzL5USMBua

# === Enterprise Keycloak (used when AUTH_MODE=keycloak-enterprise) ===
ENTERPRISE_KC_SERVER_URL=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com
ENTERPRISE_KC_REALM=avionics
ENTERPRISE_KC_CLIENT_ID=clarity-dev
ENTERPRISE_KC_CLIENT_SECRET=8cmWkED0CtGLzijIcKZysnUnJA6Mabjv

# === Corporate OIDC (RTX SSO — production) ===
COMP_OIDC_CLIENT_ID=CLARA_CoPilot_Dev_Prod_AC
COMP_OIDC_CLIENT_SECRET=iPvy1EcuMkUTeAQrSb3zmrdqWxSS6tT1lzkrAy3mwGKd4AQswANT5T4EDHkaS2MF
CORP_OIDC_DISCOVERY_ENDPOINT=https://sso.rtx.com/.well-known/openid-configuration
CORP_OIDC_ISSUER=https://sso.rtx.com
CORP_OIDC_AUTHORIZATION_URL=https://sso.rtx.com/as/authorization.oauth2
CORP_OIDC_TOKEN_URL=https://sso.rtx.com/as/token.oauth2
CORP_OIDC_JWKS_URL=https://sso.rtx.com/pf/JWKS
CORP_OIDC_USER_INFO_URL=https://sso.rtx.com/idp/userinfo.openid

# === RTX Model Hub (placeholder) ===
META_OPENAI_URL=https://model-hub-gateway-dev.apim.xeta.rtx.com
META_OPENAI_KEY=67b3aa3c3c6a90bafacc73b3be75c722

# === Archer GRC ===
ARCHER_USERNAME=API-ATOClarityPOC
ARCHER_PASSWORD=_jvh-<*l0z#HE2?|OuaPckSJ[W7%N{
ARCHER_INSTANCE_NAME=ArcherPOC
ARCHER_BASE_URI=https://archerpoc.corp.ray.com
ARCHER_SOAP_SEARCH_URI=https://archerpoc.corp.ray.com/ws/search.asmx?WSDL
ARCHER_SOAP_GENERAL_URI=https://archerpoc.corp.ray.com/ws/general.asmx?WSDL
MAPPING_REPORT=08F55A31-90CD-421D-A26D-290DE093BA82

# === Seeding ===
SEED_DATA=true

# === Frontend (Nuxt) ===
# --- For AUTH_MODE=keycloak (local): ---
#NUXT_OAUTH_KEYCLOAK_REALM=clarity
#NUXT_OAUTH_KEYCLOAK_CLIENT_ID=nuxt-frontend
#NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=nEMT2PXHmL9shdQPP8UpQLHeHfrGX1tF
#NUXT_OAUTH_KEYCLOAK_SERVER_URL=http://localhost:8080
#NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/sso/callback
#NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/sso/callback
#
# --- For AUTH_MODE=keycloak-enterprise (uncomment and swap above): ---
NUXT_OAUTH_KEYCLOAK_REALM=avionics
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=clarity-dev
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=8cmWkED0CtGLzijIcKZysnUnJA6Mabjv
NUXT_OAUTH_KEYCLOAK_SERVER_URL=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/sso/callback
NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/sso/callback

NUXT_API_BASE=http://localhost:4000
NUXT_SESSION_PASSWORD=adfadsfdaasfdasfdasfdasfdasfdasfdasdafdsafdasfdsafdsa
NODE_TLS_REJECT_UNAUTHORIZED=0
BACKEND_EOF

echo "Created backend/.env"

# --- Frontend .env ---
cat > frontend/.env << 'FRONTEND_EOF'
NUXT_SESSION_PASSWORD=c58ced7685b54a44ab7a2d2d26ca620a
AUTH_MODE=keycloak-enterprise
#NUXT_OAUTH_KEYCLOAK_REALM=clarity
#NUXT_OAUTH_KEYCLOAK_CLIENT_ID=nuxt-frontend
#NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=nEMT2PXHmL9shdQPP8UpQLHeHfrGX1tF
#NUXT_OAUTH_KEYCLOAK_SERVER_URL=http://localhost:8080/kc
#NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/keycloak

NUXT_OAUTH_KEYCLOAK_REALM=avionics
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=clarity-dev
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=8cmWkED0CtGLzijIcKZysnUnJA6Mabjv
NUXT_OAUTH_KEYCLOAK_SERVER_URL=https://keycloak-npd.c32p1-colk8s.wg1.aws.ray.com
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3000/auth/sso/callback

NODE_TLS_REJECT_UNAUTHORIZED=0
FRONTEND_EOF

echo "Created frontend/.env"

# --- Root .env ---
cat > .env << 'ROOT_EOF'
# === PostgreSQL ===
CLARITY_SQL_DB=clarity
CLARITY_SQL_USER=root
CLARITY_SQL_PASSWORD=claritySqlAdminPassword
CLARITY_SQL_HOST=localhost
CLARITY_SQL_PORT=5432

# === Keycloak ===
CLARITY_KC_HOST=localhost
CLARITY_KC_PORT=8080
CLARITY_KC_REALM=clarity
CLARITY_KC_ADMIN=admin
CLARITY_KC_ADMIN_PASSWORD=admin
CLARITY_KC_MGMT_CLIENT_SECRET=PE1JjykdiIq0XAg8W68u0MzL5USMBua

# === Corporate OIDC (RTX SSO) ===
COMP_OIDC_CLIENT_ID=CLARA_CoPilot_Dev_Prod_AC
COMP_OIDC_CLIENT_SECRET=iPvy1EcuMkUTeAQrSb3zmrdqWxSS6tT1lzkrAy3mwGKd4AQswANT5T4EDHkaS2MF
CORP_OIDC_DISCOVERY_ENDPOINT=https://sso.rtx.com/.well-known/openid-configuration
CORP_OIDC_ISSUER=https://sso.rtx.com
CORP_OIDC_AUTHORIZATION_URL=https://sso.rtx.com/as/authorization.oauth2
CORP_OIDC_TOKEN_URL=https://sso.rtx.com/as/token.oauth2
CORP_OIDC_JWKS_URL=https://sso.rtx.com/pf/JWKS
CORP_OIDC_USER_INFO_URL=https://sso.rtx.com/idp/userinfo.openid

# === RTX Model Hub (placeholder) ===
META_OPENAI_URL=https://model-hub-gateway-dev.apim.xeta.rtx.com
META_OPENAI_KEY=67b3aa3c3c6a90bafacc73b3be75c722

# === Archer GRC ===
ARCHER_USERNAME=API-ATOClarityPOC
ARCHER_PASSWORD=_jvh-<*l0z#HE2?|OuaPckSJ[W7%N{
ARCHER_INSTANCE_NAME=ArcherPOC
ARCHER_BASE_URI=https://archerpoc.corp.ray.com
ARCHER_SOAP_SEARCH_URI=https://archerpoc.corp.ray.com/ws/search.asmx?WSDL
ARCHER_SOAP_GENERAL_URI=https://archerpoc.corp.ray.com/ws/general.asmx?WSDL
MAPPING_REPORT=08F55A31-90CD-421D-A26D-290DE093BA82

# === Seeding ===
SEED_DATA=true

# === Frontend (Nuxt) ===
NUXT_API_BASE=http://localhost:4000
NUXT_OAUTH_KEYCLOAK_REALM=clarity
NUXT_OAUTH_KEYCLOAK_CLIENT_ID=nuxt-frontend
NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET=nEMT2PXHmL9shdQPP8UpQLHeHfrGX1tF
NUXT_OAUTH_KEYCLOAK_SERVER_URL=http://localhost:8080
NUXT_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3001/auth/sso/callback
NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL=http://localhost:3001/auth/sso/callback
NUXT_SESSION_PASSWORD=adfadsfdaasfdasfdasfdasfdasfdasfdasdafdsafdasfdsafdsa
NODE_TLS_REJECT_UNAUTHORIZED=0
ROOT_EOF

echo "Created .env"

# --- Load all into current shell ---
export $(cat backend/.env | grep -v '^#' | grep -v '^$' | xargs)
echo ""
echo "All .env files created and loaded."
echo "AUTH_MODE=$AUTH_MODE"
echo "CLARITY_SQL_DB=$CLARITY_SQL_DB"
echo ""
