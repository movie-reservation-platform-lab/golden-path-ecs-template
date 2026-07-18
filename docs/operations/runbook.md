# Runbook

This runbook is intentionally early. It describes the operational questions the project should eventually answer.

---

## Local Health Checks

For the NestJS service:

```text
GET /health
GET /ready
```

Expected basic responses:

```json
{ "status": "ok" }
```

```json
{ "status": "ready" }
```

Use `/health` to check that the process is alive.
Use `/ready` to check that the service can receive real traffic.

The service should keep three operational health concepts separate:

| Layer                         | Question it answers                                                                   | Typical use                                                                                                                                                                                                                |
| ----------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Liveness: `/health`           | Is the process alive?                                                                 | Container/runtime liveness checks. A failure usually means the process is broken and can be restarted.                                                                                                                     |
| Platform readiness: `/ready`  | Can this process accept traffic from the platform?                                    | Load balancer, ECS, Docker Compose, or future Kubernetes readiness. This should be conservative about dependency failures so one dependency outage does not automatically cause all API tasks/pods to flap out of service. |
| Business/dependency readiness | Can this service currently perform its business job, including required dependencies? | Dependency probing, diagnostics, alerts, dashboards, and future observability history. For Postgres mode, this is where a database connectivity/check query belongs.                                                       |

Do not blindly point platform probes at every dependency check. A database
outage means the service is degraded or unable to fulfill some business
operations; it does not necessarily mean the API process should be restarted or
removed from every load balancer target.

---

## GraphQL Smoke Test

Once GraphQL is implemented, use `/graphql` for movie reservation operations.

Example query:

```graphql
query ListScreenings($movieId: ID) {
  screenings(movieId: $movieId) {
    id
    movieId
    auditoriumId
    startsAt
    seats {
      id
      row
      number
    }
  }
}
```

Example mutation:

```graphql
mutation RequestReservation($input: RequestReservationInput!) {
  requestReservation(input: $input) {
    id
    screeningId
    status
  }
}
```

Example polling query:

```graphql
query ReservationRequest($id: ID!) {
  reservationRequestStatus(id: $id) {
    id
    screeningId
    seatIds
    requestedByUserId
    status
  }
}
```

GraphQL is for business operations. Do not use GraphQL as the load balancer health check.

---

## Local Docker Compose Checks

Docker Compose can start Postgres, the app-local OpenTelemetry Collector, and a
compiled API container. The default `docker compose up -d postgres` path remains
available for host-based npm development.

Database scripts are split into two layers:

- `db:migrate`, `db:migrate:status`, and `db:seed:local` are environment
  agnostic. They expect `DATABASE_URL` and pool settings to come from the
  process environment, which is the same contract future ECS tasks or
  Kubernetes Jobs should use.
- `*:local-postgres` scripts are local developer conveniences. They load
  `movie-reservation-service/env_files/local/local-postgres.env` before
  running the same TypeScript migration and seed entrypoints.

Start local Postgres:

```sh
docker compose up -d postgres
```

Compose binds Postgres to `127.0.0.1:5432` so local tools can connect through
`localhost` without exposing the predictable development credentials on every
network interface.

Run schema migrations explicitly:

```sh
npm -w movie-reservation-service run db:migrate:local-postgres
```

Seed local/demo catalog data separately from migrations:

```sh
npm -w movie-reservation-service run db:seed:local-postgres
```

Run the API against Postgres:

```sh
npm -w movie-reservation-service run dev:local-postgres
```

Start the local collector when you want traces and metrics from a host-run API:

```sh
docker compose --profile observability up -d otel-collector
```

Host-run profiles send OTLP/HTTP to `http://localhost:14318`. The collector
forwards traces and metrics to `host.docker.internal:4317` by default, which is
intended to be the external observability stack collector. It also exposes
Prometheus metrics on `http://localhost:18889/metrics` as a local debugging
endpoint.

Run the compiled API container after migrations and seed data:

```sh
docker compose --profile api up -d --build api
```

The API container uses the in-Docker profile, sends OTLP to
`http://otel-collector:4318`, writes JSON logs to stdout, and publishes to host
port `3001` by default so it can run beside Grafana on host port `3000`.

The local Postgres profile enables the fake in-process reservation worker. It
is useful for local polling workflows, but it is not a production worker
runtime or the final control-plane/data-plane deployment shape.

Worker retries are split by failure type:

- lease timeouts are abandoned claims, usually caused by process crashes,
  deploy/scale-in interruption, OOM kills, missed heartbeats, blocked event
  loop work, or a hung database/external call;
- transient failures are handled processor errors. D6.1 keeps the classifier
  coarse by treating `unexpected-error` as retryable, then failing the request
  after the configured transient failure budget is exhausted.

Seat conflicts and invalid request data are business outcomes, not transient
failures, and should not be retried.

Check migration status:

```sh
npm -w movie-reservation-service run db:migrate:status:local-postgres
```

Open a `psql` shell inside the Postgres container:

```sh
docker compose exec postgres psql -U movie_reservation_service -d movie_reservation_service
```

The local Compose credentials are intentionally non-secret:

```text
user:     movie_reservation_service
password: movie_reservation_service
database: movie_reservation_service
```

Reset the local database volume when you want a clean database:

```sh
docker compose down -v
```

Migrations are not run by normal API startup. That keeps local behavior aligned
with the future ECS/Kubernetes model where a one-off task or job runs the same
compiled migration runner before API tasks receive traffic.

When an environment injects `DATABASE_URL` directly, use the generic commands:

```sh
npm -w movie-reservation-service run db:migrate
npm -w movie-reservation-service run db:migrate:status
```

For a Bash shell, you can also load the local Compose env file into the current
session and then run those same generic commands:

```sh
set -a
source movie-reservation-service/env_files/local/local-postgres.env
set +a

npm -w movie-reservation-service run db:migrate
npm -w movie-reservation-service run db:migrate:status
```

`set -a` makes variables read from the env file exported, so child processes
started by `npm` can see `COMPOSITION_PROFILE`, `DATABASE_URL`, and the pool
settings. This affects only the current shell session.

Postgres e2e tests use Testcontainers by default:

```sh
npm -w movie-reservation-service run test:e2e
```

To run the same e2e tests against a developer-managed database, use
`TEST_DATABASE_URL`. This mode is destructive to that database because the test
harness resets the `public` schema:

```sh
TEST_DATABASE_URL=postgres://movie_reservation_service:movie_reservation_service@localhost:5432/movie_reservation_service \
  npm -w movie-reservation-service run test:e2e:external
```

Observability smoke check:

```sh
npm -w movie-reservation-service run smoke:observability
```

Local observability checks:

- API responses echo `X-Correlation-Id` and `X-Request-Id`
- GraphQL operations increment `graphql_operation` metrics
- collector metrics are visible at `http://localhost:18889/metrics`
- external Prometheus scrapes the external stack collector after this repo
  pushes metrics to it over OTLP
- external Alloy/Loki collects JSON stdout logs from containers labelled
  `observability.logs=true`
- traces from the app-local collector reach the external stack collector

---

## Reservation Workflow Checks

Target checks:

- movies can be listed
- screenings can be listed
- a reservation request can be submitted
- the request can be polled by id
- the request eventually reaches `CONFIRMED`, `REJECTED`, or `FAILED`
- conflicting seat requests do not both confirm

Keep these checks local first. They become more useful than infrastructure checks because they prove the app still behaves correctly after moving from in-memory state to Postgres, then from in-process async work to SQS.

---

## Frontend Observability Checks

Target checks:

- the frontend can call the GraphQL API
- a browser action produces a backend trace
- `traceparent`, `tracestate`, `X-Correlation-Id`, and `X-Request-Id` are
  preserved from frontend to backend where feasible
- backend logs include the same trace id as the request trace
- failed reservation requests are visible in both UI state and backend logs

---

## k3d Checks

Target checks:

- cluster exists
- namespace exists
- deployment is available
- service has endpoints
- ingress route works
- readiness probe passes
- traces reach the collector
- app uses the same image contract as Docker Compose and ECS

Document exact `kubectl` commands once manifests exist.

---

## ECS Checks

Current checks for the in-memory ECS/ADOT stack:

- ECS service desired count equals running count;
- the essential app is running and the target group `GET /health` check passes;
- the nonessential `adot-collector` container reports its independent health
  state without gating app availability;
- app JSON logs and collector diagnostics arrive in separate CloudWatch log
  groups;
- `npm -w ecs-infra run smoke:xray` finds the exact generated trace and
  `movie-reservation-service` segment through `BatchGetTraces`;
- the task role and X-Ray endpoint policy expose only `PutTraceSegments` and
  `PutTelemetryRecords`;
- no metrics/AMP/Grafana or database resources appear before their own issues.

Use the exact AWS CLI inspection, trace smoke, rollback, and teardown commands
in [the local CDK deployment runbook](aws-cdk-local-deployment.md).

Future checks remain separate: issue #7 must prove the RDS migration `RunTask`,
and issue #8 must prove independently deployable API/worker signaling.

---

## Common Failure Modes To Document Later

- container fails to start
- wrong port configured
- `/health` path mismatch
- task cannot pull image
- task execution role missing permissions
- app task role too broad or too narrow
- database security group blocks app connections
- migrations were skipped before deploying code that expects a new schema
- migration task uses different environment variables than the API task
- SQS worker is not updating reservation request status
- dead-letter queue receives messages silently
- OpenTelemetry endpoint misconfigured while the application remains healthy
- collector unhealthy while ECS service health remains green
- collector running but X-Ray endpoint, IAM, or backend unavailable
- GraphQL schema generation fails because decorator metadata is missing
