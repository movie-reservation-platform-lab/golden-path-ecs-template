# Movie Reservation Platform Roadmap

Last reviewed: 2026-07-26

## Purpose

This is the canonical delivery roadmap for the repository. GitHub issues track
execution; detailed plans explain larger design decisions; documents under
`docs/plans/delivered/` are historical implementation records.

The target remains a small internal-platform-style movie reservation system
that teaches TypeScript, NestJS, OpenTelemetry, Docker, AWS CDK, ECS/Fargate,
and later Kubernetes without introducing all of those concerns at once.

## Current State

The repository currently contains three npm workspaces:

- `movie-reservation-service`: NestJS GraphQL API with in-memory and Postgres
  composition profiles, a deterministic in-process worker, structured JSON
  logging, and OpenTelemetry instrumentation;
- `movie-reservation-web`: React/Vite booking demonstrator with clean feature
  boundaries, runtime GraphQL response parsing, trace propagation, and Vitest
  coverage;
- `ecs-infra`: a tested CDK stack for a private Fargate task behind a
  CIDR-restricted public ALB, using CDK Docker image assets, no NAT Gateway, and
  private AWS service endpoints.

The ECS skeleton was deployed successfully from a laptop and destroyed on
2026-07-17. Public CI remains credential-free and validates all three
workspaces. AWS deployment automation is deliberately deferred.

## Delivered Milestones

| Milestone                                  | Issue               | Result                                                                                   |
| ------------------------------------------ | ------------------- | ---------------------------------------------------------------------------------------- |
| NestJS migration and movie reservation API | #1 and earlier work | NestJS health and GraphQL boundaries established                                         |
| D5 in-process processor contract           | #2                  | Reservation command processing separated behind application ports                        |
| D6 Postgres and Knex                       | #3                  | Local Postgres, migrations, repositories, and e2e coverage added                         |
| Service DI composition profiles            | #18                 | Runtime modes made explicit and typed                                                    |
| CI foundation                              | #14                 | Credential-free service, web, and CDK checks added                                       |
| D7 local observability                     | #4                  | JSON logs, OTel traces/metrics, collector, and local Grafana workflow added              |
| D8a frontend baseline                      | #23                 | React/Vite workspace and stabilized booking workflow adopted                             |
| ECS backend CDK skeleton                   | #6 / PR #36         | Fargate, ALB, image asset, logging, endpoints, tests, and local deployment runbook added |
| AWS ADOT/X-Ray trace path                  | #37 / PR #39        | Repo-owned ADOT sidecar, private X-Ray path, smoke tooling, and runbook added            |

The corresponding detailed records live in
[`delivered/`](delivered/).

## Active Workstreams

The next work is not one fully serial queue. The AWS managed-observability path
and the distributed local-demo adoption can progress independently. Each
workstream has its own internal ordering, and they converge before RDS or
Kubernetes work begins.

### Workstream A: AWS Managed Observability

#### A1. ADOT Traces And X-Ray

Issue: [#37](https://github.com/patex1987/golden-path-ecs-template/issues/37)

Status: delivered by PR #39.

The ECS stack now includes a repo-owned ADOT collector image and nonessential
sidecar. The in-memory NestJS service sends OTLP/HTTP traces through ADOT to
X-Ray over the private AWS path. Laptop-driven CDK deploy, smoke, diagnostics,
and destroy remain the operational workflow.

The historical implementation plan lives in
[`delivered/ecs-adot-xray-tracing.md`](delivered/ecs-adot-xray-tracing.md).

#### A2. Managed Metrics And Grafana

Issue: [#38](https://github.com/patex1987/golden-path-ecs-template/issues/38)

#38 is the current AWS managed-observability slice. Extend the delivered
ADOT/X-Ray baseline with bounded application and ECS metrics, export them to
CloudWatch and Amazon Managed Service for Prometheus, then connect Amazon
Managed Grafana and build the first useful dashboard.

The focused three-PR implementation plan is
[`ecs-adot-managed-metrics-grafana.md`](ecs-adot-managed-metrics-grafana.md).
The first slice, now in progress, proves CloudWatch metrics from the existing
in-memory service. The second adds AMP remote write and ECS metrics, and the
third adds Managed Grafana and the initial dashboard.

The production saturation/dashboard follow-up remains tracked by
[#30](https://github.com/patex1987/golden-path-ecs-template/issues/30).

The dependency inside this workstream is now satisfied: ADOT-to-X-Ray traces
landed in #37. Keep the ECS service in-memory throughout #38.

### Workstream B: Adopt The Distributed Observability Demo

Implementation already exists on `demo-multi-service-observability` branches
in this repository and the related Python agent, Rust recommendation, and
FastAPI observability repositories. An integrated local smoke test passed on
2026-06-11, but those changes are not part of the current `main` baseline.

The branch in this repository predates the current failure-injection work and
the ECS CDK skeleton. Treat this as an adoption and reconciliation task, not a
greenfield implementation and not a blind branch merge. The detailed inventory,
parallel work packages, and acceptance criteria are in
[`distributed-observability-demo-platform.md`](distributed-observability-demo-platform.md).

The adoption packages can run in parallel with #38:

- audit and transplant the reservation MCP and GraphQL read-model changes onto
  current `main`;
- reconcile the agent-assisted frontend with the D8 customer UI, exposing
  technical identifiers only in an explicit local demo mode;
- review and land the existing agent, recommendation API/MCP, and observability
  repository branches;
- reassemble the Compose topology, then rerun the happy, slow-dependency, and
  dependency-error distributed smoke scenarios.

Create a dedicated GitHub adoption issue, or a parent issue with repository
subtasks, before code is transplanted. The existing D8 and AWS issues do not own
this cross-repository landing work.

### Workstream C: Finish The D8 Frontend Product Slice

Parent issue: [#5](https://github.com/patex1987/golden-path-ecs-template/issues/5)

The technical frontend baseline exists, but the remaining D8 issues are still
open:

- #24: frontend foundation and GraphQL client acceptance;
- #25: customer booking workflow and polling states;
- #26: external observability verification;
- #27: final verification, docs, CI wiring, and browser smoke coverage.

Use
[`movie-reservation-frontend-product-requirements.md`](movie-reservation-frontend-product-requirements.md)
as the acceptance bar and
[`frontend-follow-up-triage.md`](frontend-follow-up-triage.md) for current
sequencing.

This workstream can proceed alongside AWS infrastructure work. Coordinate it
with Workstream B because both may change the frontend and GraphQL contract.
Reconcile the old issue descriptions and the demo branch before implementing
anything that appears missing.

## Convergence Gate Before Persistence

Before starting RDS or Kubernetes work:

- #38 has proved the intended AWS metric path, or an explicit decision has
  rescheduled the unfinished metrics work;
- the multi-service demo changes have been rebased or selectively transplanted
  onto the current repositories and reviewed;
- the normal customer UI and explicit local demo UI have distinct boundaries;
- the integrated multi-service smoke scenarios pass against the adopted code;
- remaining D8 issues describe actual gaps rather than already-implemented
  branch work.

This gate keeps the next data and runtime changes from being built on two
divergent application baselines.

## Subsequent Delivery Order

### 1. RDS And Deployment-Time Migrations

Issue: [#7](https://github.com/patex1987/golden-path-ecs-template/issues/7)

Provision RDS only after the in-memory managed-observability path is understood.
Migrations must run as a separate ECS `RunTask`, analogous to a Kubernetes Job,
against the reachable RDS endpoint. Do not add a Postgres sidecar to the API
task and do not run migrations during API startup.

CloudFormation does not model `RunTask` as a persistent resource, so migration
execution belongs to deployment orchestration. The initial orchestration may be
a laptop command/wrapper; the later private deployment workflow will run the
same task before updating the service.

### 2. Durable Worker Signaling

Issue: [#8](https://github.com/patex1987/golden-path-ecs-template/issues/8)

After durable persistence exists, separate the API control plane from worker
execution and add a signaling mechanism such as SQS. Postgres remains the
source of truth for reservation state; the queue wakes workers rather than
replacing durable state.

### 3. Kubernetes Target

Issue: [#9](https://github.com/patex1987/golden-path-ecs-template/issues/9)

Add k3d after the ECS path, RDS migration shape, and worker boundaries are
understood. Reuse the same image, health paths, environment contract, and OTel
signal conventions.

## Later Product And Platform Work

- #10: production authorization research and hardening;
- #11: GraphQL subscriptions after polling and auth behavior are stable;
- #12: payments exploration;
- #28, #29, and #32: explicit API read outcomes, catalog read-model ownership,
  and command idempotency;
- #31: scalable CI, Playwright, and Docker/Postgres e2e strategy;
- GraphQL client generation and schema-drift checks after the adopted contracts
  are stable;
- private AWS deployment promotion workflow from
  [ADR 015](../architecture/architecture-decisions.md#adr-015-keep-public-ci-credential-free-and-deploy-from-a-private-promotion-workflow);
- production hardening of the adopted multi-service demo, including OIDC/JWKS,
  service discovery, and non-demo deployment topology.

## Sequencing Rules

- Keep public CI credential-free.
- Continue laptop-driven CDK deployment until the private promotion workflow is
  implemented deliberately.
- Keep the AWS stack disposable and run `cdk destroy` after experiments.
- Add one managed telemetry path at a time: X-Ray is now delivered; metrics,
  AMP, and AMG are next.
- Keep the ECS service in-memory while implementing #38.
- Allow independent repository and AWS workstreams to proceed in parallel, but
  require explicit contract and integration gates before they converge.
- Adopt the existing multi-service branches before starting RDS or Kubernetes;
  do not reimplement their completed work from old plans or issue descriptions.
- Add RDS and the migration `RunTask` together under #7.
- Do not run database migrations from API startup.
- Keep metric labels bounded; identifiers belong in logs and traces.
- Extract reusable CDK constructs only after repeated resource patterns exist.

## Roadmap Completion Signals

The core learning path is complete when:

- the frontend can exercise the reservation workflow;
- the adopted local demo creates one distributed trace across the agent, MCP,
  recommendation, and reservation service boundaries;
- the same service contract runs locally, on ECS, and on k3d;
- ECS traces, logs, application metrics, and platform metrics are observable;
- RDS migrations run as an explicit deployment-time ECS task;
- the API and worker have durable, independently deployable boundaries;
- CI validates changes without holding deployment credentials;
- deployment and teardown procedures are documented and repeatable.
