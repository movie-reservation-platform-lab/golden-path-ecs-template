# Implementation Plan: CDK Application Image Artifact Contract

> Status: proposed implementation plan for issue
> [#50](https://github.com/movie-reservation-platform-lab/golden-path-ecs-template/issues/50).
> This planning branch does not change synthesized infrastructure.

Last reviewed: 2026-07-31

## 1. Summary

Decouple the CDK application deployment path from the local
`movie-reservation-service` source checkout while preserving the current local
learning and deployment path.

The implementation introduces one application-image boundary with two modes:

- `local-docker-asset`, the backward-compatible default, builds the existing
  service Dockerfile and derives `SERVICE_VERSION` from its package metadata;
- `ecr-image` consumes a complete, digest-pinned private Amazon ECR image and an
  explicit service version without reading the service source tree.

The first ECR contract is deliberately narrow: the repository must already
exist in the deployment account and Region. CDK imports that repository and
uses `ecs.ContainerImage.fromEcrRepository`, which binds the required ECR pull
permissions to the ECS task execution role. Issue #50 does not provision,
populate, query, or delete the repository.

`GoldenPathDemoStack` will consume one resolved `ecs.ContainerImage` and service
version. Everything after that boundary—the task definition, application
container, ALB target, health check, logging, environment, and telemetry—stays
unchanged.

This contract is the prerequisite for moving `ecs-infra` into a future
infrastructure repository. It is not the repository extraction, service image
publishing pipeline, private promotion workflow, or real deployment proof.

## 2. Goals

- Make the reservation service image an explicit, typed CDK deployment input.
- Preserve the current local `DockerImageAsset` behavior as the default.
- Allow credential-free synthesis from an immutable, same-account,
  same-Region ECR image reference without the reservation service checkout.
- Remove the hidden external-mode dependency on
  `movie-reservation-service/package.json`.
- Validate the image contract strictly and offline before deployment.
- Grant ECR pull permissions to the ECS task execution role without granting
  application task-role access.
- Preserve the current ECS runtime, networking, health, logging, telemetry,
  and deployment behavior.
- Prove local and ECR modes with focused tests and credential-free public CI
  synthesis.
- Document the durable artifact decision and the concrete operator workflow.
- Deliver the work through small, independently reviewable pull requests.

## 3. Non-goals

- Do not move `ecs-infra` or create `movie-platform-infra`.
- Do not build, publish, mirror, scan, sign, or attest a service image.
- Do not provision or delete an ECR repository.
- Do not query ECR during synthesis or prove that a referenced digest exists.
- Do not deploy or destroy AWS resources.
- Do not implement the future environment-manifest or promotion repository.
- Do not add AWS credentials, deployment authority, or registry credentials to
  public CI.
- Do not support cross-account ECR, cross-Region ECR, ECR Public, GHCR, or
  generic private registries in this slice.
- Do not externalize the repository-owned ADOT collector image; it remains an
  infrastructure Docker asset.
- Do not change application behavior, ECS sizing, networking, deployment
  percentages, health timing, failure injection, or telemetry topology.
- Do not generalize the implementation for every future Python or Rust service
  before a second workload proves the reusable shape.
- Do not implement the two-level lab teardown model in issue #50.

## 4. Current State

### CDK entrypoint and configuration

[`ecs-infra/bin/infra.ts`](../../ecs-infra/bin/infra.ts) reads CDK context,
resolves one `PlatformConfig`, and creates `GoldenPathDemoStack`. Its stack
environment comes from `CDK_DEFAULT_ACCOUNT` and `CDK_DEFAULT_REGION`.

[`ecs-infra/lib/config/platform-config.ts`](../../ecs-infra/lib/config/platform-config.ts)
is the existing untrusted-input boundary:

- `PlatformConfigContext` accepts `unknown` values from CDK context;
- `resolvePlatformConfig` validates and normalizes those values once;
- `PlatformConfig` gives the stack a resolved TypeScript shape.

This is the correct boundary for mode selection and runtime input validation.
Raw `tryGetContext` calls and unvalidated image strings must not spread into the
stack.

### Current application image coupling

[`ecs-infra/lib/infra-stack.ts`](../../ecs-infra/lib/infra-stack.ts) currently:

1. computes the monorepo root;
2. creates the `AppImage` `DockerImageAsset`;
3. builds `movie-reservation-service/Dockerfile` with the repository root as
   Docker context;
4. reads `movie-reservation-service/package.json`;
5. converts the asset into an `ecs.ContainerImage`;
6. injects the package version as `SERVICE_VERSION`.

The Dockerfile needs the repository root because it copies workspace metadata
and the root lockfile. Moving CDK while retaining that flow would merely replace
visible colocation with a cross-repository source checkout.

The package-version read is a second coupling. ECR mode must provide its own
service version or CDK would still require service package metadata.

### Current runtime and network contract

The application task currently has:

- service and container name `movie-reservation-service`;
- Linux/x86-64 Fargate runtime behavior;
- application port `3000`;
- bind address `0.0.0.0`;
- ALB health path `/health`, requiring HTTP `200`;
- CloudWatch Logs integration;
- `SERVICE_VERSION` in logs and OpenTelemetry resource identity;
- OTLP/HTTP export to task-local ADOT at `http://127.0.0.1:4318`;
- existing composition, worker, failure-injection, GraphiQL, and observability
  environment settings.

Fargate tasks run in private isolated subnets with no NAT gateway and no public
IP. ECR API and ECR Docker interface endpoints plus the S3 gateway endpoint
provide the existing private image-pull path. A generic public registry image
would require outbound internet connectivity that the task does not have.

### Current tests and CI

[`ecs-infra/test/infra.test.ts`](../../ecs-infra/test/infra.test.ts) uses Jest
and CDK assertions through a synthesis helper. It already covers the config
boundary and behaviorally important CloudFormation properties.

The public `infra` GitHub Actions job builds, tests, validates, and runs one
credential-free local-mode synthesis. The `ecs-infra` `ci` script mirrors that
single synthesis path.

### Existing architecture decisions

- [ADR 015](../architecture/architecture-decisions.md#adr-015-keep-public-ci-credential-free-and-deploy-from-a-private-promotion-workflow)
  keeps AWS credentials and deployment authority out of public CI.
- [ADR 021](../architecture/architecture-decisions.md#adr-021-use-runtime-boundary-repositories-under-the-platform-organization)
  keeps CDK colocated temporarily and names issue #50 as the prerequisite for a
  future infrastructure-repository extraction.

## 5. Requirements and Assumptions

### Confirmed issue requirements

- Supplying neither application image reference nor service version selects
  local mode.
- Supplying both valid values selects ECR mode.
- Supplying only one value fails fast with a key-specific error.
- ECR mode accepts only a complete private ECR URI pinned by SHA-256 digest.
- The ECR account and Region must match the concrete deployment target.
- Validation is offline; synthesis must not call AWS or the registry.
- `applicationServiceVersion` is opaque and non-empty. CDK must not require
  semantic versioning.
- The ECR repository is imported, not created.
- ECR pull access belongs to the ECS task execution role, not the task role.
- Local mode remains the default and preserves its current asset settings and
  package-derived version.
- Public CI synthesizes both modes without AWS credentials.
- A real mirror and ECS deployment are separate follow-up work.

### Accepted target operating model

The following decisions define the direction that issue #50 prepares for but
does not implement:

1. Each service repository builds, tests, and publishes its own immutable
   candidate artifact after a successful merge to `main`.
2. Artifact publication is not deployment. A candidate can exist without being
   promoted anywhere.
3. Public service CI publishes a candidate without AWS access. The private
   promotion path copies the exact artifact into environment ECR without
   rebuilding it.
4. The digest-pinned ECR reference is the canonical deployment identity.
   `applicationServiceVersion` is human/telemetry-facing metadata; a future
   promotion manifest also records source revision.
5. A future private promotion repository stores a Git-versioned manifest for
   each environment. GitHub is the first operator UI; a developer portal is
   deferred and may later act as a UI over the same Git state.
6. Merging an environment-manifest change initiates deployment. Explicit PRs
   promote revisions from dev to staging to production.
7. Every environment has quality gates and promotion blockers; dev is a
   controlled integration environment, not an ungoverned junkyard.
8. Components are promoted independently by default. A multi-component
   manifest change is reserved for releases that genuinely require coordinated
   compatible versions.
9. Durable per-service ECR repositories belong to platform foundation
   infrastructure. Workload stacks import and consume them; service
   repositories and workload stacks do not own their lifecycle.
10. Routine runtime teardown removes costly ECS, ALB, endpoint, observability,
    and log resources. A separate explicit full-lab purge may empty and delete
    disposable ECR mirrors and bootstrap artifacts. Production-like foundation
    resources retain artifacts.

### Assumptions

- The first ECR implementation targets the standard AWS commercial partition
  and a repository in the stack's account and Region.
- `CDK_DEFAULT_ACCOUNT` and `CDK_DEFAULT_REGION` are concrete for ECR-mode
  deployment.
- Public CI may set explicit dummy account and Region values to prove ECR-mode
  synthesis; these are validation inputs, not credentials.
- The ADOT asset still requires the infrastructure checkout and Docker for a
  real CDK deployment.
- Compatibility enforcement, consumer contract testing, promotion policies,
  and multi-service release orchestration remain follow-up platform work.

### Open questions

None block issue #50.

Follow-up work must still select the public candidate registry, define the
mirroring implementation, design environment manifests and gates, and prove one
real mirrored deployment.

## 6. Proposed Design

### 6.1 Typed application-image configuration

Add a discriminated union to
`ecs-infra/lib/config/platform-config.ts`:

```ts
export type ApplicationImageConfig =
  | {
      readonly kind: 'local-docker-asset';
    }
  | {
      readonly kind: 'ecr-image';
      readonly imageReference: string;
      readonly registryAccount: string;
      readonly registryRegion: string;
      readonly repositoryName: string;
      readonly imageDigest: string;
      readonly serviceVersion: string;
    };
```

Add `applicationImage: ApplicationImageConfig` to `PlatformConfig`, and accept
these untrusted context inputs:

```ts
readonly applicationImageReference?: unknown;
readonly applicationServiceVersion?: unknown;
```

The parsed ECR attributes prevent the image adapter from reparsing a raw string.
The discriminant prevents a partially resolved ECR configuration from reaching
the stack, similar to how a Rust enum carries variant-specific fields.

### 6.2 Mode selection and strict offline validation

`resolvePlatformConfig` applies this matrix:

| Image reference | Service version | Result |
| --- | --- | --- |
| omitted | omitted | `local-docker-asset` |
| valid ECR digest URI | non-empty | `ecr-image` |
| present | omitted | fail: missing `applicationServiceVersion` |
| omitted | present | fail: missing `applicationImageReference` |
| malformed, mutable, or mismatched | present | fail with the violated contract |

A valid first-slice reference has this shape:

```text
123456789012.dkr.ecr.eu-central-1.amazonaws.com/movie-reservation-service@sha256:<64-hex-digest>
```

Validation must:

- trim both inputs;
- require a 12-digit registry account;
- require a private ECR hostname, non-empty repository name, and full digest;
- reject tags, including `latest` and semantic-version tags;
- reject a bare repository, bare digest, malformed account or Region, and a
  digest shorter or longer than 64 hexadecimal characters;
- require a concrete deployment account and Region in ECR mode;
- compare the parsed registry account and Region with the deployment target;
- avoid network, AWS SDK, context-provider, and registry calls.

The CDK entrypoint should resolve the target once from
`CDK_DEFAULT_ACCOUNT`/`CDK_DEFAULT_REGION`, supply it to the validation
boundary, and pass the same target into `StackProps.env`. Local mode remains
compatible with the current environment-agnostic CI synthesis.

Runtime validation protects the boundary from raw CDK inputs. The TypeScript
union protects internal code after parsing; compile-time types alone cannot
validate command-line context.

### 6.3 Dedicated application-image boundary

Add `ecs-infra/lib/application-image.ts`, not
`ecs-infra/lib/assets/application-artifact.ts`.

The module name reflects that an imported ECR image is a deployment input, not
a CDK asset. It returns:

```ts
export interface ResolvedApplicationImage {
  readonly image: ecs.ContainerImage;
  readonly serviceVersion: string;
}
```

For `local-docker-asset`, it will:

- compute the existing repository root;
- create `AppImage` with the current Dockerfile, context, ignore rules, and
  construct ID;
- read the existing service package version;
- return `ContainerImage.fromDockerImageAsset(appImage)` and that version.

For `ecr-image`, it will:

- avoid service path and package metadata access;
- import the pre-existing same-account/same-Region repository by name;
- call `ContainerImage.fromEcrRepository(repository, imageDigest)`;
- return the ECR image and configured service version.

Binding the returned ECR image to the task definition lets CDK add repository
pull permissions to the task execution role. The application task role receives
no ECR permissions. Repository import synthesizes no `AWS::ECR::Repository`.

`infra-stack.ts` consumes only the returned `image` and `serviceVersion` for the
application container. ADOT asset construction stays in the stack.

### 6.4 CDK, CloudFormation, and deployed-resource behavior

Local mode:

```text
CDK code
  -> DockerImageAsset
  -> CDK cloud-assembly asset
  -> bootstrap ECR publication during deploy
  -> ECS task definition references the published asset
```

ECR mode:

```text
CDK code
  -> import existing same-account/same-Region ECR repository
  -> ContainerImage.fromEcrRepository(repository, sha256 digest)
  -> execution-role repository pull grant
  -> no application Docker asset
  -> ECS task definition references the selected immutable image
```

Both modes synthesize the same ECS service, task sizing, load balancer, health
check, network, logs, and observability resources. Only application image
identity, `SERVICE_VERSION`, and ECR execution-role authorization differ.

Synthesis proves parsing, construct wiring, IAM generation, and CloudFormation
shape. It does not prove repository existence, image compatibility, or a
successful pull.

### 6.5 Future artifact and promotion flow

The long-term flow is:

```text
service main
  -> build/test candidate once
  -> publish immutable candidate
  -> private promotion mirrors identical bytes into environment ECR
  -> environment manifest records digest + version + source revision
  -> gated manifest merge
  -> infrastructure deploys the selected ECR digest
```

No portal or database becomes a second source of truth. A future portal may
render or edit the Git-backed manifest through reviewed pull requests.

### 6.6 Cost and teardown boundary

Issue #50 creates no ECR repository, so the current stack's normal destroy
behavior remains unchanged.

In the future split:

- runtime stacks own disposable/costly runtime resources and are safe to
  destroy routinely;
- foundation stacks own ECR mirrors and other durable deployment prerequisites;
- a lab profile may use `RemovalPolicy.DESTROY` plus `emptyOnDelete`;
- a production-like profile retains repositories;
- an explicit full-lab purge handles artifact deletion separately from routine
  runtime teardown.

This separation prevents a normal application teardown from deleting rollback
artifacts while preserving a deliberate minimum-cost escape hatch.

### 6.7 Pull request sequence

Use issue #50 as the umbrella across four small PRs:

1. Planning PR — current branch
   `issue-50_infra-image-artifact-contract`
   - add and index this revised plan;
   - reference #50 without closing it;
   - make no production, CI, or synthesized-infrastructure change.

2. PR 50-A — behavior-preserving image extraction
   - suggested branch:
     `issue-50_infra-extract-application-image`;
   - add `application-image.ts`;
   - move only current local `AppImage` and package-version behavior behind it;
   - wire the stack to the returned image/version pair;
   - add focused regression coverage;
   - keep every public interface and synthesized behavior unchanged.

3. PR 50-B — ECR image contract
   - suggested branch:
     `issue-50_infra-ecr-image-contract`;
   - add the config union, pair validation, ECR parser, target matching,
     ECR import, execution-role pull grant, tests, and dual CI synthesis;
   - preserve local mode as the default;
   - reference #50 without closing it.

4. PR 50-C — durable documentation and closure
   - suggested branch:
     `issue-50_docs-image-artifact-contract`;
   - add the ADR and update architecture, runbook, and CI documentation;
   - move this plan to `docs/plans/delivered/`;
   - use `Closes #50` only after 50-A and 50-B have merged.

Each code PR answers one review question: did extraction preserve behavior, and
does the ECR contract work correctly?

## 7. Alternatives Considered

### Alternative A: Generic `ContainerImage.fromRegistry`

- Pros:
  - accepts many OCI registries;
  - requires little parsing.
- Cons:
  - does not grant private ECR pull permissions;
  - generic public registries require internet egress that isolated tasks do
    not have;
  - fails to model the selected private mirroring architecture.
- Decision: rejected.

### Alternative B: Same-account, same-Region private ECR import

- Pros:
  - works with the existing no-NAT ECR endpoint path;
  - `fromEcrRepository` grants pull access to the execution role;
  - keeps repository ownership outside the workload stack;
  - provides an incremental path to future environment promotion.
- Cons:
  - intentionally excludes cross-account and generic registries;
  - requires explicit target account and Region.
- Decision: accepted.

### Alternative C: Provision ECR in the workload stack

- Pros:
  - makes a demo deployment self-contained.
- Cons:
  - couples durable artifact lifecycle to routine runtime teardown;
  - conflicts with foundation ownership;
  - still does not populate the repository.
- Decision: rejected.

### Alternative D: Query ECR during synthesis

- Pros:
  - can prove that the repository and digest currently exist.
- Cons:
  - requires AWS credentials and account access;
  - breaks credential-free public CI;
  - makes synthesis dependent on mutable external state.
- Decision: rejected. Existence belongs to promotion/deployment validation.

### Alternative E: Replace local mode immediately

- Pros:
  - removes all application source coupling at once.
- Cons:
  - breaks the current learning and local deployment path;
  - requires publishing and mirroring before the contract is proven.
- Decision: rejected.

### Alternative F: Clone service source from the infra workflow

- Pros:
  - requires little CDK change.
- Cons:
  - preserves build-time coupling, checkout credentials, and source-layout
    assumptions;
  - prevents independent immutable releases and deterministic rollback.
- Decision: rejected.

### Alternative G: Configuration-first PR

- Pros:
  - minimizes the number of files in the first code PR.
- Cons:
  - merges configuration that no deployment path consumes;
  - makes the first slice conceptually incomplete.
- Decision: rejected in favor of a behavior-preserving vertical extraction.

## 8. API / Interface Changes

There is no application HTTP or GraphQL API change.

The CDK CLI gains two optional paired context values:

```text
applicationImageReference
applicationServiceVersion
```

Local synthesis remains:

```bash
npm -w ecs-infra run cdk -- synth \
  -c allowedIngressCidr=203.0.113.10/32
```

ECR synthesis requires a concrete matching target:

```bash
CDK_DEFAULT_ACCOUNT=123456789012 \
CDK_DEFAULT_REGION=eu-central-1 \
npm -w ecs-infra run cdk -- synth \
  -c allowedIngressCidr=203.0.113.10/32 \
  -c applicationImageReference=123456789012.dkr.ecr.eu-central-1.amazonaws.com/movie-reservation-service@sha256:<64-hex-digest> \
  -c applicationServiceVersion=<opaque-release-identifier>
```

Internal TypeScript changes:

- `PlatformConfigContext` accepts the two raw context values;
- target account and Region are supplied to the config resolver;
- `PlatformConfig` contains `applicationImage`;
- `ApplicationImageConfig` models valid local/ECR states;
- `ResolvedApplicationImage` gives the stack one image/version pair.

## 9. Data Model / Persistence Changes

None.

There are no schema changes, migrations, backfills, or application data
compatibility concerns.

## 10. Security, Privacy, and Abuse Considerations

- Require digest pinning so a mutable tag cannot deploy different bytes under
  unchanged reviewed configuration.
- Validate same-account and same-Region ownership to avoid silently widening
  IAM or network scope.
- Import the specific repository and rely on its pull grant; do not add broad
  wildcard ECR repository access.
- Keep ECR pull permission on the task execution role. Application code does
  not need ECR API access.
- Do not accept or log passwords, tokens, or AWS credentials as CDK context.
- Keep public CI credential-free and permissioned only for source access.
- Treat digest identity as necessary but insufficient trust. Signing, SBOMs,
  scanning, provenance attestations, and promotion authorization remain future
  controls.
- Image reference and service version are non-secret and may appear in
  synthesized templates and CI logs.
- A malicious promoted image runs with the existing task role; the future
  private promotion workflow must authorize deployable digests.

## 11. Performance, Scalability, and Reliability Considerations

- ECR mode avoids application source hashing, Docker build, and application
  asset publication during CDK deployment.
- The infra-owned ADOT image remains a Docker asset, so this issue does not
  remove all Docker requirements from real infra deployment.
- Existing private ECR and S3 endpoints provide the application image-pull path
  without NAT.
- Digest pinning makes rollback deterministic: redeploy a previously accepted
  digest/version pair.
- ECS circuit-breaker and rollback behavior remain unchanged.
- A missing repository/digest, unsupported architecture, invalid image startup,
  or failed health check appears during deployment, not synthesis.
- The first runtime contract remains Linux/x86-64, port `3000`, and `/health`.
- No request-path latency, scaling, or application resource usage changes.

## 12. Implementation Steps

### Planning PR

1. Finalize the design record
   - Change:
     - revise this plan with the accepted ECR-specific contract, long-term
       operating model, validation boundary, tests, and PR sequence;
     - keep the plan linked from `docs/index.md`.
   - Files/modules:
     - `docs/plans/cdk-application-image-artifact-contract.md`
     - `docs/index.md`
   - Verification:
     - inspect the documentation diff;
     - verify the index link resolves.

### PR 50-A: behavior-preserving extraction

2. Extract the current local image resolver
   - Change:
     - add `ResolvedApplicationImage`;
     - move the current `AppImage` asset construction and service package
       version read into `application-image.ts`;
     - return the image/version pair;
     - leave ADOT asset construction in `infra-stack.ts`;
     - replace the stack's local variables with the resolver result.
   - Files/modules:
     - new `ecs-infra/lib/application-image.ts`
     - `ecs-infra/lib/infra-stack.ts`
     - existing helpers under `ecs-infra/lib/assets/`
   - Notes:
     - preserve `AppImage`, Docker context, Dockerfile, ignore behavior, and
       package path exactly;
     - add no ECR config or branch yet.
   - Verification:
     - local task image and `SERVICE_VERSION` remain unchanged;
     - all existing infra tests pass.

3. Add extraction regression coverage
   - Change:
     - assert the resolver still creates the local `AppImage`;
     - retain task definition, port, health, environment, logs, telemetry, IAM,
       and deployment assertions.
   - Files/modules:
     - `ecs-infra/test/infra.test.ts`
   - Verification:
     - `npm -w ecs-infra run build`;
     - `npm -w ecs-infra test -- --runInBand`;
     - local credential-free CDK synth.

### PR 50-B: ECR image contract

4. Add the typed config and target-aware parser
   - Change:
     - add `ApplicationImageConfig`;
     - add `applicationImage` to `PlatformConfig`;
     - read both context values at the entrypoint;
     - pass one target account/Region object to both config resolution and
       stack `env`;
     - implement pair selection and strict offline ECR validation.
   - Files/modules:
     - `ecs-infra/bin/infra.ts`
     - `ecs-infra/lib/config/platform-config.ts`
     - `ecs-infra/test/infra.test.ts`
   - Notes:
     - raw external values remain `unknown` until parsed;
     - local mode may synthesize without a concrete target;
     - ECR mode requires and matches a concrete target;
     - keep service version opaque.
   - Verification:
     - focused configuration matrix tests;
     - build/typecheck through the workspace build.

5. Add the ECR resolver branch
   - Change:
     - extend `application-image.ts` for `ecr-image`;
     - import the parsed repository without provisioning it;
     - call `ContainerImage.fromEcrRepository` with the parsed digest;
     - ensure the ECR branch never reads service source or package metadata.
   - Files/modules:
     - `ecs-infra/lib/application-image.ts`
     - `ecs-infra/lib/infra-stack.ts`
   - Notes:
     - keep the stack as a consumer of one image/version result;
     - keep ADOT unchanged.
   - Verification:
     - ECR mode has no `AppImage`;
     - no `AWS::ECR::Repository` is synthesized;
     - task definition uses the selected digest;
     - execution role receives repository pull permissions;
     - task role does not receive ECR pull permissions.

6. Add focused CloudFormation and regression tests
   - Change:
     - cover every config variant and failure;
     - assert ECR image identity and `SERVICE_VERSION`;
     - assert execution-role ECR authorization;
     - assert unchanged application name, port, health check, environment,
       logging, telemetry, networking, and deployment settings.
   - Files/modules:
     - `ecs-infra/test/infra.test.ts`
   - Notes:
     - assert behaviorally important structure, not complete snapshots,
       generated logical IDs, or asset hashes.
   - Verification:
     - `npm -w ecs-infra test -- --runInBand`.

7. Synthesize both modes in public CI
   - Change:
     - retain local-mode synthesis;
     - add ECR-mode synthesis with a clearly fake but valid matching account,
       Region, repository, all-zero digest, and `ci-contract-test` version;
     - align the package `ci` script and GitHub Actions job.
   - Files/modules:
     - `ecs-infra/package.json`
     - `.github/workflows/ci.yml`
   - Notes:
     - set dummy `CDK_DEFAULT_ACCOUNT` and `CDK_DEFAULT_REGION` only for the ECR
       synth;
     - no AWS credentials, OIDC, registry call, pull, or deployment;
     - label the reference as non-deployable.
   - Verification:
     - run both synth paths locally;
     - inspect workflow permissions and environment values.

### PR 50-C: documentation and closure

8. Record the durable architecture decision
   - Change:
     - append an ADR for service-owned immutable candidates, private ECR
       mirroring, digest-based deployment, foundation repository ownership, and
       transitional local mode;
     - explain how it evolves ADR 015 and ADR 021.
   - Files/modules:
     - `docs/architecture/architecture-decisions.md`
   - Verification:
     - inspect the focused ADR diff and references.

9. Update architecture and operator documentation
   - Change:
     - show local and ECR image paths in the ECS deployment architecture;
     - document ECR execution-role permissions and the existing no-NAT endpoint
       path;
     - add local/ECR synth, diff, deploy, rollback, validation-failure, and
       teardown guidance;
     - explain both credential-free CI synthesis checks.
   - Files/modules:
     - `docs/architecture/ecs-fargate-deployment.md`
     - `docs/operations/aws-cdk-local-deployment.md`
     - `docs/workflows/ci-workflow.md`
   - Verification:
     - inspect the documentation diff;
     - validate changed relative links.

10. Close the planning lifecycle
    - Change:
      - move this plan to
        `docs/plans/delivered/cdk-application-image-artifact-contract.md`;
      - add it to the delivered-plan index;
      - update `docs/index.md`;
      - close #50 from the final PR.
    - Files/modules:
      - this plan
      - `docs/plans/delivered/README.md`
      - `docs/index.md`
    - Notes:
      - keep the plan active until PR 50-A and PR 50-B are merged;
      - use `Closes #50` only in PR 50-C.
    - Verification:
      - no stale active-plan link remains;
      - GitHub closes #50 after the final merge.

## 13. Testing Strategy

### Configuration unit tests

- no external inputs resolves local mode;
- a valid matching ECR digest URI plus version resolves ECR mode;
- values are trimmed;
- image without version fails;
- version without image fails;
- blank values fail;
- mutable tags fail;
- bare digest and bare repository fail;
- malformed account, Region, repository, or SHA-256 digest fails;
- ECR mode without concrete target account or Region fails;
- registry account mismatch fails;
- registry Region mismatch fails;
- no test performs an AWS or registry call.

### CDK and CloudFormation tests

- local mode still creates `AppImage`;
- local mode still injects package version `1.0.0`;
- ECR mode does not create `AppImage`;
- ECR mode synthesizes no `AWS::ECR::Repository`;
- ECR mode selects the expected repository and digest;
- ECR mode injects the explicit `SERVICE_VERSION`;
- the execution role receives the expected ECR authorization-token and
  repository pull actions;
- the application task role receives no ECR pull actions;
- ADOT remains a Docker image asset;
- container name, port `3000`, ALB `/health`, logging, environment, telemetry,
  service deployment, and networking behavior remain unchanged.

### Credential-free synthesis tests

Run local mode:

```bash
npm -w ecs-infra run cdk -- synth \
  -c allowedIngressCidr=203.0.113.10/32
```

Run ECR contract mode:

```bash
CDK_DEFAULT_ACCOUNT=111111111111 \
CDK_DEFAULT_REGION=eu-central-1 \
npm -w ecs-infra run cdk -- synth \
  -c allowedIngressCidr=203.0.113.10/32 \
  -c applicationImageReference=111111111111.dkr.ecr.eu-central-1.amazonaws.com/ci-placeholder@sha256:0000000000000000000000000000000000000000000000000000000000000000 \
  -c applicationServiceVersion=ci-contract-test
```

The second command proves parsing, target matching, repository import, task
image wiring, IAM generation, and CloudFormation synthesis. It does not prove
that the placeholder repository or digest exists.

### Broader regression for each code PR

```bash
npm -w ecs-infra run build
npm -w ecs-infra test -- --runInBand
npm -w ecs-infra run validate:adot-image
npm -w ecs-infra run validate:xray-smoke
npm -w ecs-infra run validate:managed-metrics-smoke
npm -w ecs-infra run validate:grafana-dashboard
```

No live AWS test is required for #50. A follow-up must mirror a real candidate,
deploy it through the private path, verify ECS reaches steady state and
`/health`, and test rollback to a previous digest.

## 14. Rollout / Migration Plan

1. Merge the planning PR; no runtime or CloudFormation behavior changes.
2. Merge PR 50-A; local mode remains the only mode and its behavior is
   preserved behind the new boundary.
3. Merge PR 50-B; local mode remains the default while ECR mode becomes
   available and CI-proven.
4. Merge PR 50-C; record the decision, publish operator instructions, archive
   the plan, and close #50.
5. In a separate issue, provision/identify the foundation ECR repository,
   publish and mirror one real candidate without rebuilding, deploy its digest,
   verify health, and prove rollback.
6. Extract `ecs-infra` only after the real artifact path works and remaining
   repository-relative dependencies are inventoried.

Rollback remains simple:

- PR 50-A can be reverted without an external contract dependency;
- omitting both external values returns to local mode after PR 50-B;
- an ECR deployment rolls back by restoring the previously accepted
  digest/version pair;
- a failed ECR rollout does not require rebuilding the artifact.

## 15. Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
| --- | ---: | ---: | --- |
| ECR mode still accesses reservation service files | High | Medium | Keep every source/package read inside the local union branch and assert `AppImage` is absent externally |
| Mutable image identity causes non-repeatable deployment | High | Medium | Accept only full private ECR references pinned by 64-character SHA-256 digest |
| Registry account or Region does not match the stack | High | Medium | Require a concrete target and compare it during offline config resolution |
| Imported repository or digest does not exist | High | Medium | Keep synth offline; prove existence and runtime pull in the dedicated mirrored-deployment follow-up |
| Execution role cannot pull the image | High | Low | Use `fromEcrRepository` and assert repository pull IAM on the execution role |
| Application task role receives unnecessary ECR access | Medium | Low | Assert ECR pull actions are absent from task-role policies |
| Image is incompatible with runtime, port, health, or startup contract | High | Medium | Document the runtime contract and prove a real deployment in follow-up work |
| Digest and `SERVICE_VERSION` represent different source revisions | Medium | Medium | Require both fields; future manifest also records source revision and promotion provenance |
| Local default changes during extraction | High | Low | Make PR 50-A behavior-preserving and retain all existing assertions plus synth |
| Tests overfit CDK logical IDs or token rendering | Medium | Low | Assert semantic repository/digest/IAM behavior rather than full template snapshots |
| CI placeholder is mistaken for deployable infrastructure | Medium | Low | Use an all-zero digest, fake account, `ci-placeholder`, and explicit documentation |
| Routine runtime teardown deletes rollback artifacts | High | Low | Keep ECR foundation-owned and outside the workload stack; define explicit full-lab purge separately |
| Scope expands into pipelines, manifests, or infra extraction | High | Medium | Keep explicit non-goals and separate follow-up issues |

## 16. Done Criteria

- [ ] Local image construction is isolated in `application-image.ts` without
      behavior change.
- [ ] Omitting both external values preserves the current local
      `DockerImageAsset` path and package-derived version.
- [ ] A valid same-account, same-Region ECR digest and opaque service version
      synthesize without reservation service source or package metadata.
- [ ] Partial, malformed, mutable, unresolved-target, or mismatched-target
      configuration fails before deployment.
- [ ] ECR mode imports but does not provision the repository.
- [ ] The task execution role receives repository pull permissions and the task
      role does not.
- [ ] Tests cover both image variants and important runtime regressions.
- [ ] Public CI synthesizes both modes without AWS or registry credentials.
- [ ] No live AWS deployment is required to merge #50.
- [ ] ADR, ECS architecture, local deployment runbook, and CI documentation
      accurately describe the contract.
- [ ] No service API, ECS runtime, observability, or networking behavior
      changes.
- [ ] The plan is archived and #50 closes only in the final documentation PR.

## 17. Review Checklist

- [x] Requirements are explicit.
- [x] Non-goals are explicit.
- [x] Existing code and documentation conventions were checked.
- [x] Alternatives were considered.
- [x] Security and IAM implications were reviewed.
- [x] No-NAT networking implications were reviewed.
- [x] Cost and teardown ownership were reviewed.
- [x] Testing strategy is credential-free and implementation-ready.
- [x] Rollout and rollback are defined.
- [x] The hidden package-metadata coupling is covered.
- [x] Registry existence is not implied by successful synth.
- [x] Pull request boundaries are small and independently reviewable.
- [x] Long-term promotion decisions are separated from issue #50 scope.

## 18. Handoff Prompt for Implementation Agent

Start with only PR 50-A:

```text
Implement PR 50-A from
docs/plans/cdk-application-image-artifact-contract.md on a fresh branch from
updated main.

Suggested branch:
issue-50_infra-extract-application-image

Goal:
Extract the existing local application Docker asset and package-version
resolution into ecs-infra/lib/application-image.ts without changing behavior.

Constraints:
- Implement only section 12 steps 2 and 3.
- Do not add ECR mode, new context values, or CI changes yet.
- Preserve the AppImage construct ID, Docker context, Dockerfile, ignore rules,
  package-version source, application container configuration, and ADOT asset.
- Return one ecs.ContainerImage and serviceVersion pair for infra-stack.ts to
  consume.
- Follow existing Jest/CDK assertion conventions.
- Do not introduce dependencies.
- If implementation reality conflicts with the plan, stop and update the plan
  or request approval before changing scope.

Relevant files/modules:
- ecs-infra/lib/infra-stack.ts
- ecs-infra/lib/application-image.ts
- ecs-infra/lib/assets/docker-build-context.ts
- ecs-infra/lib/assets/package-metadata.ts
- ecs-infra/test/infra.test.ts

Expected verification:
- npm -w ecs-infra run build
- npm -w ecs-infra test -- --runInBand
- npm -w ecs-infra run cdk -- synth \
    -c allowedIngressCidr=203.0.113.10/32
```
