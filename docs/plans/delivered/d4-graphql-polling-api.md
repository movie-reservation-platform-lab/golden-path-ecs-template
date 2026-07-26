# Implementation Plan: D4 GraphQL Polling API

> Status: delivered by issue #1 / PR #13. Preserved as implementation history.

## 1. Summary

Add the first movie reservation GraphQL polling API on top of the existing movie reservation domain, auth context, and in-memory repository. The recommended approach is test-first at the GraphQL boundary, then small application/repository additions to support the resolver without moving business rules into NestJS.

## 2. Goals

- Expose `movies`, `screenings`, `requestReservation`, `reservationRequestStatus`, and `reservationResult`.
- Keep `movieProviderId` out of normal GraphQL inputs and derive tenant scope from `ActorContext`.
- Keep GraphQL classes, decorators, and input models in the presentation layer.
- Add e2e and schema coverage before implementation.

## 3. Non-goals

- No durable database or migrations.
- No worker processor or automatic confirmation flow.
- No GraphQL subscriptions.
- No production OIDC/JWKS validation.

## 4. Current State

- `AppModule` configures NestJS GraphQL code-first schema generation through `generatedGraphqlSchemaPath`.
- `MovieReservationsResolver` currently exposes only `me`.
- `MovieReservationsService` can list movies, get one movie, and get an authorized reservation.
- `InMemoryMovieReservationRepository.withSeedData()` already contains provider-scoped movies, screenings, seats, reservation requests, and reservations.
- `GraphqlAuthenticationMiddleware` stores both `authenticatedUser` and `actor` on the request.

## 5. Requirements and Assumptions

### Confirmed Requirements

- GraphQL e2e covers `movies`, `screenings`, `requestReservation`, `reservationRequestStatus`, and `reservationResult`.
- Schema test proves old booking fields are gone and movie reservation fields exist.
- Commands and queries pass `ActorContext` into application services.

### Assumptions

- `requestReservation` should create a `REQUESTED` request and return immediately; D5 will process it.
- `screenings(movieId)` may filter provider-scoped screenings by movie id.
- `reservationRequestStatus(id)` follows the same provider/owner/admin placeholder authorization style as reservations.

### Open Questions

- None blocking D4. Final field naming can be adjusted after the first frontend demonstrator if needed.

## 6. Proposed Design

Add GraphQL object models and mappers for movies, seats, screenings, reservation requests, and reservations. The resolver will read input/context, call `MovieReservationsService`, and map results back to GraphQL models.

The application service will gain provider-scoped use cases for listing screenings, fetching reservation requests, and creating reservation requests. The repository port will gain only the methods needed by those use cases.

## 7. Alternatives Considered

### Alternative A: Put All Logic in the Resolver

- Pros: Fewer files for the first GraphQL slice.
- Cons: Mixes NestJS transport code with authorization and domain workflow.
- Decision: Rejected.

### Alternative B: Add Thin Resolver Plus Application Methods

- Pros: Matches the existing clean architecture direction and keeps NestJS at the edge.
- Cons: Requires a few more explicit types and mappers.
- Decision: Recommended.

## 8. API / Interface Changes

GraphQL adds:

- `movies: [Movie!]!`
- `screenings(movieId: ID): [Screening!]!`
- `reservationRequestStatus(id: ID!): ReservationRequest`
- `reservationResult(requestId: ID!): Reservation`
- `requestReservation(input: RequestReservationInput!): ReservationRequest!`

## 9. Data Model / Persistence Changes

No durable persistence changes. The in-memory repository will support saving reservation requests.

## 10. Security, Privacy, and Abuse Considerations

Tenant scope comes from `ActorContext`, not GraphQL input. Reservation request reads should not expose another provider's request, and customer reads should stay owner-only unless a tenant-admin/scope placeholder permits broader access.

## 11. Performance, Scalability, and Reliability Considerations

The in-memory implementation is only for local development and tests. D6 and D11 will address durable persistence, concurrency, and worker signaling.

## 12. Implementation Steps

1. Add failing e2e and schema tests.
   - Change: Cover the new queries/mutation and schema fields.
   - Files/modules likely affected: `movie-reservation-service/test/e2e/graphql.test.ts`, `movie-reservation-service/test/schema.test.ts`.
   - Verification: Focused Vitest run should fail before implementation.

2. Add application/repository behavior.
   - Change: Add request creation, reservation request lookup, and screening listing methods.
   - Files/modules likely affected: application service, repository port, in-memory repository, authorization service.
   - Verification: Service and repository tests if needed.

3. Add GraphQL models, input, mappers, and resolver operations.
   - Change: Keep decorators and GraphQL classes in `presentation/graphql`.
   - Files/modules likely affected: `movie-reservation-service/src/presentation/graphql`.
   - Verification: E2E and schema tests pass.

4. Run the service check.
   - Verification: `npm -w movie-reservation-service run check`.

## 13. Testing Strategy

Start with e2e tests because D4 is an API contract change. Schema tests protect generated GraphQL shape and removal of old booking fields. Unit tests are added only if application or repository behavior grows beyond what the e2e tests clearly cover.

## 14. Rollout / Migration Plan

No data migration. This is a breaking API replacement already planned by the roadmap. Rollback is a git revert of the D4 branch.

## 15. Risks and Mitigations

| Risk                                             | Impact | Likelihood | Mitigation                                                   |
| ------------------------------------------------ | -----: | ---------: | ------------------------------------------------------------ |
| Resolver grows business logic                    | Medium |     Medium | Keep authorization and tenant scoping in application service |
| Input accidentally accepts tenant id             |   High |        Low | Schema test for `RequestReservationInput` fields             |
| Request creation gets confused with confirmation | Medium |     Medium | Return `REQUESTED`; leave processing for D5                  |

## 16. Done Criteria

- D4 GitHub issue acceptance criteria are met.
- E2E tests cover the required operations.
- Schema test covers old booking removal and new movie reservation fields.
- `npm -w movie-reservation-service run check` passes.
