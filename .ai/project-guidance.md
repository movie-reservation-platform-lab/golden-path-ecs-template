# Project AI Guidance

This repository is a learning project for building a small internal-platform-style ECS service template with TypeScript application code, AWS CDK infrastructure code, and ECS/Fargate deployment concepts.

The user is learning TypeScript, NestJS, AWS CDK, and platform engineering. Understanding is part of the deliverable: keep explanations concrete, tie them to actual files, and explain tradeoffs instead of hiding them behind broad abstractions.

## Repository Layout

- `movie-reservation-service/`: NestJS TypeScript backend. Keep NestJS in bootstrap, DI, controllers, and GraphQL resolvers; keep domain and application code plain TypeScript where possible.
- `ecs-infra/`: AWS CDK TypeScript workspace. Explain how constructs map to CloudFormation and AWS resources.
- `docs/`: project documentation. Start at `docs/index.md`; save implementation plans under `docs/plans/`.
- `.ai/`: source of truth for AI guidance, rules, skills, and review agents. `AGENTS.md` is generated from this folder by `.ai/sync.sh`.

## Dev Environment Tips

- Use `npm`, not pnpm or yarn.
- This is an npm workspace repo with `movie-reservation-service` and `ecs-infra` workspaces.
- Prefer workspace commands from the repo root, for example `npm -w movie-reservation-service run check`.
- Check the relevant `package.json` before inventing commands or assuming tooling.
- Read existing docs and source before asking questions the repository can answer.

## Build And Test Commands

- Root build: `npm run build`
- Root tests: `npm test`
- Root lint: `npm run lint`
- Service dev server: `npm -w movie-reservation-service run dev`
- Service full check: `npm -w movie-reservation-service run check`
- Service typecheck: `npm -w movie-reservation-service run typecheck`
- Service tests: `npm -w movie-reservation-service test`
- Service focused test: `npm -w movie-reservation-service test -- -t "<test name>"`
- Infra build: `npm -w ecs-infra run build`
- Infra tests: `npm -w ecs-infra test`
- CDK commands: `npm -w ecs-infra run cdk -- <args>`

Run the narrowest useful check while iterating, then run the relevant full check before handing work back.

## Code And Architecture Conventions

- Prefer small, incremental changes that fit existing project structure.
- Do not over-engineer early abstractions; extract patterns only after the duplication or boundary is real.
- The service is NestJS now. Do not introduce Fastify or Express route patterns unless explicitly asked to revisit the HTTP adapter.
- Keep framework decorators and DI wiring at the edges. Domain types, application services, ports, and repositories should stay plain TypeScript where possible.
- Place feature-specific dependency interfaces under the application feature that owns the use case, for example `movie-reservation-service/src/application/movie-reservations/ports/`. Infrastructure adapters implement those ports. This keeps dependencies pointing inward and avoids both domain code depending on persistence details and repository god objects with unrelated responsibilities.
- Use explicit, readable TypeScript types when they improve clarity.
- Distinguish compile-time TypeScript safety from runtime validation. Use Zod or framework validation at external boundaries.
- For infrastructure, explain what AWS resource is being modeled and how CDK code maps to deployed infrastructure.
- Roadmap technologies such as PostgreSQL, Knex, SQS, Kubernetes, and k3d should only be introduced in the phase that calls for them.

## Planning Guidance

- For non-trivial features, refactors, integrations, migrations, infrastructure changes, or architecture changes, plan before implementing.
- Use the `principal-engineer-planner` skill for ambiguous, cross-cutting, risky, or design-heavy work.
- Do not implement from vague requirements when a short planning pass would materially reduce risk.
- Prefer the smallest design that satisfies the requirements and fits existing project conventions.
- Save implementation plans under `docs/plans/`.

## Testing Guidance

- Add or update tests for behavior changes.
- Service tests use Vitest; HTTP/e2e-style tests use Supertest.
- Infra tests use Jest and CDK assertions.
- Prefer fake-first tests and small real integration boundaries over brittle over-mocking.
- After moving files or changing imports, run typecheck/lint/tests for the affected workspace.

## Security And Operations

- Do not commit secrets, credentials, tokens, or local `.env` values.
- Treat IAM, networking, public exposure, auth, validation, and logging choices as explicit design decisions.
- Keep health and readiness endpoints simple and platform-friendly.
- Avoid adding AWS resources, public endpoints, databases, queues, or background workers without a plan and a rollback/removal path.

## Documentation And Review

- Update docs for user-facing behavior, architecture decisions, operations, or developer workflow changes.
- Use `docs/architecture/architecture-decisions.md` for durable architectural decisions.
- Use `docs/workflows/curated-technology-resources.md` for the expanded resource list.
- For documentation-only changes, inspect the relevant diff. Do not run Prettier, builds, linters, or application tests unless the user explicitly requests them or the repository has a dedicated documentation check required for the changed files.
- Treat verification commands embedded in implementation plans as scoped to implementing that plan, not as global repository instructions.
- Validate local documentation links only when links, files, or directories are added, moved, renamed, or removed.
- PR or review summaries should explain what changed, why it changed, and how it was verified.

## Curated Technology Resources

Prefer these project-approved sources over generic training-data patterns or random tutorials. Keep this list compact; use `docs/workflows/curated-technology-resources.md` for the expanded version.

| Technology | Purpose | Preferred sources |
| --- | --- | --- |
| TypeScript + Node.js | Application and CDK language/runtime | [TypeScript Handbook](https://www.typescriptlang.org/docs/), [TSConfig Reference](https://www.typescriptlang.org/tsconfig/), [Node.js Learn](https://nodejs.org/learn) |
| NestJS | Service framework for HTTP, GraphQL, DI, and modules | [NestJS docs](https://docs.nestjs.com/), [NestJS GraphQL](https://docs.nestjs.com/graphql/quick-start), [NestJS testing](https://docs.nestjs.com/fundamentals/testing) |
| GraphQL + Apollo | Business API contract | [GraphQL Learn](https://graphql.org/learn/), [GraphQL schema docs](https://graphql.org/learn/schema/), [Apollo Server docs](https://www.apollographql.com/docs/apollo-server) |
| Zod | Runtime validation at boundaries | [Zod docs](https://zod.dev/) |
| Vitest + Supertest | Service tests and HTTP tests | [Vitest guide](https://vitest.dev/guide/), [Vitest mocking](https://vitest.dev/guide/mocking), [Supertest README](https://github.com/forwardemail/supertest) |
| Jest + CDK assertions | Infrastructure tests | [Jest docs](https://jestjs.io/docs/getting-started), [CDK testing docs](https://docs.aws.amazon.com/cdk/v2/guide/testing.html) |
| AWS CDK + Constructs | Infrastructure as code | [CDK v2 guide](https://docs.aws.amazon.com/cdk/v2/guide/home.html), [CDK best practices](https://docs.aws.amazon.com/cdk/v2/guide/best-practices.html), [CDK API reference](https://docs.aws.amazon.com/cdk/api/v2/) |
| ECS/Fargate/ALB | Primary AWS deployment target | [ECS guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/Welcome.html), [Fargate guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html), [ECS load balancing](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-load-balancing.html) |
| Docker/Compose | Container packaging and local runtime | [Docker build best practices](https://docs.docker.com/build/building/best-practices/), [Docker Compose docs](https://docs.docker.com/compose/), [Docker Node.js guide](https://docs.docker.com/guides/nodejs/) |
| GitHub Actions | Repository CI/CD automation and workflow design | [GitHub Actions tutorials](https://docs.github.com/en/actions/tutorials), [Understanding GitHub Actions](https://docs.github.com/en/actions/get-started/understand-github-actions), [GitHub Actions CI/CD best practices](https://github.com/github/awesome-copilot/blob/main/instructions/github-actions-ci-cd-best-practices.instructions.md) |
| OpenTelemetry | Planned traces/logs/metrics contract | [OTel concepts](https://opentelemetry.io/docs/concepts/), [OTel JavaScript](https://opentelemetry.io/docs/languages/js/), [OTel Collector](https://opentelemetry.io/docs/collector/) |
| Static checks | Formatting, linting, typed linting | [ESLint config](https://eslint.org/docs/latest/use/configure/), [typescript-eslint](https://typescript-eslint.io/getting-started/), [Prettier](https://prettier.io/docs/), [Oxlint](https://oxc.rs/docs/guide/usage/linter.html) |
