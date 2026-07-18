# Distributed Observability Demo Platform Adoption Plan

Last reviewed: 2026-07-17

## Purpose And Status

This document governs adoption of an already-implemented multi-service demo,
not a greenfield build. The implementation exists on branches named
`demo-multi-service-observability` across this repository and three related
repositories. The integrated branch set passed its local smoke workflow on
2026-06-11, but it has not been reconciled with the current `main` branches.

The adoption belongs before RDS and Kubernetes because it establishes the
multi-service contracts, local topology, and distributed trace behavior that
those later runtime changes should preserve. It can proceed in parallel with
the ECS managed-observability issues because the local demo and AWS telemetry
paths have different deployment boundaries.

## Implemented Branch Inventory

| Repository                            | Implemented branch                 | Existing work                                                                                        |
| ------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `golden-path-ecs-template`            | `demo-multi-service-observability` | Reservation MCP, reserved-seat GraphQL read, frontend agent workflow, Compose wiring, tests, runbook |
| `python-agent-with-idp`               | `demo-multi-service-observability` | Bounded Python agent that coordinates recommendation and reservation MCP tools                       |
| `axum_tools_random_api`               | `demo-multi-service-observability` | Rust/Axum recommendation API, recommendation MCP boundary, telemetry, and demo fault behavior        |
| `fastapi_otel_prometheus_grafana_poc` | `demo-multi-service-observability` | Local Grafana/Tempo/Loki/Prometheus integration and multi-service dashboard                          |

The implemented local flow is:

```text
browser -> Python agent -> recommendation MCP -> Rust recommendation API
                        -> reservation MCP -> NestJS GraphQL API
```

Trace, correlation, and request context are propagated across those boundaries.
The branch runbook records successful happy-path, slow-recommendation, and
controlled dependency-error scenarios. The resulting trace included the agent,
both MCP services, the recommendation API, and the reservation API.

## Why Adoption Is Still Required

The branch in this repository diverged from the D8a baseline before the current
failure-injection and ECS CDK work landed. A direct merge would mix old
assumptions with newer service, infrastructure, and documentation changes.

Adoption therefore means:

- audit behavior and tests rather than assuming every branch decision should
  become permanent;
- selectively transplant or rebase the useful commits onto current `main`;
- preserve current failure-injection, CDK, CI, and documentation behavior;
- reconcile cross-repository API and telemetry contracts;
- rerun the full integrated smoke workflow on the adopted branch set.

Until that is complete, the demo is validated branch work, not a delivered
mainline milestone.

## Product And Architecture Boundaries

- Keep normal D8 customer UI movie-focused. The agent panel and technical trace
  identifiers must be available only through an explicit local/demo mode.
- Preserve W3C `traceparent`, optional `tracestate`, `X-Correlation-Id`, and a
  fresh `X-Request-Id` at each HTTP request boundary.
- Keep stable operation names and bounded metric dimensions. Reservation,
  request, trace, and correlation identifiers belong in logs and traces, not
  metric labels.
- Keep secrets, bearer tokens, cookies, raw headers, and prompt transcripts out
  of logs and traces.
- Keep demo-only fault controls disabled by default and unavailable in
  production profiles.
- Use explicit configured service URLs for this local topology. Service
  discovery is a later concern.
- Treat the branch's `Seat.isReserved` read shape as a pragmatic demo contract.
  Review it against #29 before treating it as the final catalog read model.

## Parallel Adoption Work Packages

### Package A: Reservation API And MCP

- Rebase the reserved-seat GraphQL behavior and its repository tests onto the
  current service.
- Adopt `movie-reservation-mcp` with its Dockerfile, typed tools, telemetry,
  GraphQL client, and tests.
- Verify current auth, failure-injection, logging, and runtime-profile behavior
  remains intact.

This package can proceed independently after its GraphQL contract is recorded.

### Package B: Frontend Demo Mode

- Reconcile the agent client, workflow hook, panel, and reserved-seat behavior
  with the current React/Vite code.
- Put the agent workflow behind an explicit local/demo configuration boundary.
- Keep the ordinary booking path compliant with
  [`movie-reservation-frontend-product-requirements.md`](movie-reservation-frontend-product-requirements.md).
- Reconcile #24 through #27 against both current `main` and the demo branch so
  already-implemented work is not repeated.

This package can proceed alongside Package A once the GraphQL and agent proxy
contracts are fixed. Both packages touch this repository and need coordinated
integration.

### Package C: External Services

- Review and update the existing agent, recommendation API/MCP, and local
  observability branches in their owning repositories.
- Confirm timeouts, iteration limits, configured URLs, fault controls, and
  telemetry propagation still match the adopted contracts.
- Run each repository's focused checks before integrating the topology.

The three repository reviews can run in parallel with each other and with the
AWS #37/#38 work.

### Package D: Topology And Integrated Verification

- Reassemble the Compose demo from the adopted repository revisions.
- Update the operator runbook with exact repository revisions and startup order.
- Run the happy path, slow recommendation, and dependency error scenarios.
- Verify logs, traces, and metrics in the local observability stack.

This is the convergence package. It begins only after Packages A through C have
compatible revisions.

## Adoption Sequence

1. Create a dedicated GitHub issue or parent issue with repository-specific
   subtasks. Existing D8 and AWS observability issues do not own this landing.
2. Create adoption branches from each repository's current `main`; do not use
   the old demo branches as the new base.
3. Record the existing cross-repository contracts and select commits or changes
   to transplant.
4. Execute Packages A, B, and C in parallel where ownership permits.
5. Integrate Package D and resolve contract or Compose drift.
6. Merge only after focused repository checks and the integrated smoke workflow
   pass.
7. Move this plan to `delivered/` after all required repositories have landed
   the adopted revisions and the final runbook references mainline code.

## Testing And Acceptance

Required repository checks:

- service and frontend typecheck, lint, unit, and integration checks;
- reservation MCP unit/integration tests and container startup check;
- agent workflow tests, including iteration and dependency-failure bounds;
- Rust API/MCP checks and demo-fault tests;
- observability stack configuration validation.

Required integrated signals:

- happy path returns a confirmed reservation;
- slow recommendation remains successful and produces visible latency spans;
- recommendation dependency failure returns the documented controlled error;
- one trace crosses agent, both MCP services, recommendation API, and
  reservation API;
- logs correlate through bounded identifiers without exposing secrets or raw
  prompts;
- normal customer UI does not expose trace or correlation identifiers;
- demo-only controls are unavailable when the demo profile is disabled.

## Remaining Follow-Ups

These were not completed merely because the demo branches exist:

- GraphQL code generation, generated-artifact policy, and schema-drift CI;
- production OIDC/JWKS under #10;
- Playwright and scalable integration CI under #27/#31 where still missing;
- production saturation/dashboard work under #30;
- production deployment, service discovery, and security hardening;
- long-term catalog/read-model ownership under #29.

## Risks And Mitigations

| Risk                                       | Mitigation                                                                                           |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| Blind merge regresses newer mainline work  | Start from current `main` and selectively transplant reviewed behavior.                              |
| Four repositories drift during adoption    | Record compatible revisions and contracts in the runbook before the final smoke.                     |
| Demo UI leaks into the customer product    | Require an explicit demo-mode boundary and test the normal UI separately.                            |
| Demo fault controls become remotely usable | Keep controls profile-gated, disabled by default, and covered by configuration tests.                |
| Hand-written GraphQL clients drift         | Keep runtime parsing now and create a separate codegen/schema-drift issue after contracts stabilize. |

## Done Criteria

- All adopted changes are based on current repository mainlines.
- Current failure-injection, ECS CDK, CI, and D8 behavior remains intact.
- Focused checks pass in all participating repositories.
- The three integrated smoke scenarios pass with documented revisions.
- The distributed trace and correlated logs cover every intended service
  boundary.
- Customer and demo UI modes have an explicit, tested boundary.
- Follow-up gaps have GitHub issue ownership rather than remaining ambiguous
  prose.
