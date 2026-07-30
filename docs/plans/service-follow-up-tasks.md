# Service Follow-Up Tasks

Last reviewed: 2026-07-30

This file contains service/domain/API work that remains after the delivered D4
through D7 milestones. GitHub issues are the execution source of truth. Avoid
copying delivered implementation details back into this backlog.

## Issue-Backed Work

### Explicit Reservation Read Outcomes

Issue: [#28](https://github.com/patex1987/golden-path-ecs-template/issues/28)

Replace the broad nullable contract for `reservationRequestStatus` and
`reservationResult`. The API should distinguish pending, confirmed, rejected,
failed, not-found, and deliberately hidden unauthorized outcomes without
leaking cross-tenant resource existence.

### Catalog Read Model Ownership

Issue: [#29](https://github.com/patex1987/golden-path-ecs-template/issues/29)

Move catalog/read-model assembly out of the GraphQL resolver and into an
application query boundary. Revisit the current `screenings { seats }` shape so
the frontend does not load every seat for every screening during initial
catalog discovery. Consider metadata-first catalog queries and a selected
screening availability query.

### Reservation Command Idempotency

Issue: [#32](https://github.com/patex1987/golden-path-ecs-template/issues/32)

Add an idempotency contract before production-like retrying clients are used.
Define key ownership, scope, persistence, replay behavior, conflicting payload
handling, and expiry.

### RDS And Migration Task

Issue: [#7](https://github.com/patex1987/golden-path-ecs-template/issues/7)

Provision RDS and execute migrations through a separate ECS `RunTask` during
deployment. The migration task must use the compiled migration entrypoint,
connect to RDS over the VPC, report a terminal exit code, and complete before
the ECS service update proceeds. Do not run migrations in API startup.

### Durable Worker Signaling

Issue: [#8](https://github.com/patex1987/golden-path-ecs-template/issues/8)

Separate the API control plane from worker execution after durable AWS
persistence exists. Preserve Postgres as the state source of truth and use the
queue as a wake-up/scheduling mechanism. Define retry taxonomy, backoff,
dead-letter/manual recovery, and idempotent processing.

### Authorization And Subscriptions

- [#10](https://github.com/patex1987/golden-path-ecs-template/issues/10)
  owns authorization research and hardening: policy model, app-local versus
  externalized authorization, migration path, and one realistic authorization
  prototype.
- [#47](https://github.com/patex1987/golden-path-ecs-template/issues/47)
  owns identity provider and authentication strategy: OIDC/OAuth2 flows,
  issuer/audience/JWKS validation, token and claim contract, local development
  fallback, frontend login, service-to-service callers, and Agent/MCP callers.
- [#46](https://github.com/patex1987/golden-path-ecs-template/issues/46)
  owns the audit/security event contract for authentication failures,
  authorization decisions, policy errors, admin/config changes, and future
  Agent/MCP tool invocation security events.
- [#11](https://github.com/patex1987/golden-path-ecs-template/issues/11)
  owns GraphQL subscriptions and the separate WebSocket authentication path
  after the relevant #47 authentication and #10 authorization decisions are
  explicit.

Do not assume the current HTTP bearer-token middleware authenticates WebSocket
connection initialization.

## Unscheduled API Quality

- Replace generic domain/application `Error` values with explicit error types
  where transport mapping or retry classification depends on the cause.
- Add a deliberate GraphQL timestamp contract, such as a `DateTime` scalar,
  instead of exposing domain timestamps as unconstrained strings.
- Centralize allowed reservation request state transitions before the workflow
  gains more writers or states.
- Revisit string-based generated-schema assertions if they become brittle;
  prefer structural or snapshot verification when it provides clearer failures.
- Expand tenant-owner and cross-provider API coverage when #28 changes the read
  result contract.

## Authentication Boundaries

- Keep generic bearer/JWT mechanics separate from movie-reservation claim
  mapping. Extract a shared auth package only when a second service proves the
  shared contract.
- Decide token claim, role, scope, and provider membership semantics across
  #47 and #10, not as isolated middleware conditionals.
- Keep authorization decisions in application policy, persistence filtering in
  repositories, and GraphQL result/error mapping at the presentation boundary.
- Never log raw authorization headers, tokens, cookies, or GraphQL variables.

## Persistence And Worker Boundaries

- Keep the in-memory repository as the fast fake after RDS exists.
- Revisit `ReservationRequestWorkRepository` naming and responsibility before a
  real queue or multiple worker types are added; the port should remain
  workflow-shaped without hiding business policy in SQL helpers.
- Keep transaction, row-lock, lease, and claim-token mechanics in the Postgres
  adapter. Keep retry and terminal-outcome policy in application code.
- Revisit optimistic locking only when a concrete mutable workflow creates a
  lost-update risk.
- Prefer application events over multiplying direct observability calls if the
  processor later needs multiple subscribers or an outbox.

## Configuration And Runtime

- Continue evolving environment validation as a discriminated runtime-profile
  contract. New OIDC, RDS, queue, and observability settings should be required
  only for profiles that use them.
- Add runtime profile smoke tests when the configuration matrix expands beyond
  the existing static template checks.
- Decide whether local development should keep `tsx`, run compiled output, or
  use a decorator-metadata-capable runner. Add one dev-start GraphQL smoke test
  when that decision becomes a real source of failures.
- Preserve the three-layer health model: process liveness, traffic readiness,
  and dependency/business diagnostics. Define database outage semantics before
  making RDS failure remove tasks from ALB readiness.
- Revisit Docker image hardening before production promotion: pinned base image,
  build cache policy, minimal runtime contents, SBOM/provenance, and non-root
  behavior.

## Observability Maintenance

- Complete the dashboard/saturation work under
  [`production-observability-dashboard.md`](production-observability-dashboard.md)
  and issue [#30](https://github.com/patex1987/golden-path-ecs-template/issues/30).
- Revisit metric zero-initialization as operation counts grow; initialize only
  alerting-critical bounded series by default.
- Revisit whether HTTP, GraphQL, and reservation metric helpers should move
  closer to their owning adapters while shared meter/bootstrap code stays
  centralized.
- Re-evaluate the explicit NodeSDK `--import` startup model only if it causes
  ordering or lifecycle problems. Instrumentation must still load before the
  instrumented libraries.
- Extract shared observability strings only where duplication creates a real
  contract-drift risk.
