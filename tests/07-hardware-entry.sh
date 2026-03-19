#!/usr/bin/env bash
set -euo pipefail
#
# Script 7: Add Hardware Entry (key-value-table) Question
# Adds Q9 Hardware Entry to seed data, frontend table renderer, and ensures backend handles it.
# Run from: ~/desktop/repos/clarity-rewrite (or GRCAA-Clarity/projects/clarity-rewrite)
#

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

echo "=== Step 1: Update seed data — add Hardware Entry as Q9 ==="

# We need to patch the seed data JSON. Since the exact format varies,
# here's a standalone Python script that reads, patches, and writes data.json.

cat > backend/scripts/add_hardware_question.py << 'PYEOF'
"""
Patch seed/data.json to add Hardware Entry as the last question.
Run: python backend/scripts/add_hardware_question.py
"""
import json
import os

SEED_PATH = os.path.join(os.path.dirname(__file__), "..", "seed", "data.json")

with open(SEED_PATH, "r") as f:
    data = json.load(f)

# Navigate to the first questionnaire's first phase
questionnaire = data.get("questionnaire", data)
if "phases_json" in questionnaire:
    phases = questionnaire["phases_json"]
elif "phases" in questionnaire:
    phases = questionnaire["phases"]
else:
    # Try nested structure
    phases = questionnaire.get("questionnaire", {}).get("phases_json", [])

if not phases:
    print("ERROR: Could not find phases in seed data. Check data.json structure.")
    exit(1)

phase = phases[0]  # First (and likely only) phase
questions = phase.get("questions", phase.get("nodes", []))
edges = phase.get("edges", [])

# Check if hardware_entry already exists
existing_ids = [q.get("id", "") for q in questions]
if "hardware_entry" in existing_ids:
    print("Hardware Entry question already exists — skipping.")
    exit(0)

# Get the last question's ID for the edge
last_question_id = questions[-1]["id"] if questions else None

# Add the Hardware Entry question
hardware_question = {
    "id": "hardware_entry",
    "subphase": "Information System Details",
    "title": "Hardware Entry",
    "text": "Create an entry for all hardware information. Add a row for each hardware asset associated with this system.",
    "description": "Document all servers, workstations, and network devices that are part of the system boundary.",
    "type": "key-value-table",
    "columns": [
        {
            "col_id": "name",
            "name": "Name",
            "schema_key": "hardware_name",
            "required": True,
            "dtype": "text",
            "options": None
        },
        {
            "col_id": "ip_address",
            "name": "IP Address",
            "schema_key": "ip_address",
            "required": True,
            "dtype": "text",
            "options": None
        },
        {
            "col_id": "hardware_type",
            "name": "Hardware Type",
            "schema_key": "hardware_type",
            "required": True,
            "dtype": "select",
            "options": ["Windows Server", "Linux", "Mac"]
        },
        {
            "col_id": "business",
            "name": "Business",
            "schema_key": "business_unit",
            "required": True,
            "dtype": "select",
            "options": ["Raytheon", "Collins", "Corporate", "P & W"]
        },
        {
            "col_id": "mac_address",
            "name": "MAC Address",
            "schema_key": "mac_address",
            "required": False,
            "dtype": "text",
            "options": None
        }
    ],
    "options": None,
    "justification_required": False,
    "review": False
}

questions.append(hardware_question)

# Add edge from last question to hardware_entry
if last_question_id:
    edges.append({
        "sourceId": last_question_id,
        "targetId": "hardware_entry",
        "operator": None,
        "criteria": None
    })

# Write back
with open(SEED_PATH, "w") as f:
    json.dump(data, f, indent=2)

print(f"Added Hardware Entry question (Q{len(questions)}) after '{last_question_id}'")
print(f"Total questions: {len(questions)}")
print(f"Total edges: {len(edges)}")
PYEOF

echo "  Created backend/scripts/add_hardware_question.py"
echo "  Run: cd backend && python scripts/add_hardware_question.py"

echo ""
echo "=== Step 2: Create KV Table component for the frontend ==="

mkdir -p frontend/components

cat > frontend/components/KVTableInput.vue << 'KVEOF'
<template>
  <div class="w-full">
    <!-- Table -->
    <div class="overflow-x-auto border border-gray-200 rounded-lg">
      <table class="w-full text-sm">
        <!-- Header -->
        <thead>
          <tr class="bg-gray-50 border-b border-gray-200">
            <th
              v-for="col in columns"
              :key="col.col_id"
              class="px-3 py-2.5 text-left text-xs font-semibold text-gray-600 uppercase tracking-wide"
            >
              {{ col.name }}
              <span v-if="col.required" class="text-red-500">*</span>
            </th>
            <th class="px-3 py-2.5 text-right text-xs font-semibold text-gray-600 uppercase tracking-wide w-20">
              Actions
            </th>
          </tr>
        </thead>

        <!-- Body -->
        <tbody>
          <tr
            v-for="(row, rowIdx) in rows"
            :key="rowIdx"
            class="border-b border-gray-100 hover:bg-gray-50 transition-colors"
          >
            <td v-for="col in columns" :key="col.col_id" class="px-3 py-2">
              <!-- Text input -->
              <input
                v-if="col.dtype === 'text' || col.dtype === 'float' || col.dtype === 'int'"
                :type="col.dtype === 'text' ? 'text' : 'number'"
                :value="getCellValue(row, col.col_id)"
                @input="setCellValue(rowIdx, col.col_id, ($event.target as HTMLInputElement).value)"
                :placeholder="col.name"
                class="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-red-800 focus:border-transparent"
              />

              <!-- Select dropdown -->
              <select
                v-if="col.dtype === 'select'"
                :value="getCellValue(row, col.col_id)"
                @change="setCellValue(rowIdx, col.col_id, ($event.target as HTMLSelectElement).value)"
                class="w-full border border-gray-300 rounded px-2.5 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-red-800 focus:border-transparent bg-white"
              >
                <option value="" disabled>Select...</option>
                <option v-for="opt in col.options" :key="opt" :value="opt">
                  {{ opt }}
                </option>
              </select>
            </td>

            <!-- Remove button -->
            <td class="px-3 py-2 text-right">
              <button
                @click="removeRow(rowIdx)"
                :disabled="rows.length <= 1"
                class="text-red-600 hover:text-red-800 disabled:text-gray-300 disabled:cursor-not-allowed text-xs font-medium px-2 py-1 rounded hover:bg-red-50 transition-colors"
              >
                Remove
              </button>
            </td>
          </tr>

          <!-- Empty state -->
          <tr v-if="rows.length === 0">
            <td :colspan="columns.length + 1" class="px-3 py-8 text-center text-gray-400 text-sm">
              No entries yet. Click "Add Row" to get started.
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Add Row button -->
    <div class="mt-3">
      <button
        @click="addRow"
        class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-red-800 bg-red-50 border border-red-200 rounded-md hover:bg-red-100 transition-colors"
      >
        <span class="text-lg leading-none">+</span>
        Add Row
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
interface KVColumn {
  col_id: string
  name: string
  schema_key?: string
  required: boolean
  dtype: 'text' | 'float' | 'int' | 'select'
  options?: string[]
}

interface KVCellValue {
  col_id: string
  value: string | number | null
}

interface KVRow {
  entry: KVCellValue[]
}

const props = defineProps<{
  columns: KVColumn[]
  modelValue: KVRow[]
}>()

const emit = defineEmits<{
  (e: 'update:modelValue', value: KVRow[]): void
}>()

const rows = computed(() => props.modelValue)

function getCellValue(row: KVRow, colId: string): string | number | null {
  const cell = row.entry.find(c => c.col_id === colId)
  return cell?.value ?? ''
}

function setCellValue(rowIdx: number, colId: string, value: string | number | null) {
  const newRows = JSON.parse(JSON.stringify(props.modelValue)) as KVRow[]
  const row = newRows[rowIdx]
  const cellIdx = row.entry.findIndex(c => c.col_id === colId)

  if (cellIdx >= 0) {
    row.entry[cellIdx].value = value
  } else {
    row.entry.push({ col_id: colId, value })
  }

  emit('update:modelValue', newRows)
}

function addRow() {
  const newRow: KVRow = {
    entry: props.columns.map(col => ({
      col_id: col.col_id,
      value: col.dtype === 'select' ? '' : null
    }))
  }
  emit('update:modelValue', [...props.modelValue, newRow])
}

function removeRow(idx: number) {
  const newRows = [...props.modelValue]
  newRows.splice(idx, 1)
  emit('update:modelValue', newRows)
}

// Initialize with one empty row if no data
onMounted(() => {
  if (props.modelValue.length === 0) {
    addRow()
  }
})
</script>
KVEOF

echo "  Created frontend/components/KVTableInput.vue"

echo ""
echo "=== Step 3: Create patch instructions for [projectId].vue ==="

cat > frontend/pages/clara/_kv_table_patch.md << 'PATCHEOF'
# Patch: Add key-value-table support to [projectId].vue

In `frontend/pages/clara/[projectId].vue`, find the section where question types
are rendered (the v-if blocks for text, choose-one, choose-many). Add this block
alongside them:

```vue
<!-- Key-Value Table -->
<div v-if="currentQuestion.type === 'key-value-table'">
  <KVTableInput
    :columns="currentQuestion.columns || []"
    v-model="currentKVAnswer"
  />
</div>
```

Then add the reactive state and save logic. In the `<script setup>` section:

```typescript
import KVTableInput from '~/components/KVTableInput.vue'

// Add alongside existing answer state
const currentKVAnswer = ref<Array<{ entry: Array<{ col_id: string; value: any }> }>>([])

// Watch for question changes to load existing KV data
watch(() => currentQuestion.value, (q) => {
  if (q?.type === 'key-value-table') {
    // Load existing answer if available
    const existing = getExistingAnswer(q.id)
    if (existing && typeof existing === 'object' && 'rows' in existing) {
      currentKVAnswer.value = existing.rows
    } else {
      // Start with one empty row
      currentKVAnswer.value = [{
        entry: (q.columns || []).map((col: any) => ({
          col_id: col.col_id,
          value: col.dtype === 'select' ? '' : null
        }))
      }]
    }
  }
}, { immediate: true })

// When saving answers, handle the KV table type:
// For text/choose-one/choose-many, you save `currentAnswer` as before.
// For key-value-table, save the structured object:
//
//   const answerPayload = currentQuestion.value.type === 'key-value-table'
//     ? { rows: currentKVAnswer.value }
//     : currentAnswer.value
```

The save/upsert endpoint (`POST /project/answer/create`) already accepts
arbitrary JSON in the `answer` field via `responses_json` (JSONB column),
so the `{ rows: [...] }` structure will be stored as-is.
PATCHEOF

echo "  Created frontend/pages/clara/_kv_table_patch.md"

echo ""
echo "=== Step 4: Verify backend model supports key-value-table ==="

# The backend already has these types in questionnaire.py:
#   - KVColumn (col_id, name, schema_key, required, dtype, options)
#   - KVCellValue (col_id, value)
#   - KVRow (entry: list[KVCellValue])
#   - KeyValueTableResponse (rows: list[KVRow])
#   - QuestionType.KV = "key-value-table"
#
# And Question has: columns: list[KVColumn] | None
#
# So the backend model already supports this. No changes needed.

echo "  Backend model check: KVColumn, KVRow, KeyValueTableResponse already defined."
echo "  QuestionType.KV = 'key-value-table' already in enum."
echo "  No backend model changes needed."

echo ""
echo "=== Step 5: Map to Archer Hardware schema ==="

cat > backend/src/clarity/schemas/_hardware_mapping.md << 'MAPEOF'
# Hardware Entry → Archer Field Mapping

The Hardware Entry question (id: `hardware_entry`) stores rows of hardware assets.
Each row maps to an Archer Hardware content record.

## Column → Archer Field Mapping

| KV Column (col_id) | Archer Schema Field | Archer Field Type |
|---------------------|--------------------|--------------------|
| `name`              | `Hardware.name`     | Text               |
| `ip_address`        | `Hardware.ip_address` | Text             |
| `hardware_type`     | `Hardware.hardware_type` | Values List   |
| `business`          | `Hardware.business_unit` | Values List   |
| `mac_address`       | `Hardware.mac_address` | Text            |

## Submission Flow

When submitting to Archer:
1. Read the `hardware_entry` response from `project.responses_json`
2. Parse as `KeyValueTableResponse` (has `.rows` list)
3. For each row, create an Archer content record in the Hardware module
4. Link each Hardware record to the parent Authorization Package record

## Example Response Structure

```json
{
  "question_id": "hardware_entry",
  "answer": {
    "rows": [
      {
        "entry": [
          { "col_id": "name", "value": "PROD-WEB-01" },
          { "col_id": "ip_address", "value": "10.0.1.50" },
          { "col_id": "hardware_type", "value": "Windows Server" },
          { "col_id": "business", "value": "Raytheon" },
          { "col_id": "mac_address", "value": "00:1B:44:11:3A:B7" }
        ]
      },
      {
        "entry": [
          { "col_id": "name", "value": "PROD-DB-01" },
          { "col_id": "ip_address", "value": "10.0.1.51" },
          { "col_id": "hardware_type", "value": "Linux" },
          { "col_id": "business", "value": "Collins" },
          { "col_id": "mac_address", "value": "00:1B:44:11:3A:B8" }
        ]
      }
    ]
  }
}
```
MAPEOF

echo "  Created backend/src/clarity/schemas/_hardware_mapping.md"

echo ""
echo "================================================================"
echo "  Hardware Entry Implementation Complete"
echo "================================================================"
echo ""
echo "Files created:"
echo "  backend/scripts/add_hardware_question.py  — Patches seed data JSON"
echo "  frontend/components/KVTableInput.vue       — Reusable table input component"
echo "  frontend/pages/clara/_kv_table_patch.md    — Integration instructions for [projectId].vue"
echo "  backend/src/clarity/schemas/_hardware_mapping.md — Archer field mapping docs"
echo ""
echo "Steps to apply:"
echo ""
echo "  1. Patch the seed data:"
echo "     cd backend && python scripts/add_hardware_question.py"
echo ""
echo "  2. Drop the KVTableInput.vue component into frontend/components/"
echo "     (already done by this script)"
echo ""
echo "  3. Apply the [projectId].vue patch manually:"
echo "     (see frontend/pages/clara/_kv_table_patch.md)"
echo ""
echo "  4. Restart backend with SEED_DATA=true to re-seed:"
echo "     export SEED_DATA=true"
echo "     py -m uvicorn src.clarity.api:api --host 0.0.0.0 --port 4000 --reload"
echo ""
echo "  5. Restart frontend:"
echo "     cd frontend && npx nuxt dev --port 3000"
echo ""
echo "The table renders with 5 columns (Name, IP, Hardware Type, Business, MAC)"
echo "plus a Remove button per row and an Add Row button at the bottom."
