# Implementation Plan: Movie Reservation Web Orchestrator Refactor

> Status: delivered as part of issue #23 / PR #33. Preserved as implementation
> history.

## 1. Summary

Refactor `MovieReservationDemo` so it remains the page-level composer while stateful workflow logic moves into small feature-local hooks. Preserve the current UI, GraphQL operation flow, polling limits, cancellation behavior, and diagnostics exchange log.

## 2. Goals

- Reduce the size and responsibility count of `MovieReservationDemo`.
- Keep catalog loading, selection state, reservation polling, and GraphQL exchange logging easier to reason about.
- Avoid new dependencies or visual redesign.
- Keep observability headers and diagnostics behavior unchanged.

## 3. Non-goals

- No backend, GraphQL schema, or API contract changes.
- No routing, global state library, or server-state library introduction.
- No layout or styling redesign.

## 4. Current State

`movie-reservation-web/src/features/movie-reservations/movie-reservation-demo.tsx` currently owns page layout plus catalog fetch state, selected movie/screening/seats, reservation submission, bounded polling, workflow trace context, exchange history, and reset/cancellation behavior. Presentational panels are already split into separate components.

## 5. Requirements and Assumptions

### Confirmed Requirements

- Refactor the large component because it contains too many responsibilities.

### Assumptions

- The existing user-visible behavior should remain unchanged.
- The refactor should stay local to the frontend reservation feature.

### Open Questions

- None blocking.

## 6. Proposed Design

Introduce feature-local hooks:

- `useGraphqlExchangeLog` owns latest exchange and bounded exchange history.
- `useMovieCatalog` owns catalog loading and selected movie/screening state.
- `useReservationWorkflow` owns selected seats, reservation request/result state, submission, bounded polling, errors, and cancellation.

`MovieReservationDemo` will own only the trace workflow identity and compose the panels.

## 7. Alternatives Considered

### Alternative A: Keep logic inline

- Pros: Lowest file count.
- Cons: Keeps async workflow state hard to scan.
- Decision: Rejected because it does not address the reported pain.

### Alternative B: Use `useReducer`

- Pros: Can model reservation lifecycle as one state machine.
- Cons: Larger rewrite and less direct for this learning-oriented UI.
- Decision: Defer until workflow state grows further.

### Alternative C: Extract focused hooks

- Pros: Small, idiomatic React refactor with clear responsibility boundaries.
- Cons: More files and hook interfaces to read.
- Decision: Recommended.

## 8. API / Interface Changes

No external API changes. Internal hook interfaces are added inside the frontend feature folder.

## 9. Data Model / Persistence Changes

None.

## 10. Security, Privacy, and Abuse Considerations

No new secrets or storage. Diagnostics continue to display only trace/correlation/request identifiers, not auth tokens.

## 11. Performance, Scalability, and Reliability Considerations

Polling remains bounded by `maxPollAttempts` and `pollDelayMs`. The run-id cancellation guard must continue to prevent stale async requests from updating current UI state.

## 12. Implementation Steps

1. Add `useGraphqlExchangeLog`.
   - Files/modules likely affected: `movie-reservation-web/src/features/movie-reservations/adapters/react/use-graphql-exchange-log.ts`.
   - Verification: TypeScript compile.

2. Add `useMovieCatalog`.
   - Files/modules likely affected: `movie-reservation-web/src/features/movie-reservations/adapters/react/use-movie-catalog.ts`.
   - Verification: Catalog panel still receives the same data and reload handler shape.

3. Add `useReservationWorkflow`.
   - Files/modules likely affected: `movie-reservation-web/src/features/movie-reservations/adapters/react/use-reservation-workflow.ts`.
   - Verification: Reservation submit, reset, terminal status handling, and polling cancellation remain intact.

4. Slim `MovieReservationDemo`.
   - Files/modules likely affected: `movie-reservation-web/src/features/movie-reservations/movie-reservation-demo.tsx`.
   - Verification: `npm -w movie-reservation-web run check`.

## 13. Testing Strategy

Run the web workspace typecheck, tests, and build through `npm -w movie-reservation-web run check`.

## 14. Rollout / Migration Plan

No rollout needed. This is an internal structure-only frontend refactor.

## 15. Risks and Mitigations

| Risk                                | Impact | Likelihood | Mitigation                                                                 |
| ----------------------------------- | -----: | ---------: | -------------------------------------------------------------------------- |
| Stale polling updates current state | Medium |     Medium | Preserve run-id cancellation guard in the reservation hook.                |
| Trace diagnostics regress           | Medium |        Low | Keep `GraphqlExchange` logging API unchanged.                              |
| Hook interfaces hide too much state |    Low |     Medium | Return explicit named values instead of broad opaque objects where useful. |

## 16. Done Criteria

- `MovieReservationDemo` is mostly page composition.
- Stateful workflow logic lives in focused hooks.
- Existing frontend checks pass.
