# Documentation Index

This folder is organized by purpose. Start here when you need to decide where a new note belongs.

## `architecture/`

Durable design documents for the platform and service shape.

Use this folder for:

- current system architecture
- accepted or proposed architecture decisions
- platform/golden-path design
- future platform APIs and service contracts

Current documents:

- [architecture.md](architecture/architecture.md) - current system architecture and target direction.
- [architecture-decisions.md](architecture/architecture-decisions.md) - ADR-style decision log and tradeoffs.
- [database-schema.md](architecture/database-schema.md) - current Postgres table relationships and reservation workflow constraints.
- [ecs-fargate-deployment.md](architecture/ecs-fargate-deployment.md) - high-level runtime architecture and detailed AWS resource topology for the ECS/Fargate stack.
- [frontend-architecture.md](architecture/frontend-architecture.md) - React/Vite frontend clean architecture layers, folder structure, dependency rules, and diagrams.
- [graphql-request-flow.md](architecture/graphql-request-flow.md) - GraphQL request path through NestJS, Apollo, middleware, context, resolvers, and clean architecture layers.
- [golden-path.md](architecture/golden-path.md) - the opinionated service path this template should provide.
- [movie-reservation-domain-vocabulary.md](architecture/movie-reservation-domain-vocabulary.md) - shared domain vocabulary for movie providers, auditoriums, screenings, seats, reservation requests, and reservations.
- [observability-log-contract.md](architecture/observability-log-contract.md) - structured JSON log field contract, id semantics, and trace/correlation/request boundaries.
- [platform-api.md](architecture/platform-api.md) - future platform-facing API and CDK construct ideas.
- [service-di-composition.md](architecture/service-di-composition.md) - service runtime profile, dependency injection composition, and provider wiring diagrams.

## `plans/`

Implementation plans, migration plans, roadmaps, and follow-up task lists.

Use this folder when a document describes planned work, sequencing, risks, or acceptance criteria.

Current documents:

- [d4-graphql-polling-api.md](plans/d4-graphql-polling-api.md) - implementation plan for the movie reservation GraphQL polling API.
- [d8a-rebase-frontend-spike.md](plans/d8a-rebase-frontend-spike.md) - implementation plan for safely porting the frontend spike onto finalized D7 observability.
- [distributed-observability-demo-platform.md](plans/distributed-observability-demo-platform.md) - future follow-ups for the multi-service observability demo platform direction.
- [ecs-adot-managed-observability.md](plans/ecs-adot-managed-observability.md) - implementation plan for ECS/Fargate deployment with an ADOT sidecar, X-Ray, CloudWatch metrics, AMP, AMG, and demo reservation failure injection.
- [github-actions-ci-foundation.md](plans/github-actions-ci-foundation.md) - implementation plan for the first small GitHub Actions CI workflow.
- [implementation-plan.md](plans/implementation-plan.md) - overall learning and build plan.
- [frontend-follow-up-triage.md](plans/frontend-follow-up-triage.md) - D8 frontend issue split and priority decision for related follow-ups.
- [local-observability-foundation.md](plans/delivered/local-observability-foundation.md) - delivered implementation plan for local structured logging, OpenTelemetry traces/metrics, API containerization, and collector integration.
- [movie-reservation-frontend-product-requirements.md](plans/movie-reservation-frontend-product-requirements.md) - product and UX requirements for the D8 customer-facing movie booking frontend.
- [movie-reservation-platform-roadmap.md](plans/movie-reservation-platform-roadmap.md) - roadmap for the movie reservation platform slice.
- [nestjs-service-migration.md](plans/nestjs-service-migration.md) - completed/active migration plan for moving the service to NestJS.
- [platform-follow-up-tasks.md](plans/platform-follow-up-tasks.md) - platform, CI/CD, infrastructure workflow, and delivery-system follow-up tasks.
- [production-observability-dashboard.md](plans/production-observability-dashboard.md) - follow-up plan for production traffic, latency, errors, saturation dashboards, alerts, and operations procedures.
- [service-di-composition-breakdown.md](plans/service-di-composition-breakdown.md) - post-D4 plan for splitting NestJS dependency wiring into typed composition profiles and focused provider groups.
- [service-follow-up-tasks.md](plans/service-follow-up-tasks.md) - intentional leftovers from the service migration.

## `learning/`

Personal learning notes, cheat sheets, and concept explanations.

Use this folder for material whose primary job is teaching or memory support, not project governance.

Current documents:

- [my-learning-notes.md](learning/my-learning-notes.md) - chronological personal learning notes.
- [graphql-context-factory-notes.md](learning/graphql-context-factory-notes.md) - notes on Apollo GraphQL context creation and request enrichment.
- [monorepo-vs-multirepo-frontend-backend.md](learning/monorepo-vs-multirepo-frontend-backend.md) - learning note comparing monorepo and multi-repo options for frontend/backend development and deployment.
- [node-package-tooling-cards.md](learning/node-package-tooling-cards.md) - Trello-card-style notes for nvm, npm, Corepack, pnpm, and Yarn.
- [ts-cdk-learning-path.md](learning/ts-cdk-learning-path.md) - TypeScript and CDK study path.
- [typescript-docstrings-and-generated-docs.md](learning/typescript-docstrings-and-generated-docs.md) - notes on TypeScript documentation comments and generated docs.
- [vitest-cheat-sheet.md](learning/vitest-cheat-sheet.md) - Vitest notes from a pytest mental model.

## `operations/`

Operational procedures and runtime checks.

Use this folder for runbooks, health-check procedures, deployment checks, smoke tests, and incident/debugging notes.

Current documents:

- [runbook.md](operations/runbook.md) - local and future operational checks for the service/platform.

## `workflows/`

Development workflows that support the project but are not product architecture.

Use this folder for repeatable collaboration, review, release, or AI-assistant workflows.

Current documents:

- [ai-review-workflow.md](workflows/ai-review-workflow.md) - how the repository's AI review agents are organized and used.
- [ci-workflow.md](workflows/ci-workflow.md) - local and GitHub Actions CI commands, jobs, required checks, and test categories.
- [curated-technology-resources.md](workflows/curated-technology-resources.md) - expanded trusted technology references for AI and human contributors.
- [debug-postgres-e2e-tests.md](workflows/debug-postgres-e2e-tests.md) - terminal and WebStorm workflow for debugging Postgres-backed e2e tests.
- [graphql-reservation-query-examples.md](workflows/graphql-reservation-query-examples.md) - local GraphiQL, curl, and Postman examples for the movie reservation story.
- [git-workflow.md](workflows/git-workflow.md) - branch naming, commit messages, squash merges, and issue-linked workflow.
- [local-observability.md](workflows/local-observability.md) - local structured logs, OTel traces/metrics, collector ports, external Grafana stack stitching, and smoke checks.
- [observability-manager-demo.md](workflows/observability-manager-demo.md) - meeting runbook for demonstrating Tempo, Loki, Prometheus, trace/log correlation, and reservation business metrics.

## `scratch/`

Temporary notes and rough captures that may later become plans, learning notes, or architecture docs.

Use this folder for unfinished thinking. When a scratch note becomes useful and durable, move it into the appropriate category above.

Current documents:

- [temp-notes.md](scratch/temp-notes.md) - temporary working notes.
