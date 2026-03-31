<template>
  <div>
    <!-- Toggle Button -->
    <button
      @click="isOpen = !isOpen"
      class="fixed bottom-6 right-6 z-50 bg-red-700 hover:bg-red-800 text-white rounded-full p-3 shadow-lg transition-all duration-200"
      :class="{ 'opacity-0 pointer-events-none': isOpen }"
    >
      <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z" />
      </svg>
    </button>

    <!-- Sidebar Overlay -->
    <div
      v-if="isOpen"
      @click="isOpen = false"
      class="fixed inset-0 bg-black/20 z-40 transition-opacity"
    />

    <!-- Sidebar Panel -->
    <div
      class="fixed top-0 right-0 h-full w-96 bg-white shadow-2xl z-50 transform transition-transform duration-300 flex flex-col"
      :class="isOpen ? 'translate-x-0' : 'translate-x-full'"
    >
      <!-- Header -->
      <div class="bg-gray-900 text-white px-4 py-3 flex items-center justify-between shrink-0">
        <div class="flex items-center gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 3.104v5.714a2.25 2.25 0 01-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 014.5 0m0 0v5.714a2.25 2.25 0 00.659 1.591L19 14.5M14.25 3.104c.251.023.501.05.75.082M19 14.5l-2.47 2.47a2.25 2.25 0 00-.659 1.591v2.927" />
          </svg>
          <span class="font-semibold text-sm">Clarity AI Copilot</span>
          <span
            class="ml-1 w-2 h-2 rounded-full"
            :class="aiStatus === 'available' ? 'bg-green-400' : 'bg-yellow-400'"
          />
        </div>
        <button @click="isOpen = false" class="text-gray-400 hover:text-white transition-colors">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>

      <!-- Messages -->
      <div ref="messagesContainer" class="flex-1 overflow-y-auto p-4 space-y-4">
        <!-- Welcome message -->
        <div v-if="messages.length === 0" class="text-center py-8">
          <div class="text-4xl mb-3">🤖</div>
          <h3 class="font-semibold text-gray-900 mb-1">Clarity AI Copilot</h3>
          <p class="text-sm text-gray-500 mb-4">
            Ask me about IRAMP/ATO requirements, compliance questions, or anything about your project.
          </p>
          <div class="space-y-2">
            <button
              v-for="suggestion in suggestions"
              :key="suggestion"
              @click="sendMessage(suggestion)"
              class="block w-full text-left text-sm px-3 py-2 bg-gray-50 hover:bg-gray-100 rounded-lg text-gray-700 transition-colors"
            >
              {{ suggestion }}
            </button>
          </div>
        </div>

        <!-- Chat messages -->
        <div
          v-for="(msg, index) in messages"
          :key="index"
          class="flex"
          :class="msg.role === 'user' ? 'justify-end' : 'justify-start'"
        >
          <div
            class="max-w-[80%] rounded-lg px-3 py-2 text-sm"
            :class="msg.role === 'user'
              ? 'bg-red-700 text-white'
              : 'bg-gray-100 text-gray-900'"
          >
            <div class="whitespace-pre-wrap">{{ msg.content }}</div>
            <div
              v-if="msg.source"
              class="mt-1 text-xs opacity-60"
            >
              via {{ msg.source }}
            </div>
          </div>
        </div>

        <!-- Loading indicator -->
        <div v-if="isLoading" class="flex justify-start">
          <div class="bg-gray-100 rounded-lg px-3 py-2">
            <div class="flex items-center gap-1">
              <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0ms" />
              <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 150ms" />
              <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 300ms" />
            </div>
          </div>
        </div>
      </div>

      <!-- Input -->
      <div class="border-t border-gray-200 p-3 shrink-0">
        <div class="flex gap-2">
          <input
            v-model="inputMessage"
            @keydown.enter="sendMessage(inputMessage)"
            type="text"
            placeholder="Ask about IRAMP/ATO..."
            class="flex-1 text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent"
            :disabled="isLoading"
          />
          <button
            @click="sendMessage(inputMessage)"
            :disabled="!inputMessage.trim() || isLoading"
            class="bg-red-700 hover:bg-red-800 disabled:bg-gray-300 text-white rounded-lg px-3 py-2 transition-colors"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
            </svg>
          </button>
        </div>
        <div class="mt-1 text-xs text-gray-400 text-center">
          Powered by {{ aiStatus === 'available' ? 'Phi-3 Mini (Local)' : 'AI Service' }}
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, nextTick, onMounted } from 'vue'

interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
  source?: string
}

const isOpen = ref(false)
const inputMessage = ref('')
const messages = ref<ChatMessage[]>([])
const isLoading = ref(false)
const aiStatus = ref('checking')
const messagesContainer = ref<HTMLElement | null>(null)

const suggestions = [
  'What is an ATO?',
  'Explain NIST 800-37 risk framework',
  'What are the key steps in the IRAMP process?',
  'Help me understand DFARS compliance',
]

const apiBase = useRuntimeConfig().public.apiBase || '/be'

async function checkHealth() {
  try {
    const response = await $fetch<{ ollama: string; xeta: string }>(`${apiBase}/ai/health`)
    if (response.ollama === 'available' || response.xeta === 'available') {
      aiStatus.value = 'available'
    } else {
      aiStatus.value = 'degraded'
    }
  } catch {
    aiStatus.value = 'unavailable'
  }
}

async function sendMessage(text: string) {
  if (!text.trim() || isLoading.value) return

  const userMessage = text.trim()
  inputMessage.value = ''

  messages.value.push({ role: 'user', content: userMessage })
  await scrollToBottom()

  isLoading.value = true

  try {
    const conversationHistory = messages.value
      .filter(m => m.role === 'user' || m.role === 'assistant')
      .slice(-10)
      .map(m => ({ role: m.role, content: m.content }))

    const response = await $fetch<{ reply: string; source: string }>(`${apiBase}/ai/chat`, {
      method: 'POST',
      body: {
        message: userMessage,
        conversation_history: conversationHistory.slice(0, -1),
      },
    })

    messages.value.push({
      role: 'assistant',
      content: response.reply,
      source: response.source,
    })
  } catch (error: any) {
    messages.value.push({
      role: 'assistant',
      content: 'Sorry, I encountered an error. Please try again.',
    })
    console.error('AI chat error:', error)
  } finally {
    isLoading.value = false
    await scrollToBottom()
  }
}

async function scrollToBottom() {
  await nextTick()
  if (messagesContainer.value) {
    messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
  }
}

onMounted(() => {
  checkHealth()
})
</script>
