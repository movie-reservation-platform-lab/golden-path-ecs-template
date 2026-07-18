# Implementation Plan: D6 Docker Compose, Postgres, and Knex

> Status: delivered by issue #3 / PR #17. Preserved as implementation history.

## 1. Summary

Add local Postgres persistence for the movie reservation service using Docker Compose, Knex migrations, a Postgres repository adapter, and focused Testcontainers e2e coverage.

The recommended approach is to keep in-memory persistence as the default local mode, add a dedicated Postgres development profile, keep migrations explicit and schema-only, and implement Postgres behind the existing application ports. D6 should prove the durable reservation workflow without containerizing the API, introducing the full DI composition profile refactor, or adding D7 observability behavior.

## 2. Goals

- Add Docker Compose for local Postgres.
- Add Knex and `pg` as the Postgres persistence stack.
- Add schema-only migrations and explicit migration runner commands.
- Add a separate local/test seed catalog path.
- Add a Postgres implementation of both movie reservation persistence ports.
- Preserve the in-memory adapter and existing fast tests.
- Add focused Testcontainers e2e tests for the Postgres-backed workflow.
- Enforce double-confirmed-seat prevention at the database layer.
- Keep migration execution explicit and suitable for future ECS tasks or Kubernetes Jobs.
- Keep the service architecture clean: domain and application stay plain TypeScript; Knex and SQL stay in infrastructure.

## 3. Non-goals

- Do not containerize the NestJS API in D6. That is tracked as the post-D6 `Docker-1` roadmap deliverable.
- Do not implement the full service DI composition profile refactor in D6. Only add the minimal persistence-mode wiring needed for Postgres.
- Do not add RDS, ECS migration tasks, Kubernetes Jobs, or deployment automation.
- Do not add PgBouncer, HAProxy, RDS Proxy, database failover drills, or retry/failover hardening.
- Do not add D7 business/dependency readiness probing, metrics, dashboards, or a `/dependencies` endpoint.
- Do not add a dedicated reservation work queue table yet.
- Do not add generic optimistic-locking `version` columns yet.
- Do not run migrations from normal app startup.

## 4. Current State

- The service is a NestJS application in `movie-reservation-service/`.
- `movie-reservation-service/src/config.ts` parses environment variables eagerly with Zod.
- `movie-reservation-service/src/app.module.ts` wires GraphQL, health, and `MovieReservationsGraphqlModule.forRoot({ authMode })`.
- `movie-reservation-service/src/di/movie-reservations/movie-reservations-composition.module.ts` currently wires auth, in-memory repositories, the in-process processor, clocks, and ID generators.
- Application persistence ports already exist:
  - `src/application/movie-reservations/ports/movie-reservation-repository.ts`
  - `src/application/movie-reservations/ports/reservation-request-work-repository.ts`
- In-memory adapters currently live under `src/infrastructure/repositories/in-memory/`.
- The D5 processor contract already separates customer/API persistence from worker-facing persistence:
  - `MovieReservationRepository` owns catalog/request/result reads and request creation.
  - `ReservationRequestWorkRepository` owns claiming, conflict lookup, terminal transitions, and attempt history.
- Existing tests are categorized under `test/unit/**` and `test/integration/**`.
- Current Supertest/Nest API tests live under `test/integration/api/**`; future Docker/Testcontainers e2e tests should live under `test/e2e/**`.
- The current domain ID helpers accept any non-empty string. Runtime generators already use `crypto.randomUUID()` but prefix generated request/reservation IDs with readable strings.
- The current in-memory seed data uses readable IDs such as `provider-aurora`, `screening-aurora-1`, and `seat-aurora-1-a1`.
- `docs/operations/runbook.md` now documents the three-layer health model:
  - `/health`: process liveness.
  - `/ready`: platform traffic readiness.
  - business/dependency readiness: dependency health and diagnostics.

## 5. Requirements and Assumptions

### Confirmed Requirements

- In-memory remains the default persistence mode.
- D6 adds a dedicated Postgres local env file.
- Docker Compose in D6 starts Postgres only.
- Migrations are explicit and not run by the API on startup.
- Knex migrations are schema-only.
- Local/test seed data uses a separate seed path.
- The migration runner should be usable later from CI/CD, ECS one-off tasks, or Kubernetes Jobs.
- Postgres e2e tests use Testcontainers by default.
- A manual/external DB e2e mode should be possible for Docker Compose or developer-managed Postgres.
- Service-owned entity IDs should become UUIDs.
- `UserId` remains a text/string because it comes from external identity systems.
- `MovieProvider.code` is added as a human-friendly, unique provider handle.
- Auth claims require `movie_provider_id` as the authoritative UUID provider identity.
- Auth claims may include optional `movie_provider_code` for human context.
- `ActorContext` stays scoped by `movieProviderId`; provider code is not used for authorization.
- Timestamps use `timestamptz` in Postgres and ISO 8601 strings at application/API boundaries.
- Request seats and confirmed reservation seats use relational join tables.
- The confirmed-seat invariant is enforced with a unique database constraint on `(screening_id, seat_id)`.
- Reservation requests get a Postgres-owned internal sequence for FIFO claiming.
- Terminal request transition and processing-attempt recording become atomic for both in-memory and Postgres adapters.
- Unique confirmed-seat constraint races map to `REJECTED` with reason `seat-conflict`, not `FAILED`.
- Runtime Postgres mode uses one shared Knex connection pool injected into both Postgres repositories.
- D6 adds minimal explicit pool config such as `DATABASE_POOL_MIN` and `DATABASE_POOL_MAX`.

### Assumptions

- D6 can update tests, docs, seed data, and GraphQL examples to use UUID IDs.
- The service can add `knex`, `pg`, `testcontainers`, and `@testcontainers/postgresql`; `@types/pg` may be added if TypeScript needs direct `pg` types.
- The exact package versions should be selected during implementation from npm/lockfile resolution.
- UUID validation can be implemented with a small local helper without pulling a new UUID validation dependency.
- Local Postgres credentials are non-secret development values in checked-in env templates/files where appropriate.
- Production/staging secrets and RDS wiring are deferred to later deliverables.

### Open Questions

- None blocking. Exact UUID constants, migration file names, and script names can be finalized during implementation while preserving this design.

## 6. Proposed Design

### Persistence Mode

Add a minimal persistence mode setting:

```text
PERSISTENCE_MODE=in-memory | postgres
```

Default remains `in-memory`. Add a dedicated local Postgres env file, for example:

```text
movie-reservation-service/env_files/local/local-postgres.env
```

That file should set:

```text
AUTH_MODE=local-fixed-user
PERSISTENCE_MODE=postgres
DATABASE_URL=postgres://...
DATABASE_POOL_MIN=0
DATABASE_POOL_MAX=5
```

D6 should not add the broader `COMPOSITION_PROFILE` design. The post-D6 DI plan will normalize this wiring.

### Database Ownership and Migrations

Knex owns migrations. The app does not run migrations on startup.

Use a programmatic migration runner as the official platform entrypoint. Npm scripts are local wrappers, not the architecture:

```text
npm -w movie-reservation-service run db:migrate
npm -w movie-reservation-service run db:migrate:status
npm -w movie-reservation-service run db:seed:local
```

Future ECS tasks or Kubernetes Jobs should be able to run the compiled migration runner directly, for example:

```text
node dist/src/infrastructure/database/migrate.js
```

Knex CLI can still be available for developer migration creation when useful.

Migration policy:

- Write migrations forward-first.
- Include `down` only where it is genuinely safe for local/development rollback.
- Production/staging rollback is roll-forward or restore from backup/snapshot.
- Destructive migrations require a separate plan.
- Prefer expand/contract thinking for future schema changes.

### Schema Shape

Use normalized relational tables.

Planned tables:

```text
movie_providers
movies
auditoriums
screenings
seats
reservation_requests
reservation_request_seats
reservations
reservation_seats
reservation_request_processing_attempts
```

Representative schema intent:

```text
movie_providers
  id uuid primary key
  code text unique not null
  name text not null

movies
  id uuid primary key
  movie_provider_id uuid not null references movie_providers(id)
  title text not null
  rating text not null
  duration_minutes integer not null

auditoriums
  id uuid primary key
  movie_provider_id uuid not null references movie_providers(id)
  name text not null

screenings
  id uuid primary key
  movie_provider_id uuid not null references movie_providers(id)
  movie_id uuid not null references movies(id)
  auditorium_id uuid not null references auditoriums(id)
  starts_at timestamptz not null
  ends_at timestamptz not null

seats
  id uuid primary key
  movie_provider_id uuid not null references movie_providers(id)
  auditorium_id uuid not null references auditoriums(id)
  row_label text not null
  seat_number integer not null
  unique(auditorium_id, row_label, seat_number)

reservation_requests
  id uuid primary key
  sequence bigint generated always as identity
  movie_provider_id uuid not null references movie_providers(id)
  screening_id uuid not null references screenings(id)
  requested_by_user_id text not null
  status text not null
  requested_at timestamptz not null
  claimed_at timestamptz null
  processed_at timestamptz null
  updated_at timestamptz not null

reservation_request_seats
  reservation_request_id uuid not null references reservation_requests(id)
  seat_id uuid not null references seats(id)
  primary key (reservation_request_id, seat_id)

reservations
  id uuid primary key
  movie_provider_id uuid not null references movie_providers(id)
  reservation_request_id uuid not null unique references reservation_requests(id)
  screening_id uuid not null references screenings(id)
  reserved_by_user_id text not null
  confirmed_at timestamptz not null

reservation_seats
  reservation_id uuid not null references reservations(id)
  screening_id uuid not null references screenings(id)
  seat_id uuid not null references seats(id)
  primary key (reservation_id, seat_id)
  unique(screening_id, seat_id)
```

The `reservation_seats` unique constraint is the final double-confirmation guard. Multiple requests can ask for the same seat; only one confirmed reservation can own a seat for a screening.

Add useful indexes for:

- `movie_provider_id`
- `reservation_requests(status, sequence)`
- `reservation_requests(requested_by_user_id)`
- reservation/result lookup by request ID

### IDs and Human-Friendly Provider Code

Service-owned entity IDs become UUID strings in domain, GraphQL, seed data, and Postgres:

- `MovieProviderId`
- `MovieId`
- `AuditoriumId`
- `ScreeningId`
- `SeatId`
- `ReservationRequestId`
- `ReservationId`

`UserId` remains a non-empty string.

Add `MovieProvider.code`:

```ts
interface MovieProvider {
  readonly id: MovieProviderId;
  readonly code: string;
  readonly name: string;
}
```

Use code for docs, logs, seed readability, and future observability. Do not use code as the authorization boundary in D6.

### Authentication Context

Update local auth and JWT claim parsing:

```json
{
  "sub": "local-dev-user",
  "movie_provider_id": "11111111-1111-4111-8111-111111111111",
  "movie_provider_code": "aurora-silver-maple"
}
```

`movie_provider_id` is required and authoritative. `movie_provider_code` is optional and used only for human context. Add optional `movieProviderCode` to `AuthenticatedUser`, but keep `ActorContext` scoped by `movieProviderId` only.

Do not perform a database lookup during authentication to convert provider code to provider ID.

### Repository Adapters

Implement both Postgres adapters:

```text
PostgresMovieReservationRepository
PostgresReservationRequestWorkRepository
```

Both receive the same Knex instance/pool from Nest composition in Postgres mode.

`PostgresMovieReservationRepository` implements:

- provider/movie/screening/seat reads
- save reservation request plus request-seat rows
- reservation request status reads
- reservation/result reads

`PostgresReservationRequestWorkRepository` implements:

- atomic claim of the lowest-sequence `REQUESTED` request
- confirmed-seat conflict lookup
- atomic confirm/reject/fail terminal operations with processing-attempt recording
- processing-attempt reads for tests/diagnostics

Claiming should use the durable shape:

```sql
WITH next_request AS (
  SELECT id
  FROM reservation_requests
  WHERE status = 'REQUESTED'
  ORDER BY sequence ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED
)
UPDATE reservation_requests rr
SET status = 'PROCESSING',
    claimed_at = now(),
    updated_at = now()
FROM next_request
WHERE rr.id = next_request.id
RETURNING rr.*;
```

### Atomic Processing Attempts

Refine `ReservationRequestWorkRepository` so terminal operations accept the processing attempt and write it atomically with terminal state.

Example target shape:

```ts
confirmClaimedReservationRequest({
  claimedWorkItem,
  reservation,
  attempt,
});
```

```ts
rejectClaimedReservationRequest({
  claimedWorkItem,
  reason: "seat-conflict",
  attempt,
});
```

```ts
failClaimedReservationRequest({
  claimedWorkItem,
  reason: "unexpected-error",
  attempt,
});
```

The processor should no longer separately call `recordReservationRequestProcessingAttempt(...)` as part of the write path. Keep read methods for tests and diagnostics.

### Race Handling

The processor can still perform the friendly pre-check:

```text
findConflictingConfirmedReservation(...)
```

But the database unique constraint on `reservation_seats(screening_id, seat_id)` is authoritative. If confirmation loses a race and Postgres raises the known unique-constraint violation, the Postgres adapter should convert that to a rejected request with reason `seat-conflict`.

It should not be treated as `FAILED` because the business result is a normal seat conflict.

### Knex Pool Lifecycle

Runtime Postgres mode should create one shared Knex instance. Repositories should not create pools themselves.

Add minimal explicit pool configuration:

```text
DATABASE_POOL_MIN=0
DATABASE_POOL_MAX=5
```

Use small local defaults. Validate min/max with Zod.

The service should close/destroy the Knex pool on application shutdown. This is the TypeScript/Nest equivalent of owning database pool lifecycle in the web framework lifespan.

Defer:

- connection lifetime tuning
- PgBouncer compatibility
- HAProxy/RDS Proxy/RDS/Aurora failover drills
- transient retry policy
- backend identity logging

### Health and Dependency Readiness

D6 should not add a dependency probing endpoint or make `/ready` a database probe.

Record the intended model:

```text
/health
  process liveness

/ready
  platform traffic readiness

business/dependency readiness
  "Can the service currently perform its business purpose?"
```

D7 should add periodic Postgres dependency checks, metrics, and observability history. D6 validates Postgres through migrations, repository behavior, and e2e tests.

### E2E Database Setup

Add `test/e2e/**`.

Default e2e mode uses Testcontainers:

```text
npm -w movie-reservation-service run test:e2e
```

Flow:

```text
start disposable Postgres container
run migrations
seed test catalog
set PERSISTENCE_MODE=postgres and DATABASE_URL before importing app modules
start Nest app
run tests
stop container
```

External/manual DB mode uses a developer-managed database:

```text
TEST_DATABASE_URL=postgres://... npm -w movie-reservation-service run test:e2e:external
```

The test harness owns setup/reset/seed for the test database. Use `TEST_DATABASE_URL` for destructive test setup rather than plain `DATABASE_URL`.

## 7. Alternatives Considered

### Alternative A: Store Seat IDs as JSON/Array Columns

- Pros:
  - Fewer tables.
  - Mirrors the domain `seatIds` array shape.
- Cons:
  - Harder for Postgres to enforce no double-confirmed seats.
  - Awkward foreign keys and indexes.
  - More custom SQL or trigger logic.
- Decision:
  - Rejected. Use relational join tables.

### Alternative B: Dedicated Work Queue Table in D6

- Pros:
  - Cleaner later retry/lease/dead-letter separation.
  - More explicit worker mechanics.
- Cons:
  - More schema and consistency work before it is needed.
  - Current request table can serve as durable pending work.
- Decision:
  - Deferred. Keep `ReservationRequestWorkRepository` intent-shaped so a future queue/work table can be added inside the adapter.

### Alternative C: App Runs Migrations on Startup

- Pros:
  - Convenient locally.
- Cons:
  - Creates different local/production behavior if production uses jobs.
  - Multiple replicas can race.
  - Normal API runtime needs schema-change permissions.
  - Does not match future ECS/k8s migration task model.
- Decision:
  - Rejected. Migrations are explicit everywhere.

### Alternative D: Test Against Developer Compose DB Only

- Pros:
  - Fewer test dependencies.
  - Easy to inspect manually.
- Cons:
  - Local state leaks into test results.
  - CI setup is less isolated.
- Decision:
  - Rejected as the default. Use Testcontainers by default; keep external DB mode as an escape hatch.

### Alternative E: Provider Code as the Authorization Boundary

- Pros:
  - Human-readable in tokens and logs.
  - Can be globally unique.
- Cons:
  - Requires lookup/caching if internal IDs are UUID.
  - Couples authentication to database availability.
  - Can leak customer identity more easily.
- Decision:
  - Rejected for D6. Use UUID `movie_provider_id` for auth and optional `movie_provider_code` for human context.

## 8. API / Interface Changes

GraphQL IDs for service-owned entities become UUID strings.

Expected impact:

- `Movie.id`
- `Screening.id`
- `Screening.movieId`
- `Screening.auditoriumId`
- `Seat.id`
- `ReservationRequest.id`
- `ReservationRequest.screeningId`
- `ReservationRequest.seatIds`
- `Reservation.id`
- `Reservation.reservationRequestId`
- `Reservation.screeningId`
- `Reservation.seatIds`

No new GraphQL operations are required by D6.

Internal interface changes:

- Service-owned ID constructors validate UUID strings.
- `UserId` remains non-empty string.
- `MovieProvider` gains `code`.
- `AuthenticatedUser` gains optional `movieProviderCode`.
- `ActorContext` remains unchanged except its `movieProviderId` value is now UUID-shaped.
- `ReservationRequestWorkRepository` terminal methods accept processing attempts and own atomic attempt recording.
- Separate processor-path `recordReservationRequestProcessingAttempt(...)` should be removed or no longer used for terminal processing.

Configuration/interface changes:

- Add `PERSISTENCE_MODE`.
- Add `DATABASE_URL` required only in Postgres mode.
- Add `DATABASE_POOL_MIN` and `DATABASE_POOL_MAX`.
- Add local Postgres env file/template.
- Add migration/seed/e2e npm scripts.

## 9. Data Model / Persistence Changes

D6 introduces the first durable Postgres schema for movie reservations.

Key persistence decisions:

- UUID primary keys for service-owned entities.
- Text user IDs for external identity values.
- `movie_providers.code` as unique human-readable provider handle.
- `timestamptz` for DB timestamps.
- Join tables for request seats and reservation seats.
- Unique `(screening_id, seat_id)` for confirmed reservation seats.
- Internal identity/sequence column on `reservation_requests` for FIFO claiming.
- Processing attempts stored in a dedicated table.

Rollback strategy:

- Local rollback can use safe Knex `down` migrations where practical.
- Production rollback is roll-forward or restore from backup/snapshot.
- Destructive schema changes require a separate plan and should use expand/contract migration strategy.

## 10. Security, Privacy, and Abuse Considerations

- Do not commit real database credentials.
- Local Docker Compose credentials are development-only.
- `DATABASE_URL` should not be logged.
- Migration commands should print sanitized status and errors.
- Auth uses UUID `movie_provider_id` as the authoritative tenant/provider boundary.
- Optional `movie_provider_code` is useful for logs and observability, but it should not become authorization input in D6.
- Do not leak raw database errors through GraphQL.
- Postgres queries should use Knex parameterization instead of string interpolation.
- Keep local auth modes blocked in staging/production as current config already intends.
- Future production DB credentials should come from Secrets Manager/SSM or platform secret injection.
- Future migration jobs should use permissions appropriate for schema changes; normal API runtime should eventually use narrower permissions.

## 11. Performance, Scalability, and Reliability Considerations

- The database is the source of truth for request state in Postgres mode.
- Confirmed-seat uniqueness must be enforced by Postgres, not only by application checks.
- FIFO ordering uses Postgres-owned `sequence`; gaps are acceptable.
- Claiming uses row locks and `FOR UPDATE SKIP LOCKED` semantics.
- D6 does not add generic optimistic locking. Revisit for mutable catalog/admin workflows.
- D6 does not add a dedicated work queue. Revisit when retries, leases, delayed work, dead letters, or multiple worker types become concrete.
- Keep pool sizes explicit and bounded.
- Use one shared Knex pool per app process in Postgres mode.
- Close the Knex pool on shutdown.
- Do not tune failover/pooler behavior in D6; capture that for later RDS/HA hardening.
- Keep platform readiness separate from business/dependency readiness to avoid dependency outages causing platform probe flapping.

## 12. Implementation Steps

1. Add dependencies, scripts, and config shape.
   - Change: Add `knex`, `pg`, `testcontainers`, `@testcontainers/postgresql`, and `@types/pg` if needed. Add initial npm scripts for migration, seed, and e2e commands.
   - Files/modules likely affected: `movie-reservation-service/package.json`, `package-lock.json`, `movie-reservation-service/src/config.ts`, env files/templates.
   - Notes: Keep `PERSISTENCE_MODE` defaulted to `in-memory`. Require `DATABASE_URL` only for Postgres mode. Add `DATABASE_POOL_MIN/MAX`.
   - Verification: Config unit tests cover valid/invalid combinations.

2. Convert service-owned IDs to UUIDs.
   - Change: Update ID helpers so service-owned IDs validate UUID strings. Keep `UserId` as non-empty string.
   - Files/modules likely affected: `src/domain/movie-reservations/*-id.ts`, `src/domain/movie-reservations/id-utils.ts`, ID generator implementations, unit tests.
   - Notes: Runtime generated request/reservation IDs should use raw `crypto.randomUUID()` without readable prefixes.
   - Verification: Domain unit tests cover UUID acceptance/rejection.

3. Add `MovieProvider.code` and auth provider code context.
   - Change: Extend `MovieProvider` and seed data with `code`; parse optional `movie_provider_code` into `AuthenticatedUser`; keep `ActorContext` ID-only.
   - Files/modules likely affected: `src/domain/movie-reservations/movie-provider.ts`, auth domain/types, claims parser, local fixed auth manager, auth tests, seed data.
   - Notes: Update local JWT examples/docs with UUID provider ID and provider code.
   - Verification: Auth parser tests cover required UUID provider ID and optional provider code.

4. Update existing seed data, tests, and docs to UUID IDs.
   - Change: Replace readable service-owned IDs with stable UUID constants in in-memory seed data, tests, GraphQL examples, and docs.
   - Files/modules likely affected: in-memory seed data, unit/integration tests, GraphQL examples/docs.
   - Notes: Preserve human readability through provider code, names, movie titles, auditorium names, and seat row/number.
   - Verification: Existing unit and integration tests pass after expectation updates.

5. Add Knex infrastructure and migration runner.
   - Change: Add Knex config creation, runtime Knex provider utilities, programmatic migrate/status runners, and a local seed runner.
   - Files/modules likely affected: `src/infrastructure/database/**`, `knexfile.ts` if useful, package scripts.
   - Notes: The runner is the official future job entrypoint. Knex CLI may be used for migration creation.
   - Verification: Migration runner can connect to a local/test Postgres database and report status.

6. Add initial schema migration.
   - Change: Create the Postgres tables, constraints, indexes, and status checks described in this plan.
   - Files/modules likely affected: migration files under the chosen database migrations folder.
   - Notes: Migrations should be schema-only; no demo data.
   - Verification: Migration runs from an empty database during e2e setup.

7. Add local/test seed catalog.
   - Change: Add a local/test seed path that inserts the Aurora/Riverton demo catalog using UUID IDs and provider codes.
   - Files/modules likely affected: `src/infrastructure/database/seed-local.ts`, shared seed constants if extracted, docs.
   - Notes: Seeds are not for staging/production. Keep seed behavior idempotent enough for local reruns or document reset behavior clearly.
   - Verification: `db:seed:local` populates data after migrations.

8. Refine `ReservationRequestWorkRepository` for atomic attempts.
   - Change: Update terminal methods to accept processing attempts and remove the separate processor write-path attempt recording.
   - Files/modules likely affected: application port, processor, processing-attempt types, in-memory work repository, tests.
   - Notes: Preserve read method for attempt history.
   - Verification: Existing D5 processor tests pass after updates and prove attempts are recorded.

9. Update in-memory adapters for the refined contract and UUID data.
   - Change: Keep in-memory mode behavior equivalent while using UUID IDs and atomic terminal method shape.
   - Files/modules likely affected: `src/infrastructure/repositories/in-memory/**`, in-memory integration tests.
   - Notes: In-memory remains the fast fake.
   - Verification: `npm -w movie-reservation-service run test:integration`.

10. Implement Postgres repositories.

- Change: Add `PostgresMovieReservationRepository` and `PostgresReservationRequestWorkRepository`.
- Files/modules likely affected: `src/infrastructure/repositories/postgres/**`.
- Notes: Map DB rows to domain objects. Convert DB timestamps to ISO strings. Implement transaction boundaries for claim and terminal operations.
- Verification: Focused e2e tests prove catalog reads, request creation, processing, and conflict behavior.

11. Add Postgres DI wiring with shared Knex pool.

- Change: Add minimal `PERSISTENCE_MODE` branching to composition. In Postgres mode, create one shared Knex provider/pool and inject it into both Postgres repositories.
- Files/modules likely affected: `src/di/movie-reservations/movie-reservations-composition.module.ts`, token files, app/module lifecycle code if needed.
- Notes: Avoid full DI profile refactor. Close/destroy the Knex pool on app shutdown.
- Verification: Composition tests cover in-memory and Postgres provider resolution where practical.

12. Add Docker Compose Postgres.

- Change: Add root Compose configuration for a local Postgres service.
- Files/modules likely affected: `docker-compose.yml` or compose override files, `.gitignore` if local volumes/env outputs are introduced, docs.
- Notes: D6 Compose does not run the API container.
- Verification: `docker compose up -d postgres` starts local Postgres.

13. Add Testcontainers e2e harness and tests.

- Change: Add `test/e2e/**` and support utilities for Testcontainers and external DB mode.
- Files/modules likely affected: `movie-reservation-service/test/e2e/**`, `test/support/e2e/**`, `vitest` config/scripts if needed.
- Notes: Set env before importing app modules because config currently parses env at import time.
- Verification: `npm -w movie-reservation-service run test:e2e`.

14. Add focused Postgres e2e cases.

- Change: Add a capped suite:
  - catalog smoke
  - happy reservation process
  - conflict/race proof
  - optional direct adapter concurrent-claim test if e2e is awkward
- Files/modules likely affected: `test/e2e/postgres*.test.ts`, optional direct adapter test.
- Notes: Do not duplicate every in-memory repository test.
- Verification: E2E tests pass locally with Docker/Testcontainers.

15. Update docs.

- Change: Document local Postgres setup, migration/seed commands, e2e modes, migration policy, and health/readiness boundaries.
- Files/modules likely affected: `docs/operations/runbook.md`, `docs/workflows/graphql-reservation-query-examples.md`, roadmap/follow-up docs if more sequencing notes are needed.
- Notes: Include both host-npm Postgres flow and Testcontainers e2e flow.
- Verification: Docs review plus format check.

16. Run final verification.

- Change: No code change.
- Files/modules likely affected: none.
- Notes: Run narrow checks while iterating, then final checks before handoff.
- Verification:
  - `npm -w movie-reservation-service run test:unit`
  - `npm -w movie-reservation-service run test:integration`
  - `npm -w movie-reservation-service run test:e2e`
  - `npm -w movie-reservation-service run check`
  - `npm -w movie-reservation-service run ci`

## 13. Testing Strategy

Keep existing tests as the broad behavior safety net:

- Unit tests for domain and application behavior.
- Integration tests for in-memory adapters, DI composition, schema generation, and in-process API contract.

Add focused Postgres/Testcontainers e2e tests:

- Catalog smoke: seeded movies/screenings are visible to the Aurora provider.
- Happy path: request a seat, process pending work through DI, poll confirmed request/result.
- Conflict/race proof: two requests target the same screening seat; only one confirms and the other becomes `REJECTED` with `seat-conflict`.
- Optional direct adapter test: concurrent claim does not return the same request twice if this is too awkward through GraphQL.

Do not duplicate all in-memory repository tests for Postgres in D6. Expand later when bugs, workflows, or new persistence behavior justify it.

Expected test commands after implementation:

```bash
npm -w movie-reservation-service run test:unit
npm -w movie-reservation-service run test:integration
npm -w movie-reservation-service run test:e2e
npm -w movie-reservation-service run test:e2e:external
npm -w movie-reservation-service run check
npm -w movie-reservation-service run ci
```

Whether `check` includes `test:e2e` can be finalized during implementation. The important contract is that CI for D6 must run the Testcontainers e2e suite.

## 14. Rollout / Migration Plan

This is local/platform-template work only; there is no deployed production database yet.

Local rollout:

1. Start Postgres with Docker Compose.
2. Run explicit migrations.
3. Run local seed command.
4. Start service with the local Postgres env file.
5. Exercise GraphQL examples.

Example local flow:

```bash
docker compose up -d postgres
npm -w movie-reservation-service run db:migrate
npm -w movie-reservation-service run db:seed:local
npm -w movie-reservation-service run dev:local-postgres
```

Future deployment model:

```text
CI/CD starts one-off migration task/job
migration succeeds
API task/container version starts or becomes eligible for traffic
```

Future ECS D10 should reuse the same migration runner from a one-off ECS task. Future Kubernetes should use the same runner from a Job. Do not create a local-only migration behavior that differs from deployment behavior.

Rollback/removal:

- D6 rollback is a git revert before real deployment.
- Local DB cleanup is `docker compose down -v` for the local Postgres volume if data reset is needed.
- Future deployed rollback should be roll-forward or restore from backup/snapshot, not blind `down` execution.

## 15. Risks and Mitigations

| Risk                                                                      | Impact | Likelihood | Mitigation                                                                                                     |
| ------------------------------------------------------------------------- | -----: | ---------: | -------------------------------------------------------------------------------------------------------------- |
| D6 grows into API containerization, DI profile refactor, or observability |   High |     Medium | Keep those as explicit post-D6 deliverables already recorded in the roadmap                                    |
| UUID migration makes tests/docs noisy                                     | Medium |       High | Use stable UUID constants and provider code/name fields for readability                                        |
| Postgres tests become too broad and slow                                  | Medium |     Medium | Cap D6 Postgres-specific tests to focused e2e coverage and one adapter test if needed                          |
| Migration runner differs between local and future deployment              |   High |     Medium | Use one programmatic runner and wrap it with npm only for local convenience                                    |
| App accidentally runs migrations on startup                               |   High |        Low | Keep migration code in explicit runners and document startup expectations                                      |
| Double-confirmed seats slip through under race                            |   High |     Medium | Enforce unique `(screening_id, seat_id)` in `reservation_seats` and map constraint failures to `seat-conflict` |
| Terminal state and processing attempt diverge                             | Medium |     Medium | Refine work repository terminal methods so transition plus attempt is atomic                                   |
| Knex pools multiply or leak                                               | Medium |     Medium | Create one shared Knex provider in composition and close it on shutdown                                        |
| Config parsing at import time breaks e2e setup                            | Medium |     Medium | Ensure e2e sets env before importing app modules, or add a small app/config override path                      |
| Provider code gets confused with authorization identity                   |   High |     Medium | Keep `movieProviderId` authoritative in `ActorContext`; treat code as human context only                       |

## 16. Done Criteria

- Branch is linked to GitHub issue `#3`.
- In-memory remains the default persistence mode.
- Dedicated Postgres local env file exists.
- Docker Compose starts local Postgres.
- Knex migrations create the Postgres schema from an empty database.
- Local/test seed command populates the demo catalog separately from migrations.
- Service-owned IDs are UUIDs in domain, GraphQL, tests, and seed data.
- `UserId` remains a text/string identity.
- `MovieProvider.code` exists and is unique in persistence.
- Auth uses required UUID `movie_provider_id` and optional `movie_provider_code`.
- Postgres adapters implement both application persistence ports.
- Request claiming uses internal Postgres sequence and row locking.
- Terminal request transitions and processing attempts are atomic in both in-memory and Postgres adapters.
- Confirmed seat uniqueness is enforced by the database.
- Confirmed-seat unique constraint races map to `REJECTED seat-conflict`.
- Runtime Postgres mode uses one shared Knex pool and closes it on shutdown.
- Testcontainers e2e tests pass.
- Existing unit and integration tests pass.
- Docs explain local Postgres, migrations, seeds, e2e modes, and health/readiness boundaries.

## 17. Review Checklist

- [x] Requirements are explicit
- [x] Non-goals are explicit
- [x] Existing code conventions were checked
- [x] Alternatives were considered
- [x] Security implications were reviewed
- [x] Scalability and reliability implications were reviewed
- [x] Testing strategy is complete
- [x] Rollout and rollback are defined
- [x] Implementation steps are ordered and concrete

## 18. Handoff Prompt for Implementation Agent

Copy/paste this prompt into a coding agent:

```text
Implement the plan in docs/plans/d6-docker-compose-postgres-knex.md.

Constraints:
- Stay within the scope of the plan.
- Do not containerize the NestJS API in D6.
- Do not implement the full service DI composition profile refactor in D6.
- Do not add RDS, ECS migration tasks, Kubernetes Jobs, PgBouncer, HAProxy, RDS Proxy, failover drills, or D7 observability.
- Keep in-memory persistence as the default mode.
- Keep migrations explicit; do not run migrations from app startup.
- Use Knex and pg for Postgres persistence.
- Use Testcontainers for the default e2e Postgres tests.
- Keep domain and application code plain TypeScript where possible.
- Keep Knex, SQL, and database row mapping inside infrastructure.
- Preserve existing public behavior except for the intentional UUID ID shape and MovieProvider.code addition.
- If implementation reality differs from the plan, stop and update the plan or ask for approval before changing scope.

Relevant files/modules:
- movie-reservation-service/package.json
- movie-reservation-service/src/config.ts
- movie-reservation-service/src/app.ts
- movie-reservation-service/src/app.module.ts
- movie-reservation-service/src/domain/movie-reservations/*-id.ts
- movie-reservation-service/src/domain/movie-reservations/movie-provider.ts
- movie-reservation-service/src/domain/authentication/authenticated-user.ts
- movie-reservation-service/src/application/authentication/actor-context.ts
- movie-reservation-service/src/infrastructure/authentication/movie-reservation-claims-parser.ts
- movie-reservation-service/src/application/movie-reservations/ports/movie-reservation-repository.ts
- movie-reservation-service/src/application/movie-reservations/ports/reservation-request-work-repository.ts
- movie-reservation-service/src/application/movie-reservations/in-process-reservation-request-processor.ts
- movie-reservation-service/src/infrastructure/repositories/in-memory/**
- movie-reservation-service/src/infrastructure/repositories/postgres/**
- movie-reservation-service/src/infrastructure/database/**
- movie-reservation-service/src/di/movie-reservations/**
- movie-reservation-service/test/unit/**
- movie-reservation-service/test/integration/**
- movie-reservation-service/test/e2e/**
- docs/operations/runbook.md

Expected verification commands:
- npm -w movie-reservation-service run test:unit
- npm -w movie-reservation-service run test:integration
- npm -w movie-reservation-service run test:e2e
- npm -w movie-reservation-service run check
- npm -w movie-reservation-service run ci
```
