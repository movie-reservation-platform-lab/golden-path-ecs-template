# Architecture Decisions

This file records current architectural direction and the tradeoffs behind it.

---

## ADR 001: Use NestJS For The TypeScript Service

Status: accepted.

### Decision

Use NestJS as the primary TypeScript backend framework in `movie-reservation-service/`.

### Reason

The immediate learning goal is NestJS. Nest also gives useful structure for a platform-style service:

- modules for boundaries
- dependency injection for providers
- controllers for REST endpoints
- resolvers for GraphQL endpoints
- testing utilities for app/module setup

### Tradeoff

NestJS has more framework concepts than a minimal Fastify or Express app. That is acceptable here because learning those concepts is part of the project goal.

---

## ADR 002: Keep Health Checks As REST Endpoints

Status: accepted.

### Decision

Expose `/health` and `/ready` as plain HTTP endpoints.

### Reason

ECS target groups, Kubernetes probes, Docker Compose checks, and humans can all use simple HTTP paths easily.

### Tradeoff

This means the service has both REST and GraphQL. That is fine: health endpoints are operational boundaries, while GraphQL is a business API boundary.

---

## ADR 003: Use Code-First GraphQL Initially

Status: accepted.

### Decision

Use NestJS code-first GraphQL for movie reservation operations.

### Reason

Code-first GraphQL is useful for learning how TypeScript classes, decorators, and runtime metadata interact. It keeps the initial schema close to the service code.

### Tradeoff

GraphQL schema-first can be better when the schema is the main contract shared across teams. Start code-first for learning. Revisit schema-first if multiple clients or teams depend on the schema later.

---

## ADR 004: Build Docker Compose, k3d, And ECS Paths

Status: proposed.

### Decision

Support three runtime targets over time:

- Docker Compose
- k3d Kubernetes
- ECS/Fargate

### Reason

Each target teaches a different platform concern:

- Docker Compose teaches local developer experience.
- k3d teaches Kubernetes primitives locally.
- ECS teaches AWS container operations and CDK automation.

### Tradeoff

Supporting three paths adds maintenance cost. Keep the app contract common across all three: container, port, health path, config, secrets, telemetry.

---

## ADR 005: Standardize On OpenTelemetry For Traces And Metrics

Status: accepted.

### Decision

Use OpenTelemetry as the common observability contract for traces and metrics.
Keep application logs as structured JSON on stdout.

### Reason

OpenTelemetry can work across Node, Python, Docker Compose, Kubernetes, and
ECS. It gives a shared vocabulary for traces, metrics, resource attributes, and
W3C propagation. Logs stay on stdout because that is the least painful path for
ECS, CloudWatch, local Docker logging, and later Loki collection.

### Tradeoff

OpenTelemetry setup can feel complex early. Add it incrementally: start with
local traces and bounded business metrics, keep logs as JSON, and evolve
collector pipelines per runtime.

---

## ADR 006: Keep External Apps Independent

Status: accepted.

### Decision

Do not merge `yoga-studio-api` or `python-agent-with-idp` into this repository early.

### Reason

The platform should learn to consume independently owned apps. That is closer to real platform engineering than making one monorepo before the platform contract is clear.

### Tradeoff

Local orchestration will need paths to external repos. That is acceptable for a personal learning platform and can later be replaced by image references or app registry metadata.

---

## ADR 007: Use Movie Reservations As The Learning Domain

Status: accepted.

### Decision

Evolve the generic booking-sync domain into a movie reservation workflow.

### Reason

Movie reservations make the platform use case easier to understand:

- movies and screenings give the frontend something concrete to display
- seat selection creates a natural conflict scenario
- reservation requests create a natural async command/status flow
- confirmed reservations give the query side a clear final resource

This keeps the product small while making GraphQL, CQRS-style APIs, persistence, async work, and observability feel connected.

### Tradeoff

Renaming the existing booking code creates short-term churn. That is acceptable because the current booking-sync shape is still early and in-memory.

---

## ADR 008: Start Async GraphQL With Polling Before Subscriptions

Status: accepted.

### Decision

Implement `requestReservation` plus `reservationRequestStatus(id)` polling before adding GraphQL subscriptions.

### Reason

Polling teaches the important state model first:

- the mutation accepts a command
- the request gets a stable id
- the request status changes over time
- the client checks status until completion

Subscriptions can be added later after the states, persistence, and processing behavior are clear.

### Tradeoff

Polling is less realtime than subscriptions. That is acceptable for the first implementation because it avoids WebSocket transport, connection lifecycle, scaling, and load balancer concerns too early.

---

## ADR 009: Run Database Migrations Explicitly

Status: accepted.

### Decision

Use Knex migrations for Postgres and run them as an explicit operational step. Do not hide schema migration inside normal application startup.

### Reason

Explicit migrations teach a real deployment concern:

- local Docker Compose can run migrations against local Postgres
- ECS can run a one-off migration task before the API uses the new schema
- migration logs and failures are visible as operational events
- app startup remains focused on serving traffic

### Tradeoff

This adds a deployment step. That is acceptable because schema changes are operationally important and should be visible.

---

## ADR 010: Keep ECS As The Primary AWS Path Before EKS

Status: accepted.

### Decision

Build ECS/Fargate first, then add k3d/Kubernetes as a second runtime target. Do not jump directly to EKS.

### Reason

The purpose of the repository is to learn TypeScript, CDK, ECS/Fargate, and platform defaults. ECS is the primary AWS path. k3d is still valuable because it teaches Kubernetes concepts locally while reusing the same application contract.

### Tradeoff

The Kubernetes infrastructure will be different from ECS. That is the point: the app should stay portable while the platform layer adapts the runtime.

---

## ADR 011: Use Movie Provider Id As The Initial Tenant Boundary

Status: accepted.

### Decision

Use `movieProviderId` on authenticated users and tenant-scoped movie reservation resources as the current tenant boundary.

### Reason

The service domain is a movie reservation platform, and the tenant-like owner is the movie provider or cinema operator. A domain-specific identifier keeps application code concrete: users list movies, screenings, reservations, and requests for their movie provider.

At this stage, adding both `tenantId` and `movieProviderId` would imply two separate ownership concepts that do not yet exist.

### Tradeoff

`movieProviderId` is less generic than `tenantId`, but it is clearer for the current domain. Introduce a separate generic tenant id only if platform tenancy and movie-provider ownership diverge, for example if one tenant owns multiple providers, billing/audit tenancy differs from provider ownership, or shared platform middleware needs a domain-neutral tenant contract.

---

## ADR 012: Use Explicit Knex Migrations For Service-Owned Postgres Schema

Status: accepted.

### Decision

Use Knex and `pg` for the movie reservation service's Postgres persistence.
Keep migrations explicit and schema-only: the API process must not run
migrations during normal startup. Local/demo catalog data is seeded through a
separate command.

### Reason

This keeps local development aligned with future ECS one-off tasks and
Kubernetes Jobs: one migration entrypoint advances the schema before API tasks
serve traffic. It also keeps database-specific code in infrastructure adapters
while domain and application code stay plain TypeScript.

### Tradeoff

Developers must run migrations and seeds explicitly when using Postgres mode.
That is a little less convenient than app-start migrations, but it avoids
replica races and avoids teaching the normal API runtime to own schema-change
permissions.

---

## ADR 013: Split Reservation Worker Retry Budgets By Failure Type

Status: accepted.

### Decision

Track two reservation worker retry budgets:

- `lease_timeout_count`, bounded by `RESERVATION_WORKER_MAX_LEASE_TIMEOUTS`
- `transient_failure_count`, bounded by
  `RESERVATION_WORKER_MAX_TRANSIENT_FAILURES`

Lease timeouts and transient processor failures are both retryable, but they
mean different things and should not share one counter.

### Reason

A lease timeout means a worker claimed a reservation request and stopped proving
ownership before writing a terminal result. That can happen when:

- an ECS task is killed during deploy or scale-in
- the Node process crashes
- the container is OOM-killed
- the event loop is blocked long enough to miss heartbeats
- CPU throttling or overload delays heartbeat timers
- Postgres restarts or failover breaks the active connection or transaction
- a future database or external dependency call hangs past the lease

A transient processor failure means the worker is alive, caught a retryable
processing failure, recorded it, and released the request for another attempt.
D6.1 uses `unexpected-error` as a temporary coarse retryable bucket because no
specific transient dependency failures exist yet. Later phases should classify
specific retryable failures such as deadlocks, serialization failures,
connection resets, dependency rate limits, and temporary 503 responses.

Business outcomes are not transient failures. Seat conflicts, invalid seat
selection, missing screenings, cross-provider access, authorization failures,
and future definitive payment or provider rejections should not consume the
transient failure retry budget.

### Tradeoff

Two counters are more schema and application code than one `attempt_count`.
That extra explicitness is intentional: it keeps worker ownership recovery
separate from processor exception retry policy. The current `unexpected-error`
classification is still intentionally coarse and should be narrowed before real
external dependencies such as payment, provider inventory, or notifications are
added.

---

## ADR 014: Use Feature-First Clean Architecture For The React Frontend

Status: accepted.

### Decision

Structure `movie-reservation-web/` as a small feature-first React/Vite
frontend with explicit clean architecture boundaries:

- `features/movie-reservations/domain`
- `features/movie-reservations/application`
- `features/movie-reservations/adapters`
- `features/movie-reservations/ui`
- `platform/api`
- `platform/observability`

Domain and application code should stay framework-free. React hooks, GraphQL
operation adapters, runtime parsers, browser environment access, and
observability propagation live at the outer edges.

The detailed folder and dependency rules live in
[frontend-architecture.md](frontend-architecture.md).

### Reason

The frontend has real workflow behavior: catalog selection, screening changes,
seat selection, reservation submission, bounded polling, result lookup, and
observability propagation. Keeping those rules inside large React components
would make them harder to test and easier to regress.

The chosen structure keeps the important behavior in plain TypeScript while
still allowing React components to stay small and focused on rendering. It also
matches the backend lesson without copying backend architecture blindly into the
browser: the frontend needs clean boundaries, not NestJS-style modules.

### Tradeoff

This adds more folders than a tiny one-component Vite app. That cost is
acceptable because the frontend already has non-trivial business workflow and
runtime boundary code.

Do not generalize this into broad `utils`, `helpers`, or generic `shared`
folders. Add new feature folders or platform capabilities only when real code
needs them. Keep unit tests colocated with frontend modules for now; create
separate e2e/browser test folders when Playwright is added.

---

## ADR 015: Keep Public CI Credential-Free And Deploy From A Private Promotion Workflow

Status: accepted.

### Decision

Keep the public repository's normal CI path credential-free. Pull requests and
public `main` should build, test, and synthesize CDK without AWS access.

For AWS deployment, use a separate private deployment workflow that is driven by
an explicit public source commit SHA. The private workflow should:

- require a human-provided commit SHA or human-approved promotion event
- check out the public repository at that exact SHA
- run the relevant build, tests, CDK synth, and CDK diff steps again
- pause behind a protected deployment environment before `cdk deploy`
- assume AWS roles via OIDC only in the deploy job
- let CDK publish Docker image assets into the account's bootstrap ECR
  repository during deployment

The public repository should not push Docker images or CDK assets directly to a
private AWS account as part of normal public CI.

### Reason

The important trust boundary is not whether the source code is public. The
important boundary is which reviewed commit is allowed to obtain AWS deployment
authority.

Using the public commit SHA as the promoted artifact keeps the public project
fully inspectable while avoiding AWS credentials in public CI. The private
deployment workflow owns the AWS account wiring, deployment approvals,
environment configuration, and role assumption. This also fits the current CDK
asset model: the private workflow can build the service image and let CDK
publish it to the bootstrap ECR repository when deployment is actually
approved.

### Tradeoff

This adds one more repository or private workflow to maintain, and deployments
are intentionally less automatic. That cost is acceptable for this learning
project because it makes the deployment trust model explicit:

- public repo review decides what code may enter `main`
- private promotion decides which exact commit may reach AWS
- AWS roles are exposed only to the private deployment path

If a future environment needs fully automated deployment from public `main`,
revisit this decision with protected GitHub environments, exact OIDC subject
conditions, permission-bounded CDK bootstrap roles, and a dedicated sandbox AWS
account.
