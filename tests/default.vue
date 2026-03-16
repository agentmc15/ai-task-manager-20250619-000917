<template>
  <div class="min-h-screen bg-gray-50">
    <!-- Top Navigation -->
    <header class="bg-gray-900 text-white shadow-md">
      <div class="max-w-7xl mx-auto px-6 h-14 flex items-center justify-between">
        <div class="flex items-center gap-8">
          <NuxtLink to="/" class="text-lg font-bold tracking-tight hover:text-gray-200 transition-colors">
            Clarity
          </NuxtLink>
          <nav class="flex items-center gap-6 text-sm">
            <NuxtLink to="/" class="text-gray-300 hover:text-white transition-colors">Home</NuxtLink>
            <NuxtLink to="/clara" class="text-gray-300 hover:text-white transition-colors">IRAMP/ATOs</NuxtLink>
          </nav>
        </div>
        <div class="flex items-center gap-4 text-sm">
          <span class="text-gray-400">{{ user?.name || 'Dev User' }}</span>
          <button
            v-if="user"
            @click="handleLogout"
            class="text-gray-400 hover:text-white transition-colors"
          >
            Sign Out
          </button>
        </div>
      </div>
    </header>

    <!-- Red accent bar -->
    <div class="h-1 bg-red-700"></div>

    <!-- Page Content -->
    <main>
      <slot />
    </main>
  </div>
</template>

<script setup lang="ts">
const user = ref({ name: 'Dev User', sub: 'dev-user-001', email: 'dev@rtx.com' })

function handleLogout() {
  navigateTo('/login')
}
</script>
