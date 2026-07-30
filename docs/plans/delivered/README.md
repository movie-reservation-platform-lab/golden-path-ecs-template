# Delivered Plans

This folder keeps implementation plans after their owning issue or pull request
has landed. Treat these files as historical records, not active handoffs.

Use these records when you need to understand why a design landed, recover
acceptance criteria, or compare a future plan against earlier tradeoffs. For
current delivery order, start with
[`../movie-reservation-platform-roadmap.md`](../movie-reservation-platform-roadmap.md).

## Index

| Plan | Delivered by | Historical purpose |
| --- | --- | --- |
| [`nestjs-service-migration.md`](nestjs-service-migration.md) | early service work | NestJS migration and initial clean architecture service boundary |
| [`d4-graphql-polling-api.md`](d4-graphql-polling-api.md) | issue #1 / PR #13 | Movie reservation GraphQL polling API |
| [`d5-in-process-processor-contract.md`](d5-in-process-processor-contract.md) | issue #2 / PR #16 | In-process reservation processor contract |
| [`d6-docker-compose-postgres-knex.md`](d6-docker-compose-postgres-knex.md) | issue #3 / PR #17 | Local Postgres, Knex migrations, and persistence |
| [`d6-1-review-findings.md`](d6-1-review-findings.md) | issue #3 / PR #17 follow-up | D6 review fixes around leases, readiness, and test gaps |
| [`service-di-composition-breakdown.md`](service-di-composition-breakdown.md) | issue #18 / PR #19 | Runtime composition profiles and provider wiring |
| [`github-actions-ci-foundation.md`](github-actions-ci-foundation.md) | issue #14 / PR #15 | Credential-free GitHub Actions foundation |
| [`local-observability-foundation.md`](local-observability-foundation.md) | issue #4 / PR #22 | Local logs, traces, metrics, collector, and Grafana workflow |
| [`d8a-rebase-frontend-spike.md`](d8a-rebase-frontend-spike.md) | issue #23 / PR #33 | Frontend spike rebase and adoption strategy |
| [`movie-reservation-web-orchestrator-refactor.md`](movie-reservation-web-orchestrator-refactor.md) | issue #23 / PR #33 | Frontend orchestration refactor |
| [`movie-reservation-web-clean-architecture-refactor.md`](movie-reservation-web-clean-architecture-refactor.md) | issue #23 / PR #33 | Frontend clean architecture refactor |
| [`movie-reservation-web-stabilization-review-findings.md`](movie-reservation-web-stabilization-review-findings.md) | issue #23 / PR #33 | Frontend stabilization review fixes |
| [`ecs-adot-xray-tracing.md`](ecs-adot-xray-tracing.md) | issue #37 / PR #39 | Repo-owned ADOT sidecar and X-Ray trace path |
| [`ecs-adot-managed-metrics-grafana.md`](ecs-adot-managed-metrics-grafana.md) | issue #38 / PRs #41-#43 | CloudWatch, AMP, ECS metrics, Managed Grafana, and dashboard |
| [`platform-repository-organization-options.md`](platform-repository-organization-options.md) | issue #44 | Repository organization, service-boundary, contract-gate, and adoption backlog decision |
| [`hybrid-teaching-mode-skill.md`](hybrid-teaching-mode-skill.md) | repository AI workflow | Learning-first AI implementation contract with engineer-owned practice |

## Maintenance Rules

- Add a short delivered status banner to every plan moved here.
- Keep old implementation wording when it helps explain the historical branch.
- Move remaining live follow-up work to an active plan, roadmap, ADR, runbook,
  or GitHub issue before archiving the original plan.
- Update [`../../index.md`](../../index.md) when adding or removing records.
