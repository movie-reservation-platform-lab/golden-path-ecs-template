# CI Workflow

This repository uses a small GitHub Actions CI foundation for pull requests, pushes to `main`, and manual runs.

The workflow is intentionally deployment-free. It proves the service, web, and
CDK workspaces are typed, tested, buildable, and CDK-synthesizable where
applicable without using AWS credentials or repository secrets.

## Local Commands

Run the full local CI contract from the repository root:

```sh
npm run ci
```

That delegates to the workspace-owned CI commands:

```sh
npm -w movie-reservation-service run ci
npm -w ecs-infra run ci
npm -w movie-reservation-web run check
```

This is the current small-repo monorepo contract: the root `ci` command runs all
three workspaces so local and pull-request checks do not forget the frontend.
Issue #31 owns the future CI design for affected/path-filtered workspace checks,
Playwright browser tests, Docker/Postgres e2e checks, and slower merge-time
integration jobs once the repository grows.

The local service `ci` script includes `test:e2e`, so it requires Docker for
the Testcontainers Postgres database. The GitHub Actions workflow currently
spells out its jobs manually and intentionally skips the Docker/Postgres e2e
step until that CI runtime strategy is designed.

The service workspace also exposes category-specific test commands:

```sh
npm -w movie-reservation-service run test:unit
npm -w movie-reservation-service run test:integration
npm -w movie-reservation-service test
```

The infrastructure workspace also validates the pinned collector artifact and
the credential-free parts of the X-Ray smoke tool:

```sh
npm -w ecs-infra run validate:adot-image
npm -w ecs-infra run validate:xray-smoke
```

The collector command builds and starts the repository-owned image, then runs
its bundled `/healthcheck`. It supplies no AWS credentials and exports no test
trace. The smoke validation performs shell/static helper checks; Jest uses fake
`aws` and `curl` executables to cover structured success and failure reports.

## Runtime Version

Node is pinned with `.nvmrc`:

```text
24
```

GitHub Actions reads the same file through `actions/setup-node`, so local development and CI use the same intended Node major version.

## Test Categories

- Unit tests live under `movie-reservation-service/test/unit/**`.
- Thin integration tests live under `movie-reservation-service/test/integration/**`.
- Postgres e2e tests live under `movie-reservation-service/test/e2e/**`, but
  they are local/manual checks for now. They require Docker/Testcontainers or a
  developer-managed Postgres database and are intentionally not part of the
  required CI-1 workflow yet.
- The X-Ray smoke helper has credential-free local tests, while a real deployed
  trace remains a laptop system/smoke check until the private promotion
  workflow exists.

Current in-process NestJS Supertest checks are integration/API contract tests because they start the app in-process with local/fake infrastructure. They are not Docker-network e2e tests.

## GitHub Actions Jobs

The workflow at `.github/workflows/ci.yml` exposes six required CI-1 jobs:

- `service-quality`: service format check, lint checks, and TypeScript typecheck.
- `service-unit-tests`: service unit tests.
- `service-integration-tests`: service thin integration/API contract tests.
- `service-build`: service TypeScript build.
- `infra`: CDK workspace build, Jest tests, pinned ADOT image/config/health
  validation, X-Ray smoke-tool validation, and `cdk synth`.
- `web`: frontend TypeScript typecheck, Vitest tests, and Vite production build.

As a temporary CI-only bridge, the `infra` job synthesizes with
`allowedIngressCidr=203.0.113.10/32`. `203.0.113.0/24` is reserved for
documentation, so this gives credential-free CI a deterministic,
non-production configuration without allowing public internet ingress. It is
not the final environment-configuration design and must not be reused as a
deployment default.

The public workflow must remain credential-free: it must not receive AWS access
keys, an AWS OIDC deploy role, account-specific deployment configuration, or
permission to publish CDK assets. Pulling the public pinned ADOT base image and
building a local Docker image does not grant AWS deployment authority. Real
`cdk diff`, `deploy`, trace export, and `destroy`
operations belong to the private promotion workflow described by
[ADR 015](../architecture/architecture-decisions.md#adr-015-keep-public-ci-credential-free-and-deploy-from-a-private-promotion-workflow).
That workflow will check out an approved public commit SHA, assume a short-lived
AWS role through OIDC, and provide the real restricted ingress CIDR explicitly.

`service-unit-tests`, `service-integration-tests`, `service-build`, and `infra`
run after `service-quality` passes. The `web` job runs separately so frontend
failures are visible as their own pull request check.

## Required Checks

Branch protection or a GitHub repository ruleset should require these checks before merging to `main`:

- `service-quality`
- `service-unit-tests`
- `service-integration-tests`
- `service-build`
- `infra`
- `web`

GitHub may require the workflow to run once before these status checks are available to select in repository settings.

## Deferred Work

CI-1 does not include deployment, Docker image publishing, real X-Ray export,
dependency audit gates, action SHA pinning, custom caches, artifact uploads, test reports,
special PR annotations, Node matrices, Docker/Testcontainers e2e checks,
Playwright browser checks, affected/path-filtered workspace selection, or
deployed smoke tests.

Issue #31 tracks the next CI strategy wave: keep fast workspace checks stable,
decide which checks should be path/affected-filtered, decide where Playwright
frontend/backend tests run, and design Docker/Postgres e2e without making normal
pull request checks flaky.

Postgres e2e tests should be added later as a separate CI job after the Docker
runtime strategy is chosen. On GitHub-hosted Ubuntu runners, Testcontainers can
usually talk to the runner VM's Docker daemon directly. In GitLab-style Docker
executor jobs, the equivalent setup often needs Docker-in-Docker or an exposed
Docker socket because the test process is already running inside a container.
An alternative is to run Postgres as a CI service/Compose dependency and execute
the e2e suite in external database mode.

The delivered foundation design is in
[github-actions-ci-foundation.md](../plans/delivered/github-actions-ci-foundation.md).
Deferred hardening and delivery work is tracked in
[platform-follow-up-tasks.md](../plans/platform-follow-up-tasks.md).
