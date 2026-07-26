# Implementation Plan: GitHub Actions CI Foundation

> Status: delivered by issue #14 / PR #15. Preserved as implementation history.

## 1. Summary

Add the first CI automation for this repository using GitHub Actions. The recommended approach is a small pull-request and main-branch workflow that installs dependencies with `npm ci`, runs visible check jobs for code quality, service behavior, and infrastructure, and synthesizes the CDK app without deploying anything.

This should be intentionally boring: CI should wrap the commands developers can run locally, then leave room for later jobs such as Docker image builds, security scans, deployment previews, smoke tests, and branch protection.

Deferred platform and delivery follow-ups from this plan are tracked in `docs/plans/platform-follow-up-tasks.md`.

## 2. Goals

- Add a GitHub Actions workflow for pull requests and pushes to `main`.
- Use npm workspaces and the existing package scripts instead of introducing a new task runner.
- Run formatting, linting, type checking, tests, builds, and CDK synth.
- Add a root `ci` script so local and GitHub checks share one command.
- Split the GitHub Actions workflow into distinct visible jobs so a pull request makes the failure category obvious from the checks list.
- Run the workflow in simple waves: quality checks first, then tests/build/infra after quality passes.
- Keep the first workflow independent of AWS credentials and deployment permissions.
- Require the CI jobs for changes to `main` immediately after the workflow exists.
- Document the CI contract clearly enough that later deliverables can extend it.

## 3. Non-goals

- Do not deploy to AWS.
- Do not build or push Docker images yet.
- Do not add Docker-network e2e, smoke, or Testcontainers-based checks to CI-1.
- Do not add CircleCI, Buildkite, Jenkins, or another CI provider.
- Do not add complex branch governance beyond requiring the first CI check on `main`.
- Do not add secrets, AWS credentials, OIDC federation, or deployment environments.
- Do not add dependency audit gates to the first blocking workflow.
- Do not pin GitHub Actions to exact commit SHAs in CI-1.
- Do not design a custom caching strategy in CI-1.
- Do not upload test reports, coverage reports, build artifacts, CDK synth artifacts, or logs as workflow artifacts in CI-1.
- Do not add special GitHub PR annotations, problem matchers, or CI observability instrumentation in CI-1.
- Do not add matrix builds for multiple Node versions in CI-1.
- Do not split the infrastructure workspace into multiple packages in CI-1.
- Do not add path filters, docs-only shortcuts, fast deploy override pipelines, or dev-stage deployment shortcuts in CI-1.

## 4. Current State

- The root `package.json` is an npm workspace with `movie-reservation-service` and `ecs-infra`.
- Root scripts currently provide:
  - `npm run build` as `npm run build --workspaces`
  - `npm test` as `npm run test --workspaces`
  - `npm run lint` as `npm run lint --workspaces --if-present`
- `movie-reservation-service/package.json` already has a strong `ci` script: `npm run check && npm run build`.
- Service `check` runs formatting check, oxlint, ESLint, TypeScript typecheck, and Vitest tests.
- The service test folder already has partial category structure: `test/domain`, `test/application`, `test/infrastructure`, `test/di`, and `test/e2e`.
- Current `test/e2e` tests start the Nest app in-process and use Supertest against HTTP/GraphQL. They are request/response e2e-style tests, not Docker/Testcontainers whole-stack tests.
- `movie-reservation-service/vitest.config.ts` currently includes all `test/**/*.test.ts` files, and `movie-reservation-service/package.json` exposes one `test` script for all Vitest tests.
- The current test folder does not fully match the intended long-term categories: unit, thin integration, Docker/Testcontainers e2e, and deployed system/smoke.
- `ecs-infra/package.json` has `build`, `test`, and `cdk` scripts.
- There is no `.github/workflows` directory.
- There is no `.circleci` directory.
- There is no committed Node version pin such as `.nvmrc`, `.node-version`, or an `engines.node` field.
- The local environment inspected for this plan uses Node `v24.14.0` and npm `11.9.0`.
- The roadmap already lists expected verification commands, including service checks, infra build/test, CDK synth, root build/test/lint.

## 5. Requirements and Assumptions

### Confirmed Requirements

- Start with something small that can be expanded later.
- GitHub Actions is good enough for the first CI provider.
- The first CI should cover checks such as linting, formatting, and building.
- CI-1 should create executable unit and thin-integration service test categories instead of running all current Vitest tests as one undifferentiated bucket.
- CI-1 should refactor the current service test folders to match the agreed test categories.
- The first CI check should become required for `main` as part of this task, even if the initial workflow needs follow-up fixes.
- Dependency audit checks should stay out of blocking CI for CI-1 and be tracked as later security hardening.
- The Node version choice should be documented in a simple, industry-standard way.
- The roadmap should include this work as a planned task.
- A GitHub issue should track the implementation work.

### Assumptions

- The repository's default protected branch is or will be `main`.
- CI should run on pull requests and pushes to `main`.
- CI-1 should run on all pull requests, not only path-filtered changes.
- CI should also support manual `workflow_dispatch` runs for learning and debugging.
- CI should cancel stale in-progress runs for the same branch when newer commits arrive.
- GitHub Actions should use official actions pinned by major version for CI-1, such as `actions/checkout@v4` and `actions/setup-node@v4`.
- CI-1 should use the standard `actions/setup-node@v4` npm cache.
- CI-1 should rely on GitHub Actions job logs for failure diagnosis. Artifact and report publishing should be a later investigation.
- CI-1 should not add special PR annotations. CI observability should be treated as a later platform concern.
- README updates should stay short and point to dedicated docs instead of duplicating CI details.
- CI-1 should add a short operational workflow document at `docs/workflows/ci-workflow.md`.
- Branch protection or a GitHub ruleset should require the CI workflow before merging to `main`.
- Branch protection should require all CI-1 jobs: `service-quality`, `service-unit-tests`, `service-integration-tests`, `service-build`, and `infra`.
- Node 24 is the right first CI runtime because the local repo currently uses Node 24 and the service uses modern Node flags such as `--env-file`.
- The repo should commit `.nvmrc` with `24`, and GitHub Actions should read that file with `node-version-file: .nvmrc`.
- CI-1 should run one Node version from `.nvmrc`, not a Node version matrix.
- `npm ci` should be used in CI because this repo has a committed `package-lock.json`.
- CDK synth should not require AWS credentials for the current infra app. If future CDK context lookups require credentials, that should be handled in a later deployment-oriented plan.
- Separate GitHub Actions jobs are worth the extra YAML because they make failures visible from the pull request checks list.
- The first CI pipeline should run cheap/static quality checks before heavier tests, builds, and CDK synth.
- Future e2e and smoke tests should be separate CI jobs or waves from unit/integration-style tests because they may need Docker, service images, and runtime dependencies.
- Existing in-process Nest/Supertest request/response tests should be treated as thin integration/API contract tests for CI-1, even if their current folder is named `e2e`.

### Open Questions

- None blocking CI-1. Deferred CI/CD hardening and delivery workflow questions are tracked in `docs/plans/platform-follow-up-tasks.md`.

## 6. Proposed Design

Add one root CI contract and one GitHub Actions workflow with small, distinct jobs.

The root script should stay readable and orchestrate workspace-level CI contracts:

```json
"ci": "npm -w movie-reservation-service run ci && npm -w ecs-infra run ci"
```

The service workspace should own its detailed service CI contract, including formatting, linting, typecheck, unit tests, integration tests, and build. This keeps the root `package.json` from becoming a long list of every service command while still preserving a single local `npm run ci` entry point.

The infra/CDK workspace should be validated separately from the service workspace. It can follow the same broad CI idea, but it should not be forced into the service's unit/integration/e2e taxonomy. CDK validation has a different shape:

- TypeScript build proves the CDK app compiles.
- Jest/CDK assertion tests prove selected constructs synthesize the expected AWS resources.
- `cdk synth` proves the CDK app can produce CloudFormation templates without deploying.

In other words, the root package orchestrates both workspaces, but each workspace owns checks that make sense for its responsibility.

Add an `ecs-infra` workspace `ci` script:

```json
"ci": "npm run build && npm test && npm run cdk -- synth"
```

This gives both workspaces the same ownership pattern without forcing them into the same internal check categories. A future platform may split infrastructure into multiple packages, for example shared constructs, environment stacks, or deployment tooling. Do not design for that now; keep CI-1 focused on the single existing `ecs-infra` workspace.

That makes `npm run ci` the local aggregate command. This is the same idea as a Python project putting `ruff`, `mypy`, and `pytest` behind one `make ci` target: the repository owns the quality contract, not the CI provider.

GitHub Actions should run the same underlying checks as separate jobs so a pull request shows which category failed without opening logs first. The first pipeline should use two simple waves:

Wave 1:

- `service-quality`: service formatting, oxlint, ESLint, and TypeScript typecheck.

Wave 2, after `service-quality` passes:

- `service-unit-tests`: service unit tests.
- `service-integration-tests`: service thin integration/API contract tests.
- `service-build`: service TypeScript build.
- `infra`: CDK workspace build, Jest tests, and CDK synth.

This does repeat `npm ci` across jobs, but that is acceptable for the first version because the repo is small and clear failure reporting matters more than optimizing CI minutes.

The tradeoff is that if `service-quality` fails, the second wave may be skipped. That is acceptable for CI-1 because formatting, linting, and type errors are cheap to fix and should be cleared before deeper checks matter.

`service-quality` should be one required job with named steps, not three separate required jobs. The pull request checks list should show the broad quality gate, while the job log should make the failing category clear:

- format check
- lint check
- typecheck

Future e2e and smoke tests should not be hidden inside the unit or integration jobs. They should become their own later wave, for example:

Wave 3, after service build and image build support exists:

- `service-image`: build the service container image.
- `e2e-smoke`: run Testcontainers, Docker Compose, or similar Docker-network tests against the built service image and dependencies.

That later design needs its own plan because GitHub Actions jobs run on separate runners. A Docker image built in one job is not automatically available in another job. The implementation will need to choose between pushing to a registry such as GitHub Container Registry, saving/loading a Docker image artifact, or building the image again inside the e2e job. CI-1 should leave this path open without implementing it.

Use these test category names consistently, aligned with the existing `vitest-testing` guidance and the Python/pytest mental model in `docs/learning/vitest-cheat-sheet.md`:

- Unit tests: domain logic and application services with direct construction.
- Thin integration tests: interactions between service components, such as repositories, DI composition, schema generation, or in-process Nest request/response tests.
- E2E tests: future Docker/Testcontainers tests that run the service with realistic dependencies.
- System/smoke tests: tests against an already deployed dev, staging, or production-like environment; these can become deployment quality gates, rollback monitors, or operational smoke checks.

CI-1 should refactor the current service test folders toward this shape:

```text
movie-reservation-service/test/
  unit/
    domain/
    application/
    config/
    infrastructure/
  integration/
    api/
    di/
    schema/
    infrastructure/
```

Current file mapping should be reviewed during implementation, but the intended direction is:

- `test/domain/*` -> `test/unit/domain/`
- `test/application/*` -> `test/unit/application/`
- simple parser/config tests that do not start Nest -> `test/unit/config/` or `test/unit/infrastructure/`
- repository behavior tests that exercise an adapter contract -> `test/integration/infrastructure/`
- DI composition tests -> `test/integration/di/`
- schema generation tests -> `test/integration/schema/`
- current Supertest/Nest HTTP and GraphQL request/response tests -> `test/integration/api/`

Do not create `test/e2e/` or `test/system/` in CI-1 unless there are real tests for those categories. Reserve those names for future Docker/Testcontainers and deployed-environment checks.

The GitHub Actions workflow should live at `.github/workflows/ci.yml` and should:

- trigger on `pull_request`
- trigger on pushes to `main`
- support `workflow_dispatch`
- use workflow concurrency to cancel stale runs for the same branch
- use `permissions: contents: read`
- use official actions pinned by major version, such as `actions/checkout@v4`
- use `actions/setup-node@v4` with `node-version-file: .nvmrc` and `cache: npm`
- run `npm ci`
- run the relevant workspace commands for each job
- set a reasonable timeout such as 15 minutes

This first design deliberately avoids a Node version matrix, deployment environments, AWS credentials, and secret access. The workflow's jobs prove the repository is formatted, linted, typed, tested, buildable, and CDK-synthesizable on the runtime version the project intends to use.

Use one Node version from `.nvmrc` for CI-1. A Node matrix is useful for libraries that promise compatibility across multiple Node versions. This repository is an application/platform template, so testing the intended runtime is enough for the first CI foundation.

Run CI-1 on all pull requests. Path filters are intentionally deferred because required checks can become awkward when workflows are skipped, and the repo is still small. Later, developer experience may require a more nuanced pipeline design: docs-only shortcuts, path-filtered jobs, fast "playground" or dev-stage deployment workflows, or remote-override-style pipelines that trade broad validation for quick feedback in non-production environments. That should be planned separately because it changes the balance between safety and speed.

Pinning actions by major version is the right first step for this proof-of-concept because it is readable and widely used. In larger companies, the policy is often stricter: exact SHA pins, allowlisted actions, internal mirrored actions, Dependabot updates for action versions, or policy-as-code checks. Treat that as later supply-chain hardening, not CI-1.

Use the built-in npm cache support from `actions/setup-node@v4` for CI-1. Do not add custom `actions/cache` keys yet. Caching strategy deserves its own later review because it can involve dependency manager behavior, monorepo cache boundaries, Docker layer caching, build artifacts, remote caches, cache poisoning risks, and invalidation policy.

Do not upload workflow artifacts in CI-1. GitHub Actions logs are enough for the first pass. Test reports, coverage reports, CDK synthesized templates, build outputs, screenshots, Docker logs, and smoke-test reports should be reviewed later as a reporting/artifact strategy. That later work should decide what is useful, how long artifacts should be retained, and whether any generated output could contain sensitive values.

Do not add special GitHub PR annotations or problem matchers in CI-1. They belong with a later CI observability and reporting review. That future work should look beyond developer convenience and ask how the platform team understands CI health over time: failure rates by job, flaky tests, queue time, runtime trends, cache hit rates, deployment gate failures, rollback signals, and whether CI/CD pipelines themselves emit useful telemetry. Business service observability is not enough if the platform and delivery path are opaque.

Use a workflow-level concurrency group so repeated pushes to the same branch cancel stale runs:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

This keeps CI feedback focused on the newest commit during active iteration.

After the workflow exists, configure GitHub branch protection or a repository ruleset so the CI jobs are required before merging to `main`. This is intentionally stricter than the lowest-risk rollout path. The accepted tradeoff is that a broken first workflow may temporarily block merges, but that is acceptable for this proof-of-concept and better matches normal team-owned repository practice.

Require all five CI-1 jobs directly:

- `service-quality`
- `service-unit-tests`
- `service-integration-tests`
- `service-build`
- `infra`

Do not add an aggregate `ci-success` job in CI-1. An aggregate required check can be useful later if the internal job list changes often, but it is extra YAML for the first version.

## 7. Alternatives Considered

### Alternative A: One Small GitHub Actions Workflow

- Pros:
  - Smallest useful CI step.
  - Uses the existing GitHub-centered workflow.
  - Easy to understand while learning CI.
  - No new external service or account setup.
  - Can be expanded later with more jobs.
- Cons:
  - Less parallelism than split jobs.
  - One failure blocks visibility into later checks in the same job.
- Decision: Use one workflow, but split it into multiple visible jobs rather than one broad job.

### Alternative B: Split Workflow Jobs by Workspace

- Pros:
  - Faster feedback once the repo grows.
  - Separate service and infra failures are easier to scan.
  - Natural place to add path filters later.
- Cons:
  - More YAML and more CI concepts up front.
  - Repeats setup steps unless carefully factored.
  - Requires multiple required checks or a later aggregate check.
- Decision: Adopt a small version now because visible failure categories are useful even in this proof-of-concept.

### Alternative C: Multi-Job Workflow With Quality Gate First

- Pros:
  - Gives visible PR checks and a clean pipeline shape.
  - Runs cheap/static checks before heavier checks.
  - Matches many mature CI pipelines where lint/type gates precede tests, builds, and deployment stages.
- Cons:
  - Downstream jobs may be skipped when quality fails, so the engineer may need another run to see later failures.
  - Requires `needs` relationships between jobs.
- Decision: Recommended for CI-1.

### Alternative D: One Job With Named Steps

- Pros:
  - Keeps branch protection to one check.
  - Avoids repeated dependency installation.
  - Still gives readable logs after opening the job.
- Cons:
  - The pull request checks list only shows one broad failure.
  - Engineers must open the job to learn whether formatting, tests, build, or infra failed.
- Decision: Reject for CI-1 because outside-the-PR visibility is a stated goal.

### Alternative E: CircleCI First

- Pros:
  - Fine CI product with reusable executors and workflows.
  - Useful if a workplace already standardizes on CircleCI.
- Cons:
  - Adds another service and project integration before the repo needs it.
  - Does not fit the current GitHub issue and branch workflow as naturally.
- Decision: Reject for now. Revisit only if there is a concrete reason to compare providers.

## 8. API / Interface Changes

- Add a root npm script:
  - `npm run ci`
- Add a GitHub Actions workflow:
  - `.github/workflows/ci.yml`
- No service HTTP, GraphQL, domain, persistence, or CDK construct APIs change.

## 9. Data Model / Persistence Changes

None.

## 10. Security, Privacy, and Abuse Considerations

- Use least-privilege workflow permissions with `contents: read`.
- Pin official GitHub Actions by major version in CI-1.
- Defer stricter action pinning, such as exact commit SHAs or allowlisted internal actions, to later supply-chain hardening.
- Use standard `actions/setup-node@v4` npm caching in CI-1.
- Defer custom dependency, build artifact, and Docker layer caching strategy to a later review.
- Use GitHub Actions job logs for CI-1 failure diagnosis.
- Defer test reports, coverage reports, build artifacts, CDK synth artifacts, and richer log collection to a later reporting/artifact review.
- Defer GitHub PR annotations, problem matchers, and CI observability instrumentation to a later platform observability review.
- Do not add repository secrets for this first workflow.
- Do not grant AWS credentials or GitHub OIDC cloud federation in the baseline CI workflow.
- Do not run deployment commands from pull requests.
- Prefer `npm ci` over `npm install` so CI uses the committed lockfile exactly.
- Keep dependency audit checks out of the first blocking workflow. Add them later only after the project defines severity thresholds, dev-dependency handling, and an exception process.

## 11. Performance, Scalability, and Reliability Considerations

- Separate jobs make pull request failures easier to diagnose from the checks list.
- `service-quality` should be the first wave because format, lint, and type failures are cheap feedback and should block heavier checks.
- Keep formatting, linting, and typecheck as named steps inside one `service-quality` job to avoid noisy required checks.
- `actions/setup-node@v4` npm caching should reduce repeated install time without adding custom cache key logic.
- Repeated `npm ci` work is acceptable for now because the repository is small.
- Custom cache key design, Docker layer caching, and artifact caching should be reviewed in a follow-up because cache invalidation and cache trust are broader CI/CD design topics.
- If test suites grow, add path filters or targeted jobs only after the repository has enough history to justify that complexity.
- CDK synth should stay credential-free; future context lookups or deployment jobs should be isolated from pull-request checks.

## 12. Implementation Steps

1. Add the root CI script.
   - Change: Add `ci` to the root `package.json`.
   - Files/modules likely affected: `package.json`.
   - Notes: Keep the root command readable. It should delegate service detail to `npm -w movie-reservation-service run ci` and infra detail to `npm -w ecs-infra run ci`.
   - Verification: `npm run ci`.

2. Add the infra CI script.
   - Change: Add `ci` to `ecs-infra/package.json`.
   - Files/modules likely affected: `ecs-infra/package.json`.
   - Notes: The infra `ci` script should run build, Jest tests, and CDK synth. Do not split the infra workspace in CI-1.
   - Verification: `npm -w ecs-infra run ci`.

3. Add the GitHub Actions workflow.
   - Change: Create `.github/workflows/ci.yml`.
   - Files/modules likely affected: `.github/workflows/ci.yml`.
   - Notes: Use Node 24 through `.nvmrc`, `npm ci`, npm cache, read-only permissions, no secrets, official actions pinned by major version, `workflow_dispatch`, concurrency cancellation, and separate jobs for service quality, service unit tests, service integration tests, service build, and infra checks. Configure `service-quality` as one job with named format, lint, and typecheck steps. Configure `service-unit-tests`, `service-integration-tests`, `service-build`, and `infra` to need `service-quality`.
   - Verification: Inspect workflow syntax and run `npm run ci` locally.

4. Refactor service test categories.
   - Change: Move current service tests into `test/unit/**` and `test/integration/**` folders that match the agreed category definitions.
   - Files/modules likely affected: `movie-reservation-service/test/**`.
   - Notes: Current `test/e2e/graphql.test.ts` and HTTP health request/response tests should move under `test/integration/api/` because they start the Nest app in-process with local/fake infrastructure. Do not add Docker/Testcontainers e2e or deployed system tests in CI-1.
   - Verification: `npm -w movie-reservation-service test`.

5. Add category-specific service test scripts.
   - Change: Add npm scripts for unit and integration test categories while preserving `npm test` as the full service test command. Update the service `ci` script so the service workspace owns formatting, linting, typecheck, unit tests, integration tests, and build.
   - Files/modules likely affected: `movie-reservation-service/package.json`, possibly `movie-reservation-service/vitest.config.ts` if separate include patterns are clearer than CLI path arguments.
   - Notes: Prefer the simplest maintainable script shape, for example `test:unit` for `test/unit/**/*.test.ts` and `test:integration` for `test/integration/**/*.test.ts`. Update `check` and `ci` only if needed to keep the local aggregate behavior equivalent.
   - Verification:
     - `npm -w movie-reservation-service run test:unit`
     - `npm -w movie-reservation-service run test:integration`
     - `npm -w movie-reservation-service test`

6. Add a Node version pin.
   - Change: Add `.nvmrc` with `24` and configure GitHub Actions to read it.
   - Files/modules likely affected: `.nvmrc`, `.github/workflows/ci.yml`, `README.md`.
   - Notes: `.nvmrc` is a simple, widely understood Node version marker. It keeps the CI runtime and local developer runtime aligned without adding a stricter package-engine policy yet.
   - Verification: `node --version` locally matches the intended major version after using the repo's Node version file, and GitHub Actions logs show Node 24.

7. Add CI workflow documentation.
   - Change: Create `docs/workflows/ci-workflow.md` as the short operational guide for local CI commands, test categories, GitHub Actions jobs, required checks, and CI-1 non-goals.
   - Files/modules likely affected: `docs/workflows/ci-workflow.md`, `docs/index.md`.
   - Notes: Keep this doc practical. It should link to this implementation plan and `docs/plans/platform-follow-up-tasks.md` instead of repeating every planning tradeoff.
   - Verification: The workflow doc explains how to run CI locally and how the GitHub Actions jobs map to local commands.

8. Update README and roadmap pointers.
   - Change: Add a short README pointer to `docs/workflows/ci-workflow.md`, mention `npm run ci` only briefly, and keep the roadmap linked to this plan.
   - Files/modules likely affected: `README.md`, `docs/index.md`, `docs/plans/movie-reservation-platform-roadmap.md`.
   - Notes: Do not make README the source of truth for CI. Prefer dedicated documents under `docs/`; README needs broader refactoring later. Document the test category meaning so `unit`, `integration`, future `e2e`, and future `system/smoke` stay distinct in the workflow doc.
   - Verification: Docs point to the CI command and plan without duplicating too much YAML detail.

9. Validate on GitHub.
   - Change: Open a pull request with the workflow and confirm GitHub Actions runs.
   - Files/modules likely affected: GitHub Actions UI, pull request checks.
   - Notes: The first run may expose workflow setup bugs. Fix those in the same CI task rather than weakening the gate.
   - Verification: Pull request shows a passing CI check.

10. Require CI for `main`.
   - Change: Configure GitHub branch protection or a repository ruleset so the CI jobs must pass before merging to `main`.
   - Files/modules likely affected: GitHub repository settings; optionally document the chosen setting in `README.md` or the implementation PR notes.
   - Notes: Require all five CI-1 jobs directly: `service-quality`, `service-unit-tests`, `service-integration-tests`, `service-build`, and `infra`. Prefer the simplest GitHub-native setting. This is repository configuration, not application code. If GitHub requires status checks to exist before they can be selected, configure them immediately after the first workflow run appears.
   - Verification: A pull request cannot merge to `main` while a required CI job is failing or pending.

## 13. Testing Strategy

- Local regression check: `npm run ci`.
- Documentation check:
  - `docs/workflows/ci-workflow.md` exists and points to the detailed plan and platform follow-up tasks.
  - README links to the workflow doc instead of duplicating CI details.
- Service checks through existing script:
  - formatting check
  - oxlint
  - ESLint
  - TypeScript typecheck
  - Vitest unit tests
  - Vitest thin integration/API contract tests
  - service build
- Service test category checks:
  - `npm -w movie-reservation-service run test:unit`
  - `npm -w movie-reservation-service run test:integration`
  - `npm -w movie-reservation-service test`
- Infra checks:
  - TypeScript build
  - Jest tests
  - CDK synth
  - `npm -w ecs-infra run ci`
- Workflow validation:
  - GitHub Actions should pass on the implementation pull request.
  - GitHub Actions should support manual `workflow_dispatch` runs.
  - A newer push to the same branch should cancel stale in-progress runs.
  - GitHub Actions should show separate service quality, service unit test, service integration test, service build, and infra checks.
  - The service quality job should have named steps for format, lint, and typecheck.
  - Service unit tests, service integration tests, service build, and infra jobs should depend on service quality.
  - E2E, smoke, Docker-network, and Testcontainers checks are not part of CI-1.
  - Branch protection or a repository ruleset should require the CI jobs for `main`.

## 14. Rollout / Migration Plan

- Add the workflow in one pull request.
- Run the full local `npm run ci` before opening the pull request.
- Let the pull request prove the workflow runs in GitHub Actions.
- If the workflow fails because of environment mismatch, fix the environment contract first, such as Node version or missing generated files.
- Require the CI jobs for `main` as soon as GitHub can select the workflow checks. Do not wait for the CI setup to become production-perfect.
- Rollback is a git revert of the CI workflow and root script. No runtime data or deployed infrastructure is affected.
  If branch protection itself blocks urgent fixes, temporarily relax the required check, merge the CI fix, then re-enable the requirement.

## 15. Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|---|---:|---:|---|
| CI uses a different Node version than local development | Medium | Medium | Commit `.nvmrc` with `24` and have GitHub Actions read it with `node-version-file`. |
| Node matrix adds complexity while the project is still learning TypeScript/Node | Low | Medium | Use one Node version from `.nvmrc`; add a matrix only if the project later promises multi-version support. |
| Full CI on every PR becomes frustrating for quick dev-stage iteration | Medium | Medium | Run all PR checks in CI-1; later design path filters or fast non-production override pipelines when CI runtime becomes painful. |
| Required check list becomes annoying to maintain | Low | Medium | Require all five CI-1 jobs directly for now; add an aggregate `ci-success` job later if job churn becomes painful. |
| Workflow becomes a dumping ground for all future checks | Medium | Medium | Keep first workflow small; add separate jobs/plans for Docker, security, and deploy gates later. |
| Required CI blocks merges because the initial workflow has a bug | Medium | Medium | Accept this for the POC; fix the workflow in the CI task or temporarily relax the required check if needed. |
| Multi-job CI repeats dependency installation | Low | Medium | Accept the cost for clearer PR checks; optimize with caching or job restructuring only after runtime becomes painful. |
| Downstream jobs are skipped when quality fails | Low | Medium | Accept this pipeline shape; fix quality issues first, then rerun to expose deeper failures. |
| Stale CI runs waste time during active iteration | Low | High | Add workflow-level concurrency with `cancel-in-progress: true`. |
| Action version policy is too loose for a larger company | Medium | Medium | Pin official actions by major version for CI-1; revisit SHA pinning, allowlists, or mirrored actions during supply-chain hardening. |
| Naive caching strategy hides stale state or creates security risk | Medium | Low | Use only setup-node npm cache in CI-1; plan a deeper caching strategy review later. |
| CI artifacts expose sensitive generated output later | Medium | Low | Do not upload artifacts in CI-1; investigate report/artifact retention and sanitization before adding uploads. |
| CI/CD platform remains opaque compared with business services | Medium | Medium | Defer CI observability from CI-1, but explicitly plan future telemetry for pipeline health, flaky tests, queue time, and deployment gates. |
| README becomes a dumping ground for CI detail | Low | Medium | Add only a short pointer in README and keep detailed CI documentation under `docs/`. |
| Test category refactor misclassifies tests | Medium | Medium | Use the existing `vitest-testing` taxonomy; keep in-process Nest/Supertest tests under integration, not future Docker e2e. |
| E2E/smoke tests get mixed into fast service tests | Medium | Medium | Keep CI-1 service tests focused; add a later e2e/smoke wave with explicit image/dependency handling. |
| CDK synth unexpectedly needs AWS credentials | Medium | Low | Keep first infra code credential-free; move credentialed deploy work to a separate workflow. |
| Infra workspace grows beyond one package | Low | Medium | Keep CI-1 scoped to existing `ecs-infra`; revisit infra package split only when shared constructs or multiple stack packages exist. |
| Dependency audit noise blocks useful work | Medium | Medium | Keep audits out of CI-1 and add a later security hardening task with severity thresholds and exception rules. |
| Too many required checks become noisy | Low | Medium | Keep CI-1 to five clear jobs and avoid adding Docker, audit, deploy, or matrix jobs until planned separately. |

## 16. Done Criteria

- `.github/workflows/ci.yml` exists.
- `.nvmrc` exists and pins Node 24.
- Root `npm run ci` exists and passes locally.
- `ecs-infra` exposes its own `ci` script.
- Service tests are organized under `test/unit/**` and `test/integration/**` for the categories that exist today.
- Service package scripts expose `test:unit` and `test:integration`.
- GitHub Actions runs on pull requests and pushes to `main`.
- GitHub Actions runs for all pull requests without path filters.
- GitHub Actions supports manual `workflow_dispatch` runs.
- GitHub Actions cancels stale in-progress runs for the same branch.
- GitHub Actions uses official actions pinned by major version.
- GitHub Actions uses `actions/setup-node@v4` npm caching.
- GitHub Actions runs one Node version from `.nvmrc`, not a matrix.
- GitHub Actions relies on job logs only; no reports or artifacts are uploaded in CI-1.
- GitHub Actions does not add special PR annotations or problem matchers in CI-1.
- GitHub Actions exposes distinct checks for service quality, service unit tests, service integration tests, service build, and infra.
- Service quality is one job with named format, lint, and typecheck steps.
- Service unit tests, service integration tests, service build, and infra checks run after service quality passes.
- GitHub branch protection or a repository ruleset requires the CI jobs before merging to `main`.
- Branch protection requires all five CI-1 jobs directly, with no aggregate `ci-success` job.
- CI uses `npm ci`, not `npm install`.
- CI runs service formatting, linting, typecheck, unit tests, integration tests, and build.
- CI runs infra build, tests, and CDK synth.
- The infra workspace is not split into multiple packages in CI-1.
- Future Docker-network e2e/smoke checks are explicitly deferred to a separate later wave.
- Dependency audit checks are explicitly deferred from blocking CI-1.
- Workflow uses read-only repository permissions and no secrets.
- Roadmap references this CI deliverable and plan.
- README includes only a short pointer to the dedicated CI documentation.
- `docs/workflows/ci-workflow.md` exists as the operational CI guide.
- Deferred CI/CD hardening and delivery workflow items are tracked in `docs/plans/platform-follow-up-tasks.md`.

## 17. Review Checklist

- [ ] Requirements are explicit
- [ ] Non-goals are explicit
- [ ] Existing code conventions were checked
- [ ] Alternatives were considered
- [ ] Security implications were reviewed
- [ ] Scalability and reliability implications were reviewed
- [ ] Testing strategy is complete
- [ ] Rollout and rollback are defined
- [ ] Implementation steps are ordered and concrete

## 18. Handoff Prompt for Implementation Agent

Copy/paste this prompt into a coding agent:

```text
Implement the plan in docs/plans/github-actions-ci-foundation.md.

Constraints:
- Stay within the scope of the plan.
- Do not introduce new dependencies unless the plan explicitly allows it.
- Preserve existing public behavior unless the plan explicitly changes it.
- Follow existing project conventions.
- Refactor current service tests into `test/unit/**` and `test/integration/**`; reserve `test/e2e/**` and `test/system/**` for future Docker/Testcontainers and deployed-environment tests.
- Treat current in-process Nest/Supertest request/response tests as integration/API contract tests, not future Docker e2e tests.
- Keep the first GitHub Actions workflow free of secrets, AWS credentials, and deployment behavior.
- Configure GitHub branch protection or a repository ruleset so the CI jobs are required before merging to main.
- Update tests and docs described in the plan.
- If implementation reality differs from the plan, stop and update the plan or ask for approval before changing scope.

Relevant files/modules:
- package.json
- .nvmrc
- movie-reservation-service/package.json
- movie-reservation-service/vitest.config.ts
- movie-reservation-service/test/**
- ecs-infra/package.json
- .github/workflows/ci.yml
- README.md
- docs/workflows/ci-workflow.md
- docs/index.md
- docs/plans/movie-reservation-platform-roadmap.md

Expected verification commands:
- npm -w movie-reservation-service run test:unit
- npm -w movie-reservation-service run test:integration
- npm -w movie-reservation-service test
- npm -w ecs-infra run ci
- npm run ci
```
