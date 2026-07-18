# Implementation Plan: Service DI Composition Breakdown

> Status: delivered by issue #18 / PR #19. Preserved as implementation history.

## 1. Summary

After D6 adds local Postgres persistence, refactor the NestJS dependency injection wiring so the root application module stays small as authentication, persistence, workers, observability, and environment-specific runtime profiles grow.

The recommended approach is to keep using NestJS dynamic modules, but split provider construction into focused composition units and select those units through a small typed composition profile. This keeps the useful part of the previous Python `svcs` registrar pattern: a named configuration can choose a coherent set of dependency registrations. It avoids copying the risky part: arbitrary module paths in environment variables that TypeScript cannot check during refactors.

## 2. Goals

- Keep `AppModule` as a small application composition root, not a long provider wiring file.
- Make environment-specific dependency choices explicit and testable, including the D6 in-memory and Postgres persistence modes.
- Split movie reservation composition into smaller provider groups for authentication, repositories, use cases, and readiness checks.
- Preserve clean architecture boundaries: application and domain stay plain TypeScript, NestJS-specific provider metadata stays at the composition edge.
- Use Zod config validation to reject unsupported profile and auth combinations at startup.
- Keep the refactor behavior-preserving for D4 GraphQL APIs.
- Normalize the minimal persistence-mode wiring introduced by D6 into a clearer composition profile design.
- Create a shape that can later support OIDC, workers, SQS, API container runtime profiles, and observability without turning one module into a large conditional block.

## 3. Non-goals

- Do not implement Postgres persistence itself; D6 owns that behavior.
- Do not implement OIDC/JWKS, SQS, workers, or OpenTelemetry as part of this refactor.
- Do not containerize the service as part of this DI refactor. Track API containerization as a follow-up that uses the finalized profile/env contract.
- Do not introduce Inversify, tsyringe, or another DI container.
- Do not use an environment variable containing an arbitrary import path as the primary mechanism.
- Do not change GraphQL schema behavior from D4.
- Do not move business logic into NestJS modules, controllers, middleware, or resolvers.
- Do not reorganize the whole repository layout beyond the DI/composition files needed for this refactor.

## 4. Current State

- `movie-reservation-service/src/config.ts` validates environment variables with Zod and exports a parsed `config` object.
- `AUTH_MODE` currently supports `local-fixed-user`, `local-jwt`, and `oidc`, with `superRefine` preventing local auth modes in `staging` or `production`.
- `movie-reservation-service/src/app.ts` creates the Nest application from `AppModule.forRoot(options)` and configures the Nest logger from parsed config.
- `movie-reservation-service/src/app.module.ts` configures Apollo GraphQL and imports `HealthModule` plus `MovieReservationsGraphqlModule.forRoot({ authMode })`.
- `movie-reservation-service/src/presentation/graphql/movie-reservations-graphql.module.ts` imports `MovieReservationsCompositionModule.forRoot(options)` and wires GraphQL middleware and resolver classes.
- `movie-reservation-service/src/di/movie-reservations/movie-reservations-composition.module.ts` currently owns authentication provider selection, repository binding, and application service factories in one file.
- `movie-reservation-service/src/di/health/health-composition.module.ts` already keeps health service provider wiring separate.
- `movie-reservation-service/test/di/movie-reservations-composition.module.test.ts` tests that `MovieReservationsCompositionModule` resolves services and handles `local-fixed-user`, `local-jwt`, and not-yet-implemented `oidc`.
- `movie-reservation-service/test/config/env-profiles.test.ts` checks committed env templates select expected auth modes.
- D6 is expected to add local Postgres configuration, repository adapters, migrations, and a minimal persistence-mode switch. This plan should be implemented after D6 is merged so it can refactor the real persistence wiring instead of guessing at it.

## 5. Requirements and Assumptions

### Confirmed Requirements

- This is a post-D6 plan only. Do not implement it before D6 is merged.
- The refactor should prevent DI wiring from growing into one large root file.
- The design should provide an equivalent to the Python `svcs` registrar-set pattern, but in idiomatic TypeScript/NestJS.
- The result should be prioritized later and implemented as a separate work item.
- The D6 persistence-mode switch should be preserved behaviorally while being moved into clearer typed composition code.

### Assumptions

- D6 keeps the service on NestJS with GraphQL code-first schema generation.
- D6 leaves normal local development on in-memory persistence and adds a dedicated local Postgres env file backed by Dockerized Postgres.
- The service should continue to use npm workspace commands from the repository root.
- Environment selection should remain based on checked-in env templates and parsed Zod config.
- For now, `oidc` stays explicit but not implemented unless a separate deliverable lands first.
- API containerization should happen after the composition profile contract is explicit, so the container and host npm flows use the same configuration model.
- The first implementation should be a refactor, not a behavior change.

### Open Questions

- What final profile names should be exposed in env files: `local-development`, `local-jwt`, `production`, or names closer to the current env templates?
- Should the profile own `AUTH_MODE`, or should `COMPOSITION_PROFILE` and `AUTH_MODE` remain separate with Zod cross-field validation?
- When OIDC lands, should production composition fail fast until all OIDC settings are present, or should it allow partial local production-like profiles?

These questions do not block the plan. The implementation can start with conservative names and update them before merging.

## 6. Proposed Design

Add an explicit composition profile layer between parsed config and Nest module wiring.

Conceptually, this is the TypeScript/NestJS version of the Python `svcs` registrar provider:

- Python: env var selects a registrar provider function.
- TypeScript recommendation: env var selects a known profile name.
- Python registrar: mutates a registry.
- NestJS composition unit: returns `Provider[]` or `DynamicModule` metadata.
- Python `Protocol`: defines `register(registry)`.
- TypeScript: use explicit function types such as `ProviderFactory` or `FeatureComposition`.

The core design should look like this:

```text
config.ts
  parses COMPOSITION_PROFILE, AUTH_MODE, NODE_ENV, LOG_LEVEL
  rejects impossible combinations with Zod

app-composition.ts
  maps a typed profile to top-level feature module options
  contains the environment/profile decision table

app.module.ts
  configures framework modules
  imports feature modules selected by app-composition.ts

di/movie-reservations/
  movie-reservations-composition.module.ts
  authentication.providers.ts
  repository.providers.ts
  use-case.providers.ts
  movie-reservation.tokens.ts
```

The profile should be a small union type inferred from Zod, for example:

```ts
COMPOSITION_PROFILE: z.enum([
  "local-fixed-user",
  "local-jwt",
  "production-oidc",
]).default("local-fixed-user");
```

The exact enum values can be adjusted during implementation, but they should be finite and checked. Avoid `DI_REGISTRAR_PROVIDER=some.module.path` as the default design because arbitrary import paths are weakly typed, harder to bundle, easier to break during refactors, and a poor fit for a learning template that should make the dependency matrix visible.

Provider construction should move out of the current one-file `MovieReservationsCompositionModule` into focused functions:

- `createAuthenticationProviders(options)` owns auth manager and token validator bindings.
- `createMovieReservationRepositoryProviders(options)` owns repository implementation choices.
- `createMovieReservationUseCaseProviders()` owns application service factories.
- `MovieReservationsCompositionModule.forRoot(options)` remains the public NestJS module boundary and composes those arrays.

This keeps NestJS provider metadata at the edge while leaving services, ports, and domain objects framework-free.

## 7. Alternatives Considered

### Alternative A: Keep Current Single Composition Module

- Pros:
  - Lowest immediate code movement.
  - Current file is still readable at the D3/D4 size.
  - No new abstractions to learn.
- Cons:
  - Authentication, repositories, workers, readiness checks, and future persistence choices will accumulate in one file.
  - Test setup will become more branch-heavy as modes grow.
  - It does not give a clear place to document profile-level dependency sets.
- Decision:
  - Reject as the long-term shape, but keep the first refactor small. The current module can remain the public facade.

### Alternative B: Dynamic Environment Import Path

- Pros:
  - Closest to the previous Python `svcs` pattern.
  - Very flexible for tests and experiments.
  - New registrar sets can be added without editing a central enum.
- Cons:
  - TypeScript cannot check that an env string points to a real exported function.
  - File moves and renames can silently break runtime startup.
  - Bundlers and build tools can miss dynamically referenced modules.
  - It creates a broader attack and misconfiguration surface if the variable is ever influenced outside trusted deployment config.
- Decision:
  - Reject as the default. Consider only later if this project intentionally becomes a plugin host.

### Alternative C: Typed Composition Profiles With Dynamic Modules

- Pros:
  - Preserves the useful registrar-set idea while keeping TypeScript exhaustiveness and refactor support.
  - Fits NestJS conventions through `DynamicModule`, `Provider[]`, `imports`, and `exports`.
  - Easy to test with table-driven profile tests.
  - Keeps config validation in Zod and dependency selection in composition code.
- Cons:
  - Requires a small amount of extra structure before the code strictly needs it.
  - Every new profile must be added to a typed map or switch.
- Decision:
  - Recommended.

### Alternative D: Add a Third-party TypeScript DI Container

- Pros:
  - Could look more like a hand-built registry/registrar system.
  - May support advanced lifetime and override patterns.
- Cons:
  - NestJS already has a DI container.
  - A second container would increase learning burden and integration risk.
  - It could blur the boundary between framework composition and application services.
- Decision:
  - Reject.

## 8. API / Interface Changes

No GraphQL, HTTP, or domain API changes are intended.

Internal configuration/interface changes:

- Add a composition profile setting to `config.ts`, likely `COMPOSITION_PROFILE`.
- Export a type such as `CompositionProfile` from config or a dedicated composition config module.
- Extend `AppModuleOptions` only if tests need to override the profile explicitly.
- Add internal composition types, for example:
  - `AppCompositionOptions`
  - `MovieReservationsCompositionOptions`
  - `MovieReservationRepositoryMode`
  - `AuthenticationCompositionOptions`

Environment template changes:

- Update `movie-reservation-service/env_files/templates/**/*.env.template` to include the selected composition profile once names are finalized.
- Keep `AUTH_MODE` temporarily if it still provides clear learning value, or derive auth mode from profile if that removes duplication.

## 9. Data Model / Persistence Changes

None.

This plan is only about dependency wiring. D6 owns the Postgres schema, migrations, and repository behavior; this refactor should only reorganize how those existing adapters are selected.

## 10. Security, Privacy, and Abuse Considerations

- Keep startup validation strict. Production-like profiles must not allow `local-fixed-user` or unsigned local JWT validation.
- Prefer explicit profile names over arbitrary import paths to reduce runtime code-loading risk.
- Do not log secrets or raw env values while adding config diagnostics.
- OIDC settings, when added later, should be required only by OIDC profiles and validated with Zod.
- Repository and auth provider selection should remain an application startup decision, not a request-level decision.
- Tests should prove invalid local-auth plus production/staging combinations still fail.

## 11. Performance, Scalability, and Reliability Considerations

- Provider splitting has negligible runtime cost because Nest builds the provider graph at startup.
- The design should make future singleton resources explicit, especially database pools, JWKS clients, SQS clients, workers, and OpenTelemetry exporters.
- Readiness checks should remain composable. When real dependencies arrive, each infrastructure module should contribute readiness checks instead of centralizing all checks in `HealthCompositionModule`.
- Failure modes should be startup-visible. Unsupported profiles and missing profile-specific settings should fail before the server starts listening.
- Keep request path behavior unchanged. This is a startup composition refactor, not a resolver or use-case rewrite.

## 12. Implementation Steps

1. Confirm D6 baseline and capture current behavior.
   - Change: Start from the merged D6 branch. Do not implement this plan on top of the pre-D6 branch.
   - Files/modules likely affected: `movie-reservation-service/src/config.ts`, `movie-reservation-service/src/di/movie-reservations/*`, `movie-reservation-service/src/infrastructure/repositories/in-memory/*`, `movie-reservation-service/src/infrastructure/repositories/postgres/*`, `movie-reservation-service/test/integration/**`.
   - Notes: D6 may add repository-mode config, Postgres adapters, Knex lifecycle code, and local Postgres tests. Use the merged state as the source of truth.
   - Verification: `npm -w movie-reservation-service run check`.

2. Add typed composition profile config.
   - Change: Add `COMPOSITION_PROFILE` or equivalent to `movie-reservation-service/src/config.ts`.
   - Files/modules likely affected: `src/config.ts`, env templates under `movie-reservation-service/env_files/templates/`, maybe concrete env files under `movie-reservation-service/env_files/`.
   - Notes: Use Zod enum values, not arbitrary import paths. Keep or update `superRefine` so production/staging cannot select local auth behavior or incomplete persistence configuration. Decide whether the profile owns `AUTH_MODE` and `PERSISTENCE_MODE`, or validates them as separate settings.
   - Verification: Add or update config tests. Run `npm -w movie-reservation-service test -- config`.

3. Introduce top-level app composition mapping.
   - Change: Add `movie-reservation-service/src/di/app-composition.ts` that maps the typed profile to feature module options.
   - Files/modules likely affected: `src/di/app-composition.ts`, `src/app.module.ts`.
   - Notes: Keep `AppModule` focused on GraphQL setup and importing modules. The profile-to-options decision belongs in composition code.
   - Verification: Add unit tests for each supported profile mapping.

4. Split movie reservation authentication providers.
   - Change: Move auth provider construction from `movie-reservations-composition.module.ts` into `authentication.providers.ts`.
   - Files/modules likely affected: `src/di/movie-reservations/authentication.providers.ts`, `src/di/movie-reservations/movie-reservations-composition.module.ts`, `src/di/movie-reservations/movie-reservation.tokens.ts`.
   - Notes: Preserve current behavior: `local-fixed-user` works, `local-jwt` validates unsigned local JWTs for local tests, `oidc` throws until implemented.
   - Verification: Existing `movie-reservations-composition.module.test.ts` should continue passing.

5. Split repository providers.
   - Change: Move repository binding into `repository.providers.ts`.
   - Files/modules likely affected: `src/di/movie-reservations/repository.providers.ts`, `src/infrastructure/repositories/in-memory/in-memory-movie-reservation.repository.ts`.
   - Notes: Preserve the D6 behavior for both in-memory and Postgres modes. The refactor should change where provider selection lives, not what each mode does.
   - Verification: Composition module tests still resolve `MOVIE_RESERVATION_REPOSITORY` and `RESERVATION_REQUEST_WORK_REPOSITORY` for supported modes.

6. Split use-case/application service providers.
   - Change: Move `MovieReservationsService`, `AuthenticationService`, and `AuthorizationService` provider factories into `use-case.providers.ts` or a similarly named file.
   - Files/modules likely affected: `src/di/movie-reservations/use-case.providers.ts`, `src/di/movie-reservations/movie-reservations-composition.module.ts`.
   - Notes: Keep constructors plain and explicit. Do not add Nest decorators to application services just to reduce provider factories.
   - Verification: Composition module tests and GraphQL e2e tests.

7. Keep `MovieReservationsCompositionModule` as the public facade.
   - Change: Reduce the module file to `forRoot(options)`, exports, and calls to focused provider factory functions.
   - Files/modules likely affected: `src/di/movie-reservations/movie-reservations-composition.module.ts`.
   - Notes: This file should read like a table of contents for the movie reservation dependency graph.
   - Verification: Typecheck and composition tests.

8. Add profile-level tests.
   - Change: Add tests that compile `AppModule.forRoot(...)` or the new `createAppComposition(...)` for each valid profile.
   - Files/modules likely affected: `movie-reservation-service/test/di/app-composition.test.ts`, existing composition tests.
   - Notes: Prefer testing the mapping function directly where possible; compile a Nest testing module only where Nest provider behavior matters.
   - Verification: `npm -w movie-reservation-service test -- di`.

9. Update docs and follow-up notes.
   - Change: Update any affected docs that describe service composition, config profiles, persistence modes, and the future API containerization task.
   - Files/modules likely affected: `docs/architecture/graphql-request-flow.md`, `docs/plans/service-follow-up-tasks.md`, `docs/operations/runbook.md`, `docs/architecture/architecture-decisions.md` if a durable decision is needed.
   - Notes: If profile selection becomes an architectural convention for future services, record it as an ADR-style entry. Keep API containerization as a separate task that reuses this profile/env contract.
   - Verification: Documentation review plus format check.

10. Run final verification.

- Change: No code change. Validate the behavior-preserving refactor.
- Files/modules likely affected: none.
- Notes: Use the narrowest useful commands while iterating, then the full service check before handoff.
- Verification: `npm -w movie-reservation-service run check`.

## 13. Testing Strategy

- Config tests:
  - Valid profiles parse successfully.
  - Invalid profile values fail Zod validation.
  - Production/staging plus local auth remains rejected.
  - Env templates select the expected profile and auth behavior.

- DI unit tests:
  - `createAppComposition` maps each profile to expected feature options.
  - Movie reservation auth providers still support `local-fixed-user` and `local-jwt`.
  - `oidc` remains explicit until implemented.
  - Repository token resolves to the in-memory repository in local profiles.

- Nest module tests:
  - `MovieReservationsCompositionModule.forRoot(...)` compiles for supported local modes.
  - `AppModule.forRoot(...)` compiles for supported local profiles.

- Regression tests:
  - Existing GraphQL e2e tests from D4 pass unchanged.
  - Existing schema tests pass unchanged.
  - Existing health tests pass unchanged.

- Full verification:
  - `npm -w movie-reservation-service run check`.

## 14. Rollout / Migration Plan

1. Wait for D6 to merge.
2. Create a new branch for the DI composition refactor.
3. Add profile config and mapping while keeping current auth behavior.
4. Split providers behind the existing `MovieReservationsCompositionModule` facade.
5. Run full service checks and compare D4 GraphQL behavior.
6. Merge as a behavior-preserving refactor.

Rollback is a git revert of the refactor branch. There is no data migration and no runtime state to clean up.

## 15. Risks and Mitigations

| Risk                                                   | Impact | Likelihood | Mitigation                                                                                |
| ------------------------------------------------------ | -----: | ---------: | ----------------------------------------------------------------------------------------- |
| Refactor collides with D6 persistence wiring           | Medium |     Medium | Implement only after D6 is merged and use merged D6 as the baseline                       |
| API containerization sneaks into the DI refactor       | Medium |     Medium | Keep containerization as a follow-up task that reuses the completed profile/env contract  |
| Profile and auth mode duplicate each other confusingly | Medium |     Medium | Decide whether profile owns auth mode or Zod validates both together; document the choice |
| Over-abstraction makes a small service harder to learn | Medium |     Medium | Keep one public module facade and split only provider groups that already exist           |
| Invalid production/local combinations slip through     |   High |        Low | Keep Zod `superRefine` coverage and add table-driven config tests                         |
| Dynamic import temptation returns later                | Medium |        Low | Record why typed profiles are preferred; use an ADR if this becomes a template convention |
| Provider exports accidentally change                   | Medium |     Medium | Preserve existing module tests and add AppModule/profile compile tests                    |

## 16. Done Criteria

- D6 has been merged before this work starts.
- `AppModule` remains small and delegates dependency profile decisions to composition code.
- `MovieReservationsCompositionModule` is split into focused provider factory files.
- Composition profile config is parsed and validated by Zod.
- Env templates include the selected composition profile or the plan explicitly documents why profile is derived from existing auth mode.
- Existing D4 GraphQL behavior is unchanged.
- D6 in-memory and Postgres persistence modes are still selectable and covered by composition/config tests.
- API containerization remains tracked as a separate follow-up task.
- Composition and config tests cover supported and invalid modes.
- `npm -w movie-reservation-service run check` passes.

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
Implement the plan in docs/plans/service-di-composition-breakdown.md.

Constraints:
- Start only after D6 is merged.
- Stay within the scope of the plan.
- Do not introduce new dependencies.
- Do not implement new Postgres behavior, OIDC/JWKS, SQS, workers, OpenTelemetry, or API containerization.
- Preserve existing public GraphQL and HTTP behavior.
- Use typed composition profiles rather than arbitrary env-var import paths.
- Keep NestJS provider metadata at the composition edge.
- Keep domain and application code plain TypeScript where possible.
- Follow existing repository guidance in AGENTS.md and the NestJS, clean-architecture, TypeScript, and Vitest skills.
- If implementation reality differs from the plan, stop and update the plan or ask for approval before changing scope.

Relevant files/modules:
- movie-reservation-service/src/config.ts
- movie-reservation-service/src/app.ts
- movie-reservation-service/src/app.module.ts
- movie-reservation-service/src/di/health/health-composition.module.ts
- movie-reservation-service/src/di/movie-reservations/movie-reservations-composition.module.ts
- movie-reservation-service/src/di/movie-reservations/movie-reservation.tokens.ts
- movie-reservation-service/src/presentation/graphql/movie-reservations-graphql.module.ts
- movie-reservation-service/test/config/env-profiles.test.ts
- movie-reservation-service/test/di/movie-reservations-composition.module.test.ts
- movie-reservation-service/test/e2e/graphql.test.ts
- movie-reservation-service/test/schema.test.ts

Expected verification commands:
- npm -w movie-reservation-service test -- config
- npm -w movie-reservation-service test -- di
- npm -w movie-reservation-service run check
```
