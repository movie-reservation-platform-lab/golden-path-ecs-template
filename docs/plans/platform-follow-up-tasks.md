# Platform Follow-up Tasks

This file tracks platform, CI/CD, infrastructure workflow, and delivery-system follow-ups that are intentionally outside the current implementation slice.

Use `docs/plans/service-follow-up-tasks.md` for service/domain/API leftovers. Use this file for cross-cutting platform and delivery concerns.

## CI/CD Hardening

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
- Design deployed system/smoke tests for dev, staging, and production-like environments. These may become deployment quality gates, rollback monitors, or operational smoke checks.
- Revisit path filters, docs-only shortcuts, and fast non-production override pipelines once CI runtime affects developer experience. Consider playground/dev-stage workflows that trade broad validation for quick iteration outside production.
- Revisit required-check management if the list of GitHub Actions jobs changes often. A future aggregate `ci-success` job may make branch protection easier to maintain.
- Revisit Node version matrix testing only if the project commits to supporting multiple Node runtime versions.

## Developer Tooling

- Plan a migration from npm workspaces to pnpm workspaces as a learning exercise and to match likely company tooling. Cover `package.json` workspace configuration, lockfile replacement, `packageManager` pinning, Corepack setup, CI cache changes, README/workflow command updates, and a rollback path back to npm if the migration causes tool compatibility issues.

## Infrastructure Workflow

- Revisit whether `ecs-infra` should split into multiple packages when shared constructs, environment stacks, deployment tooling, or multiple independently owned infra modules exist.
- Keep CDK synth credential-free in pull-request CI where practical. If future CDK context lookups require AWS credentials, isolate that behavior in a separate deployment-oriented plan.
- Design the private AWS deployment promotion workflow described in [ADR 015](../architecture/architecture-decisions.md#adr-015-keep-public-ci-credential-free-and-deploy-from-a-private-promotion-workflow). The public repository should remain credential-free; a private workflow should accept or approve an exact public commit SHA, re-run validation, pause behind a protected deployment environment, assume AWS roles through OIDC, and let CDK publish Docker image assets to the target account during deploy.
- Replace the temporary public-CI `allowedIngressCidr=203.0.113.10/32` synth convention when the private promotion workflow owns environment-specific CDK configuration. Do not solve this by adding AWS credentials, account identifiers, deploy-role access, or real environment values to the public workflow.
