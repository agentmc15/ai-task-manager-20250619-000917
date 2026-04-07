# Questionnaire Submission Wiring - Patch Instructions

## Overview
These patches wire up the full flow:
1. Save answers on navigation (Next/Prev buttons)
2. Save final answer + trigger Archer export on Submit
3. Register the Archer export route in api.py
4. Fix the export service to use `responses_json` (matching Project model)

---

## Patch 1: [projectId].vue — Save on navigation + Submit

In `frontend/pages/clara/[projectId].vue`, make these changes:

### 1a. Fix `nextQuestion()` to save before navigating

FIND (around line 320):
```javascript
function nextQuestion() {
  if (currentIndex.value < questions.value.length - 1) {
    currentIndex.value++
    loadAnswerForQuestion(currentIndex.value)
  }
}
```

REPLACE WITH:
```javascript
function nextQuestion() {
  saveCurrentAnswer()
  if (currentIndex.value < questions.value.length - 1) {
    currentIndex.value++
    loadAnswerForQuestion(currentIndex.value)
  }
}
```

### 1b. Fix `prevQuestion()` to save before navigating

FIND (around line 327):
```javascript
function prevQuestion() {
  if (currentIndex.value > 0) {
    currentIndex.value--
    loadAnswerForQuestion(currentIndex.value)
  }
}
```

REPLACE WITH:
```javascript
function prevQuestion() {
  saveCurrentAnswer()
  if (currentIndex.value > 0) {
    currentIndex.value--
    loadAnswerForQuestion(currentIndex.value)
  }
}
```

### 1c. Fix `submitForReview()` to save + generate Archer payload

FIND (around line 339):
```javascript
function submitForReview() {
  alert('Submit for review - this will send to Archer GRC once connected.')
}
```

REPLACE WITH:
```javascript
async function submitForReview() {
  // Save the current answer first
  saveCurrentAnswer()

  try {
    // Generate the Archer payload
    const { apiFetch } = useApi()
    const payload = await apiFetch(`/project/${projectId}/archer-payload`)

    console.log('Archer payload generated:', payload)
    alert('Questionnaire submitted successfully! Archer payload has been generated.')

    // Switch to review mode
    showReview.value = true
  } catch (e) {
    console.error('Failed to generate Archer payload:', e)
    alert('Questionnaire saved but Archer payload generation failed. Check console for details.')
    showReview.value = true
  }
}
```

### 1d. Add `useApi` import if not already present

At the top of the `<script setup>` block, make sure this exists:
```javascript
const { saveAnswer, getProjects, getQuestionnaires, apiFetch } = useApi()
```

If `apiFetch` is not already destructured from `useApi()`, add it.

---

## Patch 2: useApi.ts — Add getArcherPayload function

In `frontend/composables/useApi.ts`, add this function before the `return` block:

FIND (around line 127):
```typescript
return {
    apiFetch,
    getProjects,
```

ADD BEFORE THE RETURN:
```typescript
  // ----- Archer Export -----
  async function getArcherPayload(projectId: string) {
    return apiFetch(`/project/${projectId}/archer-payload`)
  }
```

AND UPDATE THE RETURN to include it:
```typescript
  return {
    apiFetch,
    getProjects,
    getProject,
    createProject,
    deleteProject,
    saveAnswer,
    getQuestionnaires,
    getCurrentUser,
    getArcherPayload,
  }
```

---

## Patch 3: api.py — Register archer_export_routes

In `backend/src/clarity/api.py`, add the import and registration:

FIND (around line 13):
```python
from .routes.archer_routes import archer_router
```

ADD AFTER:
```python
from .routes.archer_export_routes import router as archer_export_router
```

FIND (around line 58):
```python
api.include_router(archer_router)
```

ADD AFTER:
```python
api.include_router(archer_export_router)
```

---

## Patch 4: archer_export_service.py — Use responses_json

In `backend/src/clarity/services/archer_export_service.py`, the
`get_project_responses()` function needs to use `responses_json`
instead of `responses` (matching the Project model field name).

FIND:
```python
    responses = project.responses or []
```

REPLACE WITH:
```python
    responses = project.responses_json or []
```

---

## Patch 5: archer_export_routes.py — Fix prefix

The route prefix needs to match how project routes are registered.
Looking at `project_routes.py`, the prefix is `/project`.

FIND in `archer_export_routes.py`:
```python
router = APIRouter(prefix="/projects", tags=["archer-export"])
```

REPLACE WITH:
```python
router = APIRouter(prefix="/project", tags=["archer-export"])
```

This ensures the endpoint is `/project/{project_id}/archer-payload`
which matches the frontend call.

---

## Testing

After applying all patches:

### 1. Start backend and frontend locally
```bash
# Terminal 1 - Backend
cd backend
PYTHONPATH=. python -m uvicorn src.clarity.api:api --reload --port 4000

# Terminal 2 - Frontend
cd frontend
npm run dev
```

### 2. Create a project and fill out the questionnaire
- Log in
- Create a new project
- Answer each question, clicking Next between them
- On the last question, click "Submit for Review"

### 3. Verify data in Postgres
```bash
docker exec -it clarity-db psql -U <user> -d <db>
```

```sql
-- See all projects
SELECT id, title, owner_email FROM project;

-- See responses for a project
SELECT jsonb_pretty(responses_json::jsonb) FROM project WHERE id = '<project_id>';

-- Check hardware entries specifically
SELECT jsonb_pretty(resp)
FROM project,
     jsonb_array_elements(responses_json::jsonb) AS resp
WHERE id = '<project_id>'
  AND resp->>'question_id' = 'hardware_entry';
```

### 4. Test the Archer payload endpoint
```bash
curl http://localhost:4000/project/<project_id>/archer-payload | python -m json.tool
```

This should return the full Archer-consumable JSON payload with all
questionnaire responses mapped to Archer field names.
