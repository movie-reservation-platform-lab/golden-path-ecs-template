# Implementation Plan: Issue #44 Repository Organization Decision

> Status: final issue #44 repository-organization decision record. The
> containing documentation PR should close #44. Preserved as decision history
> and follow-up backlog.

Issue: [#44](https://github.com/movie-reservation-platform-lab/golden-path-ecs-template/issues/44)

Last reviewed: 2026-07-30

## 1. Summary

Issue #44 records the repository-organization decision and an executable
follow-up backlog. It does not migrate application code.

The selected target is a dedicated GitHub organization with one repository
per independently deployable Agent, MCP, or recommendation runtime. Keep the
current reservation service, frontend demonstrator, ECS/CDK infrastructure,
and platform documentation together because they still form one deliberately
coupled reference-platform learning surface.

Adopt that target incrementally:

1. compare and choose the repository model;
2. record the decision and ownership boundaries;
3. define contract, CI, integration, release, and secret-ownership gates;
4. create repository-specific adoption issues;
5. migrate or adopt one deployable at a time through small pull requests.

Do not create the optional integration repository until it can consume pinned
commits or immutable images. Until then, keep the integrated Compose topology
and runbook with the current platform demonstrator.

## 2. Goals

- Decide whether the platform/demo ecosystem should live under a dedicated
  GitHub organization.
- Define the intended home and owner for the reservation platform, Agent,
  reservation MCP, recommendation API, recommendation MCP, and integration
  topology.
- Keep each migration or adoption pull request bounded to one repository and
  one behavior or operational boundary.
- Define how contracts move between repositories without introducing
  premature shared packages.
- Define the progression from repository-local checks to cross-repository
  integration and deployment gates.
- Keep public continuous integration credential-free.
- Preserve the project as a platform-engineering learning environment.

## 3. Non-goals

- Do not transplant Agent, MCP, recommendation, frontend, or observability code
  in issue #44.
- Do not create service repositories before their child adoption issues exist.
- Do not transplant code from the existing
  `demo-multi-service-observability` branches in issue #44.
- Do not redesign GraphQL, MCP, HTTP, authentication, or telemetry contracts as
  part of a repository move.
- Do not split the current frontend, reservation service, CDK workspace, or
  platform docs into separate repositories yet.
- Do not create a shared Python, TypeScript, Rust, schema, or telemetry package
  before repeated duplication demonstrates a stable shared abstraction.
- Do not add AWS credentials or deployment environment values to public CI.
- Do not create an empty `movie-platform-demo` repository only to complete a
  target diagram.

## 4. Current State

The current repository contains three npm workspaces:

- `movie-reservation-service`: NestJS GraphQL reservation API;
- `movie-reservation-web`: React/Vite customer and local-demo frontend;
- `ecs-infra`: CDK model for the ECS/Fargate reference deployment.

The `movie-reservation-platform-lab` GitHub organization was created on
2026-07-30 using GitHub Free. Organization-wide two-factor authentication is
required for members, outside collaborators, and billing managers. Base
repository permission is `none`, so repository access beyond public visibility
must be granted explicitly. Member repository creation remains enabled while
the organization has only its owner; revisit that setting before adding the
first non-owner member.

The organization now owns:

- `.github`: public organization profile repository with the organization
  README;
- `golden-path-ecs-template`: public canonical reservation platform repository,
  transferred from `patex1987/golden-path-ecs-template`.

The pre-organization mirror
`patex1987/golden-path-ecs-template-pre-org-archive` exists as a public archived
repository with GitHub Actions disabled. Issue #49 is closed with the final
archive handling decision.

It also owns the platform documentation, local Compose topology, and local
observability configuration. These parts currently change together often
enough that keeping them in one repository is intentional.

[ADR 006](../../architecture/architecture-decisions.md#adr-006-keep-external-apps-independent)
already says independently owned applications should not be merged into this
repository before the platform contract is clear. ADR 021 records the accepted
repository map and follow-up sequence.

The implemented distributed demo currently spans four repositories:

| Current repository | Implemented demo content |
| --- | --- |
| `golden-path-ecs-template` | Reservation GraphQL read change, Python reservation MCP, frontend Agent panel, Compose wiring, tests, and runbook |
| `python-agent-with-idp` | Python Agent orchestration and MCP clients |
| `axum_tools_random_api` | Rust/Axum recommendation API and a separate Python/FastMCP adapter |
| `fastapi_otel_prometheus_grafana_poc` | Local telemetry stack, dashboard, and multi-service observability assets |

The local runtime graph is:

```text
browser -> Python Agent -> recommendation MCP -> Rust recommendation API
                        -> reservation MCP -> NestJS GraphQL API
```

The demo branches passed an integrated smoke workflow on 2026-06-11, but they
have diverged from current mainlines. They are adoption sources, not safe merge
bases.

The existing code demonstrates two interim repository choices:

- the reservation MCP is colocated with its upstream reservation API;
- the recommendation MCP is colocated with its upstream recommendation API.

Both MCPs are thin Python services with their own container, health endpoint,
configuration, dependencies, tests, telemetry, and release boundary. That
makes separate target repositories reasonable, but it does not require a
big-bang extraction.

## 5. Requirements And Assumptions

### Confirmed Requirements

- Use issue #44 as the parent planning/discovery task.
- Follow the repository branch naming convention and link work to the issue.
- Use `movie-reservation-platform-lab` as the dedicated GitHub organization.
- Treat the source ecosystem as open source, with public repositories by
  default; private deployment configuration remains outside public source.
- Prefer multiple small pull requests over one large planning or migration pull
  request.
- Preserve the current repository's role as the reservation platform/template
  repository.
- Make per-repository and cross-repository quality gates explicit.
- Keep public CI credential-free.

### Assumptions

- The ecosystem is expected to remain useful after the current integrated demo,
  so stable repository ownership is worth establishing.
- One person may own all repositories initially, but the boundaries should
  still model independent ownership and release cadence.
- Existing repositories and branches remain the source material until a
  behavior-preserving adoption PR lands in the chosen target repository.
- `patex1987/axum_tools_random_api` and `patex1987/python-agent-with-idp`
  should be copied later into clean organization repositories, not transferred,
  because they are adoption sources rather than current canonical platform
  repositories.
- Cross-repository integration may begin as an explicit, manually triggered
  smoke workflow. It does not need to block every pull request.
- Target service repositories are created only when their child adoption issues
  are ready to execute.

### Resolved Decisions

1. Both MCP services target dedicated repositories, but adoption can be staged
   one deployable at a time.
2. The current platform repository owns the first integrated Compose topology
   until the topology can consume pinned commits or immutable images; only then
   create `movie-platform-demo`.
3. The single-maintainer organization keeps 2FA required and base repository
   permission at `none`. Default branch protection should require only checks a
   repository can actually run, and member repository-creation settings must be
   revisited before adding the first non-owner member.

## 6. Proposed Design

### Recommended Target

```text
movie-reservation-platform-lab/
  golden-path-ecs-template
    reservation service
    frontend demonstrator
    ECS/CDK infrastructure
    platform docs

  movie-reservation-agent
    Python Agent
    Agent orchestration and policies
    Agent tests

  movie-reservation-mcp
    reservation MCP server
    GraphQL client
    MCP contract tests

  movie-recommendation-service
    Rust/Axum recommendation API
    recommendation domain
    service telemetry

  movie-recommendation-mcp
    recommendation MCP server
    recommendation HTTP client
    MCP contract tests

  # Create later, after the extraction trigger is met:
  movie-platform-demo
    pinned component revisions or immutable images
    integrated Compose topology
    cross-repository smoke tests
    demo runbooks and evidence
```

This target follows the issue's deployable/runtime-boundary rule without
splitting the still-coupled reservation reference platform. A repository move
does not imply a contract redesign: each first adoption PR should preserve the
already-demonstrated behavior and tests.

### Integration Repository Extraction Trigger

Create `movie-platform-demo` only when at least one of these is true:

- the topology can consume immutable image digests rather than local relative
  build paths;
- integration tests need their own schedule, permissions, or release cadence;
- topology changes frequently without reservation-platform code changes;
- more than one platform consumer needs the same integration harness.

Until then, the current repository remains the integration consumer and records
the exact compatible revisions of external repositories.

### Contract Ownership

Contracts stay with the system that publishes them. Consumers pin or copy
small, reviewable contract artifacts initially; they do not import a new shared
package.

| Contract | Producer and source of truth | Initial consumer gate |
| --- | --- | --- |
| Reservation GraphQL schema | `golden-path-ecs-template` | Export or snapshot the schema and test the reservation MCP client against the selected revision |
| Reservation MCP tool schemas | `movie-reservation-mcp` | Agent contract fixtures plus a focused MCP smoke test |
| Recommendation HTTP API | `movie-recommendation-service` | Recommendation MCP client tests against the selected API revision |
| Recommendation MCP tool schemas | `movie-recommendation-mcp` | Agent contract fixtures plus a focused MCP smoke test |
| Trace and correlation propagation | Platform architecture docs plus each service boundary | Per-repository header/telemetry tests and one integrated trace smoke |
| Integrated component set | Current integration owner, later `movie-platform-demo` | Manifest records exact commits, image tags, or image digests |

Versioned packages become appropriate only after two or more consumers need the
same contract artifact and manual synchronization creates measurable drift.

### Quality-Gate Progression

| Gate | Scope | Required behavior |
| --- | --- | --- |
| Local | One repository | Format, lint, type/static checks, tests, build, and container startup commands documented by that repository |
| Pull request | One repository | Fast repository checks run without deployment credentials; a PR is not coupled to every external repository |
| Contract | Producer and direct consumer | Producer contract artifact is compared with consumer fixtures or exercised by a focused compatibility test |
| Integration | Selected compatible revisions | Happy, slow-dependency, and dependency-error scenarios run with revisions recorded in the result |
| Release | One deployable | Build one immutable artifact and identify its source commit; do not release unrelated services together |
| Deployment | Exact released revisions | Private promotion workflow owns cloud credentials, approvals, environment configuration, smoke gates, and rollback under issue #45 |

### Secret And Environment Ownership

- Each service repository owns names, validation, and non-secret templates for
  its own configuration.
- The integration owner owns local-demo defaults and endpoint wiring, but not
  production secrets.
- Deployment environments own secret values and target-specific configuration.
- Public CI receives no AWS deployment credentials.
- Cross-repository automation should use narrowly scoped tokens only when a
  real workflow requires them; do not create one broad organization token.

### Pull Request Boundary Rule

One PR should change one repository and one primary outcome. In particular, do
not combine:

- repository transfer or extraction;
- behavior refactoring;
- public contract redesign;
- CI redesign;
- integrated topology changes.

A behavior-preserving code transplant and its tests may stay together because
the tests are the evidence that the transplant is safe. Line count alone is not
the boundary; independent review and rollback are.

## 7. Alternatives Considered

### Alternative A: Keep The Implemented Four-Repository Layout

Keep each thin MCP with its upstream API and retain the current observability
repository as the integration owner.

- Pros:
  - least code movement;
  - upstream API and adapter can change atomically;
  - fewer repositories and less duplicated Python tooling;
  - easiest path to rerunning the existing demo.
- Cons:
  - two repositories remain polyglot and publish multiple deployables;
  - MCP release and ownership boundaries remain implicit;
  - the current platform repository gains another runtime and package manager;
  - observability proof-of-concept naming and ownership remain unclear.
- Decision:
  - acceptable as an interim adoption layout;
  - not the recommended long-term target if MCP services are independently
    released and operated.

### Alternative B: Create Every Target Repository Before Adoption

Create the organization, all five service repositories, and the integration
repository before any branch reconciliation.

- Pros:
  - clean target structure from the first adoption PR;
  - repository-local CI and ownership are explicit immediately;
  - no later extraction from interim locations.
- Cons:
  - creates six coordination surfaces before contracts are stable;
  - risks empty scaffolds and duplicated setup work;
  - makes the first integrated smoke depend on every migration completing;
  - increases version-skew and token-management work at once.
- Decision:
  - use the boundary map as the target;
  - reject the big-bang rollout and defer the integration repository.

### Alternative C: Merge The Ecosystem Into One Polyglot Monorepo

Move the Agent, MCPs, recommendation API, and observability stack into
`golden-path-ecs-template`.

- Pros:
  - atomic cross-service changes;
  - one checkout and one integration workflow;
  - simple commit pinning because all components share a revision.
- Cons:
  - conflicts with ADR 006 and issue #44's purpose;
  - creates one large Python, Rust, TypeScript, CDK, and observability CI surface;
  - hides independent ownership and release boundaries;
  - makes unrelated work and reviews easier to couple.
- Decision:
  - reject.

### Alternative D: One Shared Python Integrations Repository

Place the Agent and both MCPs in one Python workspace while keeping the
reservation and recommendation APIs separate.

- Pros:
  - one Python toolchain and shared telemetry/testing setup;
  - fewer repositories than one-deployable-per-repo;
  - Agent-to-tool contract changes can be atomic.
- Cons:
  - groups code by language rather than ownership or deployable boundary;
  - couples unrelated MCP release cycles to the Agent;
  - encourages premature shared libraries;
  - can become a general-purpose integrations repository.
- Decision:
  - reject unless one team genuinely owns and releases all three services
    together.

## 8. API / Interface Changes

The issue #44 planning PRs make no runtime API or interface changes.

Future adoption PRs must preserve the implemented GraphQL, HTTP, MCP, health,
configuration, and telemetry behavior first. Any contract redesign belongs in
a separate issue and PR after the behavior-preserving baseline is on a current
mainline.

## 9. Data Model / Persistence Changes

None.

Repository reorganization must not change reservation persistence, migrations,
or ownership of service data.

## 10. Security, Privacy, And Abuse Considerations

- Use least-privilege organization and repository roles.
- Protect default branches with the checks that each repository can actually
  run; do not invent cross-repository required checks before they are reliable.
- Keep cloud deployment credentials out of public CI.
- Keep environment secrets out of source, contract fixtures, integration
  manifests, logs, traces, prompts, and smoke-test artifacts.
- Keep demo fault controls disabled by default and unavailable in production
  profiles after code movement.
- Do not give a cross-repository integration token write access to every source
  repository when read-only artifact access is sufficient.
- Record who can publish images and promote revisions before enabling automated
  releases.

## 11. Performance, Scalability, And Reliability Considerations

Repository count does not affect runtime latency directly, but it changes
delivery reliability:

- pin exact commits or immutable image digests to prevent accidental version
  drift;
- keep repository PR checks fast and independent;
- run expensive integrated smoke tests explicitly or on a schedule until they
  are stable enough to gate releases;
- retain timeouts, Agent iteration limits, dependency-error handling, and trace
  propagation during adoption;
- publish compatibility evidence with the selected component revisions;
- avoid requiring every repository to be available merely to run one
  repository's unit tests.

## 12. Implementation Steps And Small-PR Plan

### Issue #44 Closure PR

Use one documentation-only PR to close #44 now that the organization baseline,
archive handling, target repository map, follow-up sequence, and ADR are known.

- Change:
  - add ADR 021 with the exact target repository map, ownership boundaries,
    integration-repository trigger, and infra-extraction prerequisite;
  - move this decision record under `docs/plans/delivered/`;
  - update the docs index, delivered-plan index, and roadmap references.
- Files/modules affected:
  - `docs/architecture/architecture-decisions.md`;
  - `docs/plans/delivered/platform-repository-organization-options.md`;
  - `docs/plans/delivered/README.md`;
  - `docs/plans/movie-reservation-platform-roadmap.md`;
  - `docs/index.md`.
- Notes:
  - use `Closes #44`;
  - decision only; no application, CDK, Agent, MCP, recommendation, or
    observability code changes;
  - repository adoption remains follow-up work.
- Verification:
  - inspect the focused documentation diff;
  - validate only local links added or changed.

### Follow-up Adoption And Infrastructure PRs

Create dedicated issues before these PRs. Numbers below describe dependency
order, not GitHub issue numbers.

| Slice | Primary outcome | Target repository | Depends on |
| --- | --- | --- | --- |
| M1 | Create the organization baseline, repository names, visibility, ownership, and minimal rules | GitHub settings; no code PR | Closing #44 PR |
| I1 | Decouple CDK service deployment from local service source checkout by adding an explicit image artifact contract; tracked by [#50](https://github.com/movie-reservation-platform-lab/golden-path-ecs-template/issues/50) | `golden-path-ecs-template` | Closing #44 PR |
| M2 | Adopt the current Agent behavior and focused checks from a current mainline | `movie-reservation-agent` | M1 |
| M3 | Land the reservation GraphQL read contract and tests without the MCP move | `golden-path-ecs-template` | Closing #44 PR |
| M4 | Adopt the reservation MCP behavior, tests, health check, and container as one deployable | `movie-reservation-mcp` | M1, M3 |
| M5 | Adopt the Rust recommendation API behavior, tests, health check, faults, and telemetry | `movie-recommendation-service` | M1 |
| M6 | Adopt the recommendation MCP behavior, tests, health check, and container | `movie-recommendation-mcp` | M1, M5 |
| M7 | Adopt the reusable local telemetry stack and dashboard assets | current integration owner | M1 |
| M8 | Add the explicitly gated frontend Agent/demo mode without changing the customer mode | `golden-path-ecs-template` | M2, M3, M4, M6 |
| M9 | Compose pinned compatible revisions and update the integrated runbook | current integration owner | M2, M4, M5, M6, M7 |
| M10 | Record the three-scenario smoke evidence and close the adoption parent | current integration owner | M8, M9 |

M2, M3, M5, M7, and I1 may proceed in parallel. M4 follows the reservation
contract; M6 follows the recommendation API; M9 is the convergence point. I1
must land before extracting CDK into a dedicated infrastructure repository,
because the infrastructure repository should deploy selected service artifacts
rather than build service source from sibling checkouts.

If any slice requires both a behavior transplant and substantial hardening,
split it again:

1. first PR: behavior-preserving adoption plus existing tests;
2. second PR: current-mainline compatibility fixes;
3. third PR: CI/release hardening;
4. final integration PR: update pinned revisions and runbook.

## 13. Testing Strategy

### Issue #44 Documentation PRs

- Inspect only the focused documentation diff.
- Validate local links added or changed.
- Do not run application builds, linters, or tests for documentation-only
  changes.

### Repository Adoption PRs

- Run each repository's narrowest relevant checks while iterating.
- Run that repository's complete documented check before handoff.
- Keep behavior and contract tests with the code they verify.
- Build and start each service container independently.
- Test `/health` and any readiness contract before adding the service to the
  integrated topology.

### Cross-Repository Contract And Integration Tests

- Export or snapshot producer contracts at selected revisions.
- Run focused consumer compatibility tests before integrated smoke tests.
- Run the happy path, slow recommendation, and dependency-error scenarios.
- Verify one trace crosses the Agent, both MCPs, recommendation API, and
  reservation API.
- Verify correlated logs contain bounded identifiers and no secrets or raw
  prompts.
- Verify normal customer mode does not expose demo controls or technical
  identifiers.

## 14. Rollout / Migration Plan

1. The closing #44 PR records the organization baseline: organization created,
   profile README created, `golden-path-ecs-template` transferred, the
   pre-organization archive mirror recorded, and ADR 021 accepted.
2. Keep the closed issue #49 decision as the archive policy: public for
   provenance, archived to prevent active development, and Actions disabled to
   prevent accidental workflow execution.
3. Create child issues and the gate/ownership matrix before creating service
   repositories. Include issue #50 as the prerequisite for any later
   `movie-platform-infra` extraction.
4. Copy source repositories into clean organization repositories one at a time
   only when their adoption issue is ready. Start with
   `patex1987/axum_tools_random_api` into `movie-recommendation-service`;
   copy `patex1987/python-agent-with-idp` into `movie-reservation-agent`
   later.
5. Preserve the old repository/branch as the adoption source until the target
   mainline passes focused checks.
6. Update one consumer at a time to the adopted endpoint or artifact.
7. Pin the integrated topology to known-compatible revisions.
8. Run all three smoke scenarios.
9. Deprecate old locations only after links, runbooks, and consumers point to
   the adopted mainlines.
10. Create `movie-platform-demo` later only when its extraction trigger is met.

Rollback is repository-specific: restore the prior endpoint, image, or pinned
revision and keep the previous source location available. Do not combine
source removal with the first consumer cutover.

## 15. Risks And Mitigations

| Risk | Impact | Likelihood | Mitigation |
| --- | ---: | ---: | --- |
| Too many repositories create maintenance overhead | Medium | Medium | Stage creation, defer the integration repo, and use extraction triggers |
| Active branch work is lost or diverges during transfer | High | Medium | Merge or record active work first; adopt from committed revisions, never a dirty working tree |
| Cross-repository contracts drift | High | Medium | Producer-owned artifacts, consumer compatibility tests, and pinned integrated revisions |
| Shared FastMCP setup is duplicated | Low | High | Accept small duplication until a stable repeated abstraction and multiple consumers exist |
| One PR mixes migration and redesign | High | Medium | Enforce one primary outcome and preserve behavior before hardening |
| Cross-repository automation receives broad credentials | High | Low | Prefer read-only artifacts and narrowly scoped tokens; keep AWS credentials in private promotion |
| Integration CI becomes slow or flaky | Medium | Medium | Keep local PR gates independent and run integrated smoke explicitly until stable |
| Empty integration repository becomes another backlog item | Medium | Medium | Create it only after an extraction trigger is met |
| Frontend/backend split happens before GraphQL contracts stabilize | Medium | Low | Keep the current reservation platform workspaces together |

## 16. Done Criteria

Issue #44 is complete when:

- the organization decision and exact repository names are recorded;
- every deployable and integration asset has an explicit target owner;
- the choice to split or colocate each MCP is explicit;
- contract sources of truth and consumer checks are explicit;
- local, PR, contract, integration, release, and deployment gates are defined;
- secret and environment ownership is explicit;
- the optional integration-repository trigger is explicit;
- repository-specific follow-up slices have ordered dependencies and
  acceptance intent, with child issues created before each adoption starts;
- no migration work remains hidden inside issue #44.

## 17. Review Checklist

- [x] Requirements and assumptions are explicit.
- [x] Non-goals prevent code migration during the decision.
- [x] Existing repository and demo branch layouts were inspected.
- [x] At least two viable alternatives were compared.
- [x] The target model and staged rollout are evaluated separately.
- [x] Every planned PR has one primary outcome.
- [x] Contract and integration ownership are explicit.
- [x] Public CI remains credential-free.
- [x] Security, reliability, rollout, and rollback are covered.
- [x] The final decision can be executed without rereading the whole
      conversation.

## 18. Handoff Prompt For Follow-Up Work

```text
Implement the selected follow-up from
docs/plans/delivered/platform-repository-organization-options.md.

Constraints:
- Work from the specific GitHub issue for the selected slice.
- Keep one repository and one primary outcome per PR.
- Do not create broad shared packages before repeated duplication proves a
  stable shared abstraction.
- Keep public CI credential-free.
- For infra extraction, land #50 before moving CDK to a dedicated repository.
- For service adoption, preserve behavior first, then harden CI/release gates in
  later PRs.

Relevant files:
- docs/plans/delivered/platform-repository-organization-options.md
- docs/architecture/architecture-decisions.md
- docs/plans/movie-reservation-platform-roadmap.md

Verification:
- Run the checks named by the specific follow-up issue.
- For documentation-only follow-ups, inspect the focused documentation diff and
  validate only local links added or changed.
```
