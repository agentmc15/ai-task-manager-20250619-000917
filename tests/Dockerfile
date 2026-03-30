FROM node:20-alpine AS base
WORKDIR /app

# Install dependencies
FROM base AS deps
COPY package.json package-lock.json* yarn.lock* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn install --frozen-lockfile; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  else npm install; \
  fi

# Build the Nuxt app
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG NUXT_PUBLIC_API_BASE_URL=/be
ARG NUXT_PUBLIC_AUTH_MODE=keycloak-enterprise
ENV NUXT_PUBLIC_API_BASE_URL=${NUXT_PUBLIC_API_BASE_URL}
ENV NUXT_PUBLIC_AUTH_MODE=${NUXT_PUBLIC_AUTH_MODE}

RUN npm run build

# Production runner
FROM base AS runner
ENV NODE_ENV=production

COPY --from=builder /app/.output ./.output

EXPOSE 3000

CMD ["node", ".output/server/index.mjs"]
