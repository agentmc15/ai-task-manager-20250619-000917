<template>
  <div class="min-h-screen bg-gray-50 flex items-center justify-center">
    <div class="bg-white rounded-lg shadow-lg p-8 w-full max-w-md text-center">
      <!-- Logo -->
      <h1 class="text-3xl font-bold text-gray-900 mb-2">Clarity</h1>
      <p class="text-gray-500 text-sm mb-8">IRAMP/ATO Management System</p>

      <!-- SSO Button -->
      <button
        @click="loginSSO"
        class="w-full bg-gray-900 text-white py-3 px-4 rounded-md font-medium hover:bg-gray-800 transition-colors flex items-center justify-center gap-2 mb-6"
      >
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
        </svg>
        Login with RTX SSO
      </button>

      <!-- Divider -->
      <div class="relative mb-6">
        <div class="absolute inset-0 flex items-center">
          <div class="w-full border-t border-gray-200"></div>
        </div>
        <div class="relative flex justify-center text-sm">
          <span class="bg-white px-3 text-gray-400">Admin Login</span>
        </div>
      </div>

      <!-- Admin form -->
      <div class="space-y-4">
        <input
          v-model="username"
          type="text"
          placeholder="Admin Username"
          class="w-full border border-gray-300 rounded-md px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
        />
        <input
          v-model="password"
          type="password"
          placeholder="Admin Password"
          class="w-full border border-gray-300 rounded-md px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
        />
        <button
          @click="loginAdmin"
          class="w-full bg-white border border-gray-300 text-gray-700 py-2.5 px-4 rounded-md text-sm font-medium hover:bg-gray-50 transition-colors flex items-center justify-center gap-2"
        >
          Login
        </button>
      </div>

      <!-- Dev bypass -->
      <div class="mt-6 pt-6 border-t border-gray-100">
        <button
          @click="devBypass"
          class="text-xs text-gray-400 hover:text-red-600 transition-colors"
        >
          Dev Bypass (skip auth)
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ layout: false })

const username = ref('')
const password = ref('')

function loginSSO() {
  // Would normally redirect to Keycloak
  // For now, just bypass
  devBypass()
}

function loginAdmin() {
  devBypass()
}

function devBypass() {
  // Set a dev cookie/flag and redirect
  if (import.meta.client) {
    localStorage.setItem('clarity_dev_user', JSON.stringify({
      sub: 'dev-user-001',
      name: 'Dev User',
      email: 'dev@rtx.com',
      admin: true,
    }))
  }
  navigateTo('/clara')
}
</script>
