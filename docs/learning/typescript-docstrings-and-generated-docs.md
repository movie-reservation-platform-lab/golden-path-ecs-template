# TypeScript Docstrings And Generated Documentation

## Short answer

TypeScript has a Python-docstring equivalent, but it is not written as a string inside the function body.

In TypeScript, API documentation is usually written as **JSDoc/TSDoc comments** immediately before the thing being documented:

```ts
/**
 * Requests a booking sync for a customer-facing booking source.
 *
 * @param source - External system to sync from.
 * @returns A job that can be polled for sync status.
 */
function requestBookingSync(source: string): BookingSyncJob {
  // ...
}
```

This is closer to Rust's `///` documentation comments than Python's runtime `"""docstring"""`.

Python docstrings are real runtime values. For example, `some_function.__doc__` exists at runtime.

TypeScript comments are normally **compile-time/editor documentation only**. They are not part of the JavaScript runtime unless a tool separately extracts them.

## TypeScript does not have Python-style docstrings

Python:

```py
def calculate_total(price: Decimal) -> Decimal:
    """Calculate the total price including business rules."""
    ...
```

That string is part of the function object.

TypeScript:

```ts
/**
 * Calculates the total price including business rules.
 */
function calculateTotal(price: Money): Money {
  // ...
}
```

That comment is consumed by editors, TypeScript-aware tooling, linters, and documentation generators.

The important difference:

| Feature           | Python docstring               | TypeScript JSDoc/TSDoc          |
| ----------------- | ------------------------------ | ------------------------------- |
| Syntax            | `"""..."""` inside object body | `/** ... */` before declaration |
| Runtime value     | Yes, via `.__doc__`            | No, normally stripped/ignored   |
| Editor hover docs | Yes                            | Yes                             |
| Generated docs    | Sphinx                         | TypeDoc or API Extractor        |
| Type information  | Often duplicated in text       | Usually inferred from TS types  |

## JSDoc vs TSDoc

You will see two names:

- **JSDoc**: the older JavaScript documentation comment format.
- **TSDoc**: a stricter convention for TypeScript documentation comments.

They use the same basic comment shape:

```ts
/**
 * Summary sentence.
 *
 * More details if needed.
 *
 * @param id - Booking id to look up.
 * @returns The booking when found.
 */
```

For a TypeScript project, think of TSDoc as "JSDoc with TypeScript-aware rules and conventions."

## What to document

Do not document every line or every obvious property. Prefer comments on public API boundaries:

- exported classes
- exported functions
- exported interfaces/types when their meaning is not obvious
- domain concepts
- NestJS services/resolvers/controllers when they expose important behavior
- CDK constructs when the AWS design choice matters

Good candidate in this repository:

```ts
/**
 * Application service for booking use cases.
 *
 * This layer coordinates domain objects and persistence ports, but should not
 * contain HTTP, GraphQL, or database-specific details.
 */
export class BookingsService {
  // ...
}
```

Less useful:

```ts
/** The booking id. */
id: string;
```

If the type name already says the same thing, the comment is noise.

## Use TypeScript types instead of repeating types in comments

In Python, docstrings often include parameter types because the language historically did not require type annotations.

In TypeScript, the type system already carries that information:

```ts
/**
 * Finds a booking by id.
 *
 * @param id - Stable booking identifier.
 * @returns The booking, or `null` when no booking exists.
 */
async function findById(id: BookingId): Promise<Booking | null> {
  // ...
}
```

Avoid this:

```ts
/**
 * @param id - BookingId
 * @returns Promise of Booking or null
 */
```

The signature already says that. Use the comment to explain meaning, behavior, constraints, or edge cases.

## Common tags

Useful tags:

```ts
/**
 * Creates a booking sync job.
 *
 * @param requestedBy - User or system that initiated the sync.
 * @returns The created sync job.
 * @throws BookingNotFoundError when the target booking does not exist.
 */
```

Common tags:

- `@param name - Description`
- `@returns Description`
- `@throws Description`
- `@deprecated Use X instead.`
- `@example`
- `@remarks` for longer explanation

Example with `@example`:

````ts
/**
 * Converts a domain booking into a GraphQL response model.
 *
 * @example
 * ```ts
 * const gqlBooking = toBookingModel(domainBooking);
 * ```
 */
````

## Can TypeScript generate documentation like Python Sphinx?

Yes. The closest common tool is **TypeDoc**.

Sphinx usually works like this:

```text
Python source + docstrings + Sphinx extensions -> HTML docs
```

TypeScript commonly works like this:

```text
TypeScript source + TSDoc/JSDoc comments + TypeDoc -> HTML or Markdown docs
```

TypeDoc reads TypeScript's compiler information, so generated docs can include:

- modules
- classes
- interfaces
- type aliases
- functions
- method signatures
- parameter types
- return types
- comments
- deprecation notes

## Typical TypeDoc setup

Install it at the workspace root:

```bash
npm install --save-dev typedoc
```

Add a script to root `package.json`:

```json
{
  "scripts": {
    "docs:api": "typedoc"
  }
}
```

Then add `typedoc.json`:

```json
{
  "entryPoints": ["movie-reservation-service/src", "ecs-infra/lib"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "excludePrivate": true,
  "excludeInternal": true
}
```

Run:

```bash
npm run docs:api
```

That would generate static API documentation under `docs/api`.

## Important difference from Sphinx

Sphinx is a broader documentation system. It can combine prose docs, API docs, diagrams, cross-references, custom extensions, and multiple source formats.

TypeDoc is more focused: it generates API reference documentation from TypeScript code.

For a TypeScript project, a common split is:

- Markdown files in `docs/` for learning notes, design docs, runbooks, and architecture decisions.
- TypeDoc output in `docs/api/` for generated API reference.

That maps well to this repository:

- `docs/architecture/architecture.md` explains design.
- `docs/operations/runbook.md` explains operations.
- TypeDoc could generate reference docs from `movie-reservation-service/src`
  and `ecs-infra/lib`.

## TypeScript documentation comments and runtime validation

Documentation comments do not validate anything at runtime.

This matters in TypeScript because types disappear when compiled to JavaScript:

```ts
function handlePort(port: number): void {
  // At runtime, JavaScript does not enforce that port is a number.
}
```

If input comes from HTTP, GraphQL variables, environment variables, or AWS configuration, you still need runtime validation.

In this repository, that is relevant to:

- service inputs
- GraphQL inputs
- environment config
- CDK context/config values

The comment explains the contract. The TypeScript type checks internal code. Runtime validation protects the boundary.

## Recommended style for this project

Use documentation comments sparingly but intentionally.

Good places:

- domain classes and value objects in `movie-reservation-service/src/domain`
- application services and ports in `movie-reservation-service/src/application`
- mappers when they translate between domain and GraphQL models
- CDK stack constructs in `ecs-infra/lib`

Avoid documenting:

- private implementation details
- obvious constructor assignments
- every field when the type name is enough
- comments that only repeat the function name

Good comment:

```ts
/**
 * Port used by the application layer to persist bookings.
 *
 * Infrastructure adapters implement this interface. Keeping this as an
 * interface prevents application code from depending on a specific database.
 */
export interface BookingRepository {
  findById(id: BookingId): Promise<Booking | null>;
}
```

Weak comment:

```ts
/**
 * Booking repository interface.
 */
export interface BookingRepository {
  // ...
}
```

The weak version adds no information beyond the name.

## Practical rule of thumb

Write comments when they answer one of these questions:

- Why does this abstraction exist?
- What behavior should callers rely on?
- What does this domain concept mean?
- What are the important edge cases?
- What should implementers of this interface preserve?
- What infrastructure decision is being modeled?

Do not write comments merely to prove that a function has a parameter or return type. TypeScript already does that better.
