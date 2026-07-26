# Observability Log Contract

This document defines the JSON log contract for the movie reservation service.
It is the application-level contract used by stdout logs, Docker log scraping,
Loki queries, CloudWatch Logs, and future incident runbooks.

Logs stay as structured JSON on stdout. OpenTelemetry owns traces and metrics;
logs carry only the join keys needed to move between logs, traces, business
state, and support/debug context.

## Goals

- Keep logs ECS and CloudWatch compatible by writing JSON to stdout.
- Make the primary query fields obvious and stable.
- Preserve frontend-to-backend and async correlation without logging raw
  propagation ballast.
- Avoid high-cardinality ids as Loki labels; keep them as JSON fields.
- Avoid secrets, raw headers, request bodies, GraphQL variables, and tokens.

## Required Base Fields

Every application log line should have these fields:

| Field             | Meaning                                                                                       |
| ----------------- | --------------------------------------------------------------------------------------------- |
| `time`            | ISO timestamp emitted by Pino.                                                                |
| `level`           | Numeric Pino severity. Use this as the current severity field.                                |
| `service_name`    | Stable service name, currently `movie-reservation-service`.                                   |
| `service_version` | Version emitted by the service config.                                                        |
| `environment`     | Runtime environment, for example `development`.                                               |
| `event`           | Stable machine-readable event name. This is the primary log query key.                        |
| `message`         | Human-readable message. It may equal `event`; do not use it as the primary structured filter. |

If we later need a human-readable severity field for CloudWatch/Loki ergonomics,
add a separate `severity_text` field. Do not overload `message` for severity.

## Request Context

Request context is contextual information related to the request/response
lifecycle. It should be available to logs emitted while handling an inbound
request, but the logger should attach only the fields that make sense for the
specific boundary or event.

For request lifecycle logs, these fields should be present:

| Field            | Meaning                                                                                |
| ---------------- | -------------------------------------------------------------------------------------- |
| `trace_id`       | OpenTelemetry/W3C trace id. Use it to jump between Tempo traces and Loki logs.         |
| `correlation_id` | Application workflow id. Groups related requests and async work for one business flow. |

The frontend or other consumer decides when a new business workflow starts and
therefore when to create a new `correlation_id`. For example, a booking flow can
reuse one correlation id across catalog browsing, reservation creation, polling,
and result fetching. A later unrelated user action should get a new correlation
id.

HTTP-only request fields belong on HTTP request logs:

| Field                 | Meaning                                                                                 |
| --------------------- | --------------------------------------------------------------------------------------- |
| `request_id`          | One inbound HTTP request id. Useful for response-header matching, but noisy in logs.    |
| `aws_x_amzn_trace_id` | AWS edge/proxy trace metadata when `X-Amzn-Trace-Id` is present. Secondary cross-check. |
| `http_method`         | Inbound HTTP method.                                                                    |
| `http_route`          | Inbound route/path known at the service boundary.                                       |

`request_id` is intentionally HTTP-hop scoped. Keep echoing it in response
headers, but do not attach it to every business event by default. Use it when
investigating one exact API call rather than a multi-request workflow.

GraphQL-only fields belong on GraphQL operation logs:

| Field                    | Meaning                                                    |
| ------------------------ | ---------------------------------------------------------- |
| `graphql_operation_name` | GraphQL operation name supplied by the client.             |
| `graphql_operation_type` | GraphQL operation type, for example `query` or `mutation`. |

`graphql_operation_name` is client-supplied and useful for debugging a caller.
`business_operation` is server-classified and stable enough for grouping logs,
metrics, and dashboards. Keep the two concepts separate.

Application classification and identity fields can appear when the authenticated
request context has them:

| Field                 | Meaning                                                                    |
| --------------------- | -------------------------------------------------------------------------- |
| `business_operation`  | Bounded application operation, for example `requestReservation`.           |
| `user_id`             | Authenticated application user id.                                         |
| `movie_provider_code` | Human-friendly provider code when available. Prefer this over provider id. |

Do not log `movie_provider_id` by default. The provider code is easier to scan
and reduces noise. Add a provider id only for a specific incident or event where
a durable data join is more important than log readability.

## Business Event Fields

Business logs should stay sparse. Use structured fields for correlation,
classification, and handoff keys. Put human context in `message`.

| Field         | Meaning                                                            |
| ------------- | ------------------------------------------------------------------ |
| `outcome`     | Optional bounded result for completion events.                     |
| `reason`      | Optional bounded reason when `outcome` needs classification.       |
| `duration_ms` | Optional operation duration in milliseconds for completion events. |

Avoid default structured entity ids. Add a structured entity id only when it is
the key someone will use to continue the investigation across async work or
another system.

Normal event example:

```json
{
  "event": "reservation_request.rejected",
  "message": "Reservation request rejected because seats are already booked.",
  "outcome": "rejected",
  "reason": "seat-conflict",
  "trace_id": "...",
  "correlation_id": "..."
}
```

Async handoff example:

```json
{
  "event": "reservation_request.created",
  "message": "Reservation request created.",
  "reservation_request_id": "...",
  "trace_id": "...",
  "correlation_id": "..."
}
```

`reservation_request_id` earns its place on creation and worker logs because it
bridges the GraphQL mutation to later async worker activity. If that id lived
only inside `message`, text search would still work, but a clean "show me all
logs for this work item" query would be harder.

Do not include these fields in the shared business event contract:

- `reason_message`: use `message` instead.
- `reservation_request_sequence`: too internal for normal investigation. Use it
  only for focused worker lease or ordering debugging.
- `reservation_id`: include it only on events where the reservation itself is
  the thing being discussed.

For the reservation workflow, the most important business events are:

| Event                                            | Meaning                                                                      |
| ------------------------------------------------ | ---------------------------------------------------------------------------- |
| `reservation_request.created`                    | The API accepted a reservation request.                                      |
| `reservation_request.processing_started`         | The worker claimed an async reservation request.                             |
| `reservation_request.confirmed`                  | The reservation was confirmed.                                               |
| `reservation_request.rejected`                   | The reservation was rejected, for example because a seat was already booked. |
| `reservation_request.processing_retry_scheduled` | The worker hit a retryable internal failure.                                 |
| `reservation_request.processing_failed`          | The worker reached a terminal internal failure.                              |

## Fields We Do Not Log By Default

Do not log these fields in normal application logs:

| Field               | Why it stays out of logs                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| `traceparent`       | It is a W3C propagation header, not a query/display field. `trace_id` is enough for joins.        |
| `tracestate`        | Vendor propagation metadata. Preserve it for propagation when needed, but do not log it.          |
| `trace_flags`       | Sampling/debug flag from trace context. It rarely helps incident search.                          |
| `parent_span_id`    | Parent context can be misleading, especially in async work.                                       |
| `span_id`           | Deferred for now. Add only if span-level log linking becomes necessary.                           |
| `movie_provider_id` | Prefer `movie_provider_code` for normal logs. Add the id only when a specific data join needs it. |

The service may persist `traceparent` and optional `tracestate` as async work
metadata so a worker can continue trace propagation later. Persisting
propagation metadata is different from logging it.

## Id Creation Boundaries

The inbound HTTP middleware is the application boundary for ids. In this repo,
that boundary is implemented by `RequestContextMiddleware` and
`createRequestContext`.

For every inbound HTTP request:

- If `X-Correlation-Id` is present and matches the safe id format, the API uses
  it. Otherwise the API generates a UUID.
- If `X-Request-Id` is present and matches the safe id format, the API uses it.
  Otherwise the API generates a UUID.
- The response echoes `X-Correlation-Id` and `X-Request-Id`.
- OpenTelemetry handles W3C `traceparent` and `tracestate` propagation.
- If `X-Amzn-Trace-Id` is present, the API captures it as
  `aws_x_amzn_trace_id` for AWS-side cross-checking.

Current local fallback behavior is intentionally simple: if the caller does not
send a correlation id, the API creates one per inbound request. That keeps every
request searchable, but it does not create a true multi-request business
workflow. The React frontend creates or preserves one
`X-Correlation-Id` for a full booking flow, while generating a fresh
`X-Request-Id` for each backend call.

## Id Scopes

`trace_id`, `correlation_id`, and `request_id` answer different questions. Only
`trace_id` and `correlation_id` should be treated as common request lifecycle
context. `request_id` is useful, but deliberately narrower and noisier.

Use `correlation_id` when investigating a user/business workflow:

- browse catalog
- submit reservation
- poll status
- fetch result
- async worker confirms or rejects the request

Use `request_id` when investigating one concrete HTTP call:

- one GraphQL mutation failed
- one proxy/client log line references a request
- one response header needs to be matched to backend logs

Use `trace_id` when moving between logs and the distributed trace. It is the
technical execution join key, not the business workflow id.

Using `request_id` as the primary investigation field would make multi-call
workflows hard to follow and would create noise. Use it at the HTTP boundary,
then prefer `correlation_id` and `trace_id` for normal cross-log investigation.
