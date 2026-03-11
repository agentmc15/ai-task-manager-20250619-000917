#!/usr/bin/env bash
# =============================================================================
# CLARITY REWRITE — Part 2: Frontend + All Start Scripts
# =============================================================================
# Copy-paste into Git Bash (Windows) or terminal (Linux). Run AFTER Part 1.
# Generates: .sh (Git Bash/Linux), .bat (Windows CMD), .ps1 (PowerShell)
# =============================================================================
set -euo pipefail
P="clarity-rewrite"
if [ ! -d "$P/backend" ]; then echo "ERROR: Run Part 1 first."; exit 1; fi
echo "Creating Clarity frontend + start scripts..."
mkdir -p "$P"/frontend/{assets/css,components/shadcn,composables,layouts,lib,middleware,pages/{admin,clara},plugins,public,server,types}

cat > "$P/frontend/Dockerfile" << '_CLARITY_EOF_'
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
EXPOSE 3001
CMD ["node", ".output/server/index.mjs"]
_CLARITY_EOF_

cat > "$P/frontend/app.vue" << '_CLARITY_EOF_'
<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>
_CLARITY_EOF_

cat > "$P/frontend/auth.d.ts" << '_CLARITY_EOF_'
import type { Project } from "@/types/project"

declare module '#auth-utils' {
  interface User {
    sub: string
    email_verified: boolean
    preferred_username: string
    name: string
    given_name: string
    family_name: string
    email: string
    admin?: boolean
    reviewer?: boolean
    projects?: Project[]
  }

  interface UserSession {
    extended?: any
    jwt?: {
      accessToken: string
      refreshToken: string
    }
    loggedInAt: number
  }

  interface SecureSessionData { }

  export { }
}
_CLARITY_EOF_

cat > "$P/frontend/nuxt.config.ts" << '_CLARITY_EOF_'
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
    public: {
      apiBase: process.env.NUXT_API_BASE || "/api",
      redirectUrl: process.env.NUXT_PUBLIC_OAUTH_KEYCLOAK_REDIRECT_URL
    },
  },
})
_CLARITY_EOF_

cat > "$P/frontend/package.json" << '_CLARITY_EOF_'
{
  "name": "clarity-ui",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "nuxt build",
    "dev": "nuxt dev --port 3001",
    "generate": "nuxt generate",
    "preview": "nuxt preview",
    "postinstall": "nuxt prepare"
  },
  "dependencies": {
    "@nuxt/icon": "^1.0.0",
    "@nuxtjs/color-mode": "^3.3.0",
    "@nuxtjs/google-fonts": "^3.0.0",
    "@tailwindcss/vite": "^4.0.0",
    "@vee-validate/zod": "^4.12.0",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.1.0",
    "lucide-vue-next": "^0.383.0",
    "nuxt": "^3.13.0",
    "nuxt-auth-utils": "^0.3.0",
    "radix-vue": "^1.9.0",
    "shadcn-nuxt": "^0.10.0",
    "tailwind-merge": "^2.2.0",
    "tailwindcss": "^4.0.0",
    "vee-validate": "^4.12.0",
    "vue": "^3.4.0",
    "zod": "^3.22.0"
  },
  "devDependencies": {
    "@nuxt/test-utils": "^3.14.0",
    "typescript": "^5.3.0",
    "vitest": "^1.0.0"
  }
}
_CLARITY_EOF_

cat > "$P/frontend/tsconfig.json" << '_CLARITY_EOF_'
{
  "extends": "./.nuxt/tsconfig.json"
}
_CLARITY_EOF_

cat > "$P/frontend/assets/css/tailwind.css" << '_CLARITY_EOF_'
@import "tailwindcss";
_CLARITY_EOF_

cat > "$P/frontend/composables/useApi.ts" << '_CLARITY_EOF_'
import { $fetch } from "ofetch"
import type { Project } from "~/types/project"
import type { QuestionResponse } from "~/types/questionnaire"

export function useApi() {
  async function getProject(projectId: string): Promise<Project> {
    const runtimeConfig = useRuntimeConfig()
    return await $fetch<Project>(`${runtimeConfig.public.apiBase}/project`, {
      method: 'get',
      query: { project_id: projectId, include_questionnaire: true },
    })
  }

  async function getProjects(userId: string): Promise<Project[]> {
    const runtimeConfig = useRuntimeConfig()
    let result = await $fetch<Project | Project[]>(`${runtimeConfig.public.apiBase}/project`, {
      method: 'get',
      query: { user_id: userId, include_questionnaire: false },
    })
    return Array.isArray(result) ? result : [result]
  }

  async function createProject(
    questionnaireId: number, userId: string,
    projectTitle: string, projectDescription: string,
    tags?: string[], attributes?: string[]
  ): Promise<Project> {
    const runtimeConfig = useRuntimeConfig()
    return await $fetch<Project>(`${runtimeConfig.public.apiBase}/project`, {
      method: 'post',
      body: { title: projectTitle, description: projectDescription, tags, attributes, user_id: userId, questionnaireId },
    })
  }

  async function saveAnswer(questionResponse: QuestionResponse): Promise<QuestionResponse> {
    const runtimeConfig = useRuntimeConfig()
    return await $fetch<QuestionResponse>(`${runtimeConfig.public.apiBase}/project/answer/create`, {
      method: 'post', body: questionResponse,
    })
  }

  async function doAssessment(projectId: string) {
    const runtimeConfig = useRuntimeConfig()
    return await $fetch(`${runtimeConfig.public.apiBase}/review/project/${projectId}`, { method: 'post' })
  }

  async function setQuestionnaireAnswer(projectId: string, questionId: string, answer: string) {
    const runtimeConfig = useRuntimeConfig()
    return await $fetch(`${runtimeConfig.public.apiBase}/review/project/${projectId}/question/${questionId}`, {
      method: 'post', body: { answer }, headers: { 'Content-Type': 'application/json' },
    })
  }

  return { createProject, getProject, getProjects, saveAnswer, doAssessment, setQuestionnaireAnswer }
}
_CLARITY_EOF_

cat > "$P/frontend/layouts/default.vue" << '_CLARITY_EOF_'
<template>
  <div class="min-h-screen">
    <nav class="border-b">
      <div class="container mx-auto flex items-center justify-between h-16 px-4">
        <NuxtLink to="/" class="text-xl font-bold">Clarity</NuxtLink>
      </div>
    </nav>
    <main>
      <slot />
    </main>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/layouts/topnav.vue" << '_CLARITY_EOF_'
<template>
  <div class="min-h-screen">
    <nav class="border-b">
      <div class="container mx-auto flex items-center justify-between h-16 px-4">
        <div class="flex items-center gap-8">
          <NuxtLink to="/" class="text-xl font-bold">Clarity</NuxtLink>
          <div class="flex items-center gap-4 text-sm">
            <NuxtLink to="/" class="hover:text-primary">Home</NuxtLink>
            <NuxtLink to="/docs" class="hover:text-primary">Docs</NuxtLink>
            <NuxtLink to="/examples" class="hover:text-primary">Examples</NuxtLink>
          </div>
        </div>
      </div>
    </nav>
    <main class="container mx-auto px-4">
      <slot />
    </main>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/pages/index.vue" << '_CLARITY_EOF_'
<script setup lang="ts">
const { loggedIn, user } = useUserSession()
</script>

<template>
  <div class="flex items-center justify-center min-h-[80vh]">
    <div class="text-center">
      <h1 class="text-4xl font-bold mb-4">Clarity</h1>
      <p class="text-lg text-muted-foreground mb-8">
        IRAMP/ATO Management System
      </p>
      <div v-if="loggedIn" class="space-y-4">
        <p class="text-sm">Welcome, {{ user?.name }}</p>
        <NuxtLink to="/clara" class="inline-block px-6 py-3 bg-primary text-primary-foreground rounded-md hover:bg-primary/90">
          Your IRAMP/ATOs
        </NuxtLink>
      </div>
      <div v-else>
        <NuxtLink to="/login" class="inline-block px-6 py-3 bg-primary text-primary-foreground rounded-md hover:bg-primary/90">
          Sign In
        </NuxtLink>
      </div>
    </div>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/pages/login.vue" << '_CLARITY_EOF_'
<script setup lang="ts">
definePageMeta({ layout: "default" })
</script>

<template>
  <div class="flex items-center justify-center min-h-[80vh]">
    <div class="text-center space-y-4">
      <h1 class="text-2xl font-bold">Sign In to Clarity</h1>
      <p class="text-muted-foreground">Use your RTX credentials to sign in via SSO.</p>
      <a href="/auth/keycloak" class="inline-block px-6 py-3 bg-primary text-primary-foreground rounded-md hover:bg-primary/90">
        Sign In with SSO
      </a>
    </div>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/pages/admin/index.vue" << '_CLARITY_EOF_'
<script setup lang="ts">
definePageMeta({ layout: "default" })
</script>

<template>
  <div class="container mx-auto py-8">
    <h1 class="text-2xl font-bold mb-4">Admin Dashboard</h1>
    <div class="space-y-4">
      <NuxtLink to="/admin/users" class="block p-4 border rounded-lg hover:bg-muted">
        <h2 class="font-semibold">User Management</h2>
        <p class="text-sm text-muted-foreground">Manage user roles and permissions</p>
      </NuxtLink>
    </div>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/pages/admin/users.vue" << '_CLARITY_EOF_'
<script setup lang="ts">
definePageMeta({ layout: "default" })
</script>

<template>
  <div class="container mx-auto py-8">
    <h1 class="text-2xl font-bold mb-4">User Management</h1>
    <p class="text-muted-foreground">User management features coming soon.</p>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/pages/clara/index.vue" << '_CLARITY_EOF_'
<script setup lang="ts">
import { toTypedSchema } from '@vee-validate/zod'
import { Check, Circle, Dot } from 'lucide-vue-next'
import { ref } from 'vue'
import * as z from 'zod'

definePageMeta({ layout: "topnav" })

const { createProject } = useApi()
const userSession = useUserSession()

const onSubmit = async (values: any) => {
  if (!userSession.user.value) return navigateTo("/")
  try {
    const project = await createProject(1, userSession.user.value?.sub, values.projectTitle, values.projectDescription, values.tags, [])
    return navigateTo(`/clara/${project.id}`)
  } catch (err) { console.error(err) }
}

interface IntakeStep { step: number; title: string; description: string }
interface AttributeItem { title: string; display: string }

const attributeItems: AttributeItem[] = [
  { title: "EAR", display: "The data my application works with falls under EAR classification" },
  { title: "ITAR", display: "The data my application works with falls under ITAR classification" },
  { title: "CUI", display: "My application handles CUI/CUI data" },
  { title: "Foreign National Access Required", display: "I will require foreign nationals to be able to access my application" },
  { title: "Cloud-Hosted", display: "I plan to host my application in a Cloud environment" },
  { title: "On-Prem", display: "I plan to host my application on-prem (RTX-managed hardware)" },
  { title: "Collins Internal Data", display: "The application will handle Collins-proprietary (internal) data" },
  { title: "Third-Party Data", display: "The application will handle external, third-party data" },
]

const formSchema = z.object({
  projectTitle: z.string().min(1, "Project title cannot be empty."),
  projectDescription: z.string().min(250, "Project description must be at least 250 characters long."),
}).and(z.object({
  selectedAttributes: z.array(z.string()).refine(value => value.some(item => item), { message: "You have to select at least one item." })
})).and(z.object({
  tags: z.array(z.string().min(1, "Tag value cannot be empty").max(30, "Tag values can be a maximum of 30 characters long")).max(15, "Can only add up to 15 tags")
}))

const stepIndex = ref(0)
const intakeSteps: IntakeStep[] = [
  { step: 1, title: "Project Details", description: "Tell us a little about your project." },
  { step: 2, title: "Attributes", description: "Choose which project attributes apply to your application." },
  { step: 3, title: "Tags", description: "Project metadata tags will help optimize your CLARA copilot." },
]
const initialValues = { projectTitle: "", projectDescription: "", selectedAttributes: [] as string[], tags: [] as string[] }

const buildReminderString = (curVal?: string): string => {
  if (curVal === undefined) return "250 more characters required"
  return `${Math.max(250 - curVal.length, 0)} more characters required`
}
</script>

<template>
  <div class="flex items-center justify-center py-8">
    <div class="w-full max-w-2xl">
      <h1 class="text-2xl font-bold text-center mb-6">Your IRAMP/ATOs
        <button class="ml-4 px-4 py-2 bg-gray-900 text-white text-sm rounded-md">+ Start a New IRAMP/ATO</button>
      </h1>

      <table class="w-full text-center mb-8">
        <thead><tr>
          <th class="py-2">Project ID</th>
          <th class="py-2">Title</th>
          <th class="py-2">Description</th>
        </tr></thead>
        <tbody>
          <tr><td colspan="3" class="py-4 text-muted-foreground">No IRAMP/ATOs to display</td></tr>
        </tbody>
      </table>

      <div class="border-t pt-8">
        <h2 class="text-xl font-semibold text-center mb-6">Create New IRAMP/ATO</h2>

        <Form v-slot="{ meta, values, validate }" :validation-schema="toTypedSchema(formSchema)" :initial-values="initialValues" keep-values as="">
          <Stepper v-slot="{ isNextDisabled, isPrevDisabled, nextStep, prevStep }" v-model="stepIndex" class="block w-full">
            <div class="flex w-full flex-start gap-2 mb-6">
              <StepperItem v-for="step in intakeSteps" :key="step.step" v-slot="{ state }" :step="step.step" class="relative flex w-full flex-col items-center justify-center">
                <StepperSeparator v-if="step.step !== intakeSteps[intakeSteps.length - 1].step" class="absolute left-[calc(50%+20px)] right-[calc(-50%+10px)] top-5 block h-0.5 shrink-0 rounded-full bg-muted group-data-[state=completed]:bg-primary" />
                <StepperTrigger as-child>
                  <Button :variant="state === 'completed' || state === 'active' ? 'default' : 'outline'" size="icon" class="z-10 rounded-full shrink-0" :class="[state === 'active' && 'ring-2 ring-ring ring-offset-2']" :disabled="state !== 'completed' && !meta.valid">
                    <Check v-if="state === 'completed'" class="size-5" />
                    <Circle v-if="state === 'active'" class="size-5" />
                    <Dot v-if="state === 'inactive'" />
                  </Button>
                </StepperTrigger>
                <div class="mt-5 flex flex-col items-center text-center">
                  <StepperTitle :class="[state === 'active' && 'text-primary']" class="text-sm font-semibold">{{ step.title }}</StepperTitle>
                  <StepperDescription :class="[state === 'active' && 'text-primary']" class="sr-only text-xs text-muted-foreground md:not-sr-only">{{ step.description }}</StepperDescription>
                </div>
              </StepperItem>
            </div>

            <div class="flex flex-col gap-4">
              <template v-if="stepIndex === 0">
                <FormField v-slot="{ componentField }" name="projectTitle">
                  <FormItem><FormLabel>Project Title</FormLabel><FormControl><Input type="text" v-bind="componentField" placeholder="Title" /></FormControl><FormMessage /></FormItem>
                </FormField>
                <FormField v-slot="{ componentField }" name="projectDescription">
                  <FormItem><FormLabel>Project Description</FormLabel><FormControl><Textarea rows="5" v-bind="componentField" placeholder="Please describe what you are trying to accomplish using natural language." /></FormControl>
                    <div class="text-primary text-xs text-right">{{ buildReminderString(componentField.modelValue as string) }}</div><FormMessage /></FormItem>
                </FormField>
              </template>

              <template v-if="stepIndex === 1">
                <FormField v-slot="{ value, handleChange }" name="selectedAttributes">
                  <FormItem><FormLabel class="text-base">Select all attributes that apply to your project/application.</FormLabel>
                    <div class="flex flex-col gap-2 mt-2">
                      <div v-for="attr in attributeItems" :key="attr.title" class="flex items-start gap-3">
                        <FormControl><Checkbox :model-value="value.includes(attr.title)" @update:model-value="(checked: boolean) => { checked && !value.includes(attr.title) ? handleChange([...value, attr.title]) : handleChange(value.filter((v: string) => v !== attr.title)) }" /></FormControl>
                        <FormLabel>{{ attr.display }}</FormLabel>
                      </div>
                    </div><FormMessage /></FormItem>
                </FormField>
              </template>

              <template v-if="stepIndex === 2">
                <FormField v-slot="{ componentField }" name="tags">
                  <FormItem><FormLabel>Metadata Tags</FormLabel><FormControl>
                    <TagsInput :model-value="componentField.modelValue" @update:model-value="componentField['onUpdate:modelValue']">
                      <TagsInputItem v-for="item in componentField.modelValue" :key="item" :value="item"><TagsInputItemText /><TagsInputItemDelete /></TagsInputItem>
                      <TagsInputInput placeholder="Type Tag (e.g. 'Life', 'RUN') and Press 'Enter'" />
                    </TagsInput></FormControl>
                    <FormDescription>Add metadata tags to your project description. This will help optimize Clarity's performance.</FormDescription><FormMessage /></FormItem>
                </FormField>
              </template>
            </div>

            <div class="flex items-center justify-between mt-4">
              <Button :disabled="isPrevDisabled" variant="outline" size="sm" @click="prevStep()">Back</Button>
              <div class="flex items-center gap-3">
                <Button v-if="stepIndex !== intakeSteps.length - 1" :type="meta.valid ? 'button' : 'submit'" :disabled="!meta.valid" size="sm" @click="nextStep()">Next</Button>
                <Button v-if="stepIndex === intakeSteps.length - 1" size="sm" type="submit" @click="onSubmit(values)">Submit</Button>
              </div>
            </div>
          </Stepper>
        </Form>
      </div>
    </div>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/pages/clara/[projectId].vue" << '_CLARITY_EOF_'
<script setup lang="ts">
/**
 * Questionnaire flow page — displays questions from the questionnaire DAG
 * and allows users to answer them one at a time.
 */
const route = useRoute()
const projectId = route.params.projectId as string
const { getProject, saveAnswer } = useApi()

const project = ref<any>(null)
const currentPhaseIdx = ref(0)
const currentQuestionIdx = ref(0)
const userAnswer = ref("")
const selectedOptions = ref<string[]>([])
const loading = ref(true)

onMounted(async () => {
  try {
    project.value = await getProject(projectId)
  } catch (e) {
    console.error("Failed to load project:", e)
  } finally {
    loading.value = false
  }
})

const phases = computed(() => project.value?.graph?.phases || [])
const currentPhase = computed(() => phases.value[currentPhaseIdx.value])
const questions = computed(() => currentPhase.value?.nodes || [])
const currentQuestion = computed(() => questions.value[currentQuestionIdx.value])

const isTextQuestion = computed(() =>
  currentQuestion.value?.type === "text" || currentQuestion.value?.type === "Text"
)
const isSingleSelect = computed(() =>
  currentQuestion.value?.type === "choose-one" ||
  currentQuestion.value?.type === "MultiChoice - single select" ||
  currentQuestion.value?.type === "yes-no"
)
const isMultiSelect = computed(() =>
  currentQuestion.value?.type === "choose-many" ||
  currentQuestion.value?.type === "MultiChoice - multiple select"
)

const existingAnswer = computed(() => {
  if (!project.value?.responses || !currentQuestion.value) return null
  return project.value.responses.find(
    (r: any) => r.questionId === currentQuestion.value.id || r.question_id === currentQuestion.value.id
  )
})

watch(currentQuestion, () => {
  if (existingAnswer.value) {
    const ans = existingAnswer.value.value || existingAnswer.value.answer
    if (Array.isArray(ans)) {
      selectedOptions.value = ans
      userAnswer.value = ""
    } else {
      userAnswer.value = ans || ""
      selectedOptions.value = []
    }
  } else {
    userAnswer.value = ""
    selectedOptions.value = []
  }
})

async function submitAnswer() {
  if (!currentQuestion.value) return

  const answer = isMultiSelect.value ? selectedOptions.value :
    isSingleSelect.value ? userAnswer.value : userAnswer.value

  try {
    await saveAnswer({
      questionId: currentQuestion.value.id,
      value: answer,
      submittedAt: new Date().toISOString(),
      justification: undefined,
    })
    // Advance to next question
    if (currentQuestionIdx.value < questions.value.length - 1) {
      currentQuestionIdx.value++
    } else {
      // TODO: handle phase completion / project completion
    }
  } catch (e) {
    console.error("Failed to save answer:", e)
  }
}

function goBack() {
  if (currentQuestionIdx.value > 0) {
    currentQuestionIdx.value--
  }
}
</script>

<template>
  <div class="max-w-3xl mx-auto py-8">
    <div v-if="loading" class="text-center py-16">
      <p class="text-muted-foreground">Loading project...</p>
    </div>

    <div v-else-if="!project" class="text-center py-16">
      <p class="text-destructive">Project not found.</p>
      <NuxtLink to="/clara" class="text-primary underline mt-2 inline-block">Back to projects</NuxtLink>
    </div>

    <template v-else>
      <div class="mb-6">
        <h1 class="text-2xl font-bold">{{ project.title }}</h1>
        <p class="text-sm text-muted-foreground mt-1">{{ currentPhase?.title }}</p>
      </div>

      <div v-if="currentQuestion" class="border rounded-lg p-6 space-y-4">
        <div>
          <h2 class="text-lg font-semibold">{{ currentQuestion.title }}</h2>
          <p class="text-sm text-muted-foreground mt-1">{{ currentQuestion.text }}</p>
        </div>

        <!-- Text input -->
        <div v-if="isTextQuestion">
          <textarea
            v-model="userAnswer"
            rows="4"
            class="w-full border rounded-md p-3 text-sm"
            placeholder="Type your answer here..."
          />
        </div>

        <!-- Single select (radio-style) -->
        <div v-else-if="isSingleSelect" class="space-y-2">
          <label
            v-for="opt in (currentQuestion.options || [])"
            :key="opt"
            class="flex items-center gap-2 p-2 border rounded-md cursor-pointer hover:bg-muted"
            :class="{ 'border-primary bg-primary/5': userAnswer === opt }"
          >
            <input type="radio" :value="opt" v-model="userAnswer" class="accent-primary" />
            <span class="text-sm">{{ opt }}</span>
          </label>
        </div>

        <!-- Multi select (checkbox-style) -->
        <div v-else-if="isMultiSelect" class="space-y-2">
          <label
            v-for="opt in (currentQuestion.options || [])"
            :key="opt"
            class="flex items-center gap-2 p-2 border rounded-md cursor-pointer hover:bg-muted"
            :class="{ 'border-primary bg-primary/5': selectedOptions.includes(opt) }"
          >
            <input type="checkbox" :value="opt" v-model="selectedOptions" class="accent-primary" />
            <span class="text-sm">{{ opt }}</span>
          </label>
        </div>

        <!-- Navigation -->
        <div class="flex justify-between pt-4 border-t">
          <button
            @click="goBack"
            :disabled="currentQuestionIdx === 0"
            class="px-4 py-2 text-sm border rounded-md disabled:opacity-50"
          >
            Back
          </button>
          <div class="flex items-center gap-2">
            <span class="text-xs text-muted-foreground">
              {{ currentQuestionIdx + 1 }} / {{ questions.length }}
            </span>
            <button
              @click="submitAnswer"
              class="px-4 py-2 text-sm bg-primary text-primary-foreground rounded-md hover:bg-primary/90"
            >
              {{ currentQuestionIdx === questions.length - 1 ? 'Complete' : 'Next' }}
            </button>
          </div>
        </div>
      </div>

      <div v-else class="text-center py-16">
        <p class="text-lg font-semibold">All questions completed!</p>
        <NuxtLink to="/clara" class="text-primary underline mt-2 inline-block">Back to projects</NuxtLink>
      </div>
    </template>
  </div>
</template>
_CLARITY_EOF_

cat > "$P/frontend/types/project.ts" << '_CLARITY_EOF_'
import type { QuestionResponse } from "./questionnaire"

export interface Project {
  id: string
  title: string
  description: string
  tags: string[]
  userId: string
  questionnaireId: number
  created: string
  updated: string
  responses: QuestionResponse[]
  attributes: Attribute[]
  graph?: Questionnaire
}

export interface Attribute {
  id?: number
  text: string
}

export interface Questionnaire {
  id: number
  version?: string
  active: boolean
  phases: Phase[]
}
_CLARITY_EOF_

cat > "$P/frontend/types/questionnaire.ts" << '_CLARITY_EOF_'
export interface Phase {
  title: string
  description?: string
  nodes: Question[]
  edges: FlowEdge[]
}

export interface Question {
  id: string
  title: string
  text: string
  description?: string
  type: "text" | "choose-one" | "choose-many" | "key-value-table"
  columns?: KVColumn[]
  subphase?: string
  options?: string[]
  justificationRequired: boolean
  review: boolean
}

export interface FlowEdge {
  operator?: "EQUALS" | "IN" | "NOT-IN" | "NE"
  criteria?: string | string[]
  sourceId: string
  targetId: string
}

export interface KVColumn {
  col_id: string
  name: string
  schema_key?: string
  required: boolean
  dtype: "text" | "float" | "int" | "select"
  options?: string[]
}

export interface QuestionResponse {
  questionId: string
  value: string | string[] | KeyValueTableResponse
  submittedAt: string
  justification?: string
}

export interface KeyValueTableResponse {
  rows: KVRow[]
}

export interface KVRow {
  entry: KVCellValue[]
}

export interface KVCellValue {
  col_id: string
  value: string | number | null
}

export type Operator = "EQUALS" | "IN" | "NOT-IN" | "NE"
_CLARITY_EOF_

cat > "$P/frontend/types/completion.ts" << '_CLARITY_EOF_'
export interface Message {
  role: "user" | "assistant" | "generate-request"
  content: string
  done?: boolean
}
_CLARITY_EOF_

cat > "$P/frontend/types/review.ts" << '_CLARITY_EOF_'
export interface PassFail {
  questionId: string
  result: "pass" | "fail"
  reason?: string
}

export interface ReviewFail {
  questionId: string
  severity: "low" | "medium" | "high"
  message: string
}
_CLARITY_EOF_

echo "Creating .sh scripts (Git Bash / Linux)..."

cat > "$P/start-backend.sh" << '_SH_EOF_'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Starting Clarity backend..."
if [ ! -d "$ROOT/backend/.venv" ]; then
  echo "  Creating Python venv..."
  python3 -m venv "$ROOT/backend/.venv" 2>/dev/null || python -m venv "$ROOT/backend/.venv"
fi
source "$ROOT/backend/.venv/bin/activate" 2>/dev/null || source "$ROOT/backend/.venv/Scripts/activate"
pip install -r "$ROOT/backend/requirements.txt" --quiet 2>/dev/null
cd "$ROOT/backend"
export CLARITY_SQL_HOST=localhost
export CLARITY_SQL_PORT=5432
export CLARITY_SQL_DB=clarity
export CLARITY_SQL_USER=clarity
export CLARITY_SQL_PASSWORD=clarity
export CLARITY_KC_REALM=clarity
export CLARITY_KC_MGMT_CLIENT_SECRET=""
export COMP_OIDC_CLIENT_ID=clarity-app
export COMP_OIDC_CLIENT_SECRET=""
export META_OPENAI_URL=""
export META_OPENAI_KEY=""
export ARCHER_USERNAME=""
export ARCHER_PASSWORD=""
export ARCHER_INSTANCE_NAME="ArcherRTX PROD"
export ARCHER_BASE_URI="https://archergrc.corp.ray.com"
export ARCHER_SOAP_SEARCH_URI=""
export ARCHER_SOAP_GENERAL_URI=""
export MAPPING_REPORT=""
export SEED_DATA=true
echo "  Backend starting on http://localhost:4000"
echo "  API docs at http://localhost:4000/docs"
uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload
_SH_EOF_
chmod +x "$P/start-backend.sh"

cat > "$P/start-frontend.sh" << '_SH_EOF_'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Starting Clarity frontend..."
cd "$ROOT/frontend"
if [ ! -d node_modules ]; then
  echo "  Installing npm dependencies..."
  npm install --silent 2>/dev/null
fi
export NUXT_API_BASE=http://localhost:4000
echo "  Frontend starting on http://localhost:3001"
npm run dev
_SH_EOF_
chmod +x "$P/start-frontend.sh"

cat > "$P/start-docker.sh" << '_SH_EOF_'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Starting PostgreSQL + Keycloak..."
cd "$ROOT" && docker compose up -d db keycloak
echo "  Waiting for PostgreSQL..."
for i in $(seq 1 30); do
  docker exec clarity-db pg_isready -U clarity 2>/dev/null | grep -q "accepting" && echo "  PostgreSQL ready" && break
  sleep 2
done
echo "  Waiting for Keycloak (~30s)..."
sleep 15
for i in $(seq 1 20); do
  curl -sf http://localhost:8080/kc/health/ready >/dev/null 2>&1 && echo "  Keycloak ready" && break
  sleep 3
done
echo ""
echo "  PostgreSQL: localhost:5432"
echo "  Keycloak:   http://localhost:8080/kc/admin (admin/admin)"
echo ""
_SH_EOF_
chmod +x "$P/start-docker.sh"

cat > "$P/start-all.sh" << '_SH_EOF_'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "============================================="
echo "  Starting all Clarity services..."
echo "============================================="
"$ROOT/start-docker.sh"
"$ROOT/start-backend.sh" &
BPID=$!; sleep 3
"$ROOT/start-frontend.sh" &
FPID=$!
echo ""
echo "============================================="
echo "  Clarity is running!"
echo "============================================="
echo "  Frontend: http://localhost:3001"
echo "  Backend:  http://localhost:4000/docs"
echo "  Keycloak: http://localhost:8080/kc/admin"
echo "  Ctrl+C to stop all."
echo ""
trap "kill $BPID $FPID 2>/dev/null; cd $ROOT && docker compose stop" EXIT INT TERM
wait
_SH_EOF_
chmod +x "$P/start-all.sh"

echo "Creating .bat scripts (Windows CMD)..."

cat > "$P/start-backend.bat" << '_BAT_EOF_'
@echo off
echo Starting Clarity backend...
cd /d "%~dp0backend"
if not exist .venv (
  echo   Creating Python venv...
  python -m venv .venv
)
call .venv\Scripts\activate.bat
pip install -r requirements.txt --quiet 2>nul
set CLARITY_SQL_HOST=localhost
set CLARITY_SQL_PORT=5432
set CLARITY_SQL_DB=clarity
set CLARITY_SQL_USER=clarity
set CLARITY_SQL_PASSWORD=clarity
set CLARITY_KC_REALM=clarity
set CLARITY_KC_MGMT_CLIENT_SECRET=
set COMP_OIDC_CLIENT_ID=clarity-app
set COMP_OIDC_CLIENT_SECRET=
set META_OPENAI_URL=
set META_OPENAI_KEY=
set ARCHER_USERNAME=
set ARCHER_PASSWORD=
set ARCHER_INSTANCE_NAME=ArcherRTX PROD
set ARCHER_BASE_URI=https://archergrc.corp.ray.com
set ARCHER_SOAP_SEARCH_URI=
set ARCHER_SOAP_GENERAL_URI=
set MAPPING_REPORT=
set SEED_DATA=true
echo   Backend starting on http://localhost:4000
echo   API docs at http://localhost:4000/docs
uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload
_BAT_EOF_

cat > "$P/start-frontend.bat" << '_BAT_EOF_'
@echo off
echo Starting Clarity frontend...
cd /d "%~dp0frontend"
if not exist node_modules (
  echo   Installing npm dependencies...
  npm install
)
set NUXT_API_BASE=http://localhost:4000
echo   Frontend starting on http://localhost:3001
npm run dev
_BAT_EOF_

cat > "$P/start-docker.bat" << '_BAT_EOF_'
@echo off
echo Starting PostgreSQL + Keycloak...
cd /d "%~dp0"
docker compose up -d db keycloak
echo   Waiting for services to start (~30s)...
timeout /t 30 /nobreak >nul
echo.
echo   PostgreSQL: localhost:5432
echo   Keycloak:   http://localhost:8080/kc/admin (admin/admin)
echo.
_BAT_EOF_

echo "Creating .ps1 scripts (PowerShell)..."

cat > "$P/start-backend.ps1" << '_PS1_EOF_'
# Clarity Backend - PowerShell
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Starting Clarity backend..." -ForegroundColor Cyan

$backendDir = Join-Path $root "backend"
$venvDir = Join-Path $backendDir ".venv"

if (-not (Test-Path $venvDir)) {
    Write-Host "  Creating Python venv..." -ForegroundColor Gray
    python -m venv $venvDir
}

& (Join-Path $venvDir "Scripts" "Activate.ps1")
pip install -r (Join-Path $backendDir "requirements.txt") --quiet 2>&1 | Out-Null

Set-Location $backendDir
$env:CLARITY_SQL_HOST = "localhost"
$env:CLARITY_SQL_PORT = "5432"
$env:CLARITY_SQL_DB = "clarity"
$env:CLARITY_SQL_USER = "clarity"
$env:CLARITY_SQL_PASSWORD = "clarity"
$env:CLARITY_KC_REALM = "clarity"
$env:CLARITY_KC_MGMT_CLIENT_SECRET = ""
$env:COMP_OIDC_CLIENT_ID = "clarity-app"
$env:COMP_OIDC_CLIENT_SECRET = ""
$env:META_OPENAI_URL = ""
$env:META_OPENAI_KEY = ""
$env:ARCHER_USERNAME = ""
$env:ARCHER_PASSWORD = ""
$env:ARCHER_INSTANCE_NAME = "ArcherRTX PROD"
$env:ARCHER_BASE_URI = "https://archergrc.corp.ray.com"
$env:ARCHER_SOAP_SEARCH_URI = ""
$env:ARCHER_SOAP_GENERAL_URI = ""
$env:MAPPING_REPORT = ""
$env:SEED_DATA = "true"

Write-Host "  Backend starting on http://localhost:4000" -ForegroundColor Green
Write-Host "  API docs at http://localhost:4000/docs" -ForegroundColor Green
uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload
_PS1_EOF_

cat > "$P/start-frontend.ps1" << '_PS1_EOF_'
# Clarity Frontend - PowerShell
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Starting Clarity frontend..." -ForegroundColor Cyan

$frontendDir = Join-Path $root "frontend"
Set-Location $frontendDir

if (-not (Test-Path (Join-Path $frontendDir "node_modules"))) {
    Write-Host "  Installing npm dependencies..." -ForegroundColor Gray
    npm install --silent 2>&1 | Out-Null
}

$env:NUXT_API_BASE = "http://localhost:4000"
Write-Host "  Frontend starting on http://localhost:3001" -ForegroundColor Green
npm run dev
_PS1_EOF_

cat > "$P/start-docker.ps1" << '_PS1_EOF_'
# Clarity Docker Services - PowerShell
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Starting PostgreSQL + Keycloak..." -ForegroundColor Cyan

Set-Location $root
docker compose up -d db keycloak

Write-Host "  Waiting for PostgreSQL..." -ForegroundColor Gray
for ($i = 0; $i -lt 30; $i++) {
    $r = docker exec clarity-db pg_isready -U clarity 2>&1
    if ($r -match "accepting") { Write-Host "  PostgreSQL ready" -ForegroundColor Green; break }
    Start-Sleep 2
}

Write-Host "  Waiting for Keycloak (~30s)..." -ForegroundColor Gray
Start-Sleep 15
for ($i = 0; $i -lt 20; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:8080/kc/health/ready" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
        if ($resp.StatusCode -eq 200) { Write-Host "  Keycloak ready" -ForegroundColor Green; break }
    } catch {}
    Start-Sleep 3
}

Write-Host ""
Write-Host "  PostgreSQL: localhost:5432" -ForegroundColor Gray
Write-Host "  Keycloak:   http://localhost:8080/kc/admin (admin/admin)" -ForegroundColor Gray
Write-Host ""
_PS1_EOF_

echo ""
echo "============================================="
echo "  Setup Complete! Full project created."
echo "============================================="
echo ""
echo "  Scripts created in clarity-rewrite/:"
echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │ Git Bash / Linux (.sh)                             │"
echo "  │   ./start-docker.sh      Start PostgreSQL+Keycloak │"
echo "  │   ./start-backend.sh     Start FastAPI backend     │"
echo "  │   ./start-frontend.sh    Start Nuxt frontend       │"
echo "  │   ./start-all.sh         Start everything at once  │"
echo "  ├─────────────────────────────────────────────────────┤"
echo "  │ Windows CMD (.bat)                                 │"
echo "  │   start-docker.bat       Start PostgreSQL+Keycloak │"
echo "  │   start-backend.bat      Start FastAPI backend     │"
echo "  │   start-frontend.bat     Start Nuxt frontend       │"
echo "  ├─────────────────────────────────────────────────────┤"
echo "  │ PowerShell (.ps1)                                  │"
echo "  │   .\\start-docker.ps1     Start PostgreSQL+Keycloak │"
echo "  │   .\\start-backend.ps1    Start FastAPI backend     │"
echo "  │   .\\start-frontend.ps1   Start Nuxt frontend       │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""
echo "  Step 1: Start Docker    (any of the docker scripts)"
echo "  Step 2: Start Backend   (new terminal)"
echo "  Step 3: Start Frontend  (new terminal)"
echo ""
echo "  Frontend: http://localhost:3001"
echo "  API Docs: http://localhost:4000/docs"
echo "  Keycloak: http://localhost:8080/kc/admin (admin/admin)"
echo ""
