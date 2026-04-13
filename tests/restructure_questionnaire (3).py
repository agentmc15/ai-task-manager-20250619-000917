"""
Restructure the Clarity questionnaire per Linda's email + v.2 spreadsheet spec.

Applies these transformations to backend/seed/data.json:

1. Title renames (5 existing questions) - id stays the same, display label changes
2. Three new questions inserted (idempotent by id):
   - information_system_owner (text, Personnel)
   - sbu_organization (choose-one-cascade on rtx_business, General)
   - hosting_environment (choose-one, Information System Details)
3. Reorder the questions array to match Linda's flow order
4. Set Q10 / Q11 options to the v.2 spreadsheet value lists
5. Replace hardware_entry.columns with Linda's 5-column spec
6. Full edges-array rewrite to the new 13-question linear flow

The script is idempotent and safe to re-run:
- Renames check for the old title before rewriting
- New question inserts skip if id already exists
- Question array is sorted to TARGET_FLOW_ORDER on every run
- Q10 / Q11 options are always set wholesale to V2_OPTION_LISTS
- Hardware columns are always replaced wholesale
- Edges are always rewritten to match the target flow

Run from the backend directory:
    cd backend && python scripts/restructure_questionnaire.py

Existing Postgres responses_json data is NOT touched - all existing question
ids are preserved, so stored answers remain valid. The mac_address hardware
column is removed; any existing answers referencing it become orphaned but are
not deleted.
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
    "hardware_entry": {
        "old": "Hardware Entry",
        "new": "Hardware",
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

# The linear order of question ids per Linda's email (Q1 through Q13).
# Used for both the questions array order AND the edges array.
TARGET_FLOW_ORDER = [
    "authorization_package_name",          # Q1  Project Name
    "mission_purpose",                     # Q2  Purpose
    "authorization_boundary_description",  # Q3  Boundary Description
    "information_system_owner",            # Q4  Information System Owner (NEW)
    "system_administrator_sa",             # Q5  System Administrator
    "clara_id",                            # Q6  Clara ID
    "rtx_business",                        # Q7  RTX Business
    "sbu_organization",                    # Q8  SBU Organization (NEW)
    "entity",                              # Q9  Entity
    "information_classification",          # Q10 Information Classification
    "connectivity",                        # Q11 Connectivity
    "hosting_environment",                 # Q12 Hosting Environment (NEW)
    "hardware_entry",                      # Q13 Hardware
]


# ---------- spec: Q10 / Q11 option lists (v.2 spreadsheet) ----------

# Per Linda's v.2 "Field Mappings and Name convention logic" spreadsheet,
# Q10 Information Classification and Q11 Connectivity have these exact
# value lists. These are the complete lists shown to the user - no
# allowed/disallowed split, no filtering, no disabled options.
#
# These lists overwrite whatever options exist in data.json today.
#
# IMPORTANT: The Phase 3b Baseline Recommendation derivation logic
# (handled by the Archer publisher service) keys off these exact strings,
# so any drift here breaks that logic. Treat these as the canonical
# source of truth and do NOT edit by hand without coordinating with
# the Archer owner.

INFORMATION_CLASSIFICATION_OPTIONS = [
    "CDI/CUI(DFARS)",
    "Competition Sensitive",
    "EXIM (ITAR,EAR)",
    "Internal User Only",
    "Most Private",
    "Personal Information",
    "Proprietary",
    "Public",
]

CONNECTIVITY_OPTIONS = [
    "External",
    "Global Orion",
    "Interconnected System - Contractor to Government (C2G)",
    "Internal Only",
    "Network Segregated",
    "Networked",
    "Public",
    "Standalone",
]

V2_OPTION_LISTS = {
    "information_classification": INFORMATION_CLASSIFICATION_OPTIONS,
    "connectivity": CONNECTIVITY_OPTIONS,
}


# ---------- spec: hardware columns ----------

# Linda's spec for Q13 Hardware: 5 columns in this exact order.
# - FQDN is new (no existing column maps to host_name)
# - Hardware Name is the existing 'name' column with display label updated
# - Business is the existing column, unchanged
# - Internal IP Address is the existing 'ip_address' column with display label updated
# - Type is the existing 'hardware_type' column with display label updated
# - mac_address is REMOVED entirely
HARDWARE_COLUMNS = [
    {
        "col_id": "fqdn",
        "name": "FQDN",
        "schema_key": "host_name",
        "required": True,
        "dtype": "text",
        "options": None,
    },
    {
        "col_id": "name",
        "name": "Hardware Name",
        "schema_key": "hardware_name",
        "required": True,
        "dtype": "text",
        "options": None,
    },
    {
        "col_id": "business",
        "name": "Business",
        "schema_key": "business_unit",
        "required": True,
        "dtype": "select",
        "options": [
            "Raytheon",
            "Collins",
            "Corporate",
            "P & W",
        ],
    },
    {
        "col_id": "ip_address",
        "name": "Internal IP Address",
        "schema_key": "ip_address",
        "required": True,
        "dtype": "text",
        "options": None,
    },
    {
        "col_id": "hardware_type",
        "name": "Type",
        "schema_key": "hardware_type",
        "required": True,
        "dtype": "select",
        "options": [
            "Windows Server",
            "Linux",
            "Mac",
        ],
    },
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


# ---------- step 3: reorder questions array ----------

def reorder_questions(questions: list[dict]) -> list[dict]:
    """Sort the questions array to match TARGET_FLOW_ORDER.

    Any question whose id is not in TARGET_FLOW_ORDER is moved to the end
    (defensive - shouldn't happen with current spec, but better than dropping).
    """
    _section("Step 3: Reorder questions array to match flow order")

    order_index = {qid: i for i, qid in enumerate(TARGET_FLOW_ORDER)}

    def sort_key(q: dict) -> tuple[int, str]:
        qid = q.get("id", "")
        # Unknown ids sort to the end (after all known ones)
        return (order_index.get(qid, len(TARGET_FLOW_ORDER)), qid)

    sorted_qs = sorted(questions, key=sort_key)

    # Detect any questions in the file that aren't in TARGET_FLOW_ORDER
    unknown = [q.get("id") for q in sorted_qs if q.get("id") not in order_index]
    if unknown:
        _log(f"[WARN] questions present in file but not in TARGET_FLOW_ORDER: {unknown}")
        _log("       these have been moved to the end of the array")

    for i, q in enumerate(sorted_qs, start=1):
        _log(f"  Q{i:<2} {q.get('id')}")

    return sorted_qs


# ---------- step 4: set v.2 option lists on Q10 / Q11 ----------

def set_v2_options(questions: list[dict]) -> int:
    """Overwrite Q10 Information Classification and Q11 Connectivity options
    with the v.2 spreadsheet value lists.

    Wholesale replacement - idempotent (same input always produces same output).
    Logs whether each list actually changed for visibility, including any
    string-level diffs (spelling, capitalization, punctuation drift).
    """
    _section("Step 4: Set Q10/Q11 options to v.2 spec")
    changed = 0

    for q in questions:
        qid = q.get("id")
        if qid not in V2_OPTION_LISTS:
            continue

        new_opts = V2_OPTION_LISTS[qid]
        old_opts = q.get("options") or []

        if old_opts == new_opts:
            _log(f"[skip] {qid}: already matches v.2 spec ({len(new_opts)} options)")
            continue

        q["options"] = list(new_opts)
        _log(f"[set]  {qid}: {len(old_opts)} opts -> {len(new_opts)} opts")

        removed = set(old_opts) - set(new_opts)
        added = set(new_opts) - set(old_opts)
        if removed:
            _log(f"  Removed: {sorted(removed)}")
        if added:
            _log(f"  Added:   {sorted(added)}")
        changed += 1

    _log(f"Questions with option changes: {changed}")
    return changed


# ---------- step 5: replace hardware columns ----------

def replace_hardware_columns(questions: list[dict]) -> bool:
    """Replace hardware_entry.columns with the spec from HARDWARE_COLUMNS.

    Always replaces wholesale (idempotent: same input always produces same output).
    """
    _section("Step 5: Replace hardware_entry columns")

    for q in questions:
        if q.get("id") != "hardware_entry":
            continue

        old_columns = q.get("columns", [])
        old_count = len(old_columns)
        old_col_ids = [c.get("col_id") for c in old_columns]

        q["columns"] = HARDWARE_COLUMNS

        _log(f"[replace] hardware_entry.columns: {old_count} cols -> {len(HARDWARE_COLUMNS)} cols")
        _log(f"  Old col_ids: {old_col_ids}")
        _log(f"  New col_ids: {[c['col_id'] for c in HARDWARE_COLUMNS]}")

        removed = set(old_col_ids) - {c["col_id"] for c in HARDWARE_COLUMNS}
        if removed:
            _log(f"  Removed: {sorted(removed)}")
        return True

    _log("[WARN] hardware_entry question not found in questions array")
    return False


# ---------- step 6: edges rewrite ----------

def rewrite_edges(questions: list[dict]) -> list[dict]:
    """Build a fresh edges array matching TARGET_FLOW_ORDER exactly.

    Validates that every id in TARGET_FLOW_ORDER exists in the questions list
    before producing edges - fails loudly if not.
    """
    _section("Step 6: Rewrite edges to target flow order")

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

    # Apply transformations in order.
    apply_renames(questions)
    apply_insertions(questions)
    questions = reorder_questions(questions)
    set_v2_options(questions)
    replace_hardware_columns(questions)
    new_edges = rewrite_edges(questions)

    # Write the reordered questions and new edges back to the phase.
    phase["questions"] = questions
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
