import tailwindcss from "@tailwindcss/vite"

export default defineNuxtConfig({
  compatibilityDate: '2024-11-01',
  devtools: { enabled: true },
  css: ['~/assets/css/tailwind.css'],
  modules: [
    '@nuxt/icon',
    '@nuxtjs/google-fonts',
    '@nuxtjs/color-mode',
    '@nuxt/test-utils/module',
    'nuxt-auth-utils',
    'shadcn-nuxt'
  ],
  colorMode: {
    classSuffix: ''
  },
  shadcn: {
    prefix: '',
    componentDir: './components/shadcn'
  },
  vite: {
    plugins: [tailwindcss()]
  },
  runtimeConfig: {
    session: {
      password: process.env.NUXT_SESSION_PASSWORD || '',
    },
    oauth: {
      keycloak: {
        clientId: process.env.NUXT_OAUTH_KEYCLOAK_CLIENT_ID || 'nuxt-frontend',
        clientSecret: process.env.NUXT_OAUTH_KEYCLOAK_CLIENT_SECRET || '',
        serverUrl: process.env.NUXT_OAUTH_KEYCLOAK_SERVER_URL || 'http://localhost:8080',
        realm: process.env.NUXT_OAUTH_KEYCLOAK_REALM || 'clarity',
        redirectUrl: process.env.NUXT_OAUTH_KEYCLOAK_REDIRECT_URL || 'http://localhost:3000/auth/sso/callback',
      },
    },
    public: {
      apiBase: process.env.NUXT_API_BASE || 'http://localhost:4000',
      authMode: process.env.AUTH_MODE || 'dev',
      redirectUrl: process.env.NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL,
    },
  },
})
