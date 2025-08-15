# Information Classification Control Allocation Decision Tree
## Complete Logic Flow and If/Then Statements

---

## Executive Summary

This document outlines the decision logic for determining the number of security controls required based on information classification and system characteristics. The system follows a hierarchical priority order with CUI having the highest override priority.

---

## Priority Hierarchy

1. **CUI (Controlled Unclassified Information)** - Highest priority, automatic 110 controls
2. **External Systems** - Second priority level
3. **Internal Systems** - Third priority level
4. **Public Data** - Lowest security requirements

---

## Control Allocation Table

| LOE Level | Classification/System Type | Control Count |
|-----------|---------------------------|---------------|
| LOE A - ATC | Pilot/Test/Demo (Short duration) | 20 |
| LOE B - Public | Public Data | 38 |
| LOE C - Internal | RTX Internal (Non-DFARS, Commercial, LTD) | 56 |
| LOE D - External | RTX External (Non-DFARS, Commercial, LTD) | 70 |
| DFARS | CUI, CDI, ITAR, EAR, EAR-99+ | 110 |

---

## Complete Decision Logic (If/Then Statements)

### Primary Decision Path

```
START DECISION PROCESS

STEP 1: Check Information Classification
    IF (CUI is selected) THEN
        CONTROLS = 110
        REASON = "CUI Override - Highest Security Level"
        END PROCESS
    END IF

STEP 2: Check for DFARS Requirements
    IF (CDI/DFARS is selected) OR (ITAR is selected) OR (EAR is selected) THEN
        CONTROLS = 110
        REASON = "DFARS Compliance Required"
        END PROCESS
    END IF

STEP 3: Check for Public Data
    IF (Public Data is selected) THEN
        CONTROLS = 38
        REASON = "LOE B - Public Data"
        END PROCESS
    END IF

STEP 4: Determine Pilot System Status
    IF (System is Pilot/Test/Demo with short duration) THEN
        CONTROLS = 20
        REASON = "LOE A - ATC (Pilot System)"
        END PROCESS
    END IF

STEP 5: Determine System Type
    IF (System is Internal) THEN
        IF (Competition Sensitive OR Proprietary OR PII is selected) THEN
            CONTROLS = 56
            REASON = "LOE C - Internal System (RTX Non-DFARS)"
            END PROCESS
        END IF
    ELSE IF (System is External) THEN
        IF (Competition Sensitive OR Proprietary OR PII is selected) THEN
            CONTROLS = 70
            REASON = "LOE D - External System (RTX Non-DFARS)"
            END PROCESS
        END IF
    END IF

DEFAULT: If no classification selected
    CONTROLS = 20 (Minimum baseline)
    REASON = "Default minimum controls"
    
END DECISION PROCESS
```

---

## Detailed Logic Rules

### Rule 1: CUI Override
**Condition:** CUI checkbox is selected  
**Action:** Immediately assign 110 controls  
**Priority:** Highest - overrides all other selections  
**Rationale:** CUI requires maximum security controls per federal requirements

### Rule 2: DFARS Compliance
**Condition:** Any of the following are selected:
- CDI (DFARS)
- ITAR
- EAR
- EAR-99+

**Action:** Assign 110 controls  
**Priority:** High - federal compliance requirement  
**Rationale:** DFARS clause requires comprehensive security implementation

### Rule 3: Public Data
**Condition:** Public data classification is selected  
**Action:** Assign 38 controls (LOE B)  
**Priority:** Low  
**Rationale:** Public information requires basic security controls

### Rule 4: Pilot Systems
**Condition:** System is identified as Pilot/Test/Demo AND duration is short-term  
**Action:** Assign 20 controls (LOE A - ATC)  
**Priority:** Medium  
**Rationale:** Temporary systems with limited scope require minimal controls

### Rule 5: Internal Systems
**Condition:** 
- System is Internal (within RTX network)
- Contains Competition Sensitive, Proprietary, or PII data
- No CUI/DFARS requirements

**Action:** Assign 56 controls (LOE C)  
**Priority:** Medium  
**Rationale:** Internal systems with sensitive business data require moderate controls

### Rule 6: External Systems
**Condition:**
- System is External (outside RTX network)
- Contains Competition Sensitive, Proprietary, or PII data
- No CUI/DFARS requirements

**Action:** Assign 70 controls (LOE D)  
**Priority:** Medium-High  
**Rationale:** External-facing systems require additional security controls

---

## Decision Tree Flow Diagram (Text Representation)

```
[START]
    |
    v
[Is CUI Selected?]
    |-- YES --> [110 Controls] --> [END]
    |
    |-- NO
        |
        v
    [Is CDI/ITAR/EAR Selected?]
        |-- YES --> [110 Controls] --> [END]
        |
        |-- NO
            |
            v
        [Is Public Data?]
            |-- YES --> [38 Controls] --> [END]
            |
            |-- NO
                |
                v
            [Is Pilot System?]
                |-- YES --> [20 Controls] --> [END]
                |
                |-- NO
                    |
                    v
                [What System Type?]
                    |
                    |-- INTERNAL --> [56 Controls] --> [END]
                    |
                    |-- EXTERNAL --> [70 Controls] --> [END]
```

---

## Implementation Examples

### Example 1: CUI Document System
- **Input:** CUI = Yes, Internal System = Yes
- **Decision Path:** Step 1 triggers (CUI selected)
- **Output:** 110 controls
- **Reason:** CUI override applies

### Example 2: Public Website
- **Input:** Public = Yes
- **Decision Path:** Step 3 triggers (Public data)
- **Output:** 38 controls
- **Reason:** LOE B for public information

### Example 3: Internal Proprietary System
- **Input:** Proprietary = Yes, Internal System = Yes
- **Decision Path:** Steps 1-4 pass, Step 5 triggers
- **Output:** 56 controls
- **Reason:** LOE C for internal sensitive data

### Example 4: External Customer Portal
- **Input:** PII = Yes, External System = Yes
- **Decision Path:** Steps 1-4 pass, Step 5 triggers
- **Output:** 70 controls
- **Reason:** LOE D for external system with PII

### Example 5: Test Environment
- **Input:** Pilot System = Yes
- **Decision Path:** Step 4 triggers
- **Output:** 20 controls
- **Reason:** LOE A for short-term pilot

---

## Quick Reference Guide

### Information Classification Types
- **CUI**: Controlled Unclassified Information (non-CDI)
- **CDI**: Covered Defense Information (DFARS requirement)
- **Competition Sensitive**: Business competitive information
- **ITAR/EAR**: Export-controlled information
- **PII**: Personal Information/Personally Identifiable Information
- **Public**: Information available to the public
- **Proprietary**: Company-owned sensitive information

### System Types
- **Pilot System**: Short-duration test, demo, or proof of concept
- **Internal System**: Within company network, not externally accessible
- **External System**: Internet-facing or externally accessible
- **RTX Managed**: Systems managed by RTX IT infrastructure

---

## Compliance Notes

1. **CUI Handling**: Any system handling CUI must implement all 110 controls regardless of other factors
2. **DFARS Compliance**: Systems with CDI, ITAR, or EAR data require full DFARS compliance (110 controls)
3. **Minimum Baseline**: No system should have fewer than 20 controls
4. **Annual Review**: Control requirements should be reviewed annually or when system purpose changes

---

## Contact Information

For questions about this decision tree or control implementation:
- Strategic Business Units Alignment Team
- Information Security Office
- Compliance Department

---

*Document Version: 1.0*  
*Last Updated: [Current Date]*  
*Classification: Internal Use Only*