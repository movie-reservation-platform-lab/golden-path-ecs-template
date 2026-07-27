# Implementation Plan: D5 In-Process Processor Contract

> Status: delivered by issue #2 / PR #16. Preserved as implementation history.

## 1. Summary

Add a production-shaped, in-process reservation request processor that claims one pending request, processes it deterministically, and records an internal processing attempt. The processor contract should expose only `processNextPendingRequest()` so tests exercise the same method a future worker loop would call.

The recommended approach is to start with high-level application tests, then add a small application processor, a separate work repository port with atomic intent-shaped operations, and in-memory work storage that models future Postgres behavior without adding Postgres, queues, timers, or worker runtimes yet.

GitHub issue: [#2 D5: Add In-Process Processor Contract](https://github.com/patex1987/golden-path-ecs-template/issues/2)

## 2. Goals

- Add a `ReservationRequestProcessor` contract with `processNextPendingRequest()`.
- Add deterministic FIFO work claiming based on internal ordering metadata. In D5 this is an in-memory monotonic `ReservationRequestSequence`.
- Keep the sequence out of the `ReservationRequest` domain model and GraphQL API, but include it in claimed work, processor results, processing attempts, and later application-owner observability for debugging. Future durable implementations may replace the exact sequence mechanism with database or queue-specific ordering metadata.
- Add a separate `ReservationRequestWorkRepository` port for worker-facing persistence operations.
- Support `REQUESTED -> PROCESSING -> CONFIRMED` when seats are available.
- Support `REQUESTED -> PROCESSING -> REJECTED` when requested seats are already taken.
- Reject the whole request on any seat conflict in D5 as a short-term processor simplification; revisit partial acceptance, alternative seats, or explicit user choice before treating this as a real customer-facing flow.
- Record internal processing attempts with sequence, timestamps, outcome, and relevant reservation/conflict ids.
- Make terminal/idempotent behavior explicit: terminal requests are not claimable and retrying when no pending work exists returns `no-pending-request`.
- Keep processing deterministic in tests by calling the production-shaped processor directly.
- Keep durable queues, worker runtimes, Postgres, and lease-based concurrency for later deliverables.

## 3. Non-goals

- No `processReservationRequestById(id)` method in D5.
- No SQS, worker process, background interval, cron loop, or transactional outbox.
- No Postgres, Knex migrations, or database transactions.
- No event sourcing, event store, Kafka, sagas, distributed locks, or read-model projectors.
- No GraphQL subscription or push notification mechanism.
- No public GraphQL mutation whose only purpose is to run the processor.
- No GraphQL exposure of processing sequence or processing attempts.
- No full production concurrency guarantee; the in-memory repository only models the contract that durable persistence will later enforce.

## 4. Current State

- `movie-reservation-service/src/domain/movie-reservations/reservation-request.ts` defines the request data shape and `createReservationRequest`.
- `movie-reservation-service/src/domain/movie-reservations/reservation-request-transitions.ts` defines the request lifecycle helpers:
  - `startProcessingReservationRequest`
  - `confirmReservationRequest`
  - `rejectReservationRequest`
  - `failReservationRequest`
- `movie-reservation-service/src/domain/movie-reservations/reservation-request-status.ts` already defines `REQUESTED`, `PROCESSING`, `CONFIRMED`, `REJECTED`, and `FAILED`.
- `movie-reservation-service/src/domain/movie-reservations/reservation.ts` is currently a data interface for confirmed reservations. There is no `createReservation()` factory yet.
- `movie-reservation-service/src/application/movie-reservations/movie-reservations.service.ts` creates new requests in `REQUESTED` state and returns immediately. It should continue doing that in D5.
- `movie-reservation-service/src/application/movie-reservations/ports/movie-reservation-repository.ts` supports read operations, `saveReservationRequest`, and `findReservationById`. It should not become the worker/work-claiming port.
- `movie-reservation-service/src/infrastructure/repositories/in-memory/in-memory-movie-reservation.repository.ts` currently owns all in-memory maps directly. D5 will split shared physical storage into an in-memory store so separate repository adapters can speak about the same data.
- `movie-reservation-service/src/di/movie-reservations/movie-reservations-composition.module.ts` wires authentication, authorization, the in-memory repository, and `MovieReservationsService`. It does not expose a processor provider, work repository, shared store token, clock, or reservation id generator.
- `movie-reservation-service/test/unit/domain/movie-reservation-domain.test.ts` already covers request validation and basic status transition rules.
- `movie-reservation-service/test/integration/api/graphql.test.ts` verifies that `requestReservation` creates a `REQUESTED` request and that clients can poll it by id. D5 should not make this test timer-dependent.
- `docs/plans/movie-reservation-platform-roadmap.md` says D5 should avoid timer-heavy tests and drive the processor deterministically.
- The local Programming KB recommends deterministic FIFO reservation processing with stable monotonic sequence values, atomic lowest-sequence claiming, and database constraints later. It also recommends deferring event sourcing and transactional outbox until their specific problems exist.

## 5. Requirements and Assumptions

### Confirmed Requirements

- Add `ReservationRequestProcessor` contract.
- Expose only `processNextPendingRequest()` in D5.
- Add an in-memory implementation for claiming and processing pending reservation requests.
- Claiming work must be atomic: claim the lowest-sequence `REQUESTED` request and transition it to `PROCESSING` as one operation.
- The FIFO sequence is internal processing metadata, not a property on `ReservationRequest` and not a GraphQL field. It is intended for operators/application owners through processing attempts, logs, traces, and metrics. Future production storage may use a different ordering primitive, but it should keep enough operator-visible metadata to debug ordering and stuck work.
- Add internal processing attempts as operational history, not compliance audit.
- Add a separate work repository port with intent-shaped methods.
- Split in-memory repositories by port while sharing one injected in-memory store instance.
- Use explicit `ReservationIdGenerator` and `Clock` dependencies for deterministic tests.
- Start implementation with high-level application tests that encode this plan's intended behavior.
- Include one deterministic GraphQL create-process-poll integration test.
- Wire the processor through application/service boundaries without introducing external queues.
- Tests cover `REQUESTED -> PROCESSING -> CONFIRMED`.
- Tests cover rejection when requested seats are already taken.
- Tests cover idempotent processing behavior for already-terminal requests.
- Tests can drive processing deterministically.
- No durable queue or worker runtime is introduced yet.
- Verification includes `npm -w movie-reservation-service test` and `npm -w movie-reservation-service run check`.

### Assumptions

- `requestReservation` should continue returning a `REQUESTED` request immediately.
- The processor should not take `ActorContext`. It is an internal application workflow that works from persisted request data and provider-scoped reservation rules, not from a caller's GraphQL identity.
- A confirmed request should create a `Reservation` record linked by `reservationRequestId`.
- A seat conflict means a confirmed reservation already exists for the same `screeningId` and at least one requested `seatId`.
- If any requested seat conflicts, the whole request is rejected in D5. This is intentionally temporary; a normal customer flow should not silently throw away all non-conflicting seats without a later product decision.
- Terminal requests are not claimable. They are skipped by the claim operation rather than reprocessed.
- `PROCESSING` requests are not reclaimed in D5. Durable claim leases/retries come later with Postgres and worker signaling.
- `FAILED` is terminal in D5. This is intentionally temporary; later worker/database phases should decide retry policy, max attempts, lease expiry, dead-letter behavior, and what failure details are safe to expose.
- Sequence assignment happens inside persistence/work storage when a request is saved. Seed requests receive sequences in constructor input order.

### Open Questions

- None blocking D5 after the planning review.
- Later product question: should reservation requests ever partially confirm non-conflicting seats? D5 explicitly rejects the whole request on any conflict.
- Later operations question: should processing attempts become a durable Postgres table, structured logs only, or both? D5 stores them in memory and keeps the fields ready for future observability.

## 6. Proposed Design

Add a new application contract under `movie-reservation-service/src/application/movie-reservations/ports/reservation-request-processor.ts`:

```ts
export interface ReservationRequestProcessor {
  processNextPendingRequest(): Promise<ReservationRequestProcessingResult>;
}
```

Use a small result union:

```ts
export type ReservationRequestProcessingResult =
  | { readonly outcome: "no-pending-request" }
  | {
      readonly outcome: "confirmed";
      readonly attempt: ReservationRequestProcessingAttempt;
      readonly reservationRequest: ReservationRequest;
      readonly reservation: Reservation;
    }
  | {
      readonly outcome: "rejected";
      readonly attempt: ReservationRequestProcessingAttempt;
      readonly reservationRequest: ReservationRequest;
      readonly reason: "seat-conflict";
    }
  | {
      readonly outcome: "failed";
      readonly attempt: ReservationRequestProcessingAttempt;
      readonly reservationRequest: ReservationRequest;
      readonly reason: "unexpected-error";
    };
```

Add a branded sequence type under `movie-reservation-service/src/domain/movie-reservations/reservation-request-sequence.ts`. Validate it as a positive safe integer. The sequence is domain vocabulary for reservation work ordering, but it is not a property on `ReservationRequest`.

Add a claimed work envelope in the application/work area:

```ts
export interface ClaimedReservationRequest {
  readonly reservationRequest: ReservationRequest;
  readonly sequence: ReservationRequestSequence;
}
```

Add internal operational history under `movie-reservation-service/src/application/movie-reservations/reservation-request-processing-attempt.ts`:

```ts
export interface ReservationRequestProcessingAttempt {
  readonly reservationRequestId: ReservationRequestId;
  readonly sequence: ReservationRequestSequence;
  readonly startedAt: string;
  readonly completedAt: string;
  readonly outcome: "confirmed" | "rejected" | "failed";
  readonly reason?: "seat-conflict" | "unexpected-error";
  readonly reservationId?: ReservationId;
  readonly conflictingReservationId?: ReservationId;
}
```

This is processing history for debugging/support and future application-owner observability. It is not a compliance audit log and is not exposed through GraphQL.

Add a separate work repository port under `movie-reservation-service/src/application/movie-reservations/ports/reservation-request-work-repository.ts`:

```ts
export interface ReservationRequestWorkRepository {
  claimNextPendingReservationRequest(): Promise<ClaimedReservationRequest | null>;

  findConflictingConfirmedReservation(input: {
    readonly screeningId: ScreeningId;
    readonly seatIds: readonly SeatId[];
  }): Promise<Reservation | null>;

  confirmClaimedReservationRequest(input: {
    readonly claimedWorkItem: ClaimedReservationRequest;
    readonly reservation: Reservation;
  }): Promise<ReservationRequest>;

  rejectClaimedReservationRequest(input: {
    readonly claimedWorkItem: ClaimedReservationRequest;
    readonly reason: "seat-conflict";
  }): Promise<ReservationRequest>;

  failClaimedReservationRequest(input: {
    readonly claimedWorkItem: ClaimedReservationRequest;
    readonly reason: "unexpected-error";
  }): Promise<ReservationRequest>;

  recordReservationRequestProcessingAttempt(
    attempt: ReservationRequestProcessingAttempt,
  ): Promise<void>;

  findReservationRequestProcessingAttemptsByRequestId(
    reservationRequestId: ReservationRequestId,
  ): Promise<readonly ReservationRequestProcessingAttempt[]>;
}
```

The application processor owns the branching decisions. The work repository owns persistence guarantees:

- `claimNextPendingReservationRequest()` atomically claims the lowest-sequence `REQUESTED` request and moves it to `PROCESSING`.
- `confirmClaimedReservationRequest()` atomically saves the reservation and marks the request `CONFIRMED`.
- `rejectClaimedReservationRequest()` moves a claimed request to `REJECTED`.
- `failClaimedReservationRequest()` moves a claimed request to `FAILED`.
- `recordReservationRequestProcessingAttempt()` stores internal processing history.

Add `createReservation()` in `movie-reservation-service/src/domain/movie-reservations/reservation.ts`. It should enforce reservation validity independently, including non-empty and non-duplicated `seatIds`, even though `ReservationRequest` already enforces similar rules.

Add explicit application dependencies:

- `ReservationIdGenerator` port for creating `ReservationId` values.
- `Clock` port for `nowIsoString()`.
- In-memory/local implementations for production-like local use.
- Fixed/fake implementations in tests.

In-memory infrastructure should split adapters while sharing physical storage:

```text
movie-reservation-service/src/infrastructure/repositories/in-memory/
  in-memory-movie-reservation.store.ts
  in-memory-movie-reservation.repository.ts
  in-memory-reservation-request-work.repository.ts
```

`InMemoryMovieReservationStore` owns maps, the next sequence counter, seed data, reservations, and processing attempts. Treat it as the fake database for D5: multiple repositories can speak about the same underlying data without turning one repository into a god object. This mirrors real systems where one database is accessed through multiple focused repositories, and it also resembles control-plane/data-plane designs where one actor creates desired state and another actor reads or processes that state.

D5 still runs the processor in the service process. A later durable phase can split this into a control-plane GraphQL API and a data-plane worker: the API creates reservation requests and exposes status/result reads, while the worker claims pending requests, confirms/rejects/fails them, handles retries or dead-letter behavior, and emits operator observability. The shared database remains the source of truth; queues should signal work rather than own reservation state.

`InMemoryMovieReservationRepository` implements `MovieReservationRepository`. `InMemoryReservationRequestWorkRepository` implements `ReservationRequestWorkRepository`. Both adapters receive the same store instance through DI.

Processor flow:

1. Call `claimNextPendingReservationRequest()`.
2. If no work is available, return `{ outcome: 'no-pending-request' }` and record no attempt.
3. Capture `startedAt` from `Clock`.
4. Look for a conflict with `findConflictingConfirmedReservation(...)`.
5. If conflict exists, reject the claimed request, capture `completedAt`, record a rejected attempt with `conflictingReservationId`, and return `rejected`.
6. If no conflict exists, create a `Reservation` with `createReservation()`, `ReservationIdGenerator`, and `Clock`; confirm the claimed request atomically with the reservation; record a confirmed attempt with `reservationId`; return `confirmed`.
7. If an unexpected error occurs after a successful claim, mark the request `FAILED`, record a failed attempt when possible, and return `failed`. D5 does not automatically retry this request.
8. Errors before claim, or errors while marking failed/recording the failed attempt, may throw because no reliable state transition or history record could be completed.

Keep GraphQL behavior stable. `requestReservation` still returns `REQUESTED`. Add one deterministic integration test that creates a request through GraphQL, calls `processNextPendingRequest()` through DI, then polls `reservationRequest` and observes the updated status.

## 7. Alternatives Considered

### Alternative A: Confirm Inside `requestReservation`

- Pros: Smallest user-visible behavior change; no separate processor surface.
- Cons: Hides the asynchronous workflow this deliverable is meant to teach, makes polling less meaningful, and does not create a contract a future worker can implement.
- Decision: Rejected.

### Alternative B: Add a Timer-Based Background Processor

- Pros: Looks closer to a running worker from the outside.
- Cons: Makes tests slower and flaky, creates lifecycle/shutdown concerns, and conflicts with the roadmap instruction to drive processing deterministically.
- Decision: Rejected for D5.

### Alternative C: Add `processReservationRequestById(id)`

- Pros: Convenient for deterministic tests and manual debugging.
- Cons: Adds a method that is not the production-shaped worker contract. Tests should use the same work-claiming path production will use.
- Decision: Rejected for D5.

### Alternative D: Add an Application Processor Contract and Work Repository

- Pros: Keeps the workflow explicit, testable, and aligned with future worker/queue adapters. It also keeps NestJS as composition wiring instead of putting business logic in resolvers.
- Cons: Requires new types, a work repository port, and shared in-memory storage.
- Decision: Recommended.

### Alternative E: Extend `MovieReservationRepository` Instead

- Pros: Fewer ports and fewer files.
- Cons: Mixes normal API read/write concerns with worker claiming, processing attempts, and atomic workflow persistence.
- Decision: Rejected. Use a separate `ReservationRequestWorkRepository`.

### Alternative F: Use Event Sourcing or Transactional Outbox Now

- Pros: Event sourcing gives replayable history; outbox solves atomic state change plus external publication.
- Cons: D5 has no external publication requirement and no durable database yet. These patterns solve future problems, not the current in-process contract.
- Decision: Rejected for D5. Mention outbox again when Postgres and queue signaling exist.

## 8. API / Interface Changes

Internal TypeScript interfaces:

- Add `ReservationRequestProcessor` with `processNextPendingRequest()`.
- Add `ReservationRequestProcessingResult`.
- Add `ReservationRequestWorkRepository`.
- Add `ClaimedReservationRequest`.
- Add `ReservationRequestProcessingAttempt`.
- Add branded `ReservationRequestSequence`.
- Add `ReservationIdGenerator`.
- Add `Clock`.
- Add `createReservation()` factory.

Nest DI:

- Add `RESERVATION_REQUEST_PROCESSOR`.
- Add `RESERVATION_REQUEST_WORK_REPOSITORY`.
- Add `IN_MEMORY_MOVIE_RESERVATION_STORE`.
- Add tokens for `ReservationIdGenerator` and `Clock` if they are bound through DI.

GraphQL:

- No required schema change for D5.
- No processing sequence field.
- No processing attempts field.
- Existing polling behavior should observe status changes after the processor runs.

Commands:

- No new npm commands.

Events/queues:

- None in D5.

## 9. Data Model / Persistence Changes

No durable schema changes.

In-memory persistence changes:

- Move map ownership into `InMemoryMovieReservationStore`.
- Store reservation requests together with internal sequence metadata.
- Assign sequence values when `saveReservationRequest()` persists a request.
- Assign seed request sequences in constructor input order.
- Claim the lowest-sequence `REQUESTED` request and transition it to `PROCESSING` atomically.
- Store updated reservation requests after processing transitions.
- Store newly confirmed reservations.
- Store processing attempts.
- Detect conflicts against confirmed reservations in the same screening.
- Avoid duplicate reservations for the same `reservationRequestId`.

Future Postgres compatibility:

- Ordering metadata should become database- or queue-owned. A Postgres implementation might use a `bigint GENERATED ALWAYS AS IDENTITY` column, an explicit sequence, or `created_at` plus an id tie-breaker.
- Claim should map to a transaction/statement that locks or updates the oldest eligible `REQUESTED` request and returns it as `PROCESSING`.
- Confirmation should save the reservation and mark the request `CONFIRMED` in one transaction.
- Seat conflict prevention should eventually rely on database-backed guarantees such as transaction plus unique/exclusion constraints.
- Transactional outbox should be considered later when reservation state changes must be atomically published to a queue or event bus.

Rollback:

- Since there is no durable migration, rollback is a git revert of the D5 code and tests.

## 10. Security, Privacy, and Abuse Considerations

- The processor is an internal application workflow, not a caller-authorized API.
- Do not expose a public GraphQL "process request" mutation.
- Do not accept `movieProviderId`, `userId`, sequence values, processing outcomes, or privileged flags from GraphQL input.
- Tenant isolation still matters inside the workflow: reservations created from a request must preserve the request's `movieProviderId`, `screeningId`, `seatIds`, and `requestedByUserId`.
- Processing sequence and attempts are operational metadata. They should stay out of the customer-facing GraphQL contract in D5, but they are appropriate for application-owner observability such as structured logs, traces, metrics, and support/debug views.
- Avoid logging full tokens or secrets. D5 does not need additional token handling.
- Normal seat conflicts should become `REJECTED`, not uncaught technical errors.

## 11. Performance, Scalability, and Reliability Considerations

- In-memory maps are acceptable for D5 and local tests, but they do not provide cross-process safety.
- FIFO ordering uses an internal monotonic sequence. It does not need to be gapless.
- The claim operation should process at most one request per call.
- `processNextPendingRequest()` returns `no-pending-request` when nothing is claimable.
- Terminal requests and `PROCESSING` requests are not claimable in D5.
- Conflict detection can scan in-memory reservations for now. The later database implementation should use indexes and uniqueness constraints.
- Idempotent retry behavior comes from claim semantics: already-terminal requests are skipped because only `REQUESTED` work can be claimed.
- Avoid timer-based loops in the Nest app. Timers introduce shutdown, backoff, duplicate work, and test flakiness concerns that belong in a later worker deliverable.
- Processing attempts provide an internal trail for debugging sequence/order problems until structured observability arrives.

## 12. Implementation Steps

1. Add high-level application tests first.
   - Change: Create tests that directly construct the shared in-memory store, repositories, fixed clock/id generator, and processor.
   - Files/modules likely affected: `movie-reservation-service/test/unit/application/reservation-request-processor.test.ts`.
   - Notes: Tests should call only `processNextPendingRequest()`. Cover FIFO confirmation, conflict rejection, no pending work, no duplicate terminal side effects, and processing attempt records.
   - Verification: Focused test run should initially fail.

2. Add domain vocabulary and reservation factory.
   - Change: Add branded `ReservationRequestSequence` and `createReservation()`.
   - Files/modules likely affected:
     - `movie-reservation-service/src/domain/movie-reservations/reservation-request-sequence.ts`
     - `movie-reservation-service/src/domain/movie-reservations/reservation.ts`
     - `movie-reservation-service/test/unit/domain/movie-reservation-domain.test.ts`
   - Notes: `ReservationRequestSequence` is not added to `ReservationRequest`. `createReservation()` validates non-empty and non-duplicated seats.
   - Verification: Domain unit tests pass.

3. Add application contracts and processing types.
   - Change: Add processor, work repository, claimed work, processing result, processing attempt, clock, and reservation id generator contracts.
   - Files/modules likely affected:
     - `movie-reservation-service/src/application/movie-reservations/ports/reservation-request-processor.ts`
     - `movie-reservation-service/src/application/movie-reservations/ports/reservation-request-work-repository.ts`
     - `movie-reservation-service/src/application/movie-reservations/ports/clock.ts`
     - `movie-reservation-service/src/application/movie-reservations/ports/reservation-id-generator.ts`
     - `movie-reservation-service/src/application/movie-reservations/reservation-request-processing-attempt.ts`
   - Notes: Do not create `common`, `shared`, or `utils` folders.
   - Verification: Typecheck once implementation begins using the contract.

4. Split in-memory storage from repository adapters.
   - Change: Move map ownership and seed data into `InMemoryMovieReservationStore`; adapt the existing repository to use the store.
   - Files/modules likely affected:
     - `movie-reservation-service/src/infrastructure/repositories/in-memory/in-memory-movie-reservation.store.ts`
     - `movie-reservation-service/src/infrastructure/repositories/in-memory/in-memory-movie-reservation.repository.ts`
     - existing in-memory repository tests
   - Notes: Preserve existing behavior and seed data. Seed request sequences follow constructor input order.
   - Verification: Existing repository and GraphQL tests continue passing after adaptation.

5. Implement the in-memory work repository.
   - Change: Add `InMemoryReservationRequestWorkRepository` implementing the work repository port over the shared store.
   - Files/modules likely affected:
     - `movie-reservation-service/src/infrastructure/repositories/in-memory/in-memory-reservation-request-work.repository.ts`
     - `movie-reservation-service/test/integration/infrastructure/in-memory-reservation-request-work.repository.test.ts` if repository behavior needs isolated coverage
   - Notes: Claim lowest-sequence `REQUESTED` work atomically. Confirmation saves reservation and marks request `CONFIRMED` in one operation.
   - Verification: Processor tests should prove the behavior; add repository tests for hard-to-diagnose claim/atomic cases.

6. Implement explicit id/time infrastructure.
   - Change: Add runtime implementations for `ReservationIdGenerator` and `Clock`, plus test fakes near tests.
   - Files/modules likely affected:
     - `movie-reservation-service/src/infrastructure/...`
     - `movie-reservation-service/test/...`
   - Notes: Keep implementations small and movie-reservation-scoped. Avoid generic shared folders.
   - Verification: Processor tests assert exact reservation ids and timestamps.

7. Implement the in-process processor.
   - Change: Add `InProcessReservationRequestProcessor`.
   - Files/modules likely affected: `movie-reservation-service/src/application/movie-reservations/in-process-reservation-request.processor.ts`.
   - Notes: Use existing request transition helpers and new `createReservation()`. Do not assign statuses manually.
   - Verification: High-level processor tests pass.

8. Wire the processor through Nest composition.
   - Change: Add tokens and providers for the shared store, normal repository, work repository, processor, clock, and reservation id generator.
   - Files/modules likely affected:
     - `movie-reservation-service/src/di/movie-reservations/movie-reservation.tokens.ts`
     - `movie-reservation-service/src/di/movie-reservations/movie-reservations-composition.module.ts`
     - `movie-reservation-service/test/integration/di/movie-reservations-composition.module.test.ts`
   - Notes: Both repositories must receive the same store instance.
   - Verification: DI integration test resolves the processor and proves repository/processor share state.

9. Add deterministic GraphQL process-then-poll coverage.
   - Change: Create a request through GraphQL, call `processNextPendingRequest()` from DI, then poll the request by id.
   - Files/modules likely affected: `movie-reservation-service/test/integration/api/graphql.test.ts`.
   - Notes: Keep this deterministic. Do not sleep or wait for background work.
   - Verification: Test observes status change to `CONFIRMED`.

10. Run service verification.

- Change: Run targeted tests while iterating, then the full service check.
- Files/modules likely affected: none.
- Verification:
  - `npm -w movie-reservation-service test`
  - `npm -w movie-reservation-service run check`

## 13. Testing Strategy

- High-level application tests come first and encode the plan before implementation details are filled in.
- Processor application tests use direct construction with the shared in-memory store, separate repositories, fixed clock, and fixed reservation id generator.
- Domain unit tests cover `ReservationRequestSequence` validation and `createReservation()` invariants.
- Repository tests are added only for claim/atomic behavior that processor tests do not diagnose clearly.
- DI integration tests prove `MovieReservationsCompositionModule` resolves the processor and injects one shared store into both repositories.
- GraphQL integration tests include one deterministic create-process-poll workflow.
- Regression cases:
  - Lowest-sequence pending request is claimed first.
  - Requested request becomes confirmed and creates a reservation.
  - Requested request becomes rejected when any selected seat is already reserved for the same screening.
  - Rejected attempt includes `conflictingReservationId`.
  - Confirmed attempt includes `reservationId`.
  - Confirmed, rejected, failed, and processing requests are not claimed by later processor calls.
  - Running with no pending work returns `no-pending-request` and records no attempt.
  - Cross-screening reservations for the same seat id do not conflict unless the screening also matches.
  - GraphQL-created request and processor share the same in-memory state through DI.

## 14. Rollout / Migration Plan

- This is an internal service-code change with no durable data migration.
- Keep GraphQL's `requestReservation` response behavior stable: newly requested reservations still start as `REQUESTED`.
- Merge D5 behind tests only; there is no feature flag needed because no public processing endpoint is added.
- Future rollout path:
  - D6 can implement the same repository/processor behavior with Postgres sequence values, transactions, and constraints.
  - D7 can emit sequence, request id, outcome, reason, and duration as structured logs/traces/metrics.
  - D11 can add worker signaling and call the same processor contract from a worker entrypoint.
- Rollback is a git revert of the D5 branch.

## 15. Risks and Mitigations

| Risk                                                    | Impact | Likelihood | Mitigation                                                                                                |
| ------------------------------------------------------- | -----: | ---------: | --------------------------------------------------------------------------------------------------------- |
| Processor logic leaks into GraphQL resolver             | Medium |        Low | Keep processor as application service and keep resolver behavior unchanged                                |
| In-memory claim semantics do not map to Postgres        |   High |     Medium | Model claim as one work repository operation that transitions lowest-sequence `REQUESTED` to `PROCESSING` |
| Confirmation writes split request and reservation state |   High |     Medium | Use one atomic `confirmClaimedReservationRequest()` operation                                             |
| Duplicate reservations are created on retry             |   High |     Medium | Only claim `REQUESTED` work and prevent duplicate reservation per request                                 |
| Seat conflict logic is incomplete                       |   High |     Medium | Test same-screening conflicts and cross-screening non-conflicts                                           |
| Sequence is mistaken for customer-facing API data       | Medium |     Medium | Keep sequence out of GraphQL and `ReservationRequest`; expose it only in work/result/attempt internals    |
| Processing attempts are mistaken for compliance audit   | Medium |        Low | Name them processing attempts and document that they are operational history only                         |
| Shared in-memory store is accidentally duplicated in DI |   High |     Medium | Add DI test proving GraphQL-created work can be processed by the processor                                |
| Timer-based processing makes tests flaky                | Medium |     Medium | Do not add background loops in D5; tests call processor directly                                          |
| Generated ids/timestamps make tests brittle             |    Low |     Medium | Inject `ReservationIdGenerator` and `Clock` fakes in tests                                                |

## 16. Done Criteria

- Branch is linked to GitHub issue `#2`.
- `ReservationRequestProcessor` exposes only `processNextPendingRequest()`.
- High-level application tests were written before implementation.
- `ReservationRequestWorkRepository` exists as a separate port with intent-shaped methods.
- In-memory repositories are split by port and share one injected store instance.
- FIFO work claiming uses internal `ReservationRequestSequence` metadata.
- `ReservationRequestSequence` is not on `ReservationRequest` and is not exposed through GraphQL.
- `createReservation()` exists and enforces reservation invariants.
- Processing attempts are recorded internally with sequence, timestamps, outcome, and relevant ids.
- DI composition exports a processor provider/token and wires the shared store correctly.
- Tests cover confirmation, rejection due to taken seats, FIFO claiming, no-pending behavior, and processing attempts.
- One GraphQL integration test proves create-process-poll behavior deterministically.
- No durable queue, worker runtime, Postgres, event sourcing, outbox, or timer loop is introduced.
- `npm -w movie-reservation-service test` passes.
- `npm -w movie-reservation-service run check` passes.

## 17. Review Checklist

- [x] Requirements are explicit.
- [x] Non-goals are explicit.
- [x] Existing code conventions were checked.
- [x] Alternatives were considered.
- [x] Security implications were reviewed.
- [x] Scalability and reliability implications were reviewed.
- [x] Testing strategy is complete.
- [x] Rollout and rollback are defined.
- [x] Implementation steps are ordered and concrete.

## 18. Handoff Prompt for Implementation Agent

Copy/paste this prompt into a coding agent:

```text
Implement the plan in docs/plans/d5-in-process-processor-contract.md.

Constraints:
- Stay within the scope of the plan.
- Start with the high-level application tests described in section 12.
- Do not introduce new dependencies.
- Do not add processReservationRequestById(id).
- Do not add timers, background loops, worker runtimes, SQS, Postgres, event sourcing, or transactional outbox.
- Preserve existing GraphQL requestReservation behavior: it creates REQUESTED and returns immediately.
- Keep ReservationRequestSequence out of ReservationRequest and GraphQL.
- Keep sequence visible in claimed work, processor results, and processing attempts.
- Use separate repository ports over a shared in-memory store.
- If implementation reality differs from the plan, stop and update the plan or ask for approval before changing scope.

Relevant files/modules:
- movie-reservation-service/src/domain/movie-reservations/reservation.ts
- movie-reservation-service/src/domain/movie-reservations/reservation-request.ts
- movie-reservation-service/src/domain/movie-reservations/reservation-request-sequence.ts
- movie-reservation-service/src/application/movie-reservations/
- movie-reservation-service/src/application/movie-reservations/ports/
- movie-reservation-service/src/infrastructure/repositories/in-memory/
- movie-reservation-service/src/di/movie-reservations/
- movie-reservation-service/test/unit/application/
- movie-reservation-service/test/unit/domain/
- movie-reservation-service/test/integration/di/
- movie-reservation-service/test/integration/api/

Expected verification commands:
- npm -w movie-reservation-service test
- npm -w movie-reservation-service run check
```
