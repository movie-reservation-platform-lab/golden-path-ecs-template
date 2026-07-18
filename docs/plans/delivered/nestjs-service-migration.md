# Implementation Plan: NestJS Service Migration

## 1. Summary

Convert `service/` from the current Fastify-style application into a NestJS application that follows clean architecture from the beginning.

The key design choice is that NestJS is an outer framework, not the application architecture. Nest decorators and framework classes belong in app bootstrap, `presentation/`, and `di/` files. Domain, application services, and infrastructure repositories stay plain TypeScript so the same application behavior can later be exposed through HTTP, GraphQL, MCP, CLI, workers, or tests without depending on Nest.

## 2. Goals

- Replace the current Fastify route registration with NestJS bootstrap, modules, controllers, and resolvers.
- Keep `GET /health` and add `GET /ready` as REST endpoints.
- Add booking GraphQL operations:
  - `booking(id)`
  - `bookings`
  - `requestBookingSync`
- Follow clean architecture fully:
  - domain types model booking concepts
  - application services own use-case behavior
  - application ports define required dependencies
  - infrastructure adapters implement ports
  - presentation maps HTTP/GraphQL requests to application calls
  - DI composition wires concrete implementations to ports
- Keep `BookingsService` transport-agnostic and storage-agnostic.
- Generate and commit `service/schema.gql` as the visible GraphQL contract.
- Add unit, integration, and e2e-style tests for the first service slice.

## 3. Non-goals

- No real database, migrations, or external persistence.
- No authentication or authorization yet.
- No OpenTelemetry instrumentation in this phase.
- No ECS/CDK infrastructure changes in this phase unless a health path assumption needs documentation.
- No separate use-case classes yet. Use one application-layer `BookingsService` until behavior grows.
- No full validation/error-handling framework yet. Phase 2 owns richer validation and consistent error mapping.

## 4. Current State

- `service/package.json` currently depends on `fastify`, `pino`, `pino-pretty`, and `zod`.
- `service/package.json` currently has `"type": "module"`.
- `service/src/app.ts` creates a Fastify instance, configures logging, registers `httpApi`, and returns the app without listening.
- `service/src/index.ts` imports `createApp()`, calls `listen({ port, host: '0.0.0.0' })`, and owns process startup.
- `service/src/config.ts` uses Zod to parse `PORT`, `LOG_LEVEL`, and `NODE_ENV` from `process.env`.
- `service/src/presentation/http/http-api.ts` registers Fastify route plugins.
- `service/src/presentation/http/routes/health-routes.ts` contains the intended `/health` route plus stray learning-snippet code after the plugin. The current baseline is already failing.
- `service/test/health.test.ts` uses `FastifyInstance` and `app.inject()`.
- `service/vitest.config.ts` is minimal and does not yet include the Nest/SWC transform setup needed for decorator-heavy tests.
- `service/tsconfig.json` uses strict TypeScript, `module: "nodenext"`, `type: "module"` in `package.json`, and does not yet enable decorator metadata.

Current verification results before planning:

- `npm -w service test` fails with `ReferenceError: app is not defined` from `health-routes.ts`.
- `npm -w service run build` fails with TypeScript errors in `health-routes.ts`.

## 5. Requirements and Assumptions

### Confirmed Requirements

- Implement the original NestJS phase now summarized by
  `docs/plans/movie-reservation-platform-roadmap.md`.
- Use NestJS for the service.
- Follow clean architecture fully rather than using a flat feature-module layout.
- Build `AppModule`, health module/controller, bookings GraphQL module/resolver, `BookingsService`, booking repository port, in-memory repository adapter, and DI composition modules.
- Use code-first GraphQL.
- Keep app creation separate from process startup.
- Use Apollo Driver for GraphQL.
- Use Vitest, configured for Nest/SWC.
- Generate and commit `service/schema.gql`.
- Return `null` for `booking(id)` when no booking is found, and document that behavior in resolver docstrings/comments.
- Deliver a locally runnable NestJS app with REST health endpoints and GraphQL booking operations.

### Assumptions

- The Nest app can use the default HTTP platform rather than preserving Fastify as the HTTP adapter.
- The existing Zod config file can stay for now because it already teaches runtime config validation clearly.
- Fake booking data can be process-local in memory and reset between app instances.
- The service can remain in the existing npm workspace rather than introducing the Nest CLI project layout.
- Phase 1 can remove the broken Fastify route files instead of preserving compatibility with Fastify internals.

### Open Questions

- Should the Nest HTTP adapter be Express or Fastify?
  - Recommendation: Express for Phase 1 because it is the default Nest platform path and pairs directly with the chosen Apollo Driver setup.
- Should `LOG_LEVEL` immediately wire into Nest logging?
  - Recommendation: keep basic logging only in Phase 1; structured logging belongs in Phase 2.
- Should health readiness include concrete dependency checks in Phase 1?
  - Recommendation: no external dependency checks yet, but build the long-term-compatible `ReadinessCheck` port shape now.

## 6. Proposed Design

Use clean architecture with Nest at the outer edge:

```text
src/
  app.module.ts
  app.ts
  index.ts
  config.ts

  domain/
    bookings/
      booking.ts
      booking-id.ts
      booking-status.ts
      booking-sync-job.ts
      booking-sync-job-id.ts
      booking-sync-job-status.ts

  application/
    bookings/
      bookings.service.ts
      booking-sync.types.ts
      ports/
        booking-repository.ts
    health/
      health.service.ts
      health.types.ts
      ports/
        readiness-check.ts

  infrastructure/
    repositories/
      in-memory/
        in-memory-booking.repository.ts

  presentation/
    http/
      health.controller.ts
      health.module.ts
    graphql/
      bookings.resolver.ts
      bookings-graphql.module.ts
      inputs/
        request-booking-sync.input.ts
      models/
        booking.model.ts
        booking-sync-job.model.ts
      mappers/
        booking.mapper.ts
        booking-sync.mapper.ts

  di/
    bookings/
      booking.tokens.ts
      bookings-composition.module.ts
    health/
      health-composition.module.ts
```

Dependency direction:

```text
presentation -> application -> domain
di -> application -> domain
di -> infrastructure -> application ports -> domain
```

Rules:

- `domain/` can import from `domain/`.
- `application/` can import from `domain/` and application ports/types.
- `infrastructure/` can import application ports and domain types.
- `presentation/` can import application services/types and presentation models/mappers.
- `di/` can import Nest, application services/ports, and infrastructure implementations.
- `domain/`, `application/`, and `infrastructure/repositories/` should not import Nest.

### Domain Model

Use lightweight domain modeling:

- `BookingId` and `BookingSyncJobId` as branded string types with constructor/parse functions.
- `BookingStatus` and `BookingSyncJobStatus` as enums or const unions.
- `Booking` and `BookingSyncJob` as readonly interfaces/types unless behavior appears.
- Domain factory functions validate basic invariants, such as non-empty ids.

This keeps TypeScript types useful without forcing every domain concept into a class. Interfaces are acceptable for compile-time domain shapes because they do not need runtime reflection. Runtime framework needs are handled at the presentation and DI layers.

### Application Services And Ports

`BookingsService` is a plain TypeScript class. It is not decorated with `@Injectable()`.

It owns:

```text
getBooking(id: BookingId): Promise<Booking | null>
listBookings(): Promise<readonly Booking[]>
requestBookingSync(input): Promise<BookingSyncJob>
```

It depends on `BookingRepository`, an application-layer port:

```text
application/bookings/ports/booking-repository.ts
```

The concrete fake repository lives under:

```text
infrastructure/repositories/in-memory/in-memory-booking.repository.ts
```

`HealthService` is also a plain application service. It owns liveness and readiness behavior and depends on zero or more `ReadinessCheck` ports. For Phase 1, readiness can have no checks and return an empty checks list.

### DI Composition

Nest cannot inject TypeScript interfaces directly because interfaces disappear at runtime. Use explicit runtime tokens:

```text
di/bookings/booking.tokens.ts
```

Example token:

```ts
export const BOOKING_REPOSITORY = Symbol("BOOKING_REPOSITORY");
```

Composition modules construct plain classes explicitly with factory providers:

```ts
{
  provide: BookingsService,
  useFactory: (repository: BookingRepository) =>
    new BookingsService(repository),
  inject: [BOOKING_REPOSITORY],
}
```

This is more verbose than the common Nest `@Injectable()` style, but it keeps inner layers framework-agnostic. It matches the same direction as the referenced Python project: API adapters and DI know about frameworks; services and domain do not.

### Presentation

REST:

- `HealthController` maps `GET /health` and `GET /ready` to `HealthService`.
- Health controller contains Nest decorators and HTTP response shape only.

GraphQL:

- `BookingsResolver` maps GraphQL operations to `BookingsService`.
- GraphQL models and inputs are decorated classes under `presentation/graphql`.
- Resolvers map GraphQL inputs to application/domain inputs before calling the service.
- Resolvers map domain outputs to GraphQL models before returning.
- `booking(id)` returns `null` when the booking is not found. Add a docstring/comment near the resolver method so the behavior is explicit.

GraphQL code-first needs decorators because TypeScript types are erased at runtime. A TypeScript interface is useful to the compiler, but Nest cannot inspect it after compilation. Decorated classes leave runtime metadata that Nest GraphQL can use to build the GraphQL schema.

## 7. Alternatives Considered

### Alternative A: Flat Nest Feature Modules

- Pros:
  - Fastest first Nest implementation.
  - Matches many beginner examples.
- Cons:
  - Mixes framework, API boundary, application behavior, and fake persistence too easily.
  - Does not match the user's preferred Python/Rust clean-architecture style.
- Decision:
  - Rejected. The migration should teach Nest and clean architecture together.

### Alternative B: Full Clean Architecture With One Application Service

- Pros:
  - Preserves transport-agnostic application behavior.
  - Makes HTTP, GraphQL, MCP, CLI, and worker adapters possible without rewriting use cases.
  - Repository port makes future persistence a DI/composition change.
  - Still avoids over-splitting three tiny booking operations into three classes.
- Cons:
  - More files and explicit provider wiring.
  - Less similar to most introductory Nest examples.
- Decision:
  - Recommended.

### Alternative C: Full Clean Architecture With Separate Use Case Classes

- Pros:
  - Very explicit per-operation responsibilities.
  - Scales well when each operation needs different dependencies.
- Cons:
  - Too much class count for this first booking slice.
  - More DI wiring before behavior justifies it.
- Decision:
  - Defer until behavior grows.

### Alternative D: Nest `@Injectable()` In Application And Infrastructure

- Pros:
  - Very common in Nest codebases.
  - Less DI boilerplate.
- Cons:
  - Application and infrastructure classes import Nest.
  - Inner behavior becomes less portable outside Nest.
- Decision:
  - Rejected for this learning project. If used later, call out the accepted framework coupling explicitly.

### Alternative E: Jest Instead Of Vitest

- Pros:
  - Current official Nest starter still uses Jest.
  - Jest remains battle-tested in many production Nest systems.
- Cons:
  - This repo already uses Vitest.
  - Vitest is the modern direction for TypeScript/ESM tooling and is supported by Nest's SWC recipe.
  - Reported Nest v12 direction moves ESM projects toward Vitest.
- Decision:
  - Use Vitest with Nest/SWC configuration.

## 8. API / Interface Changes

REST:

- Keep `GET /health -> 200 { "status": "ok" }`.
- Add `GET /ready -> 200 { "status": "ready", "checks": [] }`.

GraphQL:

- Add query `booking(id: ID!): Booking`.
  - Returns `null` when no booking exists for the id.
  - Document this behavior in resolver docstrings/comments and tests.
- Add query `bookings: [Booking!]!`.
- Add mutation `requestBookingSync(input: RequestBookingSyncInput!): BookingSyncJob!`.

Initial GraphQL type shape:

- `Booking`
  - `id: ID!`
  - `customerName: String!`
  - `status: BookingStatus!`
  - `startsAt: String!`
  - `endsAt: String!`
- `BookingStatus`
  - `REQUESTED`
  - `CONFIRMED`
  - `CANCELLED`
- `RequestBookingSyncInput`
  - `bookingId: ID!`
- `BookingSyncJob`
  - `id: ID!`
  - `bookingId: ID!`
  - `status: BookingSyncJobStatus!`
- `BookingSyncJobStatus`
  - `REQUESTED`

Generated contract:

- Commit `service/schema.gql`.

## 9. Data Model / Persistence Changes

No durable persistence.

Data moves out of `BookingsService` and into an in-memory infrastructure adapter:

```text
infrastructure/repositories/in-memory/in-memory-booking.repository.ts
```

This adapter is process-local and non-durable. Restarting the service resets fake data. Multiple service instances would not share state.

## 10. Security, Privacy, and Abuse Considerations

- No auth is planned in Phase 1, so do not expose this as a real public service with sensitive data.
- Keep fake booking data non-sensitive.
- Domain factory functions should reject obviously invalid values, such as empty ids.
- GraphQL input classes should use required fields for required inputs.
- Do not add full `class-validator`, `class-transformer`, or global `ValidationPipe` in Phase 1 unless implementation reveals a hard need.
- Avoid exposing stack traces through GraphQL responses in production mode later.
- Do not add secrets or AWS credentials to service config in this phase.

## 11. Performance, Scalability, and Reliability Considerations

- In-memory repository state is fine for learning but is not horizontally scalable.
- Health and readiness endpoints should be cheap.
- `/health` should be liveness-only.
- `/ready` should use the long-term response shape now and can add concrete dependency checks later.
- GraphQL code-first schema creation happens at startup. Generate `schema.gql` deterministically.
- No retry, queue, or async worker behavior is needed yet. The sync mutation only returns a fake job.
- Plain application/infrastructure classes make unit tests fast because they do not require Nest startup.

## 12. Implementation Steps

1. Update dependencies, module settings, and decorator support
   - Change:
     - Add Nest runtime dependencies: `@nestjs/common`, `@nestjs/core`, `@nestjs/platform-express`, `reflect-metadata`, `rxjs`.
     - Add GraphQL dependencies: `@nestjs/graphql`, `@nestjs/apollo`, `@apollo/server`, `@as-integrations/express5`, `graphql`.
     - Add test/build dependencies: `@nestjs/testing`, `vitest`, `unplugin-swc`, `@swc/core`, `@vitest/coverage-v8`, `supertest`, `@types/supertest`.
     - Remove `"type": "module"` from `service/package.json`.
     - Keep `module: "nodenext"` and `moduleResolution: "nodenext"` in `service/tsconfig.json`.
     - Enable `experimentalDecorators` and `emitDecoratorMetadata`.
     - Remove obsolete Fastify dependencies after Fastify code is removed.
   - Files/modules likely affected:
     - `service/package.json`
     - `package-lock.json`
     - `service/tsconfig.json`
   - Notes:
     - Current official Nest starter uses `nodenext` settings, but without `"type": "module"`, runtime output follows the common Nest path.
   - Verification:
     - `npm install`
     - `npm -w service run build`

2. Configure Vitest for Nest decorators
   - Change:
     - Update `service/vitest.config.ts` to use `unplugin-swc` per Nest's SWC recipe.
     - Keep tests under `service/test/**/*.test.ts` unless implementation chooses a clearer split.
   - Files/modules likely affected:
     - `service/vitest.config.ts`
   - Notes:
     - This prevents decorator metadata and DI behavior from depending on an accidental transform setup.
   - Verification:
     - `npm -w service test` reaches test execution after imports.

3. Create the Nest application shell
   - Change:
     - Add `AppModule`.
     - Update `createApp()` to use `NestFactory.create(AppModule)`.
     - Import `reflect-metadata` before Nest app creation if needed.
     - Keep `createApp()` as the no-listen app factory.
     - Update `index.ts` to call `await app.listen(config.PORT, '0.0.0.0')`.
     - Update imports from current `.js` ESM suffix style to Nest-compatible source imports.
   - Files/modules likely affected:
     - `service/src/app.module.ts`
     - `service/src/app.ts`
     - `service/src/index.ts`
   - Notes:
     - `app.ts` remains test-friendly framework setup; `index.ts` remains process startup.
   - Verification:
     - App starts locally with `npm -w service run dev`.

4. Add domain booking types
   - Change:
     - Add branded ids, status types, and readonly booking/job shapes.
     - Add minimal domain factory validation for empty ids.
   - Files/modules likely affected:
     - `service/src/domain/bookings/booking.ts`
     - `service/src/domain/bookings/booking-id.ts`
     - `service/src/domain/bookings/booking-status.ts`
     - `service/src/domain/bookings/booking-sync-job.ts`
     - `service/src/domain/bookings/booking-sync-job-id.ts`
     - `service/src/domain/bookings/booking-sync-job-status.ts`
   - Notes:
     - Domain code must not import Nest or GraphQL.
   - Verification:
     - Unit tests for id factory behavior.

5. Add application booking service and repository port
   - Change:
     - Add `BookingRepository` port under application.
     - Add plain `BookingsService` that depends on the port.
     - Implement lookup, list, and fake booking sync request behavior.
   - Files/modules likely affected:
     - `service/src/application/bookings/bookings.service.ts`
     - `service/src/application/bookings/booking-sync.types.ts`
     - `service/src/application/bookings/ports/booking-repository.ts`
   - Notes:
     - No `@Injectable()` here.
     - The service should accept/return domain/application types only.
   - Verification:
     - Unit tests instantiate `BookingsService` with a fake repository object.

6. Add in-memory repository adapter
   - Change:
     - Add plain `InMemoryBookingRepository` implementing `BookingRepository`.
     - Store fake bookings and fake sync jobs in memory.
   - Files/modules likely affected:
     - `service/src/infrastructure/repositories/in-memory/in-memory-booking.repository.ts`
   - Notes:
     - No `@Injectable()` here.
     - Concrete persistence details live outside application.
   - Verification:
     - Unit/integration tests cover repository find/list/save behavior.

7. Add booking DI composition
   - Change:
     - Add runtime token for `BookingRepository`.
     - Add Nest composition module that constructs `InMemoryBookingRepository` and `BookingsService` with factory providers.
     - Export `BookingsService`.
   - Files/modules likely affected:
     - `service/src/di/bookings/booking.tokens.ts`
     - `service/src/di/bookings/bookings-composition.module.ts`
   - Notes:
     - DI layer is allowed to know about Nest, application ports, and infrastructure implementations.
   - Verification:
     - A Nest integration test can resolve `BookingsService` from the module.

8. Add health application and presentation modules
   - Change:
     - Add plain `HealthService`.
     - Add `ReadinessCheck` port and readiness response types.
     - Add `HealthController` with `/health` and `/ready`.
     - Add health DI composition and presentation module.
   - Files/modules likely affected:
     - `service/src/application/health/health.service.ts`
     - `service/src/application/health/health.types.ts`
     - `service/src/application/health/ports/readiness-check.ts`
     - `service/src/di/health/health-composition.module.ts`
     - `service/src/presentation/http/health.controller.ts`
     - `service/src/presentation/http/health.module.ts`
     - `service/src/app.module.ts`
   - Notes:
     - `/ready` returns `{ status: "ready", checks: [] }` in Phase 1.
   - Verification:
     - Unit tests for `HealthService`.
     - HTTP integration/e2e tests for `/health` and `/ready`.

9. Add GraphQL code-first boundary
   - Change:
     - Configure `GraphQLModule` with Apollo Driver and `autoSchemaFile: 'schema.gql'`.
     - Add GraphQL models, inputs, mapper functions, resolver, and GraphQL module.
     - Import booking DI composition module into GraphQL presentation module.
     - Add resolver comment/docstring stating `booking(id)` returns `null` for missing bookings.
   - Files/modules likely affected:
     - `service/src/app.module.ts`
     - `service/src/presentation/graphql/bookings-graphql.module.ts`
     - `service/src/presentation/graphql/bookings.resolver.ts`
     - `service/src/presentation/graphql/models/booking.model.ts`
     - `service/src/presentation/graphql/models/booking-sync-job.model.ts`
     - `service/src/presentation/graphql/inputs/request-booking-sync.input.ts`
     - `service/src/presentation/graphql/mappers/booking.mapper.ts`
     - `service/src/presentation/graphql/mappers/booking-sync.mapper.ts`
     - `service/schema.gql`
   - Notes:
     - GraphQL classes are presentation models, not domain models.
     - Resolver maps GraphQL inputs to application/domain values and maps domain outputs back to GraphQL models.
   - Verification:
     - GraphQL tests for `bookings`, `booking(id)`, missing `booking(id)`, and `requestBookingSync`.
     - `service/schema.gql` is generated and committed.

10. Remove obsolete Fastify code
    - Change:
      - Remove Fastify route registration files and imports.
      - Remove Fastify dependency once no longer used.
    - Files/modules likely affected:
      - `service/src/presentation/http/http-api.ts`
      - `service/src/presentation/http/routes/health-routes.ts`
      - `service/package.json`
      - `package-lock.json`
    - Notes:
      - The current Fastify route file is broken, so replacement should happen early enough to restore build/test health.
    - Verification:
      - `rg "fastify|Fastify" service/src service/test service/package.json` shows no obsolete references.

11. Update tests and docs
    - Change:
      - Replace Fastify `app.inject()` tests with Nest HTTP server tests using `supertest(app.getHttpServer())`.
      - Add unit tests for domain/application/infrastructure.
      - Add integration/e2e tests for HTTP and GraphQL.
      - Update README/docs if local commands or endpoint examples are stale.
    - Files/modules likely affected:
      - `service/test/**/*.test.ts`
      - `README.md`
      - possibly `docs/architecture/architecture.md`
    - Notes:
      - Keep docs concrete and tied to this service slice.
    - Verification:
      - `npm -w service run build`
      - `npm -w service test`
      - optionally root `npm run build` and `npm test`

## 13. Testing Strategy

Build/type checks:

- `npm -w service run build`
- Root `npm run build` if infra build remains healthy.

Unit tests:

- Domain id factories:
  - valid `BookingId`
  - empty `BookingId` rejected
  - valid `BookingSyncJobId`
  - empty `BookingSyncJobId` rejected
- `BookingsService` with a fake repository object:
  - `listBookings()` returns bookings
  - `getBooking(existingId)` returns booking
  - `getBooking(missingId)` returns `null`
  - `requestBookingSync()` creates a job
- `HealthService`:
  - liveness returns `{ status: "ok" }`
  - readiness returns `{ status: "ready", checks: [] }` with no checks
- Mapper functions:
  - domain booking -> GraphQL `BookingModel`
  - GraphQL sync input -> application/domain input

Integration tests:

- `InMemoryBookingRepository`:
  - seeded bookings can be listed
  - existing booking can be found
  - missing booking returns `null`
  - sync job can be saved/returned
- Nest DI composition:
  - `BookingsCompositionModule` resolves `BookingsService`
  - booking repository token resolves through the composition module if exposed for testing

HTTP e2e-style tests:

- `GET /health` returns `200` and `{ status: "ok" }`.
- `GET /ready` returns `200` and `{ status: "ready", checks: [] }`.

GraphQL e2e-style tests:

- POST `/graphql` `bookings` returns fake booking data.
- POST `/graphql` `booking(id)` returns one fake booking for an existing id.
- POST `/graphql` `booking(id)` returns `null` for a missing id.
- POST `/graphql` `requestBookingSync` returns a fake sync job.
- `service/schema.gql` contains the expected query, mutation, and object type names.

Regression checks:

- `rg "fastify|Fastify" service/src service/test service/package.json` after migration.
- `npm -w service test`.
- `npm -w service run build`.

## 14. Rollout / Migration Plan

- This is a local learning repository, so no staged production rollout is needed.
- Do the migration in one focused change set.
- Keep endpoint compatibility for `/health`.
- Add `/ready` before future Docker, k3d, or ECS health checks depend on it.
- Commit `service/schema.gql` with the implementation so the GraphQL contract is reviewable.
- Rollback path:
  - Revert the Nest migration commit to return to the previous Fastify shape.
  - Because there is no persistent data, no data rollback is needed.

## 15. Risks and Mitigations

| Risk                                                    | Impact | Likelihood | Mitigation                                                                                                                                                                                 |
| ------------------------------------------------------- | -----: | ---------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Clean architecture increases first-change file count    | Medium |       High | Keep one `BookingsService`; defer separate use-case classes until behavior grows.                                                                                                          |
| Application or infrastructure accidentally imports Nest | Medium |     Medium | Add plan rule: Nest imports only in app bootstrap, presentation, and `di/`. Review with `rg "@nestjs" service/src/domain service/src/application service/src/infrastructure/repositories`. |
| TypeScript interfaces disappear at runtime              |   High |       High | Use Symbol tokens for DI ports and decorated classes for GraphQL models.                                                                                                                   |
| GraphQL decorator metadata not emitted                  |   High |     Medium | Enable `experimentalDecorators` and `emitDecoratorMetadata`; use decorated classes instead of interfaces for GraphQL schema types.                                                         |
| Vitest/Nest decorator transform mismatch                |   High |     Medium | Configure `unplugin-swc` and `@swc/core`; verify with Nest integration/e2e tests.                                                                                                          |
| Current baseline is already red                         | Medium |       High | Replace the broken Fastify route file early and make build/test green as the first milestone.                                                                                              |
| In-memory state misunderstood as production-ready       | Medium |     Medium | Keep in-memory repository under infrastructure and document it as non-durable/process-local.                                                                                               |
| Generated `schema.gql` churn                            |    Low |     Medium | Commit it intentionally as the GraphQL contract and review changes with schema diffs.                                                                                                      |
| Too much validation added in Phase 1                    | Medium |     Medium | Limit Phase 1 to domain invariants and GraphQL required fields; defer global validation/error mapping to Phase 2.                                                                          |

## 16. Done Criteria

- `service/` starts as a NestJS app.
- `GET /health` returns `{ "status": "ok" }`.
- `GET /ready` returns `{ "status": "ready", "checks": [] }`.
- POST `/graphql` supports booking lookup, booking list, and booking sync request operations.
- `booking(id)` returns `null` for missing bookings and this behavior is documented in resolver comments/docstrings.
- `BookingsService` is a plain application-layer TypeScript class.
- `BookingsService` depends on a `BookingRepository` application port.
- `InMemoryBookingRepository` implements the repository port under infrastructure.
- DI composition uses explicit runtime tokens/factory providers to wire ports to implementations.
- `domain/`, `application/`, and `infrastructure/repositories/` do not import Nest.
- GraphQL models/inputs are presentation-layer decorated classes.
- Resolver methods map between GraphQL models/inputs and domain/application types.
- `service/schema.gql` is generated and committed.
- `npm -w service run build` passes.
- `npm -w service test` passes.
- Obsolete Fastify route registration code is removed or no longer referenced.

## 17. Review Checklist

- [ ] Requirements are explicit.
- [ ] Non-goals are explicit.
- [ ] Existing code conventions were checked.
- [ ] The referenced Python clean-architecture project was inspected for architectural intent.
- [ ] Alternatives were considered.
- [ ] Dependency direction is explicit.
- [ ] Runtime TypeScript limitations are addressed: interfaces are compile-time only.
- [ ] Nest decorators are kept at the outer layers.
- [ ] GraphQL schema generation and commit policy are explicit.
- [ ] Security implications were reviewed.
- [ ] Scalability and reliability implications were reviewed.
- [ ] Testing strategy includes unit, integration, and e2e-style tests.
- [ ] Rollout and rollback are defined.
- [ ] Implementation steps are ordered and concrete.

## 18. Handoff Prompt For Implementation Agent

```text
Implement the plan in docs/plans/nestjs-service-migration.md.

Constraints:
- Follow clean architecture fully.
- Keep domain, application, and infrastructure repository classes plain TypeScript.
- Do not use @Injectable() in domain, application, or infrastructure/repositories.
- Use Nest decorators only in app bootstrap, presentation, and di/composition files.
- Use application-layer repository ports and explicit DI tokens.
- Use Apollo Driver for code-first GraphQL.
- Generate and commit service/schema.gql.
- Keep Vitest, but configure it with Nest/SWC support.
- Add unit, integration, and e2e-style tests described in the plan.
- Verify with npm -w service run build and npm -w service test.
```
