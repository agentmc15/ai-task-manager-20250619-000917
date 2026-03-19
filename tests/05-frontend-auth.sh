#!/usr/bin/env bash
set -euo pipefail
#
# Script 5: Frontend AUTH_MODE integration
# Updates Nuxt frontend to work with both dev and keycloak auth modes.
# Run from: ~/desktop/repos/clarity-rewrite
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Create auth composable ==="

mkdir -p frontend/composables

cat > frontend/composables/useAuth.ts << 'AUTHEOF'
/**
 * Auth composable — handles both dev and keycloak modes.
 *
 * In dev mode (AUTH_MODE=dev):
 *   - No real login flow; returns a mock user.
 *   - API requests include no Bearer token (backend doesn't require one).
 *
 * In keycloak mode (AUTH_MODE=keycloak):
 *   - Uses nuxt-auth-utils for OIDC flow.
 *   - API requests include the Bearer token from the session.
 */

interface ClarityUser {
  email: string
  name: string
  roles: string[]
}

const DEV_USER: ClarityUser = {
  email: 'dev@clarity.local',
  name: 'Dev User',
  roles: ['clarity-user', 'clarity-admin'],
}

export function useAuth() {
  const config = useRuntimeConfig()
  const authMode = config.public.authMode || 'dev'

  // In keycloak mode, use nuxt-auth-utils session
  const { loggedIn, user: sessionUser, session, clear } =
    authMode === 'keycloak' ? useUserSession() : {
      loggedIn: ref(true),
      user: ref(DEV_USER),
      session: ref(null),
      clear: async () => {},
    }

  const user = computed<ClarityUser>(() => {
    if (authMode === 'dev') return DEV_USER

    if (sessionUser.value) {
      return {
        email: (sessionUser.value as any).email || 'unknown',
        name: (sessionUser.value as any).name || 'Unknown',
        roles: (sessionUser.value as any).roles || [],
      }
    }

    return DEV_USER
  })

  const isAuthenticated = computed(() => {
    if (authMode === 'dev') return true
    return loggedIn.value
  })

  const isAdmin = computed(() =>
    user.value.roles.includes('clarity-admin')
  )

  /**
   * Get authorization headers for API requests.
   * In dev mode, returns empty object (no token needed).
   * In keycloak mode, returns Bearer token from session.
   */
  function getAuthHeaders(): Record<string, string> {
    if (authMode === 'dev') return {}

    const token = (session.value as any)?.accessToken
    if (token) {
      return { Authorization: `Bearer ${token}` }
    }
    return {}
  }

  async function login() {
    if (authMode === 'dev') return // No-op in dev mode
    await navigateTo('/auth/keycloak', { external: true })
  }

  async function logout() {
    if (authMode === 'dev') {
      await navigateTo('/')
      return
    }
    await clear()
    await navigateTo('/')
  }

  return {
    authMode,
    user,
    isAuthenticated,
    isAdmin,
    getAuthHeaders,
    login,
    logout,
  }
}
AUTHEOF

echo "  Created frontend/composables/useAuth.ts"

echo ""
echo "=== Step 2: Update useApi.ts to include auth headers ==="

cat > frontend/composables/useApi.ts << 'APIEOF'
/**
 * API client composable — all backend requests go through here.
 * Automatically includes auth headers based on AUTH_MODE.
 */

export function useApi() {
  const config = useRuntimeConfig()
  const { getAuthHeaders } = useAuth()

  const baseURL = config.public.apiBase || 'http://localhost:4000'

  async function apiFetch<T>(
    path: string,
    options: RequestInit & { params?: Record<string, string> } = {},
  ): Promise<T> {
    const url = new URL(path, baseURL)

    if (options.params) {
      for (const [key, val] of Object.entries(options.params)) {
        if (val !== undefined && val !== null) {
          url.searchParams.set(key, val)
        }
      }
    }

    const headers = {
      'Content-Type': 'application/json',
      ...getAuthHeaders(),
      ...(options.headers || {}),
    }

    const response = await fetch(url.toString(), {
      ...options,
      headers,
    })

    if (!response.ok) {
      const errorBody = await response.text().catch(() => 'Unknown error')
      throw new Error(`API ${response.status}: ${errorBody}`)
    }

    return response.json()
  }

  // ----- Project CRUD -----

  async function getProjects(opts?: {
    projectId?: string
    title?: string
    includeQuestionnaire?: boolean
  }) {
    const params: Record<string, string> = {}
    if (opts?.projectId) params.project_id = opts.projectId
    if (opts?.title) params.title = opts.title
    if (opts?.includeQuestionnaire) params.include_questionnaire = 'true'

    return apiFetch<any[]>('/project/', { params })
  }

  async function getProject(projectId: string, includeQuestionnaire = false) {
    const params: Record<string, string> = {}
    if (includeQuestionnaire) params.include_questionnaire = 'true'
    return apiFetch<any>(`/project/${projectId}`, { params })
  }

  async function createProject(data: {
    title: string
    description: string
    questionnaire_id: number
    tags?: string[]
    attributes?: Array<{ text: string }>
  }) {
    return apiFetch<any>('/project/', {
      method: 'POST',
      body: JSON.stringify(data),
    })
  }

  async function deleteProject(projectId: string) {
    return apiFetch<any>('/project/', {
      method: 'DELETE',
      params: { project_id: projectId },
    })
  }

  // ----- Answers -----

  async function saveAnswer(data: {
    project_id: string
    question_id: string
    answer: string | string[]
    justification?: string
  }) {
    return apiFetch<any>('/project/answer/create', {
      method: 'POST',
      body: JSON.stringify(data),
    })
  }

  // ----- Questionnaires -----

  async function getQuestionnaires(opts?: {
    questionnaireId?: number
    version?: string
    active?: boolean
  }) {
    const params: Record<string, string> = {}
    if (opts?.questionnaireId) params.questionnaire_id = String(opts.questionnaireId)
    if (opts?.version) params.version = opts.version
    if (opts?.active !== undefined) params.active = String(opts.active)

    return apiFetch<any>('/questionnaire/', { params })
  }

  return {
    apiFetch,
    getProjects,
    getProject,
    createProject,
    deleteProject,
    saveAnswer,
    getQuestionnaires,
  }
}
APIEOF

echo "  Updated frontend/composables/useApi.ts"

echo ""
echo "=== Step 3: Add auth middleware ==="

mkdir -p frontend/middleware

cat > frontend/middleware/auth.ts << 'MWEOF'
/**
 * Auth middleware — redirects to login if not authenticated.
 * Pages that need auth should use: definePageMeta({ middleware: 'auth' })
 */
export default defineNuxtRouteMiddleware((to) => {
  const { isAuthenticated, authMode, login } = useAuth()

  // Dev mode: always authenticated, skip middleware
  if (authMode === 'dev') return

  // Keycloak mode: check session
  if (!isAuthenticated.value) {
    // Don't redirect if already on login/callback pages
    if (to.path.startsWith('/auth') || to.path === '/login') return

    return navigateTo('/login')
  }
})
MWEOF

echo "  Created frontend/middleware/auth.ts"

echo ""
echo "=== Step 4: Update nuxt.config.ts runtime config ==="

# We need to add authMode and apiBase to the public runtime config.
# Rather than rewriting the whole file, here's what to add:

cat > frontend/_nuxt_config_patch.md << 'PATCHEOF'
# Patch: Add to nuxt.config.ts

In your `nuxt.config.ts`, add or update the `runtimeConfig` section:

```typescript
export default defineNuxtConfig({
  // ... existing config ...

  runtimeConfig: {
    // Server-side only
    session: {
      password: process.env.NUXT_SESSION_PASSWORD || '',
    },
    oauth: {
      keycloak: {
        clientId: process.env.NUXT_OAUTH_KEYCLOAK_CLIENT_ID || 'nuxt-frontend',
        clientSecret: process.env.NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET || '',
        serverUrl: process.env.NUXT_OAUTH_KEYCLOAK_SERVER_URL || 'http://localhost:8080',
        realm: process.env.NUXT_OAUTH_KEYCLOAK_REALM || 'clarity',
        redirectUrl: process.env.NUXT_OAUTH_KEYCLOAK_REDIRECT_URL || 'http://localhost:3001/auth/sso/callback',
      },
    },

    // Client-side (public)
    public: {
      apiBase: process.env.NUXT_API_BASE || 'http://localhost:4000',
      authMode: process.env.AUTH_MODE || 'dev',
    },
  },
})
```

Also make sure `nuxt-auth-utils` is in your modules array:
```typescript
  modules: [
    'nuxt-auth-utils',
    // ... other modules
  ],
```
PATCHEOF

echo "  Created frontend/_nuxt_config_patch.md (manual patch instructions)"

echo ""
echo "=== Step 5: Add AUTH_MODE to frontend .env ==="

# The frontend needs to know the auth mode via NUXT_PUBLIC_AUTH_MODE
if [ -f frontend/.env ]; then
    if ! grep -q "AUTH_MODE" frontend/.env 2>/dev/null; then
        echo "" >> frontend/.env
        echo "AUTH_MODE=dev" >> frontend/.env
    fi
fi

echo ""
echo "=== Done ==="
echo ""
echo "Frontend changes summary:"
echo "  composables/useAuth.ts  — Auth state + headers for dev/keycloak modes"
echo "  composables/useApi.ts   — API client with auto-injected auth headers"
echo "  middleware/auth.ts      — Route guard (no-op in dev mode)"
echo ""
echo "Manual steps:"
echo "  1. Apply the nuxt.config.ts patch (see frontend/_nuxt_config_patch.md)"
echo "  2. In pages that need auth, add: definePageMeta({ middleware: 'auth' })"
echo "  3. In components, use: const { user, isAdmin, logout } = useAuth()"
