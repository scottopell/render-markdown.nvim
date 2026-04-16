# Weather Newspaper - Executive Summary

## Requirements Summary

Users need weather information consolidated in one place without hunting across
multiple apps or pages. The newspaper feature provides a single-page view with
multiple independent weather columns (current conditions, 24-hour outlook,
extended forecast, detailed analysis) for a specific geographic area. Users can
quickly scan what's relevant to their plans, verify AI-generated content against
original NWS products, and share links to specific topics.

Key capabilities: Browse all weather topics on one scrollable page. See when
data is outdated (exceptional conditions like NWS outages). Access content
without creating accounts or hitting quotas. Share deep links to specific
columns. Verify AI interpretations by clicking through to exact source products
used in generation. Hero + Cards layout prioritizes immediate weather (current
conditions, next hours) prominently while keeping detailed analysis (extended
forecast, weather discussion) accessible via expandable cards.

The system handles partial failures gracefully—if one column fails to generate,
others display normally. Content updates automatically when meteorologists
publish new forecasts, with user-controlled refresh to avoid jarring mid-read
updates. Geographic scoping ensures users only see weather for their requested
area.

**Value proposition:** Faster weather scanning than multi-page apps, zero
friction access (no accounts), transparent AI with verifiable sources, resilient
to partial outages.

## Technical Summary

Column-based architecture replaces previous persona system. Each column is an
independent content unit implementing the `Column` trait (id, display_name,
required_products, generate_prompt). Columns declare which NWS product types
they need; worker routes product update events to affected columns for
regeneration.

**Multi-Model Architecture (REQ-NP-012 through REQ-NP-017, excluding REQ-NP-015):**

The system supports simultaneous generation by multiple models (Claude, Ollama,
OpenAI, custom) with all versions stored equally. Key design principles:

- **All versions equal:** No "primary vs alternate" distinction. Each model's
  output has equivalent standing in storage and retrieval.
- **Model-specific locks:** NOT IMPLEMENTED - Single-server deployment doesn't
  require coordination.
- **Server responsibility:** Each API server generates versions for its
  configured model on startup (lazy bootstrap) and when products update.
- **Newest-first selection:** On retrieval, returns newest non-error version by
  default. Users can explicitly request specific models via query param.
- **External publishing:** Non-system generators (Ollama, custom models) can
  publish pre-generated content via authenticated endpoint.
- **Version discovery:** Public endpoint enumerates all available model
  versions, enabling model comparison and debugging.

**Generation & Storage:** NewspaperWorker listens for product updates, fetches
required products from storage, generates LLM prompts with style constants,
extracts source metadata (product IDs for exact linking), stores results in
Redis with model-specific keys (`column:{id}:{office}:{generator_hash}`) and
30-day TTL. Parallel generation across models with failure isolation—one
column/model error doesn't block others. Generator metadata (model_name,
provider, generated_by, endpoint) tracked for attribution (REQ-NP-014).

**Single-Server Limitation:** Distributed locking (REQ-NP-013) is NOT
implemented. Multi-server deployments would have redundant LLM calls. This is
acceptable for current single-server deployment.

**Status Visibility:** Column status (not_generated, generated, error) is
derived on-demand per model version from version-specific content. No additional
storage needed. Enables user-facing loading states during cold start and admin
monitoring of regeneration progress. Status API returns server's model by
default, `?all=true` for cross-model visibility (REQ-NP-012).

**API Endpoints:**

- Content endpoints: `GET /api/v1/public/daily/{office}` (all columns, server's
  model), `GET /api/v1/public/daily/{office}/{column_id}` (single column,
  optional `?model=...` param)
- Status endpoints: `GET /api/v1/public/newspapers/{office}/status` (per-office,
  server's model), `GET /api/v1/public/newspapers/status` (all offices)
- Version discovery:
  `GET /api/v1/public/newspapers/{office}/{column_id}/versions` (enumerate all
  model versions)
- External publish: `POST /api/v1/admin/newspapers/{office}/{column_id}/publish`
  (authenticated, Ollama/custom models)
- Public endpoints (no auth/quotas except external publish). Content reads are
  cache-only (<100ms). Status endpoints computed on-demand from Redis state.

**Data:** Redis hash per model version (`column:{id}:{office}:{generator_hash}`)
stores generated content + source metadata + generator info. Product IDs enable
exact version linking. Configuration in `newspapers.json` (office → column list
mapping, with optional target_location for geographic focus).

**Frontend:** Single-page React component, hash fragment deep linking, polling
for update detection, click-to-refresh pattern. Status polling detects
generation completion (2-second intervals). Shows "Generating..." during cold
start instead of errors. Source products render as links to
`/api/v1/public/nws/products/id/{id}` for verification. Can explicitly request
models via query param for comparison.

**Migration:** Big-bang replacement of persona system. Clean slate
implementation, no parallel operation.

## Status Summary

| Requirement                                   | Backend | Frontend | Notes                                                                                |
| --------------------------------------------- | ------- | -------- | ------------------------------------------------------------------------------------ |
| **REQ-NP-001:** Browse Multiple Topics        | ✅      | ✅       | Integration + E2E tests                                                              |
| **REQ-NP-002:** Staleness Warnings            | ✅      | ✅       | E2E tests cover all scenarios                                                        |
| **REQ-NP-003:** Auto-Regeneration             | ✅      | ⚠️       | Backend regenerates on product updates. No UI indicators for "new content available" |
| **REQ-NP-004:** Partial Failures              | ✅      | ✅       | Integration + E2E tests                                                              |
| **REQ-NP-005:** No Auth Required              | ✅      | ✅       | Integration test owns API contract                                                   |
| **REQ-NP-006:** Deep Linking                  | ✅      | ✅       | Hash fragments + auto-scroll, E2E tested                                             |
| **REQ-NP-007:** Discovery Feed                | ✅      | ❌       | API implemented, no UI                                                               |
| **REQ-NP-008:** Office Scoping                | ✅      | ✅       | E2E tests verify metadata display                                                    |
| **REQ-NP-009:** Source Product Links          | ✅      | ✅       | E2E tests verify `links w`ork                                                          |
| **REQ-NP-010:** Admin Regen                   | ✅      | ✅       | E2E tests verify                                                                     |
| **REQ-NP-011:** Target Location               | ✅      | ❌       | Backend adds geographic focus to prompts                                             |
| **REQ-NP-012:** Status Visibility             | ✅      | ❌       | Status API implemented                                                               |
| **REQ-NP-013:** Distributed Locking           | ❌      | ❌       | **Deferred** - single-server deployment                                              |
| **REQ-NP-014:** Track Model Attribution       | ✅      | ❌       | GeneratorInfo stored with every column                                               |
| **REQ-NP-016:** External Publishing           | ✅      | ❌       | POST endpoint with bearer auth                                                       |
| **REQ-NP-017:** Version Discovery             | ✅      | ❌       | GET versions endpoint                                                                |
| **REQ-NP-018:** See Important Info First      | ✅      | ✅       | Featured section renders full content                                                |
| **REQ-NP-019:** Scan Topics w/o Overload      | ✅      | ✅       | Secondary columns have expand/collapse                                               |
| **REQ-NP-020:** Adapt Layout as Topics Evolve | ✅      | ✅       | Layout config in newspapers.json                                                     |

**Progress:** 17 complete, 1 partial (REQ-NP-003), 1 deferred (REQ-NP-013).
**REQ-NP-015 deleted** (over-engineered scoring system).

**Test Strategy:**

- **Integration tests:** Own all API contract validation
- **E2E tests:** Focus on Critical User Journeys (UI rendering, navigation, user
  interactions)
- **Separation:** API validation in integration tests (fast), UI/UX validation
  in E2E tests (comprehensive)

## Test Execution

```bash
# Integration tests
./dev.py test integration

# E2E tests (Critical User Journeys)
./dev.py test e2e --spec newspaper.spec.ts        # Main newspaper functionality
./dev.py test e2e --spec staleness-warnings.spec.ts # Staleness warnings
./dev.py test e2e --spec admin-regeneration.spec.ts # Admin regeneration

# All tests
./dev.py qa
```

## Multi-Model Architecture Implementation (REQ-NP-011 through REQ-NP-017, excluding REQ-NP-015)

**Implementation status:** 5 of 6 requirements complete. REQ-NP-015 (scoring
system) deleted as over-engineered. REQ-NP-013 (distributed locking) deferred
for single-server deployment.

**Key Achievements:**

1. **REQ-NP-011 (Target Location):** Geographic focus in prompts for large CWAs

   - Optional `target_location` field in newspapers.json (name, lat/lon)
   - Conditional "Geographic Focus" section in column generation prompts
   - API metadata exposure

2. **REQ-NP-012 (Status Visibility):** Multi-model status API endpoints

   - GET /newspapers/{office}/status (per-office column status)
   - GET /newspapers/status (platform-wide aggregation)
   - Status derivation: not_generated, generated, error
   - `?all=true` query param for cross-model visibility

3. **REQ-NP-013 (Distributed Locking):** NOT IMPLEMENTED

   - Deferred for single-server deployment
   - Multi-server would require Redis SET NX EX implementation
   - Documented in OPERATIONS.md under "Single-Server Limitation"

4. **REQ-NP-014 (Model Attribution):** Complete generator metadata tracking

   - GeneratorInfo struct (model_name, provider, generated_by, endpoint)
   - Persisted with every column generation
   - Included in all API responses

5. **REQ-NP-016 (External Publishing):** Authenticated column publishing

   - POST /admin/newspapers/{office}/{column_id}/publish
   - Bearer token authentication
   - Enables Ollama/custom model contributions

6. **REQ-NP-017 (Version Discovery):** Cross-model comparison
   - GET /newspapers/{office}/{column_id}/versions
   - Enumerates all model versions with metadata
   - Public access (no auth required)
   - Sorted by timestamp (newest first)

## Next Actions

1. ⏸️ **REQ-NP-013 deferred** - Only needed before horizontal scaling
2. **REQ-NP-003 UI indicators** - Add "new content available" notification
3. **Frontend multi-model UI** - Model selection and version comparison
4. **REQ-NP-007 Discovery feed UI** - Low priority
