<template>
  <div class="max-w-7xl mx-auto px-6 py-16 text-center">
    <h1 class="text-4xl font-bold text-gray-900 mb-4">IRAMP Workflow Automation</h1>
    <p class="text-gray-500 text-lg mb-8 max-w-2xl mx-auto">
      Streamline your IRAMP/ATO authorization package workflow. Create projects, complete questionnaires, and submit to RSA Archer GRC.
    </p>
    <NuxtLink
      to="/clara"
      class="inline-flex items-center gap-2 bg-gray-900 text-white px-6 py-3 rounded-md font-medium hover:bg-gray-800 transition-colors"
    >
      Go to IRAMP/ATOs
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
      </svg>
    </NuxtLink>
  </div>
</template>
