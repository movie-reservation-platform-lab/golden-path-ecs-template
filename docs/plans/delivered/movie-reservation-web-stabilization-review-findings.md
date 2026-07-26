# Implementation Plan: Movie Reservation Web Stabilization Review Findings

> Status: delivered as part of issue #23 / PR #33. Preserved as implementation
> history.

## 1. Summary

Stabilize the current `movie-reservation-web` branch after the frontend clean
architecture refactor. The recommended approach is a focused correctness,
configuration, CI, documentation, and test pass that does not redesign the
backend GraphQL API or add new runtime dependencies.

This plan fixes the review findings that are cheap and important now:
stale selection submission, missing web CI coverage, frontend env contract
tracking, browser-visible demo token handling, raw error presentation, missing
critical unit tests, README drift, small GraphQL overfetch, and avoidable seat
map recomputation.

Larger design items are deferred to existing follow-up issues where possible:
catalog/read-model redesign, Playwright/e2e strategy, scalable monorepo CI,
idempotency, explicit reservation read outcomes, OIDC, frontend containerization,
and frontend request resilience/failure demonstrations.

## 2. Goals

- Prevent stale hidden seat ids from being submitted after catalog reloads or
  screening changes.
- Keep selected movie/screening state valid against the latest loaded catalog.
- Add web workspace verification to the current small-repo CI contract.
- Keep frontend local env configuration consistent with the backend
  `env_files/templates` convention.
- Keep `VITE_DEMO_BEARER_TOKEN` only as local development support and make it
  browser-visible by design, never a secret.
- Map low-level backend/parser errors to stable user-facing UI messages.
- Add focused Vitest coverage for GraphQL client behavior and reservation
  polling workflow behavior.
- Trim unused frontend GraphQL identity fields without changing the backend
  schema.
- Memoize the seat-map hot path in a small local change.
- Clean up follow-up documentation so deferred work points to existing issues
  instead of scattered TODOs.

## 3. Non-goals

- Do not change the backend GraphQL schema in this stabilization pass.
- Do not redesign catalog loading into metadata-first and selected-seat queries
  now.
- Do not add Playwright in this pass.
- Do not add request aborts/timeouts now.
- Do not add OIDC, PKCE, JWKS, or production frontend auth now.
- Do not Dockerize the frontend now.
- Do not add GraphQL code generation now.
- Do not add React Testing Library or hook-testing dependencies now.
- Do not convert this branch into a production-hardening pass.

## 4. Current State

The frontend feature is now structured as:

- `movie-reservation-web/src/features/movie-reservations/domain`
- `movie-reservation-web/src/features/movie-reservations/application`
- `movie-reservation-web/src/features/movie-reservations/adapters`
- `movie-reservation-web/src/features/movie-reservations/ui`
- `movie-reservation-web/src/platform`

Relevant current behavior:

- `useMovieCatalog.reloadCatalog` loads the catalog and calls
  `selectInitialCatalogItems`, but existing selection values are kept even if
  they no longer exist in the new catalog.
- `selectInitialCatalogItems` in `domain/catalog-selection.ts` preserves
  current ids by nullish coalescing rather than validating them against the
  catalog.
- `useReservationWorkflow.submitReservation` submits the raw
  `selectedSeatIds`, even though `selectedSeats` is filtered for display.
- `requestGraphql` reads `VITE_DEMO_BEARER_TOKEN` and currently sends it as
  `Authorization: Bearer ...` whenever it is configured.
- `movie-reservation-web/.env.example` exists, but `.gitignore` ignores
  `.env.*`, so the file is not versioned.
- The backend already uses committed templates under
  `movie-reservation-service/env_files/templates/**` and ignored rendered env
  files under `movie-reservation-service/env_files/local/**` and
  `movie-reservation-service/env_files/in-docker/**`.
- Root `package.json` already includes `movie-reservation-web` in npm
  workspaces and has `check:web`, but root `ci` currently runs only service and
  infra.
- `.github/workflows/ci.yml` currently has separate service and infra jobs but
  no web job.
- `docs/workflows/ci-workflow.md` describes CI as service plus CDK only.
- `movie-reservation-web/README.md` references Playwright reports even though
  the workspace has no Playwright script yet.
- The backend exposes `screenings(movieId)` with nested seats, but there is not
  a separate public selected-screening seat query. A proper catalog overfetch
  fix is therefore a backend/frontend read-model design task.
- Existing frontend tests cover domain helpers, API response parsers, and trace
  context, but not the GraphQL client or reservation polling workflow.

Existing issue mapping:

- `#27 D8e: Add frontend verification, docs, and CI wiring` owns final D8
  frontend verification and Playwright smoke work.
- `#31 CI: Add post-D8 frontend and Docker/Postgres e2e check strategy` owns
  scalable monorepo CI, Playwright CI strategy, Docker/Postgres e2e strategy,
  and slower integration jobs.
- `#29 Service/API: Move catalog read model assembly into application query
layer` owns backend read-model placement and should be expanded in docs to
  mention frontend catalog overfetch and selected-screening seat loading.
- `#32 Service/API: Add idempotency handling for reservation commands` owns
  retrying client safety before production-like frontend use.
- `#28 Service/API: Make reservation read outcomes explicit for frontend state`
  owns replacing broad `null` read semantics with explicit outcomes.

## 5. Requirements and Assumptions

### Confirmed Requirements

- This branch is a stabilization pass, not a production-hardening pass.
- Keep `VITE_DEMO_BEARER_TOKEN`, but use it only in Vite dev mode and document
  it as local-dev only and browser-visible.
- Defer request aborts/timeouts to a future resilience and failure-demo task.
- Soften Playwright wording now; add Playwright later.
- Defer catalog overfetch/read-model redesign and record it as a relevant
  follow-up.
- Trim unused frontend GraphQL identity/auth fields if it has no backend
  downside.
- Include seat-map memoization now if it stays local and simple.
- Normalize selection on catalog reload and clear reservation state when the
  effective screening changes.
- Add lightweight user-safe error mapping now.
- Add a separate GitHub Actions web job now.
- Make root `npm run ci` the current full small-repo CI contract, while clearly
  documenting that `#31` owns future affected/path-filtered CI and e2e strategy.
- Use one frontend env template for now because there is no frontend Docker
  profile yet.
- Make `dev` delegate to a local env-file based profile for consistency with
  the backend.
- Add focused tests without overtesting or adding new frontend testing
  dependencies.

### Assumptions

- The implementation agent will not create GitHub issues in this pass unless
  separately instructed.
- Existing open issues remain the source of truth for broader follow-ups.
- CI can afford a web workspace check for the current repository size.
- The frontend remains a local demonstrator and learning app until later OIDC,
  containerization, and e2e work are planned.
- `node --env-file` is available because the repository uses Node 24.

### Open Questions

- None for this stabilization pass.

## 6. Proposed Design

Implement a small set of inward-pointing domain/application helpers and thin
adapter/UI changes.

For catalog selection, make the domain own normalization:

- keep a selected movie only when the movie still exists;
- keep a selected screening only when it still belongs to the selected movie;
- choose the first available movie and first screening when the old selection is
  no longer valid;
- expose whether the effective screening changed so the adapter can clear
  reservation state.

For seat submission, validate selected ids against the active screening before
submitting. This mirrors a Rust-style runtime guard: TypeScript says
`selectedSeatIds` is a string array, but only runtime catalog data can prove
those ids belong to the current screening.

For errors, keep low-level details in thrown `Error` objects and tests, but map
UI alerts to stable user-facing copy. This avoids showing parser internals such
as `ReservationRequest.status was not...` to the user while still allowing dev
diagnosis through console/tests.

For the demo bearer token, keep local JWT/fixed-user workflow support but gate
the browser header on `import.meta.env.DEV`. Vite `VITE_*` values are
browser-visible, unlike backend `process.env`, so the documentation must call
out that this value is not a secret.

For env files, follow the backend pattern:

- committed template under `movie-reservation-web/env_files/templates/local`;
- ignored rendered local env under `movie-reservation-web/env_files/local`;
- `dev` delegates to a local profile script using `node --env-file`.

For CI, use the current simple monorepo contract now:

- root `npm run ci` runs service, infra, and web checks;
- GitHub Actions adds a separate `web` job;
- docs explicitly say `#31` owns future path/affected filtering and slower
  frontend/backend e2e work.

## 7. Alternatives Considered

### Alternative A: Stabilization Pass Now

- Pros:
  - Fixes the correctness and CI blind spots in the current branch.
  - Keeps the clean architecture refactor reviewable.
  - Avoids backend API churn while the frontend structure is still settling.
  - Adds useful tests without new test dependencies.
- Cons:
  - Leaves catalog overfetch and request abort/timeouts for later.
  - Does not deliver Playwright or production auth yet.
- Decision:
  - Adopted.

### Alternative B: Production-Hardening Pass Now

- Pros:
  - Could address aborts/timeouts, catalog read-model design, OIDC direction,
    and Playwright earlier.
  - Moves the app closer to production-shaped frontend behavior.
- Cons:
  - Too broad for a branch that just refactored frontend architecture.
  - Requires backend API/read-model decisions and more CI/runtime design.
  - Higher risk of mixing unrelated concerns into one PR.
- Decision:
  - Rejected for this pass. Defer to follow-up issues and plans.

### Alternative C: Keep CI Manual For Web Until #31

- Pros:
  - Avoids growing root CI before scalable monorepo CI design exists.
  - Keeps PR checks smaller for now.
- Cons:
  - Leaves the newly added frontend workspace outside automated review.
  - Allows frontend regressions to pass while service/infra remain green.
- Decision:
  - Rejected. Add web CI now, document that #31 owns future scaling.

## 8. API / Interface Changes

Frontend internal interfaces may change:

- `CatalogSelection` helpers should normalize ids and expose effective selection
  information.
- `MovieCatalogWorkflow` may expose enough information for the parent UI to know
  when the effective screening changed, or accept a callback such as
  `onEffectiveScreeningChanged`.
- `RequestReservationCommand` should continue to contain only `screeningId` and
  `seatIds`.
- `MovieReservationApi` should not change for this pass unless tests need small
  optional injection points.
- `requestGraphql` may gain a small config/read-env seam only if needed to test
  dev-only token behavior cleanly.

No backend GraphQL schema changes are planned.

GraphQL operation changes:

- `ReservationUiCatalog.me` should stop selecting unused `email`, `roles`, and
  `scopes`.
- The frontend `AuthenticatedUser` domain type and parser should match the
  selected fields.

CLI/script changes:

- `movie-reservation-web` should gain `dev:local`.
- `dev` should delegate to `dev:local`.
- Root `ci` should include the web workspace.

CI changes:

- `.github/workflows/ci.yml` should include a separate `web` job.

## 9. Data Model / Persistence Changes

None.

## 10. Security, Privacy, and Abuse Considerations

- `VITE_DEMO_BEARER_TOKEN` must be documented as browser-visible and local-dev
  only.
- `requestGraphql` must ignore `VITE_DEMO_BEARER_TOKEN` unless
  `import.meta.env.DEV` is true.
- Do not log or display bearer tokens in UI or diagnostics.
- Trim unused `email`, `roles`, and `scopes` from the frontend query for data
  minimization.
- User-facing alerts should not expose raw backend/parser internals.
- The backend remains responsible for tenant/provider authorization. Frontend
  seat validation is UX/correctness, not authorization.
- Future production auth belongs to an OIDC/PKCE/JWKS follow-up, not this pass.

## 11. Performance, Scalability, and Reliability Considerations

- Seat-map memoization should reduce repeated grouping and selected-id lookups.
- Catalog overfetch remains a known scalability concern because initial load
  fetches all nested seats for all screenings.
- The catalog overfetch fix should be tied to `#29` or a child plan: design a
  catalog/read-model API that can load metadata separately from selected
  screening seats and later support date windows or pagination.
- Request aborts/timeouts remain deferred. The follow-up should cover
  `AbortController`, timeout UX, cancellation of superseded reloads/polls,
  Playwright/e2e coverage, and observability expectations for local failure
  demonstrations.
- CI runs all three current workspaces now because the repo is small. `#31`
  should design path/affected filtering and slower integration jobs before the
  workspace count or check cost grows.

## 12. Implementation Steps

1. Add catalog selection normalization
   - Change: Replace `selectInitialCatalogItems` behavior with a helper that
     validates the selected movie and screening against the latest catalog.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/domain/catalog-selection.ts`
     - `movie-reservation-web/src/features/movie-reservations/domain/movie-reservation-domain.test.ts`
   - Notes: Return enough information to know whether the effective screening
     changed.
   - Verification: Domain tests cover preserved selection, missing movie,
     missing screening, empty catalog, and screening-change detection.

2. Validate selected seats before display and submit
   - Change: Add or adjust domain helpers so selected seat ids are filtered to
     ids belonging to the active screening before submission.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/domain/seat-selection.ts`
     - `movie-reservation-web/src/features/movie-reservations/adapters/react/use-reservation-workflow.ts`
     - `movie-reservation-web/src/features/movie-reservations/domain/movie-reservation-domain.test.ts`
   - Notes: Do not rely only on UI visibility. The submit command must use the
     validated active-screening ids.
   - Verification: Tests prove stale seat ids are excluded.

3. Clear reservation state when effective screening changes
   - Change: Wire catalog normalization into the UI/adapters so reservation
     state clears when reload changes the effective screening.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/adapters/react/use-movie-catalog.ts`
     - `movie-reservation-web/src/features/movie-reservations/ui/movie-reservation-demo.tsx`
     - `movie-reservation-web/src/features/movie-reservations/adapters/react/use-reservation-workflow.ts`
   - Notes: Avoid adding React hook testing dependencies. Keep logic in pure
     helpers and make React code thin.
   - Verification: Typecheck and domain tests. Manual reload behavior can be
     smoke-checked if the local API is running.

4. Map UI errors to safe messages
   - Change: Add lightweight error mapping near UI/adapters so catalog and
     reservation alerts show stable copy.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/adapters/react/use-movie-catalog.ts`
     - `movie-reservation-web/src/features/movie-reservations/adapters/react/use-reservation-workflow.ts`
     - optionally a small feature-local error mapping module
   - Notes: Keep detailed errors available to tests/dev diagnostics, but do not
     expose raw parser/backend internals in alerts.
   - Verification: Focused tests only if mapping logic becomes non-trivial;
     otherwise typecheck/build plus existing UI paths.

5. Gate demo bearer token to dev mode
   - Change: Only add the `Authorization` header when `import.meta.env.DEV` is
     true and `VITE_DEMO_BEARER_TOKEN` is non-empty.
   - Files/modules likely affected:
     - `movie-reservation-web/src/platform/api/graphql-client.ts`
   - Notes: Document that local fixed-user mode ignores the token and local-jwt
     mode decodes JWT-shaped values without production validation.
   - Verification: GraphQL client tests cover dev-only header behavior.

6. Add focused GraphQL client tests
   - Change: Add Vitest coverage for the GraphQL request boundary.
   - Files/modules likely affected:
     - `movie-reservation-web/src/platform/api/graphql-client.test.ts`
   - Notes: Do not overtest every malformed envelope shape. Cover request body,
     observability headers, dev-only auth header, GraphQL errors, and parser
     wrapping.
   - Verification: `npm -w movie-reservation-web test`.

7. Add focused reservation workflow tests
   - Change: Add application-level tests for polling behavior without React hook
     dependencies.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/application/request-reservation-workflow.test.ts`
   - Notes: Cover confirmed-after-polling, polling limit error, and stale run
     cancellation/no further event updates.
   - Verification: `npm -w movie-reservation-web test`.

8. Trim frontend GraphQL identity fields
   - Change: Remove unused `email`, `roles`, and `scopes` from
     `ReservationUiCatalog` and from frontend runtime parsing/domain type.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/adapters/graphql/movie-reservation-api.ts`
     - `movie-reservation-web/src/features/movie-reservations/adapters/graphql/parsers/`
     - `movie-reservation-web/src/features/movie-reservations/domain/movie-reservation.ts`
     - parser/domain tests
   - Notes: Backend schema remains unchanged.
   - Verification: Parser tests and web check pass.

9. Memoize seat-map hot path
   - Change: Use `useMemo` for grouped seat rows and selected id `Set`.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/ui/seat-map.tsx`
   - Notes: Keep the change local and simple.
   - Verification: Typecheck/build.

10. Replace frontend `.env.example` with env template convention

- Change: Remove `movie-reservation-web/.env.example`; add
  `movie-reservation-web/env_files/templates/local/local-dev.env.template`.
- Files/modules likely affected:
  - `movie-reservation-web/.env.example`
  - `movie-reservation-web/env_files/templates/local/local-dev.env.template`
  - `movie-reservation-web/README.md`
- Notes: Rendered `movie-reservation-web/env_files/local/local-dev.env` is
  already ignored by `.gitignore`.
- Verification: `git check-ignore` confirms rendered env ignored and
  template not ignored.

11. Update frontend dev script

- Change: Make `dev` delegate to `dev:local`, and make `dev:local` load
  `env_files/local/local-dev.env` via `node --env-file`.
- Files/modules likely affected:
  - `movie-reservation-web/package.json`
  - `movie-reservation-web/README.md`
- Notes: Keep `check` independent of local rendered env files.
- Verification: `npm -w movie-reservation-web run check`; optionally start
  `npm -w movie-reservation-web run dev` if the env file is rendered.

12. Add web workspace to current CI contract

- Change: Add web check to root `ci`; add separate GitHub Actions `web` job.
- Files/modules likely affected:
  - root `package.json`
  - `.github/workflows/ci.yml`
  - `docs/workflows/ci-workflow.md`
  - root `README.md`
- Notes: Document explicitly that this is the current small-repo contract and
  that `#31` owns future path/affected filtering and slower e2e strategy.
- Verification: `npm run ci` if local Docker requirements are available;
  otherwise run workspace checks and explain skipped service e2e constraints.

13. Soften Playwright README wording

- Change: Reword current frontend README so it does not claim Playwright
  reports exist today.
- Files/modules likely affected:
  - `movie-reservation-web/README.md`
- Notes: Mention future Playwright smoke/report work under #27/#31.
- Verification: Documentation review.

14. Clean up follow-up documentation

- Change: Update follow-up docs so deferred work maps to existing issues and
  new gaps are issue-ready.
- Files/modules likely affected:
  - `docs/plans/frontend-follow-up-triage.md`
  - `docs/plans/distributed-observability-demo-platform.md`
  - optionally `docs/plans/service-follow-up-tasks.md`
- Notes:
  - Keep #27 for D8 frontend verification and Playwright smoke.
  - Keep #31 for scalable CI and frontend/backend e2e strategy.
  - Expand #29 docs to mention frontend overfetch and selected-screening
    seat loading.
  - Add issue-ready follow-up text for frontend OIDC/auth hardening if not
    already covered.
  - Add issue-ready follow-up text for frontend request resilience and local
    failure demonstration if not already covered.
- Verification: Documentation review; no duplicate vague TODOs.

15. Run verification

- Change: Run relevant checks.
- Files/modules likely affected: none.
- Notes: Prefer narrow checks while iterating, then full web check. Root `ci`
  may require Docker because service `ci` includes e2e tests.
- Verification:
  - `npm -w movie-reservation-web run typecheck`
  - `npm -w movie-reservation-web test`
  - `npm -w movie-reservation-web run check`
  - `npm run ci` when local Docker/Testcontainers constraints are satisfied

## 13. Testing Strategy

- Domain unit tests:
  - catalog selection normalization;
  - screening-change detection;
  - stale selected seat filtering.
- Application unit tests:
  - reservation workflow confirms after polling and loads result;
  - polling stops after max attempts and raises a timeout-style error;
  - stale run cancellation avoids further event updates.
- Platform/API unit tests:
  - GraphQL request body includes `operationName`, query, and variables;
  - observability headers are sent;
  - dev-only bearer token behavior is enforced;
  - GraphQL errors and parser failures become `GraphqlClientError`.
- Parser tests:
  - update expected `AuthenticatedUser` shape after trimming unused fields.
- CI verification:
  - web workspace check must pass;
  - root CI docs must reflect the new current contract.

No Playwright tests are added in this pass.

## 14. Rollout / Migration Plan

This is a development branch stabilization with no deployed migration.

Incremental order:

1. Land pure helper/test changes first.
2. Wire React adapters to the helpers.
3. Update GraphQL client auth gating and tests.
4. Update env template/scripts/docs.
5. Update CI.
6. Run web checks.
7. Run root CI if local Docker/Testcontainers prerequisites are available.

Rollback:

- Revert the frontend workspace stabilization commit(s).
- CI changes are isolated to root `package.json`, `.github/workflows/ci.yml`,
  and CI docs.
- Env template changes are isolated under `movie-reservation-web/env_files`.

## 15. Risks and Mitigations

| Risk                                                          | Impact |     Likelihood | Mitigation                                                                                                                                           |
| ------------------------------------------------------------- | -----: | -------------: | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Catalog normalization accidentally clears valid selections    | Medium |         Medium | Keep normalization pure and cover preserved-selection cases in domain tests.                                                                         |
| Stale seat validation hides a backend conflict demo           |    Low |            Low | Only remove seats that do not belong to the active screening; already-reserved valid seats remain selectable until backend rejects them.             |
| Root `npm run ci` becomes too slow as the repo grows          | Medium | High over time | Document current simple contract and point to #31 for affected/path-filtered CI.                                                                     |
| Dev-only bearer token test relies on brittle Vite env mocking | Medium |         Medium | Add a small explicit env-reading seam only if needed; keep tests focused.                                                                            |
| Env script fails when rendered local env file is missing      | Medium |         Medium | README must document copying the template before `dev`; consider `--env-file-if-exists` only if explicit local profile enforcement becomes annoying. |
| Raw errors disappear from diagnostics entirely                |    Low |         Medium | Keep detailed errors in thrown objects/tests and browser console during development where useful.                                                    |
| Follow-up docs duplicate existing issues                      |    Low |         Medium | Map deferred work to #27, #28, #29, #31, and #32 where possible before adding new issue-ready text.                                                  |

## 16. Done Criteria

- Stale movie/screening selections are normalized after catalog reload.
- Stale hidden seat ids are not submitted.
- Effective screening changes clear reservation state.
- UI alerts show user-safe messages.
- `VITE_DEMO_BEARER_TOKEN` is ignored outside Vite dev mode.
- Frontend env config follows `env_files/templates` convention.
- Frontend README no longer claims Playwright exists today.
- Current CI includes a separate web job.
- Root `npm run ci` includes web check and docs explain #31 owns future CI
  scaling.
- Follow-up docs are cleaned up and mapped to existing issues where possible.
- Web workspace check passes.

## 17. Review Checklist

- [ ] Requirements are explicit
- [ ] Non-goals are explicit
- [ ] Existing code conventions were checked
- [ ] Alternatives were considered
- [ ] Security implications were reviewed
- [ ] Scalability and reliability implications were reviewed
- [ ] Testing strategy is complete
- [ ] Rollout and rollback are defined
- [ ] Implementation steps are ordered and concrete

## 18. Handoff Prompt for Implementation Agent

Copy/paste this prompt into a coding agent:

```text
Implement the plan in docs/plans/movie-reservation-web-stabilization-review-findings.md.

Constraints:
- Stay within the stabilization scope.
- Do not change the backend GraphQL schema.
- Do not add Playwright, OIDC, frontend Docker, GraphQL codegen, or request abort/timeouts in this pass.
- Do not introduce new dependencies unless implementation reality makes it unavoidable and the plan is updated first.
- Keep domain/application logic framework-free.
- Keep React adapter changes thin and backed by pure helper tests.
- Keep `VITE_DEMO_BEARER_TOKEN` local-dev only and browser-visible by documentation.
- Follow the backend env-file convention: committed templates under `env_files/templates`, ignored rendered `.env` files under `env_files/local`.
- Map deferred work to existing issues #27, #28, #29, #31, and #32 where applicable.

Relevant files/modules:
- movie-reservation-web/src/features/movie-reservations/domain/catalog-selection.ts
- movie-reservation-web/src/features/movie-reservations/domain/seat-selection.ts
- movie-reservation-web/src/features/movie-reservations/adapters/react/use-movie-catalog.ts
- movie-reservation-web/src/features/movie-reservations/adapters/react/use-reservation-workflow.ts
- movie-reservation-web/src/features/movie-reservations/application/request-reservation-workflow.ts
- movie-reservation-web/src/features/movie-reservations/adapters/graphql/movie-reservation-api.ts
- movie-reservation-web/src/features/movie-reservations/adapters/graphql/parsers/
- movie-reservation-web/src/platform/api/graphql-client.ts
- movie-reservation-web/src/features/movie-reservations/ui/seat-map.tsx
- movie-reservation-web/package.json
- movie-reservation-web/README.md
- movie-reservation-web/env_files/templates/local/local-dev.env.template
- package.json
- .github/workflows/ci.yml
- docs/workflows/ci-workflow.md
- docs/plans/frontend-follow-up-triage.md
- docs/plans/distributed-observability-demo-platform.md

Expected verification commands:
- npm -w movie-reservation-web run typecheck
- npm -w movie-reservation-web test
- npm -w movie-reservation-web run check
- npm run ci when Docker/Testcontainers prerequisites for service e2e are available
```
