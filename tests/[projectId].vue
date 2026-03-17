<template>
  <div class="flex min-h-[calc(100vh-60px)]">
    <!-- Left Sidebar -->
    <aside class="w-72 bg-white border-r border-gray-200 flex-shrink-0">
      <div class="p-5 border-b border-gray-200">
        <h3 class="font-bold text-gray-900 text-sm truncate">{{ project?.title || 'Loading...' }}</h3>
        <div class="mt-2 flex items-center gap-2">
          <span class="text-xs bg-gray-100 text-gray-600 px-2 py-0.5 rounded-full">SAP Intake</span>
          <button
            @click="expandSidebar = !expandSidebar"
            class="text-xs text-gray-400 hover:text-gray-600 ml-auto"
          >
            {{ expandSidebar ? '▾' : '▸' }}
          </button>
        </div>
      </div>

      <nav v-if="expandSidebar" class="py-2">
        <button
          v-for="(q, idx) in questions"
          :key="q.id"
          @click="goToQuestion(idx)"
          class="w-full text-left px-5 py-2.5 text-sm flex items-center gap-3 transition-colors"
          :class="idx === currentIndex
            ? 'bg-red-50 text-red-900 border-r-2 border-red-800'
            : 'text-gray-600 hover:bg-gray-50'"
        >
          <span
            class="w-2 h-2 rounded-full flex-shrink-0"
            :class="getQuestionStatus(q.id) === 'answered' ? 'bg-green-500' : getQuestionStatus(q.id) === 'current' ? 'bg-red-800' : 'bg-gray-300'"
          ></span>
          <span class="truncate">Q{{ idx + 1 }} {{ q.title }}</span>
        </button>

        <!-- Review link -->
        <button
          @click="goToReview"
          class="w-full text-left px-5 py-2.5 text-sm flex items-center gap-3 transition-colors"
          :class="showReview
            ? 'bg-red-50 text-red-900 border-r-2 border-red-800'
            : 'text-gray-600 hover:bg-gray-50'"
        >
          <span class="w-2 h-2 rounded-full flex-shrink-0 bg-gray-300"></span>
          <span>Review</span>
        </button>
      </nav>
    </aside>

    <!-- Main Content -->
    <div class="flex-1 flex flex-col">
      <!-- Breadcrumb -->
      <div class="px-8 py-3 border-b border-gray-200 bg-white">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2 text-xs text-gray-400">
            <span>{{ project?.title }}</span>
            <span>›</span>
            <span v-if="!showReview">{{ currentQuestion?.subphase }}</span>
            <span v-if="!showReview">›</span>
            <span class="text-gray-600" v-if="!showReview">Q{{ currentIndex + 1 }} {{ currentQuestion?.title }}</span>
            <span class="text-gray-600" v-else>Review</span>
          </div>
          <span class="text-xs text-red-800 font-medium">RTX Proprietary - No Technical Data Permitted</span>
        </div>
      </div>

      <!-- Question View -->
      <div v-if="!showReview" class="flex-1 px-8 py-8 max-w-3xl">
        <div v-if="currentQuestion">
          <!-- Question Header -->
          <h2 class="text-xl font-bold text-gray-900 mb-2">Q{{ currentIndex + 1 }} {{ currentQuestion.title }}</h2>
          <p class="text-sm text-gray-500 mb-6">{{ currentQuestion.text }}</p>

          <!-- Text Input -->
          <div v-if="currentQuestion.type === 'text'">
            <textarea
              v-model="currentAnswer"
              rows="5"
              placeholder="Enter your response..."
              class="w-full border border-gray-300 rounded-md px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-red-800 focus:border-transparent resize-none"
            ></textarea>
          </div>

          <!-- Choose One -->
          <div v-if="currentQuestion.type === 'choose-one'" class="space-y-2">
            <label
              v-for="opt in currentQuestion.options"
              :key="opt"
              class="flex items-center gap-3 p-3 rounded-md border border-gray-200 hover:border-gray-300 cursor-pointer transition-colors"
              :class="currentAnswer === opt ? 'border-red-800 bg-red-50' : ''"
            >
              <input
                type="radio"
                :value="opt"
                v-model="currentAnswer"
                class="h-4 w-4 text-red-800 focus:ring-red-800 border-gray-300"
              />
              <span class="text-sm text-gray-700">{{ opt }}</span>
            </label>
          </div>

          <!-- Choose Many -->
          <div v-if="currentQuestion.type === 'choose-many'" class="space-y-2">
            <label
              v-for="opt in currentQuestion.options"
              :key="opt"
              class="flex items-center gap-3 p-3 rounded-md border border-gray-200 hover:border-gray-300 cursor-pointer transition-colors"
              :class="(currentAnswerMulti || []).includes(opt) ? 'border-red-800 bg-red-50' : ''"
            >
              <input
                type="checkbox"
                :value="opt"
                v-model="currentAnswerMulti"
                class="h-4 w-4 rounded text-red-800 focus:ring-red-800 border-gray-300"
              />
              <span class="text-sm text-gray-700">{{ opt }}</span>
            </label>
          </div>
        </div>

        <!-- Navigation -->
        <div class="flex items-center justify-between mt-8 pt-6 border-t border-gray-200">
          <button
            @click="prevQuestion"
            :disabled="currentIndex === 0"
            class="text-sm text-gray-500 hover:text-gray-700 transition-colors disabled:opacity-30 disabled:cursor-not-allowed flex items-center gap-1"
          >
            ← Previous
          </button>
          <div class="flex items-center gap-3">
            <button
              @click="goToReview"
              class="border border-gray-300 text-gray-600 px-4 py-2 rounded-md text-sm hover:bg-gray-50 transition-colors"
            >
              Review Answers
            </button>
            <button
              v-if="currentIndex < questions.length - 1"
              @click="nextQuestion"
              class="bg-red-800 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-red-900 transition-colors"
            >
              Next →
            </button>
            <button
              v-else
              @click="goToReview"
              class="bg-red-800 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-red-900 transition-colors"
            >
              Finish →
            </button>
          </div>
        </div>
      </div>

      <!-- Review View -->
      <div v-else class="flex-1 px-8 py-8">
        <div class="text-center mb-8">
          <h2 class="text-xl font-bold text-gray-900 mb-1">IRAMP/ATO Questionnaire Complete</h2>
          <p class="text-sm text-gray-500">Here are the next steps.</p>
          <div class="flex items-center justify-center gap-3 mt-4">
            <button
              @click="showReview = false; currentIndex = 0"
              class="border border-gray-300 text-gray-600 px-4 py-2 rounded-md text-sm hover:bg-gray-50 transition-colors"
            >
              Review Answered Questions
            </button>
            <button
              @click="submitForReview"
              class="bg-red-800 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-red-900 transition-colors"
            >
              Submit for Review
            </button>
          </div>
        </div>

        <!-- Review Table -->
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
          <table class="w-full">
            <thead>
              <tr class="border-b border-gray-200 bg-gray-50">
                <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Title</th>
                <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Overview</th>
                <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Subphase</th>
                <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Status</th>
                <th class="text-left px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(q, idx) in questions"
                :key="q.id"
                class="border-b border-gray-100"
              >
                <td class="px-6 py-3 text-sm text-gray-900">Q{{ idx + 1 }} {{ q.title }}</td>
                <td class="px-6 py-3 text-sm text-gray-500">SAP Intake</td>
                <td class="px-6 py-3 text-sm text-gray-500">{{ q.subphase }}</td>
                <td class="px-6 py-3">
                  <span
                    class="w-2.5 h-2.5 rounded-full inline-block"
                    :class="responses[q.id] ? 'bg-green-500' : 'bg-gray-300'"
                  ></span>
                </td>
                <td class="px-6 py-3">
                  <button
                    @click="showReview = false; currentIndex = idx"
                    class="text-xs text-red-700 hover:text-red-900 font-medium"
                  >
                    Edit →
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
const route = useRoute()
const { getProject, saveAnswer } = useApi()

const projectId = route.params.projectId as string
const project = ref<any>(null)
const questions = ref<any[]>([])
const responses = reactive<Record<string, any>>({})
const currentIndex = ref(0)
const currentAnswer = ref('')
const currentAnswerMulti = ref<string[]>([])
const showReview = ref(false)
const expandSidebar = ref(true)

const currentQuestion = computed(() => questions.value[currentIndex.value])

function getQuestionStatus(questionId: string) {
  if (questions.value[currentIndex.value]?.id === questionId && !showReview.value) return 'current'
  if (responses[questionId]) return 'answered'
  return 'unanswered'
}

function saveCurrentAnswer() {
  if (!currentQuestion.value) return
  const qId = currentQuestion.value.id

  if (currentQuestion.value.type === 'choose-many') {
    if (currentAnswerMulti.value.length > 0) {
      responses[qId] = [...currentAnswerMulti.value]
    }
  } else {
    if (currentAnswer.value) {
      responses[qId] = currentAnswer.value
    }
  }

  // Persist to backend
  const answer = currentQuestion.value.type === 'choose-many'
    ? currentAnswerMulti.value
    : currentAnswer.value

  if (answer && (Array.isArray(answer) ? answer.length > 0 : answer.trim())) {
    saveAnswer({
      project_id: projectId,
      question_id: qId,
      value: answer,
      submitted_at: new Date().toISOString(),
      justification: null,
    }).catch(e => console.error('Failed to save answer:', e))
  }
}

function loadAnswerForQuestion(idx: number) {
  const q = questions.value[idx]
  if (!q) return

  const saved = responses[q.id]
  if (q.type === 'choose-many') {
    currentAnswerMulti.value = Array.isArray(saved) ? [...saved] : []
    currentAnswer.value = ''
  } else {
    currentAnswer.value = saved || ''
    currentAnswerMulti.value = []
  }
}

function nextQuestion() {
  saveCurrentAnswer()
  if (currentIndex.value < questions.value.length - 1) {
    currentIndex.value++
    loadAnswerForQuestion(currentIndex.value)
  }
}

function prevQuestion() {
  saveCurrentAnswer()
  if (currentIndex.value > 0) {
    currentIndex.value--
    loadAnswerForQuestion(currentIndex.value)
  }
}

function goToQuestion(idx: number) {
  saveCurrentAnswer()
  currentIndex.value = idx
  showReview.value = false
  loadAnswerForQuestion(idx)
}

function goToReview() {
  saveCurrentAnswer()
  showReview.value = true
}

function submitForReview() {
  alert('Submit for review — this will send to Archer GRC once connected.')
}

async function loadProject() {
  try {
    const data = await getProject(projectId)
    project.value = data

    // Extract questions from the questionnaire
    const questionnaire = data?.graph || data?.questionnaire
    if (questionnaire?.phases) {
      const phases = typeof questionnaire.phases === 'string'
        ? JSON.parse(questionnaire.phases)
        : questionnaire.phases

      const allQuestions: any[] = []
      for (const phase of phases) {
        if (phase.nodes) {
          allQuestions.push(...phase.nodes)
        } else if (phase.questions) {
          allQuestions.push(...phase.questions)
        }
      }
      questions.value = allQuestions

      // Load existing responses
      const existingResponses = data.responses || data.responses_json || []
      const respArray = typeof existingResponses === 'string'
        ? JSON.parse(existingResponses)
        : existingResponses
      for (const r of respArray) {
        const qId = r.questionId || r.question_id
        responses[qId] = r.value || r.answer
      }

      loadAnswerForQuestion(0)
    }
  } catch (e) {
    console.error('Failed to load project:', e)
  }
}

onMounted(() => loadProject())
</script>
