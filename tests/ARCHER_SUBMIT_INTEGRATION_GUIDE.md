# Archer Submit Integration — Full Wiring Guide

This bundle adds **one-click submission from Clarity to Archer** with a
stepped progress UI. The flow:

1. User clicks "Submit for Review"
2. Frontend shows a modal with stepped checkmarks
3. Backend runs the full pipeline (load → export → publish → mark submitted)
4. Frontend updates modal with final success/error state
5. Project is locked (one-way for MVP)

**Dry-run mode is ON by default.** Until you have Archer credentials, the
publisher will log the payload and return fake content IDs so you can test
the wiring without a live Archer instance.

---

## Files to add

### 1. `backend/src/clarity/services/archer_publisher_service.py`
Drop-in service file. New file.

### 2. `backend/src/clarity/routes/archer_submit_routes.py`
Drop-in route file. New file.

---

## Files to modify

### 3. `backend/src/clarity/core/settings.py`

Add these Archer-related settings fields to the `ClaritySettings` class.
Exact syntax depends on whether you're using `BaseSettings` with `SettingsConfigDict`.
Add to the class body:

```python
# Archer publish configuration
archer_publish_enabled: bool = False
archer_base_url: str = "https://archergrc.corp.rtx.com/"
archer_instance: str = "ArcherPOC"
archer_username: str = ""
archer_password: str = ""
archer_user_domain: str = ""
archer_verify_ssl: bool = False
archer_auth_package_module: str = "RTX GRC Authorization Package"
archer_hardware_module: str = "RTX GRC Hardware"
```

If your `ClaritySettings` uses env_prefix, these will be picked up from
env vars like `CLARITY_ARCHER_PUBLISH_ENABLED`, `CLARITY_ARCHER_BASE_URL`, etc.

### 4. `backend/src/clarity/models/questionnaire.py`

Add two fields to the `Project` SQLModel class:

FIND the `Project` class definition and ADD these two fields:

```python
    archer_submitted_at: datetime | None = sqlmodel.Field(default=None)
    archer_content_id: str | None = sqlmodel.Field(default=None, max_length=50)
```

Make sure `from datetime import datetime` is imported at the top of the file
(it likely already is).

### 5. `backend/src/clarity/db/manager.py`

Add a new migration helper function (mirroring `_ensure_owner_email`) and
call it from `init_sql_tables`.

ADD this new function (place it near `_ensure_owner_email`):

```python
def _ensure_archer_columns(eng):
    """Add archer_submitted_at and archer_content_id columns to project table if they don't exist."""
    with eng.connect() as conn:
        # archer_submitted_at
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'project' AND column_name = 'archer_submitted_at'
        """))
        if not result.fetchone():
            log.info("Adding archer_submitted_at column to project table...")
            conn.execute(text(
                "ALTER TABLE project ADD COLUMN archer_submitted_at TIMESTAMP"
            ))
            conn.commit()

        # archer_content_id
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'project' AND column_name = 'archer_content_id'
        """))
        if not result.fetchone():
            log.info("Adding archer_content_id column to project table...")
            conn.execute(text(
                "ALTER TABLE project ADD COLUMN archer_content_id VARCHAR(50)"
            ))
            conn.commit()
```

Then in `init_sql_tables`, ADD the call after `_ensure_owner_email(eng)`:

```python
    _ensure_owner_email(eng)
    _ensure_archer_columns(eng)  # NEW
```

### 6. `backend/src/clarity/api.py`

Register the new router. ADD the import near the other route imports:

```python
from .routes.archer_submit_routes import router as archer_submit_router
```

And include it with the other routers:

```python
api.include_router(archer_submit_router)
```

### 7. `backend/.env`

Add the Archer settings. Leave `CLARITY_ARCHER_PUBLISH_ENABLED=false`
until you have real credentials:

```bash
# === Archer Publisher ===
CLARITY_ARCHER_PUBLISH_ENABLED=false
CLARITY_ARCHER_BASE_URL=https://archergrc.corp.rtx.com/
CLARITY_ARCHER_INSTANCE=ArcherPOC
CLARITY_ARCHER_USERNAME=
CLARITY_ARCHER_PASSWORD=
CLARITY_ARCHER_USER_DOMAIN=
CLARITY_ARCHER_VERIFY_SSL=false
CLARITY_ARCHER_AUTH_PACKAGE_MODULE=RTX GRC Authorization Package
CLARITY_ARCHER_HARDWARE_MODULE=RTX GRC Hardware
```

### 8. `backend/requirements.txt`

Make sure `httpx` is listed. It almost certainly already is since your
existing `archer_service.py` uses it. If not, add:

```
httpx>=0.27
```

---

## Frontend changes

### 9. `frontend/composables/useApi.ts`

Add a new function for the submit endpoint. ADD before the `return` block:

```typescript
  // ----- Archer Submit -----
  async function submitToArcher(projectId: string) {
    return apiFetch<{
      success: boolean
      dry_run: boolean
      project_id: string
      auth_package_content_id: string | null
      hardware_content_ids: string[]
      steps_completed: string[]
      all_steps: Array<{ name: string; label: string; completed: boolean }>
      errors: string[]
      warnings: string[]
      submitted_at: string | null
    }>(`/project/${projectId}/submit-to-archer`, {
      method: 'POST',
    })
  }
```

UPDATE the return block to include it:

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
    submitToArcher,   // NEW
  }
```

### 10. `frontend/pages/clara/[projectId].vue`

Two changes: add a progress modal template, and rewrite `submitForReview()`
to call the new endpoint and drive the modal state.

#### Add state refs at the top of `<script setup>`:

ADD after the existing refs:

```typescript
// Archer submission state
const submitting = ref(false)
const submitSteps = ref<Array<{ name: string; label: string; completed: boolean; active: boolean }>>([])
const submitError = ref<string | null>(null)
const submitSuccess = ref(false)
const submitDryRun = ref(false)
const submitContentId = ref<string | null>(null)
```

Also update the `useApi` destructure to include `submitToArcher`:

```typescript
const { getProject, saveAnswer, getProjects, getQuestionnaires, apiFetch, submitToArcher } = useApi()
```

#### Replace the `submitForReview` function:

FIND:

```typescript
async function submitForReview() {
  saveCurrentAnswer()

  try {
    const payload = await apiFetch(`/project/${projectId}/archer-payload`)
    console.log('Archer payload generated:', payload)
    alert('Questionnaire submitted successfully! Archer payload has been generated.')
    showReview.value = true
  } catch (e) {
    console.error('Failed to generate Archer payload:', e)
    alert('Questionnaire saved but Archer payload generation failed. Check console for details.')
    showReview.value = true
  }
}
```

REPLACE WITH:

```typescript
async function submitForReview() {
  // Save the current answer first
  saveCurrentAnswer()

  // Initialize the progress modal
  submitting.value = true
  submitError.value = null
  submitSuccess.value = false
  submitContentId.value = null
  submitSteps.value = [
    { name: 'save', label: 'Saving questionnaire responses', completed: false, active: true },
    { name: 'generate', label: 'Generating Archer payload', completed: false, active: false },
    { name: 'connect', label: 'Connecting to Archer', completed: false, active: false },
    { name: 'hardware', label: 'Creating hardware records', completed: false, active: false },
    { name: 'auth_package', label: 'Creating authorization package', completed: false, active: false },
    { name: 'complete', label: 'Complete', completed: false, active: false },
  ]

  // Animate through the early steps while the backend works
  const animateSteps = async () => {
    for (let i = 0; i < submitSteps.value.length - 1; i++) {
      submitSteps.value[i].active = true
      await new Promise((r) => setTimeout(r, 400))
      submitSteps.value[i].completed = true
      submitSteps.value[i].active = false
      if (i + 1 < submitSteps.value.length) {
        submitSteps.value[i + 1].active = true
      }
    }
  }

  // Fire the API call and the animation in parallel
  const [result] = await Promise.all([
    submitToArcher(projectId).catch((e) => {
      console.error('Submit to Archer failed:', e)
      return null
    }),
    animateSteps(),
  ])

  if (!result) {
    submitError.value = 'Failed to submit to Archer. Check the console for details.'
    return
  }

  // Update steps based on the actual backend response
  if (result.all_steps && result.all_steps.length > 0) {
    submitSteps.value = result.all_steps.map((s: any) => ({
      name: s.name,
      label: s.label,
      completed: s.completed,
      active: false,
    }))
  }

  if (result.success) {
    submitSuccess.value = true
    submitDryRun.value = result.dry_run
    submitContentId.value = result.auth_package_content_id
    // Mark the final step as complete
    const lastStep = submitSteps.value[submitSteps.value.length - 1]
    if (lastStep) lastStep.completed = true
  } else {
    submitError.value = (result.errors && result.errors.join(', ')) || 'Submission failed'
  }
}

function closeSubmitModal() {
  submitting.value = false
  if (submitSuccess.value) {
    showReview.value = true
  }
}
```

#### Add the progress modal to the template:

ADD this just before the closing `</template>` tag:

```html
    <!-- Archer Submission Modal -->
    <div
      v-if="submitting"
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
    >
      <div class="bg-white rounded-lg shadow-xl p-8 max-w-md w-full mx-4">
        <h3 class="text-xl font-bold mb-6 text-gray-800">
          Submitting to Archer
        </h3>

        <!-- Progress bar -->
        <div class="w-full bg-gray-200 rounded-full h-2 mb-6 overflow-hidden">
          <div
            class="bg-red-600 h-full transition-all duration-500"
            :style="{
              width: `${(submitSteps.filter((s) => s.completed).length / submitSteps.length) * 100}%`,
            }"
          ></div>
        </div>

        <!-- Stepped checkmarks -->
        <ul class="space-y-3 mb-6">
          <li
            v-for="step in submitSteps"
            :key="step.name"
            class="flex items-center gap-3"
          >
            <!-- Completed -->
            <span
              v-if="step.completed"
              class="w-6 h-6 rounded-full bg-green-500 text-white flex items-center justify-center text-sm font-bold"
            >
              ✓
            </span>
            <!-- Active -->
            <span
              v-else-if="step.active"
              class="w-6 h-6 rounded-full border-2 border-red-600 border-t-transparent animate-spin"
            ></span>
            <!-- Pending -->
            <span
              v-else
              class="w-6 h-6 rounded-full border-2 border-gray-300"
            ></span>

            <span
              :class="[
                'text-sm',
                step.completed
                  ? 'text-gray-800 font-medium'
                  : step.active
                  ? 'text-gray-800'
                  : 'text-gray-400',
              ]"
            >
              {{ step.label }}
            </span>
          </li>
        </ul>

        <!-- Success / dry-run state -->
        <div
          v-if="submitSuccess"
          class="border-t pt-4"
        >
          <p
            v-if="submitDryRun"
            class="text-sm text-amber-700 bg-amber-50 p-3 rounded mb-3"
          >
            <strong>Dry run mode:</strong> The payload was generated and logged, but no
            records were created in Archer. Set CLARITY_ARCHER_PUBLISH_ENABLED=true
            in the backend .env to publish live.
          </p>
          <p
            v-else
            class="text-sm text-green-700 bg-green-50 p-3 rounded mb-3"
          >
            <strong>Success!</strong> Authorization package created in Archer with
            content ID <code>{{ submitContentId }}</code>.
          </p>
          <button
            @click="closeSubmitModal"
            class="w-full bg-red-600 text-white py-2 rounded font-medium hover:bg-red-700"
          >
            Done
          </button>
        </div>

        <!-- Error state -->
        <div
          v-else-if="submitError"
          class="border-t pt-4"
        >
          <p class="text-sm text-red-700 bg-red-50 p-3 rounded mb-3">
            <strong>Error:</strong> {{ submitError }}
          </p>
          <button
            @click="submitting = false"
            class="w-full bg-gray-600 text-white py-2 rounded font-medium hover:bg-gray-700"
          >
            Close
          </button>
        </div>
      </div>
    </div>
```

---

## Testing

After applying all patches and rebuilding:

```bash
docker compose -f docker-compose.production.yaml up -d --build
```

### 1. Verify backend startup
```bash
docker logs clarity-api --tail 30
```

You should see:
```
Adding archer_submitted_at column to project table...
Adding archer_content_id column to project table...
Database tables initialized
```

### 2. Test the full flow
1. Open `http://localhost:3000`
2. Log in
3. Create a new project, fill out the questionnaire
4. Click "Submit for Review"
5. The modal should appear with the progress bar animating through the steps
6. Final state: amber "dry run" message with fake content ID

### 3. Verify dry-run worked
```bash
docker logs clarity-api --tail 50 | grep -i archer
```

You should see:
```
INFO ... Archer publish DRY RUN (enabled=False). Payload has N fields.
INFO ... Archer publish step: connect
INFO ... Archer publish step: hardware
INFO ... Archer publish step: auth_package
INFO ... Archer publish step: complete
```

### 4. Try to resubmit (should fail)
Go back to the submitted project. The submit should return a 409 Conflict
because the project is already marked as submitted.

Wait — actually, in dry-run mode the project is NOT marked as submitted
(only real submissions are locked). So you can submit as many times as you
want in dry-run mode. That's intentional for testing.

### 5. When you have real Archer credentials
1. Set `CLARITY_ARCHER_PUBLISH_ENABLED=true` in `.env`
2. Fill in `CLARITY_ARCHER_USERNAME`, `CLARITY_ARCHER_PASSWORD`, etc.
3. Rebuild and submit
4. The project will be marked as submitted and locked

---

## Rollback

If anything breaks, the Archer columns can be dropped manually:

```sql
ALTER TABLE project DROP COLUMN IF EXISTS archer_submitted_at;
ALTER TABLE project DROP COLUMN IF EXISTS archer_content_id;
```

And remove the router registration in `api.py`.
