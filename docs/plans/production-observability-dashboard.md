# Production Observability Dashboard Follow-Up

Status: open under
[#30](https://github.com/patex1987/golden-path-ecs-template/issues/30).
Issue #38 established CloudWatch/AMP/Managed Grafana metric export for the ECS
environment; this plan expands the delivered initial dashboard and missing
saturation signals.

Do not duplicate #38's initial Traffic/Errors/Latency/Saturation dashboard in
#30. Treat that dashboard as the starting artifact and use #30 for the missing
signals, alert policy, drilldowns, and operator procedure.

## Summary

The local observability foundation is enough for a useful first dashboard, but
it is not yet enough for a production-grade operational dashboard and procedure
based on traffic, latency, errors, and saturation.

Current service metrics cover traffic, latency, and errors at the HTTP,
GraphQL, and reservation workflow levels. Saturation is intentionally weaker:
the service does not yet emit enough runtime, database, queue, worker, or
platform pressure signals to answer "is the system overloaded?" with confidence.

This follow-up should turn the local observability foundation into an operations
ready dashboard and runbook.

## Current Coverage

| Signal       | Current coverage                                                                                                          | Assessment                           |
| ------------ | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| `traffic`    | `http_request_total`, `graphql_operation_total`, `reservation_request_created_total`, `reservation_processor_claim_total` | Enough for a v1 service dashboard.   |
| `latency`    | `http_request_duration_ms`, `graphql_operation_duration_ms`, `reservation_processor_duration_ms`                          | Enough for v1 p50/p95/p99 panels.    |
| `errors`     | HTTP `status_family`, GraphQL `outcome`, GraphQL exception counts, processor `outcome`/`reason`, processor exceptions     | Enough for v1 error-rate panels.     |
| `saturation` | Health/readiness checks and indirect worker outcomes only                                                                 | Not enough for production operation. |

Traces and logs are useful for drilldown. The local backends are Tempo and Loki;
the AWS path uses X-Ray and CloudWatch Logs:

- HTTP, Express, GraphQL, Knex, and pg instrumentation provide technical spans.
- Custom GraphQL spans include operation and bounded business context.
- Reservation processor spans continue the async work trace context.
- Structured logs carry `trace_id`, `correlation_id`, request context, GraphQL
  context, provider code, and reservation handoff keys.

That is good for investigation, but dashboards and alerts should be driven
mostly by metrics.

## Target Dashboard Sections

### Service Overview

- request rate by HTTP route and status family
- GraphQL operation rate by bounded `business_operation` and `outcome`
- p95/p99 HTTP request latency
- p95/p99 GraphQL operation latency
- current API task/process health
- current API task/process resource pressure

### GraphQL API

- traffic by `business_operation`
- success/error/auth-error/unexpected-error rate
- latency histogram by `business_operation`
- top failing business operations
- diagnostic exception count by bounded exception type

### Reservation Workflow

- reservation requests created per minute
- reservation processor claims per minute
- processor outcomes by `confirmed`, `rejected`, `retryable-failure`, `failed`,
  and `no-pending-request`
- processor duration p95/p99
- rejected/failed reasons
- async handoff health through `reservation_request_id` log queries

### Saturation And Backlog

Add these missing signals before calling the dashboard production-ready:

- pending reservation request count
- oldest pending reservation request age
- active claim count
- expired/stuck claim count
- retryable failure backlog
- worker active processing count
- worker claim loop duration
- worker heartbeat or lease age if the worker becomes a separate runtime
- database pool active connection count
- database pool idle connection count
- database pool waiting request count
- database query latency/error rate if OpenTelemetry pg spans are not enough for
  dashboard-level views
- Node/process memory, heap, CPU, event loop lag, and GC pressure where
  available
- ECS task CPU/memory utilization, desired/running task count, restarts, and
  task health
- ALB request count, target response time, target 5xx, and target health

### Logs And Trace Drilldown

Dashboard links and runbook procedures should support these paths:

- from high GraphQL error rate to traces by operation in Tempo or X-Ray
- from a trace to logs by `trace_id` in Loki or CloudWatch Logs Insights
- from one user workflow to logs by `correlation_id`
- from one HTTP call to logs by `request_id`
- from async reservation failures to logs by `reservation_request_id`

High-cardinality ids should remain JSON log fields and trace attributes, not
Prometheus labels.

## Operations Procedure To Add

The future runbook should include a concrete triage order:

1. Start from the alert or dashboard panel.
2. Identify whether the symptom is traffic, latency, errors, or saturation.
3. Check GraphQL and HTTP panels to determine the affected boundary.
4. Check reservation workflow panels if the symptom involves booking requests.
5. Check saturation panels for backlog, worker pressure, database pressure,
   process pressure, or platform pressure.
6. Use Tempo locally or X-Ray in AWS for representative traces.
7. Use Loki locally or CloudWatch Logs Insights in AWS with `trace_id`,
   `correlation_id`, `request_id`, or `reservation_request_id` for detailed
   logs.
8. Decide whether the response is application rollback, worker restart,
   database investigation, scaling action, or dependency/platform escalation.

## Implementation Tasks

- Define the minimal production dashboard panel list before adding more custom
  metrics.
- Add saturation metrics for reservation backlog and worker pressure.
- Add or expose database pool pressure metrics.
- Add Node/process runtime pressure metrics.
- Add platform-level ECS and ALB panels in the infrastructure/dashboard layer.
- Decide which metric series should be zero-initialized because they are
  alerting-critical.
- Add dashboard queries as documentation first; later consider Grafana dashboard
  JSON or generated dashboards.
- Update `docs/operations/runbook.md` with the traffic/latency/error/saturation
  triage procedure.
- Add smoke or e2e checks that prove critical dashboard metrics exist.

## Acceptance Criteria

- A dashboard can show traffic, latency, errors, and saturation without relying
  on ad hoc log searches.
- Alerts can distinguish API errors, GraphQL business failures, reservation
  processor failures, backlog growth, database pressure, and platform pressure.
- The operations runbook explains the first five minutes of investigation.
- Drilldown links or documented queries connect metrics to traces and logs.
- Metric labels remain bounded and avoid ids such as user id, request id,
  correlation id, trace id, reservation request id, or provider id.
