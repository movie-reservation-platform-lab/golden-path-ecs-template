# Implementation Plan: Movie Reservation Web Clean Architecture Refactor

> Status: delivered as part of issue #23 / PR #33. Preserved as implementation
> history.

## 1. Summary

Refactor `movie-reservation-web` so the movie reservation feature has explicit
domain, application, adapter, and UI boundaries. Preserve the current demo
behavior, GraphQL operations, trace propagation, diagnostics panel, and visual
layout.

## 2. Goals

- Keep React components focused on rendering and user events.
- Keep reusable reservation rules in framework-free domain modules.
- Put workflow contracts in the feature application layer.
- Validate untrusted GraphQL response data in the API adapter before it reaches
  hooks or components.
- Avoid new dependencies unless the existing code cannot reasonably handle the
  boundary.

## 3. Non-goals

- No backend GraphQL schema changes.
- No visual redesign.
- No routing, global state library, or server-state cache library.
- No changes to the frontend observability header contract.

## 4. Current State

- `src/app/app.tsx` renders `MovieReservationDemo` directly.
- `features/movie-reservations/movie-reservation-demo.tsx` composes panels and
  controller hooks.
- `adapters/react/use-movie-catalog.ts` and
  `adapters/react/use-reservation-workflow.ts` already separate much of the
  workflow state from UI components.
- `adapters/graphql/movie-reservation-api.ts` owns GraphQL operation strings but
  relies on generic TypeScript response shapes from `requestGraphql<T>()`.
- `platform/api/graphql-client.ts` parses JSON and casts it to a generic
  `GraphqlResponse<TData>`, so the compiler believes data is valid even when
  the runtime payload may not match the expected API contract.
- `platform/observability/trace-context.ts` owns trace/correlation id creation
  and currently also exposes reservation terminal-status logic.

## 5. Requirements and Assumptions

### Confirmed Requirements

- Refactor the frontend using the frontend clean architecture guidance.
- Work in the current branch and current `movie-reservation-web` workspace.

### Assumptions

- User-visible behavior should remain unchanged.
- The current Vite/React/TypeScript stack remains the right stack.
- The local diagnostics panel is still part of the demo, not production UX.

### Open Questions

- None blocking.

## 6. Proposed Design

Use a feature-first structure:

```text
features/movie-reservations/
  domain/
  application/
  adapters/
  ui/
  platform/
```

The dependency direction is:

```text
domain <- application <- adapters/controllers <- ui/app runtime
```

Domain modules define reservation entities and pure helpers such as terminal
status checks, catalog selection, and seat selection. Application modules define
the feature-owned `MovieReservationApi` port and the request-and-poll workflow.
Adapters implement GraphQL calls, runtime response parsing, and React controller
hooks. UI modules render panels and receive data/callback props.

## 7. Alternatives Considered

### Alternative A: Keep the Current Flat Feature Folder

- Pros: Fewer path changes.
- Cons: Does not make dependencies or trust boundaries obvious.
- Decision: Rejected for this refactor because the user explicitly requested
  clean architecture.

### Alternative B: Add TanStack Query and Zod

- Pros: Strong cache/polling primitives and schema parsing.
- Cons: Adds dependencies before the app has repeated cache/polling pressure.
- Decision: Rejected for now. Manual parsers are enough for this small API
  surface and keep the learning path explicit.

### Alternative C: Feature-First Clean Boundaries

- Pros: Clear dependency direction without global abstractions.
- Cons: More files and import paths to learn.
- Decision: Recommended.

## 8. API / Interface Changes

No backend API changes. Internal frontend interfaces change by adding a
feature-local `MovieReservationApi` port and passing API implementations into
controller hooks.

## 9. Data Model / Persistence Changes

None.

## 10. Security, Privacy, and Abuse Considerations

The refactor keeps bearer tokens out of diagnostics and browser storage. Runtime
GraphQL response parsing reduces the risk of rendering malformed external data
as if it were trusted application state.

## 11. Performance, Scalability, and Reliability Considerations

Polling remains bounded and still stops on terminal statuses. API response
parsing adds small CPU overhead but improves failure clarity when the backend
contract changes.

## 12. Implementation Steps

1. Move feature files into clean-architecture folders.
   - Change: create `domain`, `application`, `adapters`, and `ui` folders.
   - Files/modules likely affected: `movie-reservation-web/src/features/movie-reservations/*`.
   - Verification: TypeScript import errors guide the updates.

2. Extract domain helpers.
   - Change: move entities and pure selection/status helpers into
     framework-free modules.
   - Files/modules likely affected: `domain/movie-reservation.ts`,
     `domain/catalog-selection.ts`, `domain/seat-selection.ts`,
     `domain/reservation-status.ts`.
   - Verification: focused Vitest tests for pure helpers.

3. Add application workflow contracts.
   - Change: define `MovieReservationApi` and move request/poll coordination
     into an application use case.
   - Files/modules likely affected: `application/movie-reservation-api.ts`,
     `application/request-reservation-workflow.ts`.
   - Verification: controller hook delegates to the use case and keeps the
     stale-run cancellation guard.

4. Validate GraphQL boundary data.
   - Change: make `requestGraphql` parse the GraphQL envelope as `unknown`,
     then require feature adapters to parse operation data.
   - Files/modules likely affected: `platform/api/graphql-client.ts`,
     `adapters/graphql/movie-reservation-api.ts`.
   - Verification: Vitest parser tests for valid and invalid payloads.

5. Update UI and controllers.
   - Change: update imports and pass view/domain types through existing props.
   - Files/modules likely affected: `ui/*.tsx`, `adapters/react/use-*.ts`,
     `app/app.tsx`.
   - Verification: web workspace `check`.

## 13. Testing Strategy

- Unit tests for pure domain helpers.
- Unit tests for API response parsing.
- Existing trace context tests stay in place.
- Run `npm -w movie-reservation-web run check`.

## 14. Rollout / Migration Plan

No rollout required. This is a source-structure and internal-boundary refactor.
If needed, rollback is reverting the frontend workspace changes.

## 15. Risks and Mitigations

| Risk                                         | Impact | Likelihood | Mitigation                                                                |
| -------------------------------------------- | -----: | ---------: | ------------------------------------------------------------------------- |
| Import churn causes broken build             | Medium |     Medium | Run TypeScript and full web check.                                        |
| Runtime parser rejects a valid backend shape | Medium |        Low | Match current resolver fields and add parser tests.                       |
| Polling cancellation regresses               | Medium |        Low | Preserve run id guard in the controller hook.                             |
| Observability propagation regresses          | Medium |        Low | Keep GraphQL operation names and `requestGraphql` header behavior stable. |

## 16. Done Criteria

- Feature modules follow clear domain/application/adapters/ui boundaries.
- GraphQL API data is parsed from `unknown` before reaching controllers.
- Components do not import API clients or workflow use cases.
- Web workspace checks pass.
