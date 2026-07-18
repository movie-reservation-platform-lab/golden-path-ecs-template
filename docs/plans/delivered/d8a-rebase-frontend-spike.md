# Implementation Plan: D8a Rebase Frontend Spike

> Status: delivered by issue #23 / PR #33. Preserved as implementation history.

## 1. Summary

Issue #23 should turn the existing `observability_demo_plus_frontend` spike into
a clean, reviewable D8 starting point on top of current `main`.

The recommended approach is a selective transplant, not a branch merge:

- Start from current `main`, which already includes D7 local observability.
- Port the useful additive frontend files from spike commit `6323886`.
- Preserve finalized backend observability, Docker, metrics, logging, smoke
  script, and documentation from `main`.
- Regenerate or carefully merge `package-lock.json` through `npm install` after
  adding the new workspace.
- Leave behavior-hardening and UI-quality work to #24 through #27 unless a
  tiny fix is required to make the transplanted workspace compile.

This is a sequencing and branch-hygiene task. It is not the final frontend
product review.

The broader product direction is a distributed observability demo platform with
multiple services, generated API clients, MCP tools, agent-driven workflows,
production-shaped OIDC/JWKS, service discovery, and controlled failure
scenarios. That direction is intentionally documented separately in
`docs/plans/distributed-observability-demo-platform.md` so #23 does not absorb
future platform scope.

The frontend product direction is documented separately in
`docs/plans/movie-reservation-frontend-product-requirements.md`. The short
version: D8 should end as a customer-facing movie booking app, not a mini APM or
trace/debug console.

## 2. Goals

- Create a clean D8 branch whose diff does not regress D7 observability.
- Reuse the existing React/Vite frontend spike where it is additive and useful.
- Add or preserve the `movie-reservation-web` workspace as the frontend baseline.
- Keep backend service behavior unchanged.
- Keep the GraphQL schema unchanged.
- Keep the local observability contract unchanged:
  - one workflow-level `X-Correlation-Id`;
  - one request-level `X-Request-Id` per GraphQL HTTP call;
  - valid W3C `traceparent`;
  - optional `tracestate` preserved only when present.
- Produce a branch that principal-engineer review can evaluate without reading
  stale backend rewrites from the spike.
- Document which spike files were ported and which were intentionally rejected.
- Record the higher-level distributed observability demo direction without
  expanding #23 beyond the frontend baseline transplant.

## 3. Non-goals

- Do not merge `observability_demo_plus_frontend` wholesale.
- Do not cherry-pick commit `72322d4` as a backend observability change.
- Do not replace finalized D7 observability modules with the spike versions.
- Do not delete `docs/plans/production-observability-dashboard.md`.
- Do not remove metric helper modules under
  `movie-reservation-service/src/infrastructure/observability/metrics/`.
- Do not change backend GraphQL resolver behavior or schema for #23.
- Do not add Next.js, routing, TanStack Query, Zustand, Tailwind, shadcn/ui, or
  a design system in #23.
- Do not add frontend GraphQL code generation in #23. It should be handled soon
  after #23 inside D8, with CI checks for generated-client drift.
- Do not implement MCP servers, a ReAct agent, Rust recommendation service
  integration, OIDC/JWKS validation, service discovery, or fault injection in
  #23.
- Do not treat the spike's visible diagnostics/control-room UI as the final D8
  product direction.
- Do not require the customer UI to display trace ids, correlation ids, request
  ids, raw trace headers, or GraphQL exchange logs.
- Do not solve #28 API read-result semantics, #31 CI strategy, or #32 command
  idempotency in this branch.
- Do not treat the spike UI as production-ready merely because it compiles.

## 4. Current State

### Repository And Branch State

- Current working branch: `issue-23_rebase-frontend-spike`.
- Current `main` includes `3bd6d24 Add local observability foundation (#22)`.
- GitHub issue #4, `D7: Add Local Observability`, is closed.
- GitHub issue #23, `D8a: Rebase frontend spike onto finalized local
observability`, is open and marked ready.
- Parent frontend roadmap issue: #5.

The spike branch history is not linear with current `main`:

- `git merge-base HEAD observability_demo_plus_frontend` returns `719e92f`,
  before the finalized D7 merge.
- `git rev-list --left-right --count HEAD...observability_demo_plus_frontend`
  returns `1 4`, meaning current `HEAD` has one commit not in the spike and the
  spike has four commits not in current `HEAD`.
- The raw diff from current `HEAD` to `observability_demo_plus_frontend` includes
  useful frontend files, but also backend observability rewrites and deletions.

### Useful Spike Assets

The additive UI commit is `6323886`:

```text
6323886 #4: temp_local: throwable vibe coded UI created
```

Useful candidate files from that commit:

- `movie-reservation-web/README.md`
- `movie-reservation-web/index.html`
- `movie-reservation-web/package.json`
- `movie-reservation-web/tsconfig.json`
- `movie-reservation-web/vite.config.ts`
- `movie-reservation-web/src/app/app.tsx`
- `movie-reservation-web/src/main.tsx`
- `movie-reservation-web/src/styles.css`
- `movie-reservation-web/src/shared/api/graphql-client.ts`
- `movie-reservation-web/src/shared/observability/trace-context.ts`
- `movie-reservation-web/src/shared/observability/trace-context.test.ts`
- `movie-reservation-web/src/features/movie-reservations/*`
- `docs/plans/movie-reservation-frontend-observability-demo.md`, as source
  material, not necessarily as the final plan name.
- Root `package.json` workspace and script changes, subject to review.
- `package-lock.json` entries for the new workspace, preferably regenerated
  instead of copied blindly.

### Spike Changes To Reject By Default

The raw branch diff still includes backend and observability edits that overlap
with finalized D7:

- `movie-reservation-service/src/infrastructure/observability/**`
- `movie-reservation-service/src/application/movie-reservations/**`
  observability ports and processor changes
- `movie-reservation-service/src/presentation/graphql/plugins/graphql-operation-logging.plugin.ts`
- `movie-reservation-service/src/presentation/http/middleware/request-context.middleware.ts`
- `movie-reservation-service/scripts/observability-smoke.ts`
- `movie-reservation-service/Dockerfile`
- `docs/plans/production-observability-dashboard.md`
- `docs/plans/service-follow-up-tasks.md`
- `docs/workflows/local-observability.md`, except for small frontend-specific
  additions that are still valid against current D7 docs.

These should not be ported unless the reviewer deliberately approves a specific
line-level change.

### Current Backend API

The backend already exposes the operations the frontend spike targets:

- `movies`
- `screenings(movieId)`
- `requestReservation(input)`
- `reservationRequestStatus(id)`
- `reservationResult(requestId)`

Relevant files:

- `movie-reservation-service/src/presentation/graphql/movie-reservations.resolver.ts`
- `movie-reservation-service/schema.gql`
- `docs/workflows/graphql-reservation-query-examples.md`

The current API caveat still matters for the UI: `screenings { seats }` returns
auditorium seats, not a dedicated availability view that subtracts confirmed
reservations. Rejected reservations are useful demo outcomes, not necessarily UI
bugs.

### Current Observability Contract

Relevant docs:

- `docs/workflows/local-observability.md`
- `docs/workflows/observability-manager-demo.md`
- `docs/architecture/observability-log-contract.md`

The finalized D7 backend accepts and echoes:

- `traceparent`
- `tracestate`
- `X-Correlation-Id`
- `X-Request-Id`

The React frontend should create one correlation id for a workflow, generate a
fresh request id for each GraphQL call, and send a valid W3C `traceparent`.

These ids should be verified through browser network tools, Playwright reports,
and the backend observability stack. They should not be displayed as normal
customer-facing UI.

### Frontend Product Direction

The final D8 frontend should be a production-like movie reservation app:

- movie discovery first;
- showtime selection;
- seat selection;
- reservation request;
- customer-friendly pending, confirmed, rejected, and failed states;
- movie-specific visuals using local poster-like assets where practical.

The app should not present itself as a control room, dashboard, trace explorer,
or APM surface. Grafana, Tempo, Loki, Prometheus, browser network tools, and
Playwright reports are the observability UIs.

Detailed product and UX requirements are tracked in
`docs/plans/movie-reservation-frontend-product-requirements.md`.

### Future Distributed Demo Context

Principal-engineer Q&A for this plan confirmed that the project should move
toward a richer distributed observability demo after the browser baseline is
stable. The desired direction is:

- a focused reservation browser workflow first;
- TypeScript GraphQL code generation for the React client soon after #23;
- CI validation that generated clients stay in sync with the GraphQL schema;
- a later NestJS-to-Rust recommendation service call to create true
  service-to-service traces;
- later MCP/FastMCP wrappers and a simple ReAct agent once the service graph is
  richer;
- later production-shaped OIDC/JWKS validation with a local mock IdP/JWKS path
  for failure demos;
- later scenario-controlled, local-only fault injection and service discovery
  failures.

Those future follow-ups are tracked in
`docs/plans/distributed-observability-demo-platform.md`.

## 5. Requirements and Assumptions

### Confirmed Requirements

- #23 is the first subtask for D8.
- D8 should add a React + Vite frontend demonstrator, not Next.js.
- The existing `observability_demo_plus_frontend` branch should be reused where
  useful.
- The branch must be based on finalized D7 work from current `main`.
- The older backend observability rewrite in the spike must not regress D7.
- The plan should be detailed enough for principal-engineer review.
- #23 should remain a browser frontend baseline task. The future distributed
  demo direction should be documented, not implemented here.
- The React frontend should remain a focused reservation workflow instead of a
  generic scenario engine.
- Frontend GraphQL code generation is a near-term D8 requirement after #23, and
  generated-client drift should be caught in CI.
- D8 should end with a customer-facing movie booking app, not an
  observability/debug console.
- Observability headers and operation names should be propagated and verified
  externally, not exposed as primary app UI.

### Assumptions

- #23 may port the whole existing `movie-reservation-web` spike as a baseline,
  as long as the diff is clean and backend D7 files are preserved.
- #24 through #27 remain the place for review cleanup, customer-facing UI
  hardening, external observability verification, docs, and CI strategy.
- It is acceptable for #23 to include dependencies required by the spike:
  `react`, `react-dom`, `lucide-react`, `vite`, `@vitejs/plugin-react`,
  frontend React type packages, and `vitest`.
- Root `npm run ci` behavior should be reviewed carefully. The spike adds the
  web workspace to root `ci`; #23 can either keep that if checks pass reliably
  or defer root CI wiring to #27 while preserving the web workspace `check`
  script.
- If package-lock merge conflicts are messy, regenerate with `npm install` from
  the root after adding `movie-reservation-web/package.json`.
- #23 may keep the spike's manual typed GraphQL helper. A follow-up D8 task
  should replace or wrap that helper with a TypeScript-native generated GraphQL
  client.
- Ariadne Codegen is a better fit for the later Python MCP GraphQL service, not
  for the browser frontend.

### Resolved Planning Decisions

- Land the full additive `movie-reservation-web` baseline in #23, then use #24
  through #27 for hardening and acceptance.
- Keep the frontend UI focused on the movie reservation workflow. Do not build a
  generic demo console or scenario engine yet.
- Treat the spike's diagnostics/control-room design as temporary source
  material, not as final D8 product UI.
- Make the final D8 frontend a customer movie booking app with modern cinema
  product feel.
- Do not show trace ids, correlation ids, request ids, raw trace headers, or
  GraphQL exchange logs in normal customer UI.
- Map async backend reservation states into customer-facing booking language.
- Use local poster-like frontend assets for D8 visuals instead of changing the
  backend schema for media fields.
- Keep broader distributed-demo work in a dedicated follow-up document.
- Add frontend GraphQL codegen soon after #23 within D8, including CI validation
  for generated-client drift.
- Expand the distributed trace topology later by making the NestJS backend call
  the Rust Axum recommendation service.
- Add MCP/FastMCP and a simple ReAct agent after the recommendation service path
  exists.
- Treat OIDC/JWKS as a later production-shaped auth deliverable with local mock
  infrastructure for demos.
- Treat fault injection as later, scenario-controlled, local-only behavior.

### Remaining Open Questions

- Should root `npm run ci` include `movie-reservation-web run check` in #23, or
  should that wait for #27?
- Should frontend skill files under `.ai/skills/` be ported from the spike, or
  are the current repository/system skills already sufficient?

Recommended default answers:

- Keep the frontend workspace `check` script in #23. Include it in root `ci`
  only if the full root check remains practical and stable.
- Do not port `.ai/skills` from the spike unless those files are intentionally
  part of the repository source of truth. The current runtime already exposes
  frontend skills to the assistant.

## 6. Proposed Design

Use a frontend-only transplant strategy.

### Source Selection

Treat `6323886` as the main source commit. Prefer path-limited checkout or
manual file copy from that commit over cherry-picking the whole branch.

Candidate command shape for implementation:

```bash
git checkout 6323886 -- movie-reservation-web
```

Then manually apply the root `package.json` changes and regenerate
`package-lock.json`. Avoid:

```bash
git merge observability_demo_plus_frontend
git cherry-pick 72322d4
git cherry-pick 6323886
```

Cherry-picking `6323886` can still drag `.ai`, docs, and root package changes
that need review. If used, it should be followed by an explicit reject/revert
pass before tests.

### Target Workspace Shape

Target workspace:

```text
movie-reservation-web/
  index.html
  package.json
  tsconfig.json
  vite.config.ts
  src/
    app/
    features/
      movie-reservations/
    shared/
      api/
      observability/
```

The workspace should initially use the spike's small local state model, GraphQL
helper, and trace context helper. Do not add a router, app-wide state library, or
server-state library in #23.

### Frontend Client Boundary

#23 should keep the browser client simple enough to review:

- local TypeScript types for the current GraphQL operations;
- a small request helper that sends named GraphQL operations and observability
  headers;
- no generated-client tooling yet.

A follow-up D8 task should add a TypeScript-native GraphQL code generation path
for the React workspace and make CI fail when generated client artifacts drift
from `movie-reservation-service/schema.gql`. That follow-up should decide the
specific TypeScript codegen tool and generated artifact policy.

Do not use Ariadne Codegen in the browser frontend. Ariadne Codegen should be
considered later for a Python FastMCP service that wraps the same GraphQL API as
MCP tools.

### Root Workspace Changes

Root `package.json` should add:

- `movie-reservation-web` to `workspaces`.
- Optional convenience scripts such as `dev:web` and `check:web`.

Root `ci` decision:

- Option A: include `npm -w movie-reservation-web run check` in root `ci` if it
  is stable.
- Option B: defer root `ci` inclusion to #27 and document the reason.

For #23, the minimum acceptable check is:

```bash
npm -w movie-reservation-web run check
```

### Frontend Observability Baseline

The transplanted frontend should preserve the spike's propagation behavior:

- Generate one workflow `X-Correlation-Id`.
- Generate one valid W3C `traceparent`.
- Generate a fresh `X-Request-Id` per GraphQL call.
- Send stable GraphQL operation names.

Do not make a visible diagnostics area a final product requirement. If #23 ports
the spike's diagnostics panel as part of the clean transplant, #24 through #27
should remove or exclude that panel from normal customer UI before D8 is
accepted.

Frontend-originated observability context should be verified through browser
network inspection, Playwright reports, and Grafana/Tempo/Loki, not through an
in-app APM surface.

If `tracestate` is not implemented in #23, document it as a follow-up rather
than inventing vendor state.

### Docs Baseline

Add or keep:

- `movie-reservation-web/README.md` with local run instructions.
- This plan document.
- `docs/plans/frontend-follow-up-triage.md`.
- `docs/plans/distributed-observability-demo-platform.md`.
- `docs/plans/movie-reservation-frontend-product-requirements.md`.
- `docs/index.md` entries for the new plan docs.

If `docs/plans/local-observability-foundation.md` has been moved to
`docs/plans/delivered/local-observability-foundation.md`, update index links so
there are no broken local documentation links.

## 7. Alternatives Considered

### Alternative A: Merge The Spike Branch

- Pros:
  - Fastest command-level path.
  - Keeps the spike history intact.
- Cons:
  - Carries stale backend observability changes.
  - Deletes or rewrites finalized D7 docs and modules.
  - Makes review noisy and riskier than necessary.
- Decision:
  - Rejected. This is the failure mode #23 exists to avoid.

### Alternative B: Cherry-Pick Only `6323886`

- Pros:
  - Keeps the UI commit as a recognizable unit.
  - Faster than manual reconstruction.
- Cons:
  - Still includes `.ai` skill files, docs changes, root scripts, and lockfile
    changes that need review.
  - May conflict against current `main` because the parent commit is the stale
    backend rewrite.
- Decision:
  - Acceptable only with a strict follow-up cleanup pass. Prefer path-limited
    checkout/manual transplant if conflicts are non-trivial.

### Alternative C: Path-Limited Transplant From `6323886`

- Pros:
  - Keeps the diff focused on frontend workspace and explicit docs.
  - Avoids stale backend files by construction.
  - Makes review easier for principal-engineer and frontend review.
- Cons:
  - Loses single-commit provenance unless documented.
  - Requires manual root `package.json` and lockfile reconciliation.
- Decision:
  - Recommended.

### Alternative D: Rebuild The Frontend From Scratch

- Pros:
  - Cleanest implementation history.
  - Avoids inheriting vibe-coded UI problems.
- Cons:
  - Wastes usable work from the spike.
  - Delays frontend feedback.
  - Repeats decisions already captured in the spike.
- Decision:
  - Rejected for #23. Hardening the transplanted baseline is enough.

## 8. API / Interface Changes

Expected changes:

- Add npm workspace `movie-reservation-web`.
- Add frontend package scripts:
  - `dev`
  - `build`
  - `preview`
  - `typecheck`
  - `test`
  - `check`
- Add optional root convenience scripts:
  - `dev:web`
  - `check:web`
- Possibly update root `ci` to include frontend checks.
- Add Vite dev proxy from `/graphql` to the local API target.

No backend API changes:

- No GraphQL schema changes.
- No resolver changes.
- No service application-layer changes.
- No persistence changes.
- No Docker Compose service changes required for #23, unless docs need to
  explain the existing API container profile.

## 9. Data Model / Persistence Changes

None.

#23 should not add migrations, change Postgres tables, change in-memory store
shape, or modify reservation state transitions.

## 10. Security, Privacy, and Abuse Considerations

- Do not display bearer tokens, raw Authorization headers, cookies, or secrets
  in the UI.
- Do not store demo tokens or observability ids in localStorage/sessionStorage
  unless a later requirement explicitly needs persisted demo sessions.
- Treat trace ids, request ids, and correlation ids as debugging handles, not
  authorization or trust boundaries.
- Do not display trace ids, correlation ids, request ids, raw trace headers,
  GraphQL exchange logs, bearer tokens, cookies, or raw auth headers in normal
  customer UI.
- Preserve backend tenant scoping. The frontend must not add `movieProviderId`
  to normal GraphQL inputs.
- Keep Vite environment variables local-development oriented. Avoid committing
  real `.env` values.
- If `VITE_DEMO_BEARER_TOKEN` support is ported, document that it is local-only
  and do not print it in the UI.
- Frontend-originated ids are caller-provided and therefore untrusted. The
  backend already validates safe id format and may regenerate invalid ids.

## 11. Performance, Scalability, and Reliability Considerations

- Keep #23 dependency additions minimal and justified by the spike.
- Do not add client-side caching libraries until repetition or polling
  complexity requires them.
- Ensure polling is bounded and stops on terminal states:
  - `CONFIRMED`
  - `REJECTED`
  - `FAILED`
- Keep one catalog load path to avoid unnecessary request waterfalls.
- Keep generated ids bounded and safe for headers/log searches.
- Make the Vite proxy target configurable so the frontend works with:
  - host API on `http://127.0.0.1:3000`;
  - Compose API on `http://127.0.0.1:3001`.
- If frontend checks materially slow down root CI, defer root CI integration to
  #27 and keep the workspace-local check documented.

## 12. Implementation Steps

1. Confirm clean base and preserve existing docs changes.
   - Change: Verify the branch is based on current `main` and understand the
     existing docs-only changes already in the worktree.
   - Files/modules likely affected: none.
   - Notes: Do not overwrite unrelated user docs edits. Current branch already
     contains documentation updates and a delivered-plan move.
   - Verification:
     - `git status --short --branch`
     - `git log --oneline --decorate --max-count=5`

2. Record source and rejection list before porting.
   - Change: Capture the source commit and the files that must not be ported.
   - Files/modules likely affected: this plan document or implementation notes.
   - Notes: Source commit is `6323886`. Reject stale backend changes from
     `72322d4` and raw branch diff.
   - Verification:
     - `git diff --name-status HEAD..observability_demo_plus_frontend`
     - `git diff --name-status 72322d4..6323886`

3. Port the frontend workspace.
   - Change: Add `movie-reservation-web/` from `6323886`.
   - Files/modules likely affected:
     - `movie-reservation-web/**`
   - Notes: Prefer path-limited checkout from `6323886` or manual copy. Do not
     touch backend service files.
   - Verification:
     - `git status --short`
     - Confirm only `movie-reservation-web/**` was added at this step.

4. Reconcile root npm workspace metadata.
   - Change: Add `movie-reservation-web` to root `workspaces`; add convenience
     scripts if accepted.
   - Files/modules likely affected:
     - `package.json`
   - Notes: Decide whether root `ci` includes the web check now or waits for
     #27.
   - Verification:
     - `npm -w movie-reservation-web run typecheck` should resolve the
       workspace after install.

5. Regenerate dependency lockfile.
   - Change: Update `package-lock.json` using npm from the repo root.
   - Files/modules likely affected:
     - `package-lock.json`
     - possibly `node_modules/` locally, untracked/ignored.
   - Notes: Use npm, not pnpm or yarn. Do not hand-edit lockfile entries.
   - Verification:
     - `npm install`
     - `npm -w movie-reservation-web run check`

6. Review and adapt frontend code to current backend contract.
   - Change: Fix compile-time or obvious contract drift only.
   - Files/modules likely affected:
     - `movie-reservation-web/src/shared/api/graphql-client.ts`
     - `movie-reservation-web/src/shared/observability/trace-context.ts`
     - `movie-reservation-web/src/features/movie-reservations/*`
   - Notes: Do not redesign the UI in #23. If large issues appear, document them
     for #24 through #27.
   - Verification:
     - `npm -w movie-reservation-web run typecheck`
     - `npm -w movie-reservation-web run test`
     - `npm -w movie-reservation-web run build`

7. Preserve finalized D7 backend files.
   - Change: Compare the branch diff against `main` and remove any accidental
     backend observability changes.
   - Files/modules likely affected:
     - `movie-reservation-service/**`
     - `observability/**`
     - `docker-compose.yml`
     - `docs/workflows/local-observability.md`
     - `docs/plans/production-observability-dashboard.md`
   - Notes: These files should generally be unchanged by #23 unless docs need a
     small frontend-specific addition.
   - Verification:
     - `git diff --name-status main...HEAD`
     - Manually confirm no D7 modules are deleted or replaced.

8. Add #23 documentation.
   - Change: Add or update docs that explain the transplant boundary and next
     D8 subtasks.
   - Files/modules likely affected:
     - `docs/plans/d8a-rebase-frontend-spike.md`
     - `docs/plans/distributed-observability-demo-platform.md`
     - `docs/plans/movie-reservation-frontend-product-requirements.md`
     - `docs/plans/frontend-follow-up-triage.md`
     - `docs/index.md`
     - possibly `movie-reservation-web/README.md`
   - Notes: If the old local observability plan is moved to
     `docs/plans/delivered/`, update `docs/index.md` accordingly.
   - Verification:
     - `node_modules/.bin/prettier <touched markdown files> --check`

9. Run service regression checks.
   - Change: Verify backend D7 and existing service behavior still pass.
   - Files/modules likely affected: none unless failures identify accidental
     regressions.
   - Notes: #23 should not require backend code fixes. If service checks fail
     because of unrelated environment or Docker prerequisites, record that
     clearly.
   - Verification:
     - `npm -w movie-reservation-service run check`

10. Run final branch hygiene checks.
    - Change: Confirm the diff shape and produce handoff notes.
    - Files/modules likely affected: none.
    - Notes: The final diff should be mostly:
      - `movie-reservation-web/**`
      - root `package.json`
      - `package-lock.json`
      - frontend docs/plans
      - narrowly scoped docs index updates
    - Verification:
      - `git diff --check`
      - `git status --short --branch`
      - `git diff --name-status main...HEAD`

## 13. Testing Strategy

### Required For #23

- Frontend:
  - `npm -w movie-reservation-web run typecheck`
  - `npm -w movie-reservation-web run test`
  - `npm -w movie-reservation-web run build`
  - `npm -w movie-reservation-web run check`
- Backend regression:
  - `npm -w movie-reservation-service run check`
- Docs and hygiene:
  - `git diff --check`
  - `node_modules/.bin/prettier <touched markdown files> --check`

### Useful But Optional For #23

- Root:
  - `npm run ci`, only if root `ci` includes the frontend and local Docker
    requirements are available.
- Manual browser smoke:
  - Start API through the Compose profile.
  - Start `npm -w movie-reservation-web run dev`.
  - Load `http://127.0.0.1:5173`.
  - Confirm catalog load and no browser console errors.

### Deferred To #24 Through #27

- Accessibility pass over the full UI.
- Responsive layout screenshots.
- Browser devtools or Playwright verification of all frontend observability
  headers.
- Customer-facing redesign that removes always-visible observability diagnostics
  from normal UI.
- Movie-specific visual polish using local frontend assets.
- Frontend GraphQL code generation and CI drift checks.
- Full click-through reservation confirmation/rejection demo.
- CI strategy for frontend and Docker/Postgres e2e checks.

## 14. Rollout / Migration Plan

This is an additive local development branch.

Rollout:

1. Land #23 as a clean transplant branch.
2. Review with the principal engineer before treating the frontend as accepted
   D8 baseline.
3. Continue with #24 through #27 for hardening, frontend GraphQL codegen, and
   final D8 acceptance.
4. Use `docs/plans/movie-reservation-frontend-product-requirements.md` as the
   product/UX acceptance bar before closing D8.
5. Use `docs/plans/distributed-observability-demo-platform.md` when creating
   later issues for recommendation service integration, MCP/agent work,
   OIDC/JWKS, service discovery, and fault injection.

Rollback:

- Remove `movie-reservation-web/`.
- Remove `movie-reservation-web` from root `workspaces`.
- Remove root web convenience scripts.
- Regenerate `package-lock.json` with npm.
- Revert frontend docs added by #23.

No database rollback is required because #23 has no persistence changes.

## 15. Risks and Mitigations

| Risk                                                                               | Impact | Likelihood | Mitigation                                                                                                                          |
| ---------------------------------------------------------------------------------- | -----: | ---------: | ----------------------------------------------------------------------------------------------------------------------------------- |
| Stale backend observability code from the spike replaces finalized D7 code         |   High |     Medium | Use path-limited transplant from `6323886`; review `git diff --name-status main...HEAD`; reject backend service changes by default. |
| `package-lock.json` copy introduces stale dependency graph                         | Medium |     Medium | Regenerate with root `npm install` after adding workspace metadata.                                                                 |
| Root `ci` becomes slower or fails because frontend checks are introduced too early | Medium |     Medium | Keep workspace-local `check`; include root `ci` only if stable, otherwise defer to #27.                                             |
| Spike UI compiles but has UX/accessibility problems                                | Medium |       High | Treat #23 as baseline adoption only; track UI hardening in #24 through #27.                                                         |
| Spike diagnostics/control-room UI becomes accepted product direction               |   High |     Medium | Use `movie-reservation-frontend-product-requirements.md`; remove visible observability diagnostics before closing D8.               |
| Frontend observability ids are malformed or misleading                             | Medium |     Medium | Keep helper tests for traceparent/request id generation; verify backend echoes ids in later D8 tasks.                               |
| Future platform ideas make #23 too broad                                           |   High |     Medium | Keep #23 as a transplant task; track distributed-demo work in a separate follow-up document.                                        |
| Manual frontend GraphQL types drift from the schema                                | Medium |     Medium | Accept manual types only for #23; add TypeScript GraphQL codegen and CI drift checks in a follow-up D8 task.                        |
| Demo token handling leaks secrets into UI                                          |   High |        Low | Do not display auth headers or tokens; keep bearer token config local-only.                                                         |
| The frontend assumes seat availability that the backend does not expose            |    Low |       High | Document that `screenings { seats }` is not availability; rejected reservations are valid demo outcomes.                            |
| Local documentation links break after moving delivered plans                       |    Low |     Medium | Update `docs/index.md` as part of docs verification.                                                                                |

## 16. Done Criteria

- Branch is based on current `main`.
- `movie-reservation-web` exists as an npm workspace.
- The branch diff does not delete or rewrite finalized D7 observability files.
- Root package metadata and lockfile are consistent.
- Frontend workspace has `typecheck`, `test`, `build`, and `check` scripts.
- Frontend workspace check passes.
- Service check passes or any environment-specific inability to run it is
  documented.
- The final diff is mostly frontend workspace, root workspace metadata, lockfile,
  and docs.
- The future distributed observability demo direction is captured in
  `docs/plans/distributed-observability-demo-platform.md`.
- The final D8 frontend product requirements are captured in
  `docs/plans/movie-reservation-frontend-product-requirements.md`.
- Handoff notes identify:
  - source commit/files used from the spike;
  - stale spike changes intentionally left behind;
  - follow-up work for #24 through #27.

## 17. Review Checklist

- [ ] Requirements are explicit.
- [ ] Non-goals are explicit.
- [ ] Existing code conventions were checked.
- [ ] Alternatives were considered.
- [ ] Security implications were reviewed.
- [ ] Scalability and reliability implications were reviewed.
- [ ] Testing strategy is complete.
- [ ] Rollout and rollback are defined.
- [ ] Implementation steps are ordered and concrete.
- [ ] The plan explains why the spike branch should not be merged wholesale.
- [ ] The plan preserves D7 observability as a hard boundary.

## 18. Handoff Prompt For Implementation Agent

```text
Implement the plan in docs/plans/d8a-rebase-frontend-spike.md.

Objective:
- Complete GitHub issue #23 by porting the useful additive frontend spike from
  observability_demo_plus_frontend onto current main without carrying stale
  backend observability rewrites.

Constraints:
- Use npm, not pnpm or yarn.
- Prefer path-limited transplant from commit 6323886.
- Do not merge observability_demo_plus_frontend wholesale.
- Do not cherry-pick or preserve backend observability changes from 72322d4.
- Preserve current D7 files under movie-reservation-service, observability,
  docker-compose.yml, docs/workflows/local-observability.md, and
  docs/plans/production-observability-dashboard.md unless a reviewer explicitly
  approves a narrow docs-only change.
- Do not change the backend GraphQL schema or resolver behavior.
- Do not add new frontend dependencies beyond the spike dependencies unless the
  plan is updated and approved.
- Do not add frontend GraphQL codegen in #23. It is a required D8 follow-up, not
  part of this transplant.
- Do not implement MCP servers, a ReAct agent, Rust recommendation integration,
  OIDC/JWKS validation, service discovery, or fault injection in #23.
- Do not treat the spike's visible diagnostics/control-room UI as the final D8
  product direction. The final D8 app should follow
  docs/plans/movie-reservation-frontend-product-requirements.md.
- Treat #23 as baseline adoption. Defer UI polish, browser observability
  verification, frontend GraphQL codegen, and CI strategy to #24 through #27
  unless a small fix is needed for compile/build.

Relevant files/modules:
- package.json
- package-lock.json
- movie-reservation-web/**
- docs/plans/d8a-rebase-frontend-spike.md
- docs/plans/distributed-observability-demo-platform.md
- docs/plans/movie-reservation-frontend-product-requirements.md
- docs/plans/frontend-follow-up-triage.md
- docs/index.md
- docs/workflows/local-observability.md
- docs/architecture/observability-log-contract.md
- movie-reservation-service/src/presentation/graphql/movie-reservations.resolver.ts
- movie-reservation-service/schema.gql

Expected verification commands:
- npm install
- npm -w movie-reservation-web run check
- npm -w movie-reservation-service run check
- git diff --check
- node_modules/.bin/prettier docs/plans/d8a-rebase-frontend-spike.md docs/plans/distributed-observability-demo-platform.md docs/plans/movie-reservation-frontend-product-requirements.md docs/plans/frontend-follow-up-triage.md docs/index.md --check
- git diff --name-status main...HEAD

If implementation reality differs from the plan, stop and update the plan or ask
for approval before changing scope.
```
