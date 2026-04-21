<template>
  <div class="max-w-6xl mx-auto px-6 py-8">
    <!-- Project List View -->
    <div v-if="!showWizard">
      <div class="flex items-center justify-between mb-6">
        <h2 class="text-2xl font-bold text-gray-900">Your IRAMP/ATOs</h2>
        <button
          @click="showWizard = true"
          class="bg-red-800 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-red-900 transition-colors flex items-center gap-2"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
          Start a New IRAMP/ATO
        </button>
      </div>

      <!-- Table -->
      <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
        <table class="w-full">
          <thead>
            <tr class="border-b border-gray-200 bg-gray-50">
              <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Project ID</th>
              <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Title</th>
              <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="projects.length === 0">
              <td colspan="3" class="px-6 py-12 text-center text-gray-400 text-sm">
                No IRAMP/ATOs to display
              </td>
            </tr>
            <tr
              v-for="project in projects"
              :key="project.id"
              class="border-b border-gray-100 hover:bg-gray-50 transition-colors"
            >
              <td class="px-6 py-4 text-sm text-gray-500 font-mono">{{ project.id.slice(0, 8) }}...</td>
              <td class="px-6 py-4 text-sm font-medium text-gray-900">{{ project.title }}</td>
              <td class="px-6 py-4">
                <NuxtLink
                  :to="`/clara/${project.id}`"
                  class="text-sm text-red-700 hover:text-red-900 font-medium transition-colors"
                >
                  Open →
                </NuxtLink>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Project Creation - simplified to single form -->
    <div v-else>
      <div class="max-w-3xl mx-auto">
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-8">
          <h3 class="text-xl font-bold text-gray-900 mb-1">New IRAMP/ATO</h3>
          <p class="text-sm text-gray-500 mb-6">Give your project a name to begin.</p>

          <div class="space-y-5">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1.5">Project Title</label>
              <input
                v-model="form.title"
                type="text"
                placeholder="Enter project title"
                class="w-full border border-gray-300 rounded-md px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-red-800 focus:border-transparent"
              />
            </div>
          </div>

          <!-- Navigation -->
          <div class="flex items-center justify-between mt-8">
            <button
              @click="cancelCreate"
              class="text-sm text-gray-500 hover:text-gray-700 transition-colors"
            >
              ← Cancel
            </button>

            <button
              @click="submitProject"
              :disabled="!canSubmit || submitting"
              class="bg-red-800 text-white px-6 py-2.5 rounded-md text-sm font-medium hover:bg-red-900 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {{ submitting ? 'Creating...' : 'Create' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
definePageMeta({ middleware: 'auth' })
const { getProjects, createProject } = useApi()

const showWizard = ref(false)
const submitting = ref(false)
const projects = ref<any[]>([])

const form = reactive({
  title: '',
})

const canSubmit = computed(() => form.title.trim().length > 0)

function cancelCreate() {
  showWizard.value = false
  form.title = ''
}

async function submitProject() {
  if (!canSubmit.value) return
  submitting.value = true
  try {
    const project = await createProject({
      title: form.title.trim(),
      description: '',
      tags: [],
      user_id: 'dev-user-001',
      questionnaire_id: 1,
    })
    if (project?.id) {
      navigateTo(`/clara/${project.id}`)
    }
  } catch (e) {
    console.error('Failed to create project:', e)
  } finally {
    submitting.value = false
  }
}

async function loadProjects() {
  try {
    const data = await getProjects('dev-user-001')
    projects.value = data || []
  } catch (e) {
    console.error('Failed to load projects:', e)
  }
}

onMounted(() => loadProjects())
</script>
