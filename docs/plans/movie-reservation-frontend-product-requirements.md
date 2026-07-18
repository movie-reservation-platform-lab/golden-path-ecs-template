# Implementation Plan: Movie Reservation Frontend Product Requirements

## 1. Summary

D8 should end with a production-like movie reservation frontend, not an
observability console.

The React app should look and behave like a small customer-facing cinema booking
product:

- browse movies;
- choose a showtime;
- select seats;
- request a reservation;
- see customer-friendly pending, confirmed, rejected, and failed outcomes.

The app must still participate in the observability story by propagating trace
and correlation context, using stable GraphQL operation names, and producing
requests that can be inspected in browser network tools, Playwright reports,
Grafana, Tempo, Loki, and Prometheus. It should not display trace ids,
correlation ids, request ids, or GraphQL exchange logs as normal customer UI.

Issue #23 delivered the technical frontend baseline. The remaining D8 work in
#24 through #27 should use this document as the product and UX acceptance bar.

## 2. Goals

- Make the first screen the actual booking workflow, not a landing page and not
  a dashboard.
- Give the app a movie-specific visual identity with poster-style assets,
  showtimes, and a clear seat-selection flow.
- Keep the UI customer-facing in tone:
  - "Checking availability" instead of `PROCESSING`;
  - "Seats confirmed" instead of `CONFIRMED`;
  - "Those seats are no longer available" instead of exposing backend details.
- Keep observability as an implementation and verification contract, not as an
  application feature.
- Leave room for future product features such as recommendations and
  agent-assisted booking without showing empty tabs or placeholder controls.
- Preserve accessibility, responsive layout, loading states, error states, and
  terminal reservation states.

## 3. Non-goals

- Do not build an APM, trace explorer, log viewer, or Grafana substitute inside
  the frontend.
- Do not show trace id, correlation id, request id, raw `traceparent`,
  `tracestate`, GraphQL operation logs, or request exchange logs in normal
  customer UI.
- Do not add a generic scenario engine, demo console, or empty future tabs in
  D8.
- Do not add routing unless the booking flow has outgrown a single-page
  structure.
- Do not add backend schema fields for posters or media in D8 solely to improve
  visuals.
- Do not add recommendations, MCP, agent workflows, OIDC, service discovery, or
  fault injection as part of the D8 customer booking UI.
- A separate local/demo mode may expose agent workflows and technical
  identifiers for the distributed observability demonstration. It must be
  explicitly enabled and must not change the default customer experience.
- Do not depend on external image services for the initial visual treatment.

## 4. Current State

The current backend GraphQL API exposes the data needed for the first booking
flow:

- `movies`
- `screenings(movieId)`
- `requestReservation(input)`
- `reservationRequestStatus(id)`
- `reservationResult(requestId)`

Relevant files:

- `movie-reservation-service/schema.gql`
- `movie-reservation-service/src/presentation/graphql/movie-reservations.resolver.ts`
- `docs/workflows/graphql-reservation-query-examples.md`

Important API caveat:

- `screenings { seats }` returns auditorium seats, not a dedicated availability
  projection. A submitted reservation can still be rejected because another
  reservation already owns a requested seat. The frontend should treat rejection
  as a valid booking outcome, not as a UI bug.

The delivered `movie-reservation-web` baseline now includes:

- React/Vite workspace scaffolding and credential-free CI coverage;
- a feature-first domain/application/adapters/UI structure;
- a GraphQL request helper with runtime response parsing;
- trace/correlation/request id propagation;
- bounded reservation polling and cancellation behavior;
- movie, screening, seat, reservation, and diagnostics components.

The remaining product gap is that the baseline still behaves like a technical
demonstrator and includes a customer-visible diagnostics panel:

- it foregrounds tracing diagnostics;
- it displays trace, correlation, request, and GraphQL exchange information;
- it uses observability language as visible UI.

That was acceptable for the delivered #23 baseline, but it is not the final D8
product experience.

The observability UI already exists outside the app:

- Grafana for dashboards;
- Tempo for traces;
- Loki for structured logs;
- Prometheus for metrics;
- browser network tools and Playwright reports for frontend request inspection.

## 5. Requirements and Assumptions

### Confirmed Requirements

- The D8 frontend should feel like a customer movie booking app.
- The app should be movie-related in its product surface. Infrastructure and
  observability are part of the system, not the UI theme.
- The app should not become a mini APM.
- Observability context should still be propagated and verifiable externally.
- The first screen should show movie discovery and booking affordances, not a
  marketing page.
- Future recommendations and agent-assisted flows should extend the movie
  product experience.
- Preserve the delivered #23 technical baseline while #24 through #27 complete
  the production-like UX and verification work.

### Assumptions

- D8 can use local static poster-like assets mapped in frontend code without
  changing the GraphQL schema.
- A one-page flow is enough for the first D8 booking experience.
- Generated frontend GraphQL types are a follow-up and should not block the
  product requirements in this document.
- The authenticated user context can remain implicit or lightly represented; the
  customer app does not need an account-management surface in D8.
- Rejected reservations are useful production-like conflict outcomes and should
  be explained to the customer.

### Open Questions

- Should the UI include a short non-technical support reference on failure
  states later, or should all technical handles stay entirely outside the app?
- Should local poster assets be committed as generated image files, hand-crafted
  lightweight SVG/PNG assets, or CSS-backed poster art for D8?
- Should the first codegen follow-up commit generated artifacts or regenerate
  them during CI only?

Recommended default answers:

- Do not show support references in D8 unless a specific support workflow is
  planned.
- Use committed local poster-like assets for seeded movies if practical;
  otherwise use high-quality local CSS poster art as a short-term fallback.
- Decide generated artifact policy in the codegen follow-up.

## 6. Proposed Design

### Product Model

The D8 app should model a simple customer flow:

1. Discover movies.
2. Pick a movie.
3. Choose a showtime.
4. Select seats.
5. Submit a reservation request.
6. Wait while the system checks and reserves the seats.
7. Show a confirmed booking, unavailable seats, or a friendly failure state.

The UI should speak in customer language. Backend enum names remain useful in
TypeScript types and tests, but they should not be the primary visible copy.

### Information Architecture

Use one page with extensible sections:

```text
movie-reservation-web/
  src/
    app/
    features/
      movie-reservations/
        movie-discovery
        showtime-selection
        seat-selection
        reservation-summary
        booking-status
    shared/
      api/
      observability/
      ui/       # only after reuse is real
```

Do not add visible tabs for future recommendations or agents until those
features exist. Future expansion should fit as additional product sections, for
example:

- "Recommended for you" near movie discovery;
- optional "Need help choosing?" assistant entry point;
- contextual suggestions after a booking outcome.

### First-Screen Layout

The first viewport should show the usable booking experience:

- movie discovery area with poster-style visuals and core metadata;
- showtime selection for the chosen movie;
- seat-selection and reservation summary reachable without navigating to a
  separate debug screen.

Desktop may use a two-column or three-region layout, but the visual hierarchy
should be movie-first rather than diagnostics-first. Mobile should stack in the
natural booking order:

1. movie;
2. showtime;
3. seats;
4. reservation summary and action;
5. result.

### Visual Direction

Use a modern cinema product feel:

- real workflow first, no oversized hero section;
- movie posters or poster-like local assets;
- restrained, movie-specific palette rather than a generic observability or
  purple SaaS theme;
- clean showtime cards/buttons;
- stable seat-map dimensions;
- clear selected, available, pending, confirmed, rejected, and disabled states.

Cards are appropriate for movies, showtimes, tickets, and modal-like summaries.
Avoid cards nested inside cards and avoid turning page sections into decorative
dashboard panels.

### Reservation State Mapping

Map backend states to customer-facing copy:

| Backend State | Customer Copy               | UI Behavior                                             |
| ------------- | --------------------------- | ------------------------------------------------------- |
| idle          | Choose your seats           | Primary action disabled until showtime and seats exist. |
| submitting    | Sending reservation request | Button-local progress; prevent duplicate submission.    |
| REQUESTED     | Checking availability       | Show pending state; start or continue polling.          |
| PROCESSING    | Reserving your seats        | Show progress; continue polling.                        |
| CONFIRMED     | Seats confirmed             | Show booking confirmation details.                      |
| REJECTED      | Those seats are unavailable | Explain conflict; allow changing seats and retrying.    |
| FAILED        | Something went wrong        | Explain retry path without exposing internals.          |
| polling limit | Still checking              | Stop unbounded polling; allow manual retry/refresh.     |

### Observability Contract

The frontend should still do the important observability work:

- generate or preserve one workflow-level `X-Correlation-Id`;
- generate a fresh `X-Request-Id` per GraphQL HTTP call;
- send a valid W3C `traceparent`;
- preserve `tracestate` only when present;
- use stable GraphQL operation names;
- avoid logging or displaying secrets.

But the normal UI must not display observability internals. Verification belongs
in:

- browser network tools;
- Playwright reports;
- backend logs in Loki;
- traces in Tempo;
- dashboards in Grafana/Prometheus.

### Error And Recovery Behavior

Customer-facing errors should be specific enough to act on:

- catalog load failed: offer reload;
- showtimes empty: explain no showtimes for selected movie;
- no seats selected: disable reservation action and use helper copy;
- reservation rejected: explain seats may have been taken and allow selecting
  different seats;
- polling timeout: explain the booking is still being checked and allow retry;
- unexpected failure: offer retry without exposing stack traces or raw backend
  errors.

Developer details can be inspected through the browser console, network panel,
Playwright report, and backend observability stack.

### Accessibility And Responsiveness

The UI should use semantic HTML:

- buttons for movie, showtime, and seat selection;
- labels and accessible names for form-like controls;
- visible focus states;
- `aria-live` only for status updates where native text changes are not enough;
- text labels in addition to color for status;
- no color-only seat state distinction.

Responsive verification should cover at least:

- 320px mobile;
- 768px tablet;
- 1024px laptop;
- 1440px desktop.

Long movie titles, error messages, and generated ids that appear only in logs or
reports should not break layout. Normal app UI should not need to display long
technical ids.

## 7. Alternatives Considered

### Alternative A: Control-Room Observability UI

- Pros:
  - Makes trace and correlation ids visible during demos.
  - Reuses the spike UI almost unchanged.
  - Helps developers while wiring the frontend.
- Cons:
  - Feels like an APM/debug console, not a movie booking product.
  - Duplicates the role of Grafana, Tempo, Loki, browser devtools, and
    Playwright reports.
  - Teaches the wrong product boundary: observability internals become customer
    UI.
- Decision:
  - Rejected as the final D8 product experience. It remains temporary technical
    UI in the delivered #23 baseline and must be removed or hidden before D8
    closes. A separately enabled local/demo mode may retain technical UI for the
    distributed observability workflow.

### Alternative B: Customer Movie Booking App

- Pros:
  - Matches the domain and future product extensions.
  - Keeps observability as a real platform concern without making it the UI.
  - Gives recommendation and agent features a natural future product surface.
- Cons:
  - Requires reshaping the delivered demonstrator UI.
  - Requires separate verification discipline for observability headers and
    traces.
- Decision:
  - Recommended.

### Alternative C: Hidden Dev Diagnostics Drawer

- Pros:
  - Keeps debugging handles close to the workflow during development.
  - Can be gated by a local environment flag.
- Cons:
  - Still creates extra UI to maintain.
  - Can leak back into demos and product acceptance if the boundary is weak.
  - Less necessary when Playwright/network reports and Grafana are available.
- Decision:
  - Defer. Do not include in D8 unless a concrete debugging workflow justifies
    it.

## 8. API / Interface Changes

No backend API changes are required for this product requirement.

Expected frontend interfaces:

- one GraphQL client boundary for named operations;
- one internal observability propagation helper;
- feature components for discovery, showtimes, seat selection, reservation
  summary, and booking status;
- local poster asset mapping by stable movie id or title.

No GraphQL schema changes:

- no poster URL field in D8;
- no recommendation field in D8;
- no observability/debug field in the schema.

## 9. Data Model / Persistence Changes

None.

D8 should not add migrations, new persistence tables, or new reservation state
transitions for frontend product polish.

## 10. Security, Privacy, and Abuse Considerations

- Do not display tokens, raw authorization headers, cookies, trace headers, or
  request headers in the UI.
- Do not store trace ids, correlation ids, request ids, bearer tokens, or raw
  GraphQL payloads in durable browser storage.
- Treat all frontend-provided ids as untrusted request metadata.
- Avoid exposing detailed backend errors to customers. Show actionable product
  copy and keep technical details in logs/traces.
- Keep local poster assets static and bundled; do not fetch third-party images
  that could create privacy leaks or flaky demos.
- Preserve backend tenant and auth boundaries. The frontend must not add
  tenant/provider ids to reservation inputs.

## 11. Performance, Scalability, and Reliability Considerations

- Avoid unnecessary request waterfalls: load movies and screenings through one
  catalog flow where possible.
- Bound polling and stop polling on terminal states.
- Prevent duplicate reservation submissions while a request is in flight.
- Keep local assets reasonably sized.
- Avoid adding large UI libraries before repeated complexity justifies them.
- Keep layout stable so loading, long titles, and seat state changes do not
  cause distracting jumps.
- Treat rejected reservations as normal conflict outcomes, not retry loops.

## 12. Implementation Steps

1. Start from the delivered #23 baseline.
   - Change: Preserve the working workspace, clean-architecture boundaries,
     GraphQL client, polling behavior, and observability propagation while
     treating visible diagnostics as temporary demo UI.
   - Files/modules likely affected:
     - `docs/plans/delivered/d8a-rebase-frontend-spike.md`
     - `movie-reservation-web/**`
   - Notes: Do not rebuild the delivered baseline to satisfy stale issue text.
   - Verification:
     - Existing web checks remain green before product changes begin.

2. Reframe the app shell.
   - Change: Rename visible app framing away from "control room" and toward a
     customer booking experience.
   - Files/modules likely affected:
     - `movie-reservation-web/src/app/app.tsx`
     - `movie-reservation-web/src/features/movie-reservations/**`
     - `movie-reservation-web/src/styles.css`
   - Notes: The first screen should be usable booking UI.
   - Verification:
     - No normal UI copy presents the app as tracing, diagnostics, or control
       room software.

3. Remove customer-visible observability diagnostics.
   - Change: Remove or exclude trace id, correlation id, request id, raw
     `traceparent`, GraphQL operation log, and exchange-log panels from normal
     UI.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/ui/diagnostics-panel.tsx`
     - `movie-reservation-web/src/features/movie-reservations/ui/movie-reservation-demo.tsx`
     - `movie-reservation-web/src/platform/observability/**`
   - Notes: Keep internal propagation helpers and tests.
   - Verification:
     - UI does not display technical observability ids.
     - Network requests still include required propagation headers.

4. Add movie-specific visuals.
   - Change: Add local poster-like assets or high-quality local poster art for
     seeded movies.
   - Files/modules likely affected:
     - `movie-reservation-web/src/assets/**`
     - `movie-reservation-web/src/features/movie-reservations/**`
     - `movie-reservation-web/src/styles.css`
   - Notes: Avoid backend schema changes for D8.
   - Verification:
     - Movie cards have stable visual assets on desktop and mobile.

5. Implement customer-facing booking state copy.
   - Change: Map backend reservation states into customer copy and actions.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/ui/status-badge.tsx`
     - `movie-reservation-web/src/features/movie-reservations/ui/reservation-panel.tsx`
     - `movie-reservation-web/src/features/movie-reservations/domain/movie-reservation.ts`
   - Notes: Raw enum names can remain in TypeScript logic and tests.
   - Verification:
     - UI does not show raw `REQUESTED`, `PROCESSING`, `CONFIRMED`,
       `REJECTED`, or `FAILED` as primary customer copy.

6. Harden loading, empty, error, and terminal states.
   - Change: Add explicit states and retry paths for catalog, showtimes,
     reservation submission, polling timeout, rejection, and failure.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/**`
   - Notes: Rejection is a normal booking outcome.
   - Verification:
     - Manual or automated checks cover loading, empty, rejected, confirmed,
       failed, and polling-limit states.

7. Verify accessibility and responsive behavior.
   - Change: Ensure semantic controls, keyboard navigation, focus styles, status
     text, and responsive layouts.
   - Files/modules likely affected:
     - `movie-reservation-web/src/features/movie-reservations/**`
     - `movie-reservation-web/src/styles.css`
   - Notes: Check small and desktop viewports.
   - Verification:
     - Keyboard-only booking flow works.
     - Layout works at 320px, 768px, 1024px, and 1440px.

8. Verify observability externally.
   - Change: Add or run checks that confirm propagation without displaying
     diagnostics in UI.
   - Files/modules likely affected:
     - `movie-reservation-web/**`
     - docs/workflows as needed
   - Notes: Prefer Playwright/network inspection or documented manual browser
     checks.
   - Verification:
     - Requests include `traceparent`, `X-Correlation-Id`, and `X-Request-Id`.
     - Workflow is findable in Grafana/Tempo/Loki through backend logs/traces.

## 13. Testing Strategy

- Unit/component-level:
  - reservation status mapping returns customer-facing labels;
  - submit button disables when showtime or seats are missing;
  - polling stops on terminal states and polling limit;
  - observability helper still creates valid propagation headers.
- Browser/manual:
  - customer can complete a confirmed or rejected reservation flow;
  - keyboard navigation works across movie, showtime, seat, and submit controls;
  - mobile and desktop layouts do not overlap or overflow;
  - visible UI does not show technical observability ids.
- Observability verification:
  - browser network requests include propagation headers;
  - GraphQL operation names are stable;
  - backend logs/traces can be found in Grafana, Tempo, and Loki.
- Playwright smoke:
  - add at least one high-level browser smoke test in the D8 verification
    follow-up;
  - prefer a booking workflow test that can inspect GraphQL requests without
    displaying technical ids in the app;
  - keep Playwright HTML report and trace artifacts available for local review
    and CI failures;
  - document how to open the report or trace viewer once Playwright is added.
- Regression:
  - `npm -w movie-reservation-web run check`;
  - `npm -w movie-reservation-service run check` when backend contract safety is
    relevant;
  - `git diff --check`.

## 14. Rollout / Migration Plan

This is a local frontend product hardening path.

Rollout:

1. Use the delivered #23 baseline as the starting point.
2. Reconcile #24 and #25 with code already delivered before implementing gaps.
3. Use this document to guide #24 through #27 frontend hardening.
4. Remove or hide visible diagnostics from normal UI before closing D8.
5. Verify observability through external tools and reports.
6. Add recommendations or agent-assisted flows only after the customer booking
   baseline is solid.

Rollback:

- If customer-facing redesign causes instability, keep the ported spike as the
  technical baseline and retry the redesign in smaller feature slices.
- Revert visual assets independently from GraphQL client or propagation code.
- Keep observability propagation tests even if UI layout changes are reverted.

## 15. Risks and Mitigations

| Risk                                                  | Impact | Likelihood | Mitigation                                                                                       |
| ----------------------------------------------------- | -----: | ---------: | ------------------------------------------------------------------------------------------------ |
| The app becomes a mini APM instead of a movie product |   High |     Medium | Ban normal UI display of trace/correlation/request ids and verify observability externally.      |
| Removing diagnostics makes demos harder               | Medium |     Medium | Use browser network tools, Playwright reports, Grafana, Tempo, Loki, and clear demo runbooks.    |
| Movie visuals force backend schema changes            | Medium |        Low | Use local frontend assets for D8; defer real media fields to a catalog/recommendation follow-up. |
| Async backend states leak into customer copy          | Medium |     Medium | Centralize status-to-copy mapping and test it.                                                   |
| Seat availability semantics confuse users             | Medium |       High | Explain rejection as seats becoming unavailable and allow changing seats.                        |
| Future features create empty UI placeholders          |    Low |     Medium | Keep recommendations and agent features out of visible UI until implemented.                     |

## 16. Done Criteria

- First screen is a usable movie booking flow.
- UI has movie-specific visuals and does not look like an observability
  dashboard.
- Normal customer UI does not show trace ids, correlation ids, request ids, raw
  trace headers, or GraphQL exchange logs.
- Frontend still sends required propagation headers.
- Customer-facing state copy is used for async reservation outcomes.
- Confirmed, rejected, failed, loading, empty, and retry states are handled.
- Layout works on mobile and desktop.
- Keyboard navigation and focus states are usable.
- Future recommendation and agent features have documented extension points but
  no empty visible placeholders.

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
- [ ] The app is a movie booking product, not an observability product.
- [ ] Observability is propagated and externally verifiable.

## 18. Handoff Prompt For Implementation Agent

```text
Implement the frontend product requirements in
docs/plans/movie-reservation-frontend-product-requirements.md.

Constraints:
- Keep the app customer-facing and movie-focused.
- Do not build an APM/debug console inside the app.
- Do not show trace id, correlation id, request id, raw trace headers, or
  GraphQL exchange logs in normal UI.
- Preserve observability propagation through headers and stable GraphQL
  operation names.
- Preserve the delivered #23 technical baseline and apply this document as the
  product bar for remaining D8 work.
- Do not change the backend GraphQL schema for poster/media fields in D8.
- Use local poster-like frontend assets or local art.
- Map backend reservation states to customer-facing copy.
- Do not add recommendations, MCP, agent workflows, OIDC, service discovery, or
  fault injection in D8 UI work unless a separate plan explicitly scopes them.

Relevant files/modules:
- movie-reservation-web/**
- movie-reservation-service/schema.gql
- docs/plans/delivered/d8a-rebase-frontend-spike.md
- docs/plans/distributed-observability-demo-platform.md
- docs/workflows/local-observability.md
- docs/architecture/observability-log-contract.md

Expected verification commands:
- npm -w movie-reservation-web run check
- npm -w movie-reservation-service run check
- git diff --check

Expected manual/browser verification:
- Customer can complete a booking flow.
- Customer UI does not expose technical observability ids.
- Browser network requests include traceparent, X-Correlation-Id, and
  X-Request-Id.
- The workflow can be found in Grafana/Tempo/Loki through backend
  observability.
```
