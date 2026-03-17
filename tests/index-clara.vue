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
              <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Description</th>
              <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase tracking-wider">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="projects.length === 0">
              <td colspan="4" class="px-6 py-12 text-center text-gray-400 text-sm">
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
              <td class="px-6 py-4 text-sm text-gray-500 max-w-xs truncate">{{ project.description }}</td>
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

    <!-- Project Creation Wizard -->
    <div v-else>
      <div class="max-w-3xl mx-auto">
        <!-- Stepper -->
        <div class="flex items-center justify-center mb-10">
          <template v-for="(stepInfo, idx) in steps" :key="idx">
            <div class="flex flex-col items-center">
              <div
                class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold transition-colors"
                :class="step > idx ? 'bg-gray-900 text-white' : step === idx ? 'bg-red-800 text-white' : 'bg-gray-200 text-gray-500'"
              >
                <svg v-if="step > idx" class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                <span v-else>{{ idx + 1 }}</span>
              </div>
              <div class="mt-2 text-center">
                <p class="text-xs font-semibold" :class="step >= idx ? 'text-gray-900' : 'text-gray-400'">{{ stepInfo.title }}</p>
                <p class="text-xs text-gray-400 max-w-[140px]">{{ stepInfo.subtitle }}</p>
              </div>
            </div>
            <div
              v-if="idx < steps.length - 1"
              class="w-24 h-0.5 mb-8 transition-colors"
              :class="step > idx ? 'bg-gray-900' : 'bg-gray-200'"
            ></div>
          </template>
        </div>

        <!-- Step 1: Project Details -->
        <div v-if="step === 0" class="bg-white rounded-lg shadow-sm border border-gray-200 p-8">
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
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1.5">Project Description</label>
              <textarea
                v-model="form.description"
                rows="6"
                placeholder="Describe the project (minimum 250 characters)..."
                class="w-full border border-gray-300 rounded-md px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-red-800 focus:border-transparent resize-none"
              ></textarea>
              <p class="mt-1 text-xs text-gray-400 text-right">{{ form.description.length }} characters (250 required)</p>
            </div>
            <button
              @click="showExample = !showExample"
              class="text-sm text-gray-500 hover:text-gray-700 flex items-center gap-1"
            >
              <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              Example
            </button>
            <div v-if="showExample" class="bg-gray-50 border border-gray-200 rounded-md p-4 text-xs text-gray-600 leading-relaxed">
              This project aims to support the business in all aspects of operations to maximize cost effective &amp; sustainable environments for building operations and occupants by providing a segregated environment for monitoring infrastructure including building Automation (networks), utility metering, building equipment, and other equipment resources that generate performance data for monitoring, control, and advanced fault diagnostics.
            </div>
          </div>
        </div>

        <!-- Step 2: Attributes -->
        <div v-if="step === 1" class="bg-white rounded-lg shadow-sm border border-gray-200 p-8">
          <p class="text-sm text-gray-600 mb-4">Select all attributes that apply to your project/application.</p>
          <div class="space-y-3">
            <label
              v-for="attr in attributeOptions"
              :key="attr.value"
              class="flex items-start gap-3 p-3 rounded-md hover:bg-gray-50 cursor-pointer transition-colors"
            >
              <input
                type="checkbox"
                :value="attr.value"
                v-model="form.attributes"
                class="mt-0.5 h-4 w-4 rounded border-gray-300 text-red-800 focus:ring-red-800"
              />
              <span class="text-sm text-gray-700">{{ attr.label }}</span>
            </label>
          </div>
        </div>

        <!-- Step 3: Tags -->
        <div v-if="step === 2" class="bg-white rounded-lg shadow-sm border border-gray-200 p-8">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1.5">Metadata Tags</label>
            <div class="flex gap-2 mb-3">
              <input
                v-model="tagInput"
                @keydown.enter.prevent="addTag"
                type="text"
                placeholder="Type Tag (e.g. SLAMS, TRANE) and Press Enter"
                class="flex-1 border border-gray-300 rounded-md px-4 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-red-800 focus:border-transparent"
              />
              <button
                @click="addTag"
                class="bg-gray-100 text-gray-600 px-4 py-2.5 rounded-md text-sm hover:bg-gray-200 transition-colors"
              >
                Add
              </button>
            </div>
            <div v-if="form.tags.length" class="flex flex-wrap gap-2 mb-4">
              <span
                v-for="(tag, i) in form.tags"
                :key="i"
                class="bg-gray-100 text-gray-700 text-xs px-3 py-1.5 rounded-full flex items-center gap-1.5"
              >
                {{ tag }}
                <button @click="form.tags.splice(i, 1)" class="text-gray-400 hover:text-gray-600">
                  <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </span>
            </div>
            <p class="text-xs text-gray-400">
              Add tags (single keywords) to your project description. This will help optimize Clarity's performance when helping you fill out your IRAMP/ATO.
            </p>
          </div>
        </div>

        <!-- Navigation -->
        <div class="flex items-center justify-between mt-6">
          <button
            v-if="step > 0"
            @click="step--"
            class="text-sm text-gray-500 hover:text-gray-700 transition-colors"
          >
            ← Back
          </button>
          <button
            v-else
            @click="showWizard = false"
            class="text-sm text-gray-500 hover:text-gray-700 transition-colors"
          >
            ← Cancel
          </button>

          <button
            v-if="step < 2"
            @click="step++"
            :disabled="!canAdvance"
            class="bg-red-800 text-white px-6 py-2.5 rounded-md text-sm font-medium hover:bg-red-900 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Next
          </button>
          <button
            v-else
            @click="submitProject"
            :disabled="submitting"
            class="bg-red-800 text-white px-6 py-2.5 rounded-md text-sm font-medium hover:bg-red-900 transition-colors disabled:opacity-40"
          >
            {{ submitting ? 'Creating...' : 'Submit' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const { getProjects, createProject } = useApi()

const showWizard = ref(false)
const showExample = ref(false)
const step = ref(0)
const submitting = ref(false)
const tagInput = ref('')
const projects = ref<any[]>([])

const form = reactive({
  title: '',
  description: '',
  attributes: [] as string[],
  tags: [] as string[],
})

const steps = [
  { title: 'Project Details', subtitle: 'Tell us a little about your project.' },
  { title: 'Attributes', subtitle: 'Choose which project attributes apply.' },
  { title: 'Tags', subtitle: 'Project metadata tags will help optimize your IRAMP/ATO capture.' },
]

const attributeOptions = [
  { value: 'EAR', label: 'The data my application works with falls under EAR classification' },
  { value: 'ITAR', label: 'The data my application works with falls under ITAR classification' },
  { value: 'CUI', label: 'My application handles CUI/CDI data' },
  { value: 'ForeignNational', label: 'I will require foreign nationals to be able to access my application' },
  { value: 'Cloud', label: 'I plan to host my application in a Cloud environment' },
  { value: 'OnPrem', label: 'I plan to host my application on-prem RTX managed hardware' },
  { value: 'CollinsInternal', label: 'The application will handle Collins proprietary (internal) data' },
  { value: 'ThirdParty', label: 'The application will handle external, third-party data' },
]

const canAdvance = computed(() => {
  if (step.value === 0) return form.title.trim().length > 0 && form.description.length >= 250
  if (step.value === 1) return form.attributes.length > 0
  return true
})

function addTag() {
  const tag = tagInput.value.trim()
  if (tag && tag.length <= 30 && form.tags.length < 15 && !form.tags.includes(tag)) {
    form.tags.push(tag)
    tagInput.value = ''
  }
}

async function submitProject() {
  submitting.value = true
  try {
    const project = await createProject({
      title: form.title,
      description: form.description,
      tags: form.tags,
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
