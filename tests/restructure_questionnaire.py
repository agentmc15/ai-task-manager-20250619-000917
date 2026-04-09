"""
Restructure the Clarity questionnaire per Linda's email spec.

Applies three kinds of changes to backend/seed/data.json:

1. Title renames (4 existing questions) - id stays the same, display label changes
2. Three new questions inserted:
   - information_system_owner (text, Personnel)
   - sbu_organization (choose-one-cascade on rtx_business, General)
   - hosting_environment (choose-one, Information System Details)
3. Full edges-array rewrite to the new 13-question linear flow

The script is idempotent and safe to re-run:
- Renames check for the old title before rewriting (won't clobber if already renamed)
- New question inserts skip if the id already exists
- Edges are always rewritten to match the target flow

Run from the backend directory:
    cd backend && python scripts/restructure_questionnaire.py

Existing Postgres responses_json data is NOT touched - all existing question ids
are preserved, so stored answers remain valid.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

SEED_PATH = Path(__file__).parent.parent / "seed" / "data.json"


# ---------- spec: title renames ----------

TITLE_RENAMES = {
    "authorization_package_name": {
        "old": "Authorization Package Name",
        "new": "Project Name",
    },
    "mission_purpose": {
        "old": "Mission/Purpose",
        "new": "Purpose",
    },
    "authorization_boundary_description": {
        "old": "Authorization Boundary Description",
        "new": "Boundary Description",
    },
    "system_administrator_sa": {
        "old": "System Administrator (SA)",
        "new": "System Administrator",
    },
}


# ---------- spec: new questions ----------

# Embedded business -> SBU hierarchy for sbu_organization.
# Keys MUST exactly match the option strings in rtx_business.options.
SBU_HIERARCHY = {
    "Collins Aerospace": [
        "Advanced Structures",
        "Avionics",
        "Central",
        "Connected Aviation Solutions",
        "Interiors",
        "Mission Systems",
        "Power Controls",
    ],
    "Corporate": [
        "Corporate Strategy & Development",
        "Enterprise Services",
        "Finance",
        "Global Communications",
        "Global Government Relations",
        "Human Resources",
        "Legal/Contracts and Compliance",
        "Operations & Supply Chain",
        "Technology & Global Engineering",
    ],
    "P&W": [
        "AMER",
        "APAC",
        "EMEA",
    ],
    "Raytheon": [
        "Advanced Products & Solutions (APS)",
        "Advanced Technology (AT)",
        "Air & Space Defense Systems (ADS)",
        "Functions and International (F&I)",
        "Land & Air Defense Systems (LADS)",
        "Naval Power (NP)",
    ],
}


NEW_QUESTIONS = [
    {
        "id": "information_system_owner",
        "title": "Information System Owner",
        "text": "Enter the Employee ID of the Information System Owner (ISO).",
        "description": None,
        "type": "text",
        "subphase": "Personnel",
        "options": None,
        "justificationRequired": False,
        "review": False,
    },
    {
        "id": "sbu_organization",
        "title": "SBU Organization",
        "text": "Select the Strategic Business Unit (SBU) within the selected RTX Business that owns the Information System(s).",
        "description": None,
        "type": "choose-one-cascade",
        "subphase": "General",
        "options": None,
        "dependsOn": "rtx_business",
        "optionsByParent": SBU_HIERARCHY,
        "justificationRequired": False,
        "review": False,
    },
    {
        "id": "hosting_environment",
        "title": "Hosting Environment",
        "text": "Select the hosting environment for the system.",
        "description": None,
        "type": "choose-one",
        "subphase": "Information System Details",
        "options": [
            "aws",
            "Linux",
            "other",
        ],
        "justificationRequired": False,
        "review": False,
    },
]


# ---------- spec: target flow order ----------

# The linear order of question ids as Linda specified (Q1 through Q13).
# The edges array will be rewritten to produce exactly this chain.
TARGET_FLOW_ORDER = [
    "authorization_package_name",  # Q1 Project Name
    "mission_purpose",             # Q2 Purpose
    "authorization_boundary_description",  # Q3 Boundary Description
    "information_system_owner",    # Q4 NEW
    "system_administrator_sa",     # Q5 System Administrator
    "clara_id",                    # Q6 Clara ID
    "rtx_business",                # Q7 RTX Business
    "sbu_organization",            # Q8 NEW
    "entity",                      # Q9 Entity
    "information_classification",  # Q10 Information Classification
    "connectivity",                # Q11 Connectivity
    "hosting_environment",         # Q12 NEW
    "hardware_entry",              # Q13 Hardware
]


# ---------- tiny output helpers ----------

def _log(msg: str) -> None:
    print(f"  {msg}")


def _section(msg: str) -> None:
    print(f"\n=== {msg} ===")


# ---------- step 1: renames ----------

def apply_renames(questions: list[dict]) -> int:
    """Rename question titles per TITLE_RENAMES. Idempotent: skips if already renamed."""
    _section("Step 1: Title renames")
    changed = 0

    for q in questions:
        qid = q.get("id")
        if qid not in TITLE_RENAMES:
            continue

        old = TITLE_RENAMES[qid]["old"]
        new = TITLE_RENAMES[qid]["new"]
        current = q.get("title")

        if current == new:
            _log(f"[skip]   {qid}: already '{new}'")
        elif current == old:
            q["title"] = new
            _log(f"[rename] {qid}: '{old}' -> '{new}'")
            changed += 1
        else:
            _log(f"[WARN]   {qid}: expected '{old}' or '{new}', found '{current}' - leaving alone")

    _log(f"Total renames applied: {changed}")
    return changed


# ---------- step 2: insertions ----------

def apply_insertions(questions: list[dict]) -> int:
    """Append any new questions that don't already exist. Idempotent by id."""
    _section("Step 2: Insert new questions")
    existing_ids = {q.get("id") for q in questions}
    added = 0

    for new_q in NEW_QUESTIONS:
        qid = new_q["id"]
        if qid in existing_ids:
            _log(f"[skip]   {qid}: already exists")
            continue

        questions.append(new_q)
        _log(f"[add]    {qid}: inserted ({new_q['type']}, subphase='{new_q['subphase']}')")
        added += 1

    _log(f"Total questions added: {added}")
    return added


# ---------- step 3: edges rewrite ----------

def rewrite_edges(questions: list[dict]) -> list[dict]:
    """Build a fresh edges array matching TARGET_FLOW_ORDER exactly.

    Validates that every id in TARGET_FLOW_ORDER exists in the questions list
    before producing edges - fails loudly if not.
    """
    _section("Step 3: Rewrite edges to target flow order")

    question_ids = {q.get("id") for q in questions}
    missing = [qid for qid in TARGET_FLOW_ORDER if qid not in question_ids]
    if missing:
        print(f"\nERROR: target flow references ids not in questions list: {missing}")
        print("Aborting without writing file.")
        sys.exit(1)

    edges = []
    for i in range(len(TARGET_FLOW_ORDER) - 1):
        edges.append({
            "sourceId": TARGET_FLOW_ORDER[i],
            "targetId": TARGET_FLOW_ORDER[i + 1],
            "operator": None,
            "criteria": None,
        })

    _log(f"Built {len(edges)} edges for a {len(TARGET_FLOW_ORDER)}-question linear flow")
    for i, qid in enumerate(TARGET_FLOW_ORDER, start=1):
        _log(f"  Q{i:<2} {qid}")

    return edges


# ---------- main ----------

def main() -> int:
    print("=" * 64)
    print("Clarity questionnaire restructure")
    print("=" * 64)
    print(f"Target file: {SEED_PATH}")

    if not SEED_PATH.exists():
        print(f"\nERROR: {SEED_PATH} does not exist")
        return 1

    with open(SEED_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Navigate to the questions array. Path matches add_rtx_business_question.py:
    # data -> phases[0] -> questions
    phases = data.get("phases", [])
    if not phases:
        print("\nERROR: no phases found in data.json")
        return 1

    phase = phases[0]
    questions = phase.get("questions", [])
    if not questions:
        print("\nERROR: no questions found in phases[0]")
        return 1

    print(f"\nLoaded {len(questions)} existing questions from {phase.get('title', 'phases[0]')}")

    # Apply the three transformations in order.
    apply_renames(questions)
    apply_insertions(questions)
    new_edges = rewrite_edges(questions)

    # Replace edges on phase[0].
    phase["edges"] = new_edges

    # Write back with 2-space indent to match the existing file style.
    with open(SEED_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    _section("Done")
    _log(f"Wrote {SEED_PATH}")
    _log(f"Final question count: {len(questions)}")
    _log(f"Final edge count:     {len(new_edges)}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
