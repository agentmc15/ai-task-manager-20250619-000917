"""
Add Q4 RTX Business question to seed/data.json.
Run: cd backend && python scripts/add_rtx_business_question.py
"""
import json
import os
from pathlib import Path

SEED_PATH = Path(__file__).parent.parent / "seed" / "data.json"

with open(SEED_PATH, "r") as f:
    data = json.load(f)

# Navigate to phases
q_data = data.get("questionnaire", data)
phases = q_data.get("phases_json", q_data.get("phases", []))

if not phases:
    print("ERROR: No phases found")
    exit(1)

phase = phases[0]
questions = phase.get("questions", phase.get("nodes", []))
edges = phase.get("edges", [])

# Check if already exists
if any(q.get("id") == "rtx_business" for q in questions):
    print("RTX Business question already exists — skipping.")
    exit(0)

# Find where to insert (after entity / Q3, or at position 3)
insert_idx = 3  # After the first 3 questions (0-indexed)
for i, q in enumerate(questions):
    if q.get("id") == "entity":
        insert_idx = i + 1
        break

rtx_business = {
    "id": "rtx_business",
    "title": "RTX Business",
    "text": "Select the RTX Business that the Information System(s) Support and is financially responsible for the Information System(s).",
    "description": None,
    "type": "choose-one",
    "subphase": "General",
    "options": [
        "Corporate",
        "Collins Aerospace",
        "P&W",
        "Raytheon"
    ],
    "justificationRequired": False,
    "review": False
}

# Insert the question
questions.insert(insert_idx, rtx_business)

# Fix edges: find the edge that crosses the insertion point and split it
# We need to insert edges: prev -> rtx_business -> next
prev_id = questions[insert_idx - 1]["id"] if insert_idx > 0 else None
next_id = questions[insert_idx + 1]["id"] if insert_idx + 1 < len(questions) else None

# Remove existing edge from prev to next (if it exists)
edges[:] = [e for e in edges if not (
    e.get("sourceId") == prev_id and e.get("targetId") == next_id
)]

# Add new edges
if prev_id:
    edges.append({
        "sourceId": prev_id,
        "targetId": "rtx_business",
        "operator": None,
        "criteria": None
    })
if next_id:
    edges.append({
        "sourceId": "rtx_business",
        "targetId": next_id,
        "operator": None,
        "criteria": None
    })

with open(SEED_PATH, "w") as f:
    json.dump(data, f, indent=2)

print(f"Added Q{insert_idx + 1} RTX Business after '{prev_id}'")
print(f"Total questions: {len(questions)}")
print(f"Total edges: {len(edges)}")
