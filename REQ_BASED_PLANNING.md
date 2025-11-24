# Requirements-Based Planning Strategy

## Table of Contents

- [Overview](#overview)
- [Why This System?](#why-this-system)
- [EARS Format Guide](#ears-format-guide)
- [File Structure](#file-structure)
- [Workflow](#workflow)
- [Traceability](#traceability)
- [Migration Strategy](#migration-strategy)
- [Examples](#examples)
- [FAQ](#faq)

## Overview

This mono repo uses a **requirements-based planning system** inspired by EARS (Easy Approach to Requirements Syntax). The system provides explicit traceability from business requirements → implementation code.

### Core Principles

1. **Requirements First**: Define what needs to be built before writing code
2. **Verifiable Specifications**: Every requirement must have clear, observable success criteria
3. **Immutable Traceability**: Requirements get permanent IDs that never change
4. **Living Documentation**: Specs evolve with the codebase, not separate artifacts

### The Three-Document Pattern

Projects with non-trivial requirements use a `ProjectName/specs/` directory with:

```
ProjectName/specs/
├── requirements.md   # WHAT to build (EARS format, immutable IDs, timeless)
├── design.md         # HOW to build it (architecture, implementation, living)
└── executive.md      # WHERE are we (status tracking, executive summaries, authoritative)
```

## Why This System?

### Problems It Solves

**Problem 1: "Why did we build this?"**

- Without documented requirements, future maintainers don't understand intent
- Code comments describe "what" not "why"
- Git history provides implementation details, not business context

**Solution:** `requirements.md` captures business need and acceptance criteria

**Problem 2: "Is this feature complete?"**

- No clear definition of "done"
- Edge cases discovered in production
- Unclear verification status

**Solution:** EARS format provides verifiable acceptance criteria, `executive.md` tracks status

**Problem 3: "What will break if I change this?"**

- Hard to find all code related to a feature
- Implementation doesn't clearly link to requirements
- Refactoring is risky without understanding dependencies

**Solution:** Requirement IDs create grep-able links between requirements and code

### Benefits Over Previous Approach

**Before (Journey-based approach):**

- ✅ Good: User journey concept with personas
- ✅ Good: Comprehensive validation documents
- ⚠️ Limitation: Journey numbers informal, can shift
- ⚠️ Limitation: Documentation often written after implementation
- ⚠️ Limitation: No machine-verifiable traceability
- ⚠️ Limitation: PLAN.md cleared after completion (lost context)

**After (Requirements-based with specs/):**

- ✅ Preserves: User journey concept
- ✅ Preserves: Comprehensive documentation
- ✅ Adds: Immutable requirement IDs (REQ-RL-001)
- ✅ Adds: Requirements written before implementation
- ✅ Adds: Grep-able traceability (rg "REQ-RL-001")
- ✅ Adds: Permanent historical record

## EARS Format Guide

EARS (Easy Approach to Requirements Syntax) was developed at Rolls-Royce for aviation systems. It provides a simple, consistent structure for writing unambiguous requirements.

### Basic Structure

```
WHEN [trigger condition]
THE SYSTEM SHALL [expected behavior]
```

### The Five EARS Patterns

#### 1. **Ubiquitous Requirements** (Always true)

```markdown
THE SYSTEM SHALL validate email format before account creation
THE SYSTEM SHALL encrypt passwords using bcrypt
```

#### 2. **Event-Driven Requirements** (State changes)

```markdown
WHEN user clicks "Submit" button
THE SYSTEM SHALL validate form fields

WHEN API returns 500 error
THE SYSTEM SHALL retry request up to 3 times
```

#### 3. **State-Driven Requirements** (Conditional behavior)

```markdown
WHILE user is authenticated
THE SYSTEM SHALL display logout button

WHILE request queue is full
THE SYSTEM SHALL return 503 Service Unavailable
```

#### 4. **Unwanted Behavior** (Explicit prohibitions)

```markdown
IF user quota is exhausted
THE SYSTEM SHALL NOT process new LLM requests

IF authentication token is invalid
THE SYSTEM SHALL NOT return sensitive data
```

#### 5. **Optional Features** (Configurable behavior)

```markdown
WHERE cache is enabled
THE SYSTEM SHALL return cached data within 100ms

WHERE analysis mode is set to "premium"
THE SYSTEM SHALL include extended forecast analysis
```

### Writing Good EARS Requirements

#### ✅ Good Examples

**Specific and Measurable:**

```markdown
WHEN user makes 11th token request from same IP within 1 hour
THE SYSTEM SHALL return HTTP 429 with X-RateLimit-Remaining: 0 header
```

**Error Conditions Explicit:**

```markdown
WHEN LLM API returns 503 error
THE SYSTEM SHALL send SSE event with type: error and message: "Service temporarily unavailable"
```

**Edge Cases Covered:**

```markdown
WHEN rate limit resets at hour boundary
THE SYSTEM SHALL allow new requests from previously blocked IPs

WHEN user requests nowcast at exact midnight UTC
THE SYSTEM SHALL use current day's quota, not previous day
```

#### ❌ Bad Examples

**Vague:**

```markdown
❌ THE SYSTEM SHALL be fast
✅ THE SYSTEM SHALL return nowcast data within 2 seconds for cached locations
```

**Ambiguous:**

```markdown
❌ THE SYSTEM SHALL handle errors gracefully
✅ WHEN database connection fails, THE SYSTEM SHALL return HTTP 503 with retry-after: 60
```

**Not Testable:**

```markdown
❌ THE SYSTEM SHALL provide good user experience
✅ WHEN form validation fails, THE SYSTEM SHALL display error message within 100ms
```

**Implementation Detail (belongs in design.md):**

```markdown
❌ THE SYSTEM SHALL use Redis for rate limiting storage
✅ THE SYSTEM SHALL persist rate limit state across server restarts
```

## File Structure

### Directory Organization

Each project can optionally maintain its own specs:

```
ProjectName/
├── specs/
│   ├── requirements.md
│   ├── design.md
│   └── executive.md
├── src/
└── README.md
```

For projects with multiple distinct feature areas, use subdirectories:

```
ProjectName/
├── specs/
│   ├── feature-one/
│   │   ├── requirements.md
│   │   ├── design.md
│   │   └── executive.md
│   └── feature-two/
│       ├── requirements.md
│       ├── design.md
│       └── executive.md
├── src/
└── README.md
```

### Naming Conventions

Use **kebab-case** for directory names:

- `snippet-manager` (not `SnippetManager` or `snippet_manager`)
- `pdf-to-jpegs` (not `pdfToJpegs`)

Match names to project concepts when possible:

- ✅ `snippet-manager` - Clear user-facing project
- ⚠️ `redis-cache` - Implementation detail, not a project
- ✅ `safari-suggestions` - User-facing feature

### requirements.md Template

```markdown
# [Feature Name]

## User Story

As a [user type], I need to [capability] so that [benefit].

## Requirements

### REQ-[ABBREV]-001: [User Benefit Title]

WHEN [condition]
THE SYSTEM SHALL [behavior]

WHEN [edge case]
THE SYSTEM SHALL [error handling]

**Rationale:** [Why does the USER care? What user problem does this solve?]

**Dependencies:** REQ-[ABBREV]-002 (if applicable)

---

### REQ-[ABBREV]-002: [Next Requirement]

WHEN [condition]
THE SYSTEM SHALL [behavior]

**Rationale:** [User benefit explanation]

---
```

**Key Principles:**

- NO status fields (status lives in executive.md)
- NO test coverage sections (coverage lives in executive.md)
- NO implementation sections (implementation lives in design.md)
- Git history shows evolution (no "Updated YYYY-MM-DD" notes)
- Requirements can be added, modified, or deprecated (ID never changes)

### design.md Template

```markdown
# [Project/Feature Name] - Technical Design

## Architecture Overview

[High-level description of how components interact. Include diagrams if helpful.]

## Data Models

[Document your data structures, classes, schemas, or entities]

## Component Interactions

[Describe how different parts of the system work together]

## Error Handling Strategy

[Describe how errors are detected, reported, and recovered from]

## Security Considerations

[Document security decisions, data validation, privacy concerns]

## Performance Considerations

[Document performance requirements, optimization strategies, scaling considerations]

## Implementation Notes

[File locations, key functions/classes, technical decisions per requirement]

### REQ-[ABBREV]-001 Implementation
- Location: [file paths]
- Approach: [technical approach taken]
- Trade-offs: [decisions made and why]
```

### executive.md Template

**Purpose:** Authoritative status tracking with executive summaries. Target persona: CTO of hard-tech startup (busy, no BS, wants essential facts).

```markdown
# [Project/Feature Name] - Executive Summary

## Requirements Summary

[250 words max, user-focused: What problem does this solve? What can users do? What's the value proposition?]

## Technical Summary

[250 words max, architecture-focused: How is it built? Key technical decisions? Data flow? Design patterns?]

## Status Summary

| Requirement | Status | Notes |
|-------------|--------|-------|
| **REQ-[ABBREV]-001:** [Short Title] | ✅ Complete | Verified via [method] |
| **REQ-[ABBREV]-002:** [Short Title] | 🔄 In Progress | [Component] implemented, [other] pending |
| **REQ-[ABBREV]-003:** [Short Title] | ⚠️ Manual Only | Manual verification documented |
| **REQ-[ABBREV]-004:** [Short Title] | ❌ Not Started | Planned for next iteration |

**Progress:** X of Y complete
```

**Key Principles:**
- 250 words max for each summary
- NO code snippets (zero tolerance)
- NO fluff or boilerplate
- All verification details in Status Summary table
- Include requirement titles in table (no need to look up IDs)
- Keep notes concise (1-2 sentences max)

## Workflow

### 1. Planning a New Project/Feature

**Input:** User story or business requirement

**Steps:**

1. Create spec directory:
   ```bash
   mkdir -p ProjectName/specs
   ```

2. Write `requirements.md`:
   - Define user story
   - Write EARS-formatted requirements with IDs
   - NO status fields (status lives in executive.md)

3. Write `design.md`:
   - Document architecture approach
   - Define data models
   - Specify component interactions
   - Plan implementation approach per requirement

4. Write `executive.md`:
   - Write 250-word requirements summary (user-focused)
   - Write 250-word technical summary (architecture-focused)
   - Create status table (all ❌ initially)
   - Plan verification approach per requirement

**Output:** Complete spec ready for implementation

### 2. Implementing Requirements

**Input:** Completed spec in `ProjectName/specs/`

**Steps:**

1. Update `executive.md` status table (❌ → 🔄 for affected requirements)

2. Implement code with requirement comments:
   ```swift
   // REQ-SM-001: Display snippets sorted by timestamp
   func loadSnippets() -> [Snippet] {
     // Implementation
   }
   ```

3. Update `design.md` with implementation details:
   - Add file locations per requirement
   - Document technical decisions
   - Explain trade-offs

4. Update `executive.md`:
   - Change status as work progresses (🔄 → ✅)
   - Document verification approach in notes
   - Keep requirements.md unchanged

**Output:** Implemented requirements with complete traceability

### 3. Modifying Requirements

**Input:** Change request for existing project

**Steps:**

1. Review existing `requirements.md`
   - Does change fit existing requirements?
   - Or does it need new requirement?

2. If new requirement needed:
   - Add REQ-[ABBREV]-XXX with next sequential ID
   - **NEVER reuse or renumber existing IDs**

3. If existing requirement changes:
   - Update EARS statements in requirements.md (git shows evolution)
   - Update design.md implementation section
   - Update implementation

4. Update implementation with requirement comments

5. Update `executive.md` status and notes

**Output:** Updated spec with git audit trail

### 4. Deprecating a Requirement

**Input:** Requirement no longer needed

**Steps:**

1. Do NOT delete requirement from `requirements.md`

2. Add deprecation note:
   ```markdown
   ### REQ-[ABBREV]-003: [Requirement Title]

   **DEPRECATED:** Replaced by REQ-[ABBREV]-008

   [Original EARS statements preserved]

   **Rationale:** [Original rationale]

   **Deprecation Reason:** [Why this requirement was replaced]
   ```

3. Update `executive.md` status to indicate deprecated

4. Add deprecation comments to code if still present:
   ```
   // REQ-[ABBREV]-003: DEPRECATED - See REQ-[ABBREV]-008 instead
   ```

**Output:** Requirement preserved for historical context

## Traceability

### Grep-Based Traceability

The system is designed for **grep-based traceability** - every requirement ID should be findable across codebase.

**Find all references to a requirement:**
```bash
rg "REQ-SM-001"
```

Expected output:
```
SnippetManager/specs/requirements.md
20:### REQ-SM-001: View All Saved Snippets

SnippetManager/specs/design.md
42:### REQ-SM-001 Implementation

SnippetManager/specs/executive.md
33:| **REQ-SM-001:** View All Saved Snippets | ✅ Complete | ...

SnippetManager/Shared/SnippetStorage.swift
38:// REQ-SM-001: Display snippets sorted by timestamp
```

**Find all requirements in a project:**
```bash
rg "^### REQ-" SnippetManager/specs/requirements.md
```

**Find implementation of a requirement:**
```bash
rg "// REQ-SM-001" SnippetManager/
```

### Traceability Matrix

For each requirement, you should be able to trace:

```
REQ-SM-001
  ├── requirements.md:20 (definition)
  ├── design.md:42 (implementation approach and file locations)
  ├── executive.md:33 (status and notes)
  ├── src/SnippetStorage.swift:38 (implementation comment)
  └── git log --all --grep="REQ-SM-001" (commits)
```

## Migration Strategy

### Migrating Existing Projects

**Option 1: Retroactive Documentation (Recommended)**

For projects with clear functionality:

1. Create `ProjectName/specs/` directory
2. Extract requirements from existing documentation or README
3. Write EARS-formatted requirements (no status fields)
4. Write executive.md with current status
5. Document implementation in design.md
6. Add requirement comments to existing code

**Option 2: Gradual Migration**

For projects still evolving:

1. Write requirements.md from current behavior (no status fields)
2. Identify missing documentation
3. Add details incrementally
4. Update executive.md as understanding improves

**Option 3: Next-Touch Migration**

For stable projects not actively changing:

1. Keep existing documentation as-is
2. Add specs/ when next modified
3. Apply requirements-based process to new changes

### New Projects

**Complex new projects SHOULD use requirements-based planning:**

1. Write `ProjectName/specs/requirements.md` before implementation
2. Review requirements before starting work
3. Add requirement comments during implementation
4. Keep executive.md updated

## Examples

### Real-World Example: SnippetManager

See `SnippetManager/specs/` for a complete, real example in this mono repo:

**highlights:**
- 24 EARS-formatted requirements (REQ-SM-001 through REQ-SM-024)
- User-benefit focused requirement titles ("View All Saved Snippets", not "Display List View")
- Clear separation: requirements.md (timeless), design.md (technical), executive.md (status)
- iOS project with main app + 2 extensions sharing data via App Groups
- Manual verification approach documented in executive.md

This demonstrates the system applied to a complete, working iOS application.

## FAQ

### Q: Do I need specs for bug fixes?

**A:** Usually no. For simple bugs:

- Fix the bug
- Document the fix
- Reference issue number in commit

For bugs revealing missing requirements:

- Add requirement to existing spec
- Implement fix with REQ-* comment
- Update executive.md

### Q: When do I create a new spec vs add to existing?

**A:** Create new spec when:

- Feature is logically independent
- Different team members might work on it
- Deployment could be separate

Add to existing spec when:

- Feature extends existing capability
- Shares same data models/architecture
- Would be confusing to separate

### Q: What if requirements change frequently?

**A:** EARS format handles change well:

- Add new requirements with new IDs
- Update existing EARS statements (git shows history)
- Deprecate obsolete requirements (don't delete)
- Implementation tracks current requirements

Immutable IDs provide stability; EARS statements can evolve.

### Q: Isn't this a lot of overhead?

**A:** Upfront cost, long-term savings:

- **Cost:** 15-30 minutes to write requirements
- **Savings:** Hours debugging unclear requirements
- **Savings:** Days refactoring poorly documented code
- **Savings:** Weeks onboarding new developers

For complex projects, you'd write this documentation anyway - specs just provide structure.

### Q: How detailed should EARS statements be?

**A:** Detailed enough to implement clearly:

- If multiple interpretations possible → too vague, add specifics
- If EARS statement describes implementation → too detailed, focus on behavior
- If can't verify without reading code → add observable criteria

Good test: Can someone else implement from requirements alone?

### Q: What about performance/security requirements?

**A:** Include in requirements.md using EARS:

**Performance:**
```markdown
WHEN user requests nowcast data
THE SYSTEM SHALL respond within 2 seconds for cached locations
```

**Security:**
```markdown
WHEN authentication token is invalid
THE SYSTEM SHALL return 401 without revealing token format
```

### Q: Can requirements reference other requirements?

**A:** Yes, using Dependencies field:

```markdown
### REQ-RL-002: LLM Quota Enforcement

**Dependencies:** REQ-RL-001 (requires rate limiting infrastructure)
```

### Q: How do I handle configuration-dependent requirements?

**A:** Use EARS "WHERE" pattern:

```markdown
WHERE rate limiting is enabled in configuration
THE SYSTEM SHALL enforce 10 requests per hour limit

WHERE rate limiting is disabled
THE SYSTEM SHALL allow unlimited requests
```

## Tools and Automation

### Current Tools

**Grep-based traceability:**

```bash
# Find all references to requirement
rg "REQ-SM-001"

# List all requirements in a project
rg "^### REQ-" SnippetManager/specs/

# Find requirement comments in code
rg "// REQ-SM-" SnippetManager/
```

**Git integration:**

```bash
# Find commits related to requirement
git log --all --grep="REQ-SM-001"

# View requirement evolution
git log -p SnippetManager/specs/requirements.md
```

## References

### External Resources

- **EARS Guide**: [Rolls-Royce EARS Whitepaper](https://www.researchgate.net/publication/224079416_Easy_Approach_to_Requirements_Syntax_EARS)
- **Kiro Code**: [Specification-driven development](https://kiro.dev/docs/specs/concepts/)
- **Requirements Engineering**: [IEEE Guide to SRS](https://standards.ieee.org/standard/29148-2018.html)

### Project Documentation

- **CLAUDE.md**: Requirements-based planning workflow guide
- **ProjectName/specs/**: Project-specific specifications
  - **requirements.md**: Timeless EARS requirements (no status)
  - **design.md**: Living technical documentation
  - **executive.md**: Authoritative status tracking
- **ProjectName/README.md**: Project setup and usage

## Conclusion

Requirements-based planning provides **lightweight but rigorous structure** for project development. It preserves agility while adding traceability and clarity.

**Key takeaways:**

1. **Requirements → Implementation** workflow ensures clear intent
2. **EARS format** makes requirements specific and verifiable
3. **Immutable IDs** enable grep-based traceability
4. **Three-document pattern** balances detail with maintainability
5. **YAGNI/KISS principles** - only use specs when they add value

Apply to complex projects with multiple features. Simple utilities don't need specs.
