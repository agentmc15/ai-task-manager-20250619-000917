export function useApi() {
  const config = useRuntimeConfig()
  const baseUrl = config.public?.apiBase || 'http://localhost:4000'

  async function request(path: string, options: RequestInit = {}) {
    const url = `${baseUrl}${path}`
    const res = await fetch(url, {
      headers: {
        'Content-Type': 'application/json',
        ...options.headers,
      },
      ...options,
    })
    if (!res.ok) {
      const text = await res.text()
      throw new Error(`API ${res.status}: ${text}`)
    }
    if (res.status === 204) return null
    return res.json()
  }

  async function getProject(projectId: string) {
    return request(`/project/?project_id=${projectId}&include_questionnaire=true`)
      .then(data => Array.isArray(data) ? data[0] : data)
  }

  async function getProjects(userId?: string) {
    const params = userId ? `?user_id=${userId}` : ''
    return request(`/project/${params}`)
  }

  async function createProject(payload: {
    title: string
    description: string
    tags: string[]
    user_id: string
    questionnaire_id: number
  }) {
    return request('/project/', {
      method: 'POST',
      body: JSON.stringify({
        title: payload.title,
        description: payload.description,
        tags: payload.tags,
        user_id: payload.user_id,
        questionnaireId: payload.questionnaire_id,
        attributes: [],
      }),
    })
  }

  async function saveAnswer(payload: {
    project_id: string
    question_id: string
    value: string | string[]
    submitted_at: string
    justification: string | null
  }) {
    return request('/project/answer/create', {
      method: 'POST',
      body: JSON.stringify({
        projectId: payload.project_id,
        questionId: payload.question_id,
        value: payload.value,
        submittedAt: payload.submitted_at,
        justification: payload.justification,
      }),
    })
  }

  async function getQuestionnaires() {
    return request('/questionnaire/')
  }

  return {
    getProject,
    getProjects,
    createProject,
    saveAnswer,
    getQuestionnaires,
  }
}
