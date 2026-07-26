# Platform Follow-up Tasks

Last reviewed: 2026-07-26

This file tracks platform, CI/CD, infrastructure workflow, and delivery-system follow-ups that are intentionally outside the current implementation slice.

Use `docs/plans/service-follow-up-tasks.md` for service/domain/API leftovers. Use this file for cross-cutting platform and delivery concerns.

## Telemetry Platform Debt

The delivered ECS trace path intentionally puts one ADOT collector sidecar in
each application task. That was acceptable for issue #37 because it proved one
private OTLP-to-X-Ray path with small blast radius, but it is not the long-term
microservice topology. Copying that shape into every service would multiply
collector CPU/memory, duplicate config, keep AWS X-Ray permissions on every app
task role, and make telemetry policy drift service by service.

- Design a dedicated OpenTelemetry collector ECS service or gateway before the
  platform hosts multiple independently deployed application services. The
  [gateway options note](../architecture/otel-collector-gateway-options.md)
  records the Cloud Map, internal NLB, Service Connect, internal ALB, and hybrid
  agent/gateway alternatives without selecting one. The follow-up should define
  discovery/DNS, security-group ingress, task sizing, horizontal scaling,
  Availability Zone placement, load balancing, deployment safety, and whether
  any per-task agent remains useful for local enrichment.
- Move X-Ray/telemetry backend credentials out of application task roles when a
  shared collector service exists. Today the app and sidecar share the same ECS
  task role, so the app can technically call the two X-Ray write APIs granted
  for ADOT.
- Keep the current app availability policy explicit: telemetry fails open. The
  app must not fail startup, `/health`, or platform readiness just because the
  collector, X-Ray endpoint, or telemetry backend is unavailable. The accepted
  cost is missing spans and metrics - we may be flying blind while the app is
  still serving traffic.
- Add telemetry-path health signals after the collector topology is decided:
  collector task health, restart count, exporter errors, queue/drop counters,
  end-to-end trace smoke, and alerts/SLOs for telemetry delivery. Do not hide
  telemetry outages inside application dependency checks.
- Define an X-Ray annotation allowlist before depending on searchable trace
  fields in AWS. The current ADOT config keeps `index_all_attributes: false`
  and has no `indexed_attributes`, so generic OTel attributes remain X-Ray
  metadata rather than searchable annotations. Any allowlist should use
  low-cardinality, nonsecret fields only. Do not index request IDs, correlation
  IDs, trace IDs, user IDs, reservation IDs, raw GraphQL variables, headers, or
  tokens.
- Revisit `enduser.id` before production authentication. It maps to X-Ray's
  dedicated `user` field independently of generic annotation indexing, so the
  current fixed demo user does not establish a production privacy policy.
- Add Renovate coverage for the pinned ADOT collector Docker base image. Keep
  the Dockerfile pinned by both release tag and immutable digest, but have
  Renovate open manual-review PRs for new ADOT releases. Each update should run
  `npm -w ecs-infra run validate:adot-image`, infra tests, CDK synth, and a
  deployed X-Ray smoke check before updating the Dockerfile verification note.

## CI/CD Hardening

Issue [#31](https://github.com/patex1987/golden-path-ecs-template/issues/31)
owns the next concrete CI strategy wave: frontend/browser verification,
Docker/Postgres e2e execution, and scalable workspace selection. The remaining
items below are design inputs, not separately committed deliverables.

- Define a dependency audit policy before making audit checks blocking. Decide severity thresholds, dev-dependency handling, exception workflow, and whether to use `npm audit`, GitHub Dependabot alerts, dependency review, or a combination.
- Revisit GitHub Actions supply-chain hardening. CI-1 pins official actions by major version; future work may require exact SHA pins, allowlisted actions, internal mirrored actions, Dependabot updates for action versions, or policy-as-code checks.
- Investigate CI caching strategy deeply before adding custom caches. Cover npm cache boundaries, monorepo cache boundaries, Docker layer caching, build artifacts, remote caches, cache poisoning risks, and invalidation policy.
- Design CI reports and artifact handling. Decide whether to upload test reports, coverage reports, CDK synthesized templates, build outputs, screenshots, Docker logs, and smoke-test reports; define retention and sanitization rules.
- Add CI observability as a platform concern. Track pipeline health, failure rates by job, flaky tests, queue time, runtime trends, cache hit rates, deployment gate failures, rollback signals, and whether CI/CD emits useful telemetry.
- Design Docker/Testcontainers e2e and smoke-test waves. Decide how service images move between jobs: rebuild in the e2e job, upload/download image artifacts, or push/pull from a registry such as GitHub Container Registry.
- Add a separate Postgres e2e CI job after the Docker runtime strategy is
  chosen. Compare Testcontainers against the runner Docker daemon, a
  CI-managed Postgres service, and Docker-in-Docker style setups for CI systems
  where the job itself runs inside a container. Keep this out of required CI
  until the job is stable enough not to make normal PR checks flaky.
- Revisit the `ecs-infra` Jest `maxWorkers: 1` cap after the CDK assertion and
  shell smoke suites are stable. Identify the worker shutdown issue, then either
  restore parallel Jest workers for pure CDK tests or split shell validation
  into separate CI steps so it does not constrain assertion-test parallelism.
- Design deployed system/smoke tests for dev, staging, and production-like
  environments. These may become deployment quality gates, rollback monitors,
  or operational smoke checks. If these checks grow beyond the current X-Ray
  helper, consider a dedicated root-level black-box e2e/smoke package that knows
  deployment endpoints and public contracts, not service internals.
- Revisit path filters, docs-only shortcuts, and fast non-production override pipelines once CI runtime affects developer experience. Consider playground/dev-stage workflows that trade broad validation for quick iteration outside production.
- Revisit required-check management if the list of GitHub Actions jobs changes often. A future aggregate `ci-success` job may make branch protection easier to maintain.
- Revisit Node version matrix testing only if the project commits to supporting multiple Node runtime versions.

## Developer Tooling

- Plan a migration from npm workspaces to pnpm workspaces as a learning exercise and to match likely company tooling. Cover `package.json` workspace configuration, lockfile replacement, `packageManager` pinning, Corepack setup, CI cache changes, README/workflow command updates, and a rollback path back to npm if the migration causes tool compatibility issues.

## Infrastructure Workflow

- Revisit whether `ecs-infra` should split into multiple packages when shared constructs, environment stacks, deployment tooling, or multiple independently owned infra modules exist.
- Keep CDK synth credential-free in pull-request CI where practical. If future CDK context lookups require AWS credentials, isolate that behavior in a separate deployment-oriented plan.
- Continue laptop-driven `cdk diff`, `deploy`, smoke, and `destroy` while the AWS
  learning stack is being proved. Do not make private deployment automation a
  prerequisite for issue #38.
- Design the private AWS deployment promotion workflow described in [ADR 015](../architecture/architecture-decisions.md#adr-015-keep-public-ci-credential-free-and-deploy-from-a-private-promotion-workflow). The public repository should remain credential-free; a private workflow should accept or approve an exact public commit SHA, re-run validation, pause behind a protected deployment environment, assume AWS roles through OIDC, and let CDK publish Docker image assets to the target account during deploy.
- Replace the temporary public-CI `allowedIngressCidr=203.0.113.10/32` synth convention when the private promotion workflow owns environment-specific CDK configuration. Do not solve this by adding AWS credentials, account identifiers, deploy-role access, or real environment values to the public workflow.
