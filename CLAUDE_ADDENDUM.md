# Requirements-Based Planning Workflow

## Overview

This project uses a requirements-based planning system inspired by EARS (Easy Approach to Requirements Syntax) to maintain traceability from requirements → tests → code.

## When to Create Specs

Create a new spec directory when:

- Starting a new feature that involves multiple components (API + Frontend + Storage)
- Adding functionality that requires clear acceptance criteria
- Implementing complex business logic that needs comprehensive testing
- Working on features that will evolve over time

**Do NOT create specs for:**

- Trivial bug fixes
- Simple refactorings without behavior change
- Documentation-only changes
- Minor UI adjustments without new functionality

## File Structure

```
specs/
  feature-name/
    requirements.md   # EARS-formatted requirements with immutable IDs (timeless, no status)
    design.md         # Technical architecture and implementation notes (living document)
    executive.md      # Status tracking and executive summaries (authoritative status source)
```

## Requirements Document Format (requirements.md)

### Template Structure

```markdown
# [Feature Name]

## User Story

As a [user type], I need to [capability] so that [benefit].

## Requirements

### REQ-[FEATURE]-001: [User Benefit Title]

WHEN [trigger condition or user action]
THE SYSTEM SHALL [expected behavior]

WHEN [edge case or error condition]
THE SYSTEM SHALL [error handling behavior]

**Rationale:** [Why does the USER care? What user problem does this solve?]

**Dependencies:** REQ-[FEATURE]-002 (if applicable)

---

### REQ-[FEATURE]-002: [Next Requirement Title]

WHEN [condition]
THE SYSTEM SHALL [behavior]

**Rationale:** [User benefit explanation]

---
```

### EARS Format Rules

**Structure:** `WHEN [condition] THE SYSTEM SHALL [behavior]`

**Requirements:**

- Be specific and testable (avoid vague terms like "fast" or "user-friendly")
- Include error conditions and edge cases
- Define measurable criteria where applicable
- Use imperative language (SHALL, not "should" or "may")

**Rationale Guidelines:**

Every requirement rationale MUST answer: **"Why does the USER care about this?"** not "Why is this technically necessary?"

**Structure:** [User Benefit] + [Why it matters to user experience] + [Optional: What bad experience this prevents]

**Good Rationale (User Focused):**

```markdown
✅ "Users want to see 'where the action is' without waiting. Fast response enables
curiosity-driven browsing - users can quickly scan across regions to find
interesting weather activity. Slow responses would discourage exploration."
```

**Bad Rationale (Technical Focused):**

```markdown
❌ "Enables spatial discovery of cached weather data. The 500ms target ensures
responsive map interaction. WGS84 is the standard coordinate system."
```

**Test Questions:**

- Does this explain a user benefit or technical implementation?
- Would a non-technical user understand why this matters to THEM?
- Does this answer "so the user can..." or "because the system needs..."?

If rationale sounds like documentation for developers, rewrite for users.

**Good Examples:**

```markdown
✅ WHEN a client makes more than 10 token requests from the same IP within 1 hour
THE SYSTEM SHALL return HTTP 429 with X-RateLimit-Remaining: 0 header

✅ WHEN user submits form with invalid email format
THE SYSTEM SHALL display "Invalid email format" error below email field
```

**Bad Examples:**

```markdown
❌ THE SYSTEM SHALL be fast
❌ THE SYSTEM SHALL provide good error messages
❌ THE SYSTEM SHALL handle rate limiting
```

**Anti-Pattern Examples (Implementation Creeping In):**

```markdown
❌ WHEN a viewport query returns cached nowcasts
THE SYSTEM SHALL include geohash identifier, geographic center coordinates,
generation timestamp, confidence level, and time window identifier

Why bad: Specifies data structure (implementation detail). User doesn't care about "geohash identifier."

✅ WHEN displaying weather activity on the map
THE SYSTEM SHALL show for each location: the place on the map, when someone
last checked weather there, how confident the nowcast is, and location identifier

Why good: Describes user-visible information in user terms.
```

```markdown
❌ WHEN a viewport query is received
THE SYSTEM SHALL complete the query within 500ms by using geohash prefix queries

Why bad: Specifies HOW (geohash prefix queries) instead of just WHAT (performance target).

✅ WHEN a user explores a region by panning or zooming the map
THE SYSTEM SHALL update the displayed activity within 500ms to maintain a
fluid exploration experience

Why good: Focuses on user experience (fluid exploration), mentions performance target without specifying algorithm.
```

**Warning Signs:**

- Technical jargon in WHEN clause (viewport, geohash, API endpoint)
- Data structure field names (latitude, longitude, timestamp)
- Implementation details in SHALL clause (use Redis, query database)
- Rationales explaining "how" instead of "why the user cares"
- Time-dependent phrases making requirement dependent on arbitrary point in time:
  - ❌ "as before", "as currently implemented", "previously", "maintain existing"
  - ✅ Explicitly state both alternatives: "WHEN X... SHALL Y" AND "WHEN NOT X... SHALL Z"

### Requirement ID Format

Use immutable IDs: `REQ-[FEATURE]-###`

- **[FEATURE]**: Short abbreviation (e.g., RL for Rate Limiting, CC for Current Conditions)
- **###**: Zero-padded sequential number (001, 002, etc.)
- **Once assigned, IDs are NEVER reused or changed**

Examples:

- `REQ-RL-001` - Rate Limiting requirement #1
- `REQ-CC-003` - Current Conditions requirement #3
- `REQ-QV-012` - Quota Visibility requirement #12

### Requirement Titles

Requirement titles SHALL describe USER BENEFITS or OUTCOMES, not system features or technical mechanisms.

**Good Examples (User Benefit Focused):**

```markdown
✅ REQ-NM-001: Discover Recent Weather Activity in a Region
✅ REQ-RL-001: Prevent Token Farming Attacks
✅ REQ-CC-001: Show Current Conditions Without Waiting
```

**Bad Examples (Implementation Focused):**

```markdown
❌ REQ-NM-001: Viewport-Based Nowcast Query
❌ REQ-RL-001: IP-Based Token Rate Limiting
❌ REQ-CC-001: Cache Current Conditions Data
```

**Test:** Ask "Would a non-technical user understand what benefit this provides?" If no, rewrite.

## Design Document Format (design.md)

Document technical implementation details:

```markdown
# [Feature Name] - Technical Design

## Architecture Overview

[High-level architecture diagram or description]

## Data Models

[TypeScript interfaces, Rust structs, database schemas]

## API Endpoints

[Endpoint specifications with request/response formats]

## Component Interactions

[Sequence diagrams, data flow descriptions]

## Error Handling Strategy

[How errors are detected, reported, and recovered]

## Testing Strategy

[Unit tests with mocks, E2E tests with full stack including Redis]

## Security Considerations

[Authentication, authorization, data validation]

## Performance Considerations

[Caching, rate limiting, optimization strategies]
```

## Executive Document Format (executive.md)

**Purpose:** Authoritative status tracking with executive summaries. Target persona: CTO of hard-tech startup (busy, no BS, wants essential facts).

**Key Principles:**

- Single source of truth for "where are we?"
- NO code snippets (zero tolerance)
- NO fluff ("tests run on every PR", etc.)
- All verification details folded into Status Summary table
- 250 words max for summaries
- Requirement titles in table (no need to look up IDs)

````markdown
# [Feature Name] - Executive Summary

## Requirements Summary

[250 words max, user-focused: What problem does this solve? What can users do? What's the value proposition?]

## Technical Summary

[250 words max, architecture-focused: How is it built? Key technical decisions? Data flow? API design?]

## Status Summary

| Requirement                         | Backend | Frontend | Testing   | Verification & Gaps                                                |
| ----------------------------------- | ------- | -------- | --------- | ------------------------------------------------------------------ |
| **REQ-[ABBREV]-001:** [Short Title] | ✅      | ✅       | ✅ E2E    | E2E test simulates [scenario], verifies [outcome] (`test.spec.ts`) |
| **REQ-[ABBREV]-002:** [Short Title] | 🔄      | ❌       | ⏭️        | Manual procedure in OPERATIONS.md. Gap: No automated test          |
| **REQ-[ABBREV]-003:** [Short Title] | ✅      | N/A      | ⚠️ Manual | Manual verification only (operational feature)                     |
| **REQ-[ABBREV]-004:** [Short Title] | ❌      | ❌       | ❌        | Not implemented                                                    |

**Progress:** X of Y complete

## Test Execution

```bash
./dev.py test e2e --spec feature.spec.ts
```
````

````

**Status Legend:**
- ✅ Complete/Passing
- 🔄 In Progress/Partial
- ⏭️ Planned
- ❌ Not Started/None
- ⚠️ Manual verification only
- 🟡 Functional (works but gaps exist)
- N/A - Not applicable

## Workflow: Creating a New Feature

### 1. Planning Phase

Create spec directory and write requirements.md:

```bash
mkdir -p specs/feature-name
# Write requirements.md with EARS-formatted requirements (no status fields)
````

### 2. Design Phase

Create design.md:

- Document architecture decisions
- Define data models
- Specify API contracts
- Plan implementation approach per requirement

### 3. Executive Summary Phase

Create executive.md with status table and summaries (all requirements marked as not started initially).

### 4. Test Development Phase

Write tests:

```typescript
/**
 * @requirement REQ-[FEATURE]-001
 * @acceptance-criteria Rate limiting enforcement
 */
test.describe("Feature Name", () => {
  /**
   * @verifies REQ-[FEATURE]-001: System returns 429 after limit
   */
  test("should enforce rate limit", async ({ request }) => {
    // Test implementation
  });
});
```

```rust
// REQ-[FEATURE]-001: Rate limiting implementation
#[tokio::test]
async fn test_rate_limit_enforcement() -> Result<()> {
    // Test implementation
}
```

### 5. Implementation Phase

Add requirement comments to code and document in design.md:

```rust
// REQ-[FEATURE]-001: Token rate limiting
pub async fn check_rate_limit(
    ip_addr: &str,
    limiter: &RateLimiter,
) -> Result<RateLimitInfo> {
    // Implementation
}
```

Update design.md with implementation details per requirement (file locations, technical decisions).

### 6. Validation Phase

Update executive.md:

- Change status table cells (❌ → 🔄 → ✅)
- Add verification coverage sections
- Document any coverage gaps
- Keep requirements.md unchanged (it's timeless)

## Workflow: Updating Existing Features

### Adding Requirements

1. Add new requirement to requirements.md with next sequential ID (no status field)
2. Add row to executive.md status table (initially ❌)
3. Update design.md with planned approach
4. Write tests with `@requirement` tags
5. Implement code with `REQ-*` comments
6. Update executive.md with verification coverage

### Modifying Requirements

1. **NEVER change requirement IDs**
2. Update EARS statements in requirements.md if behavior changes (git shows history)
3. Update design.md implementation section
4. Update affected tests
5. Update executive.md verification coverage
6. Add deprecation note if requirement becomes obsolete:

   ```markdown
   ### REQ-[FEATURE]-003: [Old Requirement]

   **DEPRECATED:** Replaced by REQ-[FEATURE]-007

   [Original EARS statements preserved]
   ```

## Verification

### Manual Verification

Check traceability with grep:

```bash
# Find all references to a requirement
rg "REQ-RL-001"

# Find all requirement IDs in tests
rg "@requirement REQ-" frontend/tests/

# Find all requirement comments in code
rg "// REQ-" src/
```

### Automated Verification (Future)

```bash
# ./dev.py verify-requirements
# - Scans for REQ-* tags in code and tests
# - Validates all requirements have test coverage
# - Reports missing links
```

### Requirements Self-Check Before Committing

**RECOMMENDED APPROACH:** Use the `verify-requirement` subagent for systematic verification.

When adding or modifying a requirement:

```
I'm going to verify REQ-[FEATURE]-### with the verify-requirement agent.
```

Then launch the agent with either:

- The requirement ID: `REQ-NP-011`
- Or paste the full requirement text

The agent will:

1. Read CLAUDE_ADDENDUM.md requirements checklist
2. Explore specs/ to compare with other requirements
3. Run systematic verification (User-Centricity, Implementation-Creep, Testability, Self-Containment)
4. Provide detailed feedback with quotes and specific fixes
5. Return APPROVED or NEEDS REVISION with rewritten requirement if needed

**Alternatively**, manually run this checklist on EACH requirement:

**User-Centricity Check:**

- [ ] Requirement title describes a user benefit, not a system feature
- [ ] WHEN clause describes user action or context, not system internals
- [ ] SHALL clause describes observable user outcome, not implementation
- [ ] Rationale answers "why does the user care?" not "how does it work?"
- [ ] A non-technical user could understand what value this provides

**Implementation-Creep Check:**

- [ ] No data structure field names (geohash, latitude, timestamp) in WHEN/SHALL
- [ ] No algorithm/technology names (Redis, geohash prefix query, HTTP endpoint)
- [ ] No "HOW" in requirements (that belongs in design.md)
- [ ] No code-like language or jargon

**Testability Check:**

- [ ] Observable behavior that can be verified without reading code
- [ ] Specific criteria (numbers, states, messages) not vague terms
- [ ] Clear success/failure conditions

**Self-Containment Check:**

- [ ] No time-dependent references ("as before", "currently", "previously")
- [ ] No comparative language requiring knowledge of prior implementation
- [ ] Requirement fully understandable without reading code or git history
- [ ] Both positive and negative cases explicitly stated (not "if X then Y, otherwise as before")

**Red Flags - Rewrite if you see:**

- "The system SHALL return/include/store/cache..." (implementation language)
- Technical acronyms or protocols (WGS84, JWT, HTTP 429) without user context
- Requirement title ends in "-ing" (processing, caching, querying)
- Rationale mentions database, cache, algorithm, or data structure
- Time-dependent references: "as before", "previously", "currently", "as implemented"
- Comparative language requiring knowledge of prior state: "maintain existing behavior", "keep working as is"

**Green Flags - Good signs:**

- Requirement title starts with verb describing user action (Discover, Show, Enable)
- WHEN clause starts with "When a user..." or "When exploring..."
- SHALL clause describes what user sees/experiences
- Rationale uses words like: curiosity, discover, explore, understand, feel

## Best Practices

### DO:

- Write requirements before tests
- Write tests before implementation
- Use specific, measurable criteria in EARS statements
- Link every requirement to at least one test
- Keep requirement IDs immutable
- Update executive.md as implementation progresses
- Review test coverage in code reviews
- Keep executive.md concise (2-3 sentences per requirement, no code)
- Use git history for evolution tracking (no "Updated YYYY-MM-DD" notes)

### DON'T:

- Write vague requirements ("fast", "good UX")
- Skip writing tests for requirements
- Reuse requirement IDs
- Add status fields to requirements.md (use executive.md for status)
- Document aspirational features in requirements.md (use PLAN.md for future work)
- Create specs for trivial changes
- Let specs become stale
- Include code snippets in executive.md (zero tolerance)
- Add fluff to executive.md ("tests run on every PR", etc.)

## Integration with Existing Workflow

### PLAN.md vs specs/

- **PLAN.md**: High-level roadmap, future features, aspirational goals
- **specs/**: Detailed requirements for features being actively developed or already implemented
  - **requirements.md**: Timeless requirements (no status)
  - **design.md**: Living technical documentation
  - **executive.md**: Authoritative status tracking (single source of truth)

### Git Workflow

Commit messages should reference requirement IDs:

```
Implement token rate limiting (REQ-RL-001)

- Add IP-based rate limiting middleware
- Return 429 with rate limit headers
- Add comprehensive test coverage

Implements: REQ-RL-001, REQ-RL-002
Tests: frontend/tests/e2e/specs/rate-limiting.spec.ts
```

## Examples

See `specs/newspaper/` for a complete example of this system in practice:

- `requirements.md` - Pure EARS requirements with rationale (no status)
- `design.md` - Technical architecture and implementation details
- `executive.md` - Status tracking with executive summaries (~100 lines total)

## Questions?

Refer to REQ_BASED_PLANNING.md for detailed explanation of the strategy and rationale.
