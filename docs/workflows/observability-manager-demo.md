# Observability Manager Demo

This document is a meeting runbook for demonstrating the local observability
foundation. It is written for two audiences:

- the presenter, who needs exact commands and Grafana queries;
- the manager, who needs to understand what the system proves without reading
  the source code.

The demo shows a realistic path through the movie reservation API:

1. a frontend-like client sends GraphQL requests with `traceparent`,
   `X-Correlation-Id`, and `X-Request-Id`;
2. the API emits OpenTelemetry traces and metrics;
3. the API writes structured JSON logs to stdout;
4. the local collector forwards traces and metrics to the external Grafana
   stack;
5. Grafana Tempo, Loki, and Prometheus let us move from a failing or slow API
   operation back to traces, logs, and business metrics.

## Business Scenario

Imagine a customer wants to book a movie ticket in a cinema reservation system.
They open the movie booking UI, browse the available movies, pick a screening,
choose a seat, submit the reservation, and then wait for the backend to confirm
whether the seat was successfully reserved.

That business workflow is intentionally more than one backend call:

1. The customer opens the booking screen and the frontend loads catalog data:
   available movies, screenings, seats, and the authenticated user's provider
   context.
2. The customer submits a reservation request for one screening and one seat.
   The API accepts the request immediately and stores it as asynchronous work.
3. A local in-process worker claims the reservation request, checks for seat
   conflicts, and either confirms or rejects the reservation.
4. The frontend polls the reservation request status.
5. Once the request is confirmed, the frontend fetches the final reservation
   result.

For the demo, the script below behaves like that frontend. It runs four named
GraphQL operations:

| Step | Operation                       | Business meaning                                                |
| ---- | ------------------------------- | --------------------------------------------------------------- |
| 1    | `ManagerDemoCatalog`            | Load movies, screenings, seats, and user/provider context.      |
| 2    | `ManagerDemoRequestReservation` | Ask the API to reserve a selected seat.                         |
| 3    | `ManagerDemoReservationStatus`  | Poll whether the asynchronous request is confirmed or rejected. |
| 4    | `ManagerDemoReservationResult`  | Fetch the confirmed reservation once processing succeeds.       |

All four calls share one `X-Correlation-Id`, so they can be understood as one
business workflow. They also share one demo `trace_id`, which simulates the
frontend-to-backend trace propagation implemented by `movie-reservation-web`.
Each call still has its own `X-Request-Id`, because each HTTP request needs its
own support/debug handle.

The manager-level story is: if this booking fails, looks slow, or has a bad
business outcome, we can start from the user workflow, inspect the trace in
Tempo, jump to structured logs in Loki, and verify success/failure metrics in
Prometheus.

## Executive Summary

The observability contract is intentionally split by purpose:

| Field              | Purpose                                                         | Granularity                  |
| ------------------ | --------------------------------------------------------------- | ---------------------------- |
| `traceparent`      | W3C/OpenTelemetry trace propagation.                            | One distributed trace.       |
| `X-Correlation-Id` | Business workflow grouping across requests and future services. | One user action or workflow. |
| `X-Request-Id`     | Support/debug id for one inbound HTTP request.                  | One HTTP request.            |
| `X-Amzn-Trace-Id`  | AWS edge metadata from ALB/X-Ray-compatible infrastructure.     | AWS edge/proxy context.      |

Logs remain stdout JSON so the service stays ECS/CloudWatch-compatible. Local
Grafana Alloy scrapes Docker logs into Loki. OpenTelemetry is used for traces
and metrics, which keeps the local setup close to how this should look later
with ECS, ADOT, X-Ray, CloudWatch, or another production backend.

The field-level log schema is documented in
[observability-log-contract.md](../architecture/observability-log-contract.md).

## What This Proves

The demo proves these capabilities:

- A frontend or test runner can pass W3C `traceparent` to the backend.
- Backend traces include HTTP, GraphQL, and database spans.
- GraphQL logs include bounded business fields such as operation name,
  operation type, business operation, user id, and provider code.
- Logs include `trace_id`, `correlation_id`, and `request_id` when a request
  span is active.
- Tempo can jump from a trace to matching Loki logs by `trace_id`.
- Prometheus can query GraphQL success/error counts and reservation processor
  outcomes.
- Reservation worker logs include business events such as
  `reservation_request.confirmed` and `reservation_request.rejected`, plus the
  original `correlation_id`, `request_id`, `trace_id`, and
  `reservation_request_id`.

Current implementation caveat:

The reservation request persists `correlation_id`, `request_id`, `traceparent`,
and `tracestate`. The in-process background worker uses that persisted context
to put `correlation_id`, `request_id`, and the derived `trace_id` on structured
business outcome logs. It does not log raw `traceparent`/`tracestate`, and it
does not yet create a dedicated OpenTelemetry worker span from that persisted
context. Adding a true async worker span remains a good follow-up task.

## Prerequisites

Expected local services:

- Grafana: `http://localhost:3000`
- API: `http://127.0.0.1:3001` from the containerized API profile
- Local app collector: `http://127.0.0.1:18889/metrics`

The demo script needs:

- `curl`
- `jq`
- `openssl`

If the API is running on a different port, set `API_BASE_URL` before running
the script:

```bash
export API_BASE_URL=http://127.0.0.1:3000
```

For the Loki part of the demo, run the API through Docker Compose:

```bash
docker compose --profile api up -d --build api
```

Host-run development from WebStorm or `npm run dev:local-postgres` can still
emit traces and metrics to the local collector, but the current local log path
does not scrape host process stdout. Alloy scrapes Docker logs from containers
with the `observability.logs=true` label, so Loki will only show API logs when
the API is running as the Compose `api` service.

Before the meeting, run the smoke check once:

```bash
API_BASE_URL=http://127.0.0.1:3001 npm -w movie-reservation-service run smoke:observability
```

## Clean Data Note

The green-path reservation demo uses seat A3 from the seeded Aurora data. That
seat can only be confirmed once per local database state. After it has been
confirmed, running the same mutation again becomes a useful rejection demo
because the processor should reject the later request with a seat conflict.

For a clean green-path rehearsal, reset the local Postgres data before the
meeting. This is destructive for the local Docker database volume:

```bash
docker compose down -v
docker compose up -d postgres
docker compose --profile observability up -d otel-collector
npm -w movie-reservation-service run db:migrate:local-postgres
npm -w movie-reservation-service run db:seed:local-postgres
docker compose --profile api up -d --build api
```

## Demo Script

Run this from the repository root. It keeps one trace id and one correlation id
for the whole workflow, while giving each HTTP call its own request id. The
shared trace id simulates what a future frontend could do for one user action.

```bash
set -e
set -u
set -o pipefail

API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:3001}"
DEMO_DIR="${DEMO_DIR:-/tmp/movie-reservation-observability-demo}"
CORRELATION_ID="${CORRELATION_ID:-manager-demo-$(date +%Y%m%d-%H%M%S)}"
TRACE_ID="${TRACE_ID:-$(openssl rand -hex 16)}"
FRONTEND_SPAN_ID="${FRONTEND_SPAN_ID:-$(openssl rand -hex 8)}"

MOVIE_ID="44444444-4444-4444-8444-444444444441"
SCREENING_ID="55555555-5555-4555-8555-555555555551"
SEAT_A3="66666666-6666-4666-8666-666666666663"

mkdir -p "$DEMO_DIR"

request_graphql() {
  operation_name="$1"
  request_id="$2"
  query="$3"
  variables="$4"
  traceparent="00-${TRACE_ID}-${FRONTEND_SPAN_ID}-01"
  output_file="$DEMO_DIR/${operation_name}.json"

  echo
  echo ">>> ${operation_name}"
  echo "trace_id=${TRACE_ID}"
  echo "correlation_id=${CORRELATION_ID}"
  echo "request_id=${request_id}"

  jq -n \
    --arg query "$query" \
    --arg operationName "$operation_name" \
    --argjson variables "$variables" \
    '{query:$query, operationName:$operationName, variables:$variables}' |
    curl -sS "$API_BASE_URL/graphql" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer local-demo-token" \
      -H "X-Correlation-Id: $CORRELATION_ID" \
      -H "X-Request-Id: $request_id" \
      -H "traceparent: $traceparent" \
      --data-binary @- |
    tee "$output_file" |
    jq .
}

CATALOG_QUERY='
query ManagerDemoCatalog($movieId: ID!) {
  screenings(movieId: $movieId) {
    id
    movieId
    auditoriumId
    startsAt
    endsAt
    seats {
      id
      row
      number
    }
  }
  movies {
    id
    title
    rating
    durationMinutes
  }
  me {
    userId
    username
    movieProviderCode
    roles
    scopes
  }
}'

REQUEST_QUERY='
mutation ManagerDemoRequestReservation($input: RequestReservationInput!) {
  requestReservation(input: $input) {
    id
    status
    screeningId
    seatIds
    requestedByUserId
  }
}'

STATUS_QUERY='
query ManagerDemoReservationStatus($id: ID!) {
  reservationRequestStatus(id: $id) {
    id
    status
    screeningId
    seatIds
    requestedByUserId
  }
}'

RESULT_QUERY='
query ManagerDemoReservationResult($requestId: ID!) {
  reservationResult(requestId: $requestId) {
    id
    reservationRequestId
    screeningId
    seatIds
    reservedByUserId
    confirmedAt
  }
}'

request_graphql \
  ManagerDemoCatalog \
  "${CORRELATION_ID}-001-catalog" \
  "$CATALOG_QUERY" \
  "{\"movieId\":\"$MOVIE_ID\"}"

request_graphql \
  ManagerDemoRequestReservation \
  "${CORRELATION_ID}-002-request" \
  "$REQUEST_QUERY" \
  "{\"input\":{\"screeningId\":\"$SCREENING_ID\",\"seatIds\":[\"$SEAT_A3\"]}}"

RESERVATION_REQUEST_ID="$(jq -r '.data.requestReservation.id // empty' "$DEMO_DIR/ManagerDemoRequestReservation.json")"

if [ -z "$RESERVATION_REQUEST_ID" ]; then
  echo "requestReservation did not return an id. Check $DEMO_DIR/ManagerDemoRequestReservation.json"
  exit 1
fi

sleep 1

request_graphql \
  ManagerDemoReservationStatus \
  "${CORRELATION_ID}-003-status" \
  "$STATUS_QUERY" \
  "{\"id\":\"$RESERVATION_REQUEST_ID\"}"

request_graphql \
  ManagerDemoReservationResult \
  "${CORRELATION_ID}-004-result" \
  "$RESULT_QUERY" \
  "{\"requestId\":\"$RESERVATION_REQUEST_ID\"}"

cat <<SUMMARY

Demo ids:
  trace_id: $TRACE_ID
  correlation_id: $CORRELATION_ID
  reservation_request_id: $RESERVATION_REQUEST_ID
  output_dir: $DEMO_DIR

Open Grafana:
  http://localhost:3000
SUMMARY
```

## Grafana Walkthrough

Use this order in the meeting.

### 1. Tempo: Start From The Trace

Open Grafana:

```text
http://localhost:3000
```

Then:

1. Go to Explore.
2. Select the `Tempo` datasource.
3. Paste the printed `trace_id`.
4. Set the time picker to the last 15 minutes.
5. Run the query.

What to point out:

- The trace has several backend requests that belong to the same simulated
  frontend user action.
- The GraphQL plugin adds a `graphql.operation` span with attributes such as
  `graphql.operation.name`, `graphql.operation.type`, `business.operation`,
  `movie.provider.code`, and `enduser.id`.
- Auto-instrumentation should add HTTP and database spans, giving a path from
  API operation down to persistence work.

If the trace appears as multiple root groups, that is acceptable for this CLI
demo. The script injects a frontend-like `traceparent`, but it does not export
an actual frontend span. The later React frontend should export or at least
preserve the frontend side of the trace more naturally.

### 2. Tempo To Loki: Jump From Trace To Logs

In the Tempo trace view:

1. Select a GraphQL or HTTP span.
2. Use the logs action.
3. Grafana should query Loki by `trace_id`.

Useful manual Loki query:

```logql
{service_name="movie-reservation-service"} | json | trace_id="<TRACE_ID>"
```

What to point out:

- Logs are structured JSON, not free text.
- The same trace id appears in logs and traces.
- Logs include the request/correlation ids and trusted identity fields after
  authentication.
- This is the incident workflow: alert -> trace -> logs -> business fields.

### 3. Loki: Show The Business Workflow

Search all logs for the whole business workflow:

```logql
{service_name="movie-reservation-service"} | json | correlation_id="<CORRELATION_ID>"
```

Search one request:

```logql
{service_name="movie-reservation-service"} | json | request_id="<REQUEST_ID>"
```

Search the async reservation processor path:

```logql
{service_name="movie-reservation-service"} | json | reservation_request_id="<RESERVATION_REQUEST_ID>"
```

Search confirmed and rejected business outcomes:

```logql
{service_name="movie-reservation-service"} | json | event=~"reservation_request\\.(confirmed|rejected)"
```

Search a specific failed booking because the seat is already taken:

```logql
{service_name="movie-reservation-service"} | json | event="reservation_request.rejected" | reason="seat-conflict"
```

Search GraphQL operation lifecycle logs:

```logql
{service_name="movie-reservation-service"} | json | graphql_operation_name=~"ManagerDemo.*"
```

What to point out:

- `correlation_id` groups several HTTP requests into one business workflow.
- `request_id` narrows the view to one API call.
- `reservation_request_id` continues the investigation into async processing.
- `reservation_request.confirmed` and `reservation_request.rejected` are the
  human-readable business outcome logs to show in the meeting.
- High-cardinality ids are JSON fields, not Loki labels. This keeps Loki label
  cardinality under control.

### 4. Prometheus: Show Metrics

Open Explore and switch to the `Prometheus` datasource.

Discovery queries:

```promql
{__name__=~".*graphql_operation.*"}
```

```promql
{__name__=~".*reservation_processor.*"}
```

Manager-friendly panels:

```promql
sum by (business_operation, outcome) (increase(graphql_operation_total[15m]))
```

```promql
sum by (outcome, reason) (increase(reservation_processor_outcome_total[15m]))
```

```promql
sum by (http_method, http_route, status_family) (increase(http_request_total[15m]))
```

Latency example:

```promql
histogram_quantile(
  0.95,
  sum by (le, business_operation) (rate(graphql_operation_duration_ms_bucket[5m]))
)
```

If a metric name differs because of Prometheus/OpenTelemetry naming conversion,
use the discovery queries and Grafana autocomplete. The important names to look
for are `graphql_operation`, `reservation_processor`, and `http_request`.

What to point out:

- GraphQL success/error rate is grouped by bounded business operations.
- Processor outcomes show confirmed, rejected, failed, and no-pending-request
  categories.
- We deliberately avoid putting user ids, request ids, trace ids, or
  correlation ids into metric labels.

## Optional Rejection Demo

Use this when you want to show a negative business outcome. Seat A1 is already
reserved by the local seed data, so this request should eventually be rejected
by the reservation processor with `reason="seat-conflict"`.

Run this in the same shell after the main demo script, because it reuses the
`request_graphql` helper and query variables.

```bash
CONFLICT_SEAT_A1="66666666-6666-4666-8666-666666666661"
CONFLICT_CORRELATION_ID="manager-demo-conflict-$(date +%Y%m%d-%H%M%S)"
CORRELATION_ID="$CONFLICT_CORRELATION_ID"
TRACE_ID="$(openssl rand -hex 16)"
FRONTEND_SPAN_ID="$(openssl rand -hex 8)"

request_graphql \
  ManagerDemoRejectedReservation \
  "${CORRELATION_ID}-001-conflict-request" \
  "$REQUEST_QUERY" \
  "{\"input\":{\"screeningId\":\"$SCREENING_ID\",\"seatIds\":[\"$CONFLICT_SEAT_A1\"]}}"

REJECTED_REQUEST_ID="$(jq -r '.data.requestReservation.id // empty' "$DEMO_DIR/ManagerDemoRejectedReservation.json")"

sleep 1

request_graphql \
  ManagerDemoRejectedReservationStatus \
  "${CORRELATION_ID}-002-conflict-status" \
  "$STATUS_QUERY" \
  "{\"id\":\"$REJECTED_REQUEST_ID\"}"

echo "Rejected trace_id: $TRACE_ID"
echo "Rejected correlation_id: $CORRELATION_ID"
echo "Rejected reservation_request_id: $REJECTED_REQUEST_ID"
```

Useful queries:

```logql
{service_name="movie-reservation-service"} | json | reservation_request_id="<REJECTED_REQUEST_ID>"
```

```logql
{service_name="movie-reservation-service"} | json | event="reservation_request.rejected" | reservation_request_id="<REJECTED_REQUEST_ID>"
```

```promql
sum by (outcome, reason) (increase(reservation_processor_outcome_total[15m]))
```

## Suggested Meeting Narrative

Use this script as the explanation while clicking through Grafana:

1. "The client sends W3C `traceparent`, plus our application-level
   `X-Correlation-Id` and per-request `X-Request-Id`."
2. "The backend accepts those ids, returns the correlation/request ids in the
   response, and enriches logs with identity and provider context after
   authentication."
3. "OpenTelemetry owns traces and metrics. Logs remain stdout JSON, which is
   the natural ECS and CloudWatch contract."
4. "In Tempo we can start from a failing or slow GraphQL operation and see HTTP,
   GraphQL, and database work in one place."
5. "From a trace we can jump into Loki logs by `trace_id`, then broaden to the
   entire user action with `correlation_id`."
6. "Prometheus gives us bounded business metrics for operation success/error
   rates and processor outcomes. Those are the metrics we can alert on later."
7. "The next production hardening step is to rehydrate persisted trace context
   inside async workers, then carry the same contract through the React frontend
   and eventually ALB/ECS."

## Troubleshooting

No API response:

- Check whether the API is on `3001` or `3000`.
- Set `API_BASE_URL` explicitly.
- Confirm GraphQL requests include `Authorization: Bearer local-demo-token`.

No trace in Tempo:

- Set Grafana time range to the last 15 minutes.
- Wait 10 to 30 seconds for collector export.
- Confirm the API has observability enabled and is sending OTLP to the local
  collector.

No logs from Tempo:

- Use the manual Loki `trace_id` query.
- Confirm the API is running as a Docker container with the
  `observability.logs=true` label when relying on Alloy Docker log scraping.
- Confirm the external Grafana stack has Loki and Alloy running.

No metrics:

- Start with the discovery queries.
- Wait one Prometheus scrape interval.
- Confirm the local collector forwards metrics to the external collector, or
  check the app-local endpoint at `http://127.0.0.1:18889/metrics`.

Reservation result is `null`:

- The worker may not have processed the request yet. Poll status again.
- If the request status is `REJECTED`, the seat was already reserved. That is a
  valid conflict demo.
- Reset local data before the meeting if you need the green path to confirm.
