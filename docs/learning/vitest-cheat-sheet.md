# Vitest Cheat Sheet For Fake-First Testing

This note is written from a Python/pytest mental model.

The goal is not "mock everything". The goal is to keep most tests close to real behavior by using small dependency boundaries, reusable fake implementations, and explicit setup.

## Quick Mapping From Pytest

| Python / pytest              | TypeScript / Vitest                               | Notes                                                                             |
| ---------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------- |
| `pytest`                     | `vitest`                                          | Test runner.                                                                      |
| `assert value == expected`   | `expect(value).toEqual(expected)`                 | Vitest uses matcher functions.                                                    |
| `@pytest.fixture`            | factory functions, `beforeEach`, or `test.extend` | Use the simplest option first.                                                    |
| yielded fixture teardown     | `afterEach`, `afterAll`, or fixture cleanup       | Useful for app/server/database lifecycle.                                         |
| reusable fake implementation | class/function implementing a TS interface        | This maps very well to your testing style.                                        |
| monkeypatch/mock             | `vi.fn()`, `vi.spyOn()`, module mocks             | Use sparingly, mostly at hard external boundaries.                                |
| FastAPI `TestClient`         | `supertest` against Nest app HTTP server          | Already used in `movie-reservation-service/test/integration/api/graphql.test.ts`. |

## Basic Test Shape

```ts
import { describe, expect, it } from "vitest";

function add(left: number, right: number): number {
  return left + right;
}

describe("add", () => {
  it("adds two numbers", () => {
    expect(add(2, 3)).toBe(5);
  });
});
```

Mental model:

- `describe` groups related tests.
- `it` or `test` defines one behavior.
- `expect` asserts the result.
- `toBe` checks primitive identity/value.
- `toEqual` checks object/array structure.

## Common Matchers

```ts
expect(value).toBe(123);
expect(object).toEqual({ id: "booking-1" });
expect(object).toMatchObject({ id: "booking-1" });
expect(array).toHaveLength(2);
expect(value).toBeNull();
expect(value).toBeUndefined();
expect(text).toContain("booking");
expect(text).toMatch(/^booking-\d+$/);
```

Use `toEqual` when you care about the full object.
Use `toMatchObject` when you care only about selected fields.

## Async Tests

```ts
import { describe, expect, it } from "vitest";

async function loadBooking(): Promise<{ id: string; customerName: string }> {
  return { id: "booking-1", customerName: "Ada Lovelace" };
}

describe("loadBooking", () => {
  it("returns a booking", async () => {
    await expect(loadBooking()).resolves.toEqual({
      id: "booking-1",
      customerName: "Ada Lovelace",
    });
  });

  it("can also use await directly", async () => {
    const booking = await loadBooking();

    expect(booking.customerName).toBe("Ada Lovelace");
  });
});
```

The second style is often easier to read once the test has multiple steps.

## Arrange, Act, Assert

This is the same testing rhythm you probably already use in Python.

```ts
it("confirms a reservation", () => {
  // Arrange
  const reservation = { id: "reservation-1", status: "REQUESTED" };

  // Act
  const confirmed = { ...reservation, status: "CONFIRMED" };

  // Assert
  expect(confirmed).toEqual({
    id: "reservation-1",
    status: "CONFIRMED",
  });
});
```

In real tests, avoid comments when the code is already obvious. They are shown here only to teach the shape.

## Factory Functions For Test Data

Use factories when creating valid domain objects is noisy.

```ts
type Booking = {
  id: string;
  customerName: string;
  status: "CONFIRMED" | "CANCELLED";
};

function createBooking(overrides: Partial<Booking> = {}): Booking {
  return {
    id: "booking-1",
    customerName: "Ada Lovelace",
    status: "CONFIRMED",
    ...overrides,
  };
}

it("creates a cancelled booking variant", () => {
  const booking = createBooking({ status: "CANCELLED" });

  expect(booking).toMatchObject({
    id: "booking-1",
    status: "CANCELLED",
  });
});
```

`Partial<Booking>` means "an object with any subset of `Booking` fields".

This is a good TypeScript equivalent to small pytest fixture/data-builder helpers.

## Dependency Injection With Interfaces

TypeScript interfaces are compile-time contracts.

```ts
type Booking = {
  id: string;
  customerName: string;
};

interface BookingRepository {
  findById(id: string): Promise<Booking | null>;
  findAll(): Promise<readonly Booking[]>;
}

class BookingsService {
  constructor(private readonly repository: BookingRepository) {}

  async getBooking(id: string): Promise<Booking | null> {
    return this.repository.findById(id);
  }

  async listBookings(): Promise<readonly Booking[]> {
    return this.repository.findAll();
  }
}
```

This is the same idea as depending on a Python protocol/abstract class instead of a concrete database implementation.

Important TypeScript detail: interfaces do not exist at runtime. They are checked by `tsc`, then erased from the emitted JavaScript.

## Fake Implementation

A fake is a working implementation with simplified infrastructure.

```ts
class FakeBookingRepository implements BookingRepository {
  private readonly bookings = new Map<string, Booking>();

  seed(booking: Booking): void {
    this.bookings.set(booking.id, booking);
  }

  async findById(id: string): Promise<Booking | null> {
    return this.bookings.get(id) ?? null;
  }

  async findAll(): Promise<readonly Booking[]> {
    return [...this.bookings.values()];
  }
}

it("lists seeded bookings", async () => {
  const repository = new FakeBookingRepository();
  repository.seed(createBooking({ id: "booking-1" }));
  repository.seed(
    createBooking({ id: "booking-2", customerName: "Grace Hopper" }),
  );

  const service = new BookingsService(repository);

  await expect(service.listBookings()).resolves.toHaveLength(2);
});
```

This is usually the best default for application-service tests.

It tests real service behavior while replacing only the slow/external part.

## Stub Implementation

A stub returns fixed data and has little behavior.

```ts
function createStubRepository(): BookingRepository {
  return {
    async findById() {
      return createBooking();
    },
    async findAll() {
      return [createBooking()];
    },
  };
}

it("uses a stub repository", async () => {
  const service = new BookingsService(createStubRepository());

  await expect(service.getBooking("anything")).resolves.toMatchObject({
    customerName: "Ada Lovelace",
  });
});
```

Use a stub when behavior does not matter.
Use a fake when state and interactions across calls matter.

## Spy Or Mock Function

Use `vi.fn()` when the important thing is "was this dependency called correctly?"

```ts
import { expect, it, vi } from "vitest";

type EmailSender = {
  sendEmail(to: string, subject: string): Promise<void>;
};

class BookingNotifier {
  constructor(private readonly emailSender: EmailSender) {}

  async notifyCustomer(email: string): Promise<void> {
    await this.emailSender.sendEmail(email, "Booking confirmed");
  }
}

it("sends a confirmation email", async () => {
  const emailSender: EmailSender = {
    sendEmail: vi.fn(),
  };
  const notifier = new BookingNotifier(emailSender);

  await notifier.notifyCustomer("ada@example.com");

  expect(emailSender.sendEmail).toHaveBeenCalledWith(
    "ada@example.com",
    "Booking confirmed",
  );
});
```

This is useful at an outbound boundary.

Do not use this style for every dependency. If every test asserts internal calls, refactoring becomes painful and the tests stop describing behavior.

## beforeEach Setup

Use `beforeEach` when each test needs fresh mutable state.

```ts
import { beforeEach, describe, expect, it } from "vitest";

describe("BookingsService with beforeEach", () => {
  let repository: FakeBookingRepository;
  let service: BookingsService;

  beforeEach(() => {
    repository = new FakeBookingRepository();
    repository.seed(createBooking());
    service = new BookingsService(repository);
  });

  it("returns a booking", async () => {
    await expect(service.getBooking("booking-1")).resolves.toMatchObject({
      id: "booking-1",
    });
  });

  it("lists bookings", async () => {
    await expect(service.listBookings()).resolves.toHaveLength(1);
  });
});
```

This is close to a pytest fixture in effect, but it is scoped to the `describe` block.

Tradeoff:

- Clear for local setup.
- Can become hard to follow if the setup gets too large.

## Vitest Fixtures With test.extend

Vitest has pytest-like fixtures through `test.extend`.

```ts
import { expect, test as baseTest } from "vitest";

const test = baseTest
  .extend("repository", () => {
    const repository = new FakeBookingRepository();
    repository.seed(createBooking());
    return repository;
  })
  .extend("service", ({ repository }) => {
    return new BookingsService(repository);
  });

test("gets a booking through a fixture-created service", async ({
  service,
}) => {
  await expect(service.getBooking("booking-1")).resolves.toMatchObject({
    id: "booking-1",
  });
});
```

This is the closest Vitest equivalent to:

```py
@pytest.fixture
def service():
    repository = FakeBookingRepository()
    repository.seed(create_booking())
    return BookingsService(repository)
```

When using `test.extend`, destructure the context:

```ts
test("example", async ({ service }) => {
  // use service here
});
```

Prefer this for shared test infrastructure that is reused across files or suites.

For one file with simple setup, a factory function or `beforeEach` is usually enough.

## Fixture Cleanup

Use cleanup when the fixture opens something that must be closed.

```ts
import { expect, test as baseTest } from "vitest";

type FakeServer = {
  url: string;
  close(): Promise<void>;
};

async function startFakeServer(): Promise<FakeServer> {
  return {
    url: "http://127.0.0.1:9999",
    async close() {},
  };
}

const test = baseTest.extend("server", async ({}, { onCleanup }) => {
  const server = await startFakeServer();
  onCleanup(() => server.close());
  return server;
});

test("uses a server fixture", ({ server }) => {
  expect(server.url).toBe("http://127.0.0.1:9999");
});
```

This is the Vitest equivalent of a pytest fixture that uses `yield` for teardown.

## Testing Errors

```ts
class BookingNotFoundError extends Error {}

async function requireBooking(
  repository: BookingRepository,
  id: string,
): Promise<Booking> {
  const booking = await repository.findById(id);

  if (booking === null) {
    throw new BookingNotFoundError(`Booking ${id} was not found`);
  }

  return booking;
}

it("throws when a booking is missing", async () => {
  const repository = new FakeBookingRepository();

  await expect(requireBooking(repository, "missing")).rejects.toThrow(
    BookingNotFoundError,
  );
});
```

Use:

- `toThrow` for sync functions.
- `rejects.toThrow` for async functions returning promises.

## Parameterized Tests

Use this when the same behavior should hold for multiple inputs.

```ts
import { describe, expect, it } from "vitest";

function isTerminalStatus(status: string): boolean {
  return status === "CONFIRMED" || status === "CANCELLED";
}

describe("isTerminalStatus", () => {
  it.each([
    ["CONFIRMED", true],
    ["CANCELLED", true],
    ["REQUESTED", false],
  ])("returns %s for %s", (status, expected) => {
    expect(isTerminalStatus(status)).toBe(expected);
  });
});
```

This maps to `pytest.mark.parametrize`.

## Testing NestJS DI Wiring

Use this when you want to verify the Nest module can resolve its providers.

```ts
import { Test } from "@nestjs/testing";
import { describe, expect, it } from "vitest";

describe("BookingsCompositionModule", () => {
  it("resolves the service", async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [BookingsCompositionModule],
    }).compile();

    const service = moduleRef.get(BookingsService);

    expect(service).toBeInstanceOf(BookingsService);
  });
});
```

This is a wiring test.

It should stay small. Its job is not to retest every business rule. Its job is to catch broken provider tokens, factories, and module exports.

## Overriding Nest Providers In Tests

Use this when you want an app/module test with selected fake dependencies.

```ts
const repository = new FakeBookingRepository();
repository.seed(createBooking());

const moduleRef = await Test.createTestingModule({
  providers: [
    BookingsService,
    {
      provide: BOOKING_REPOSITORY,
      useValue: repository,
    },
  ],
}).compile();
```

For a full Nest module:

```ts
const moduleRef = await Test.createTestingModule({
  imports: [BookingsCompositionModule],
})
  .overrideProvider(BOOKING_REPOSITORY)
  .useValue(repository)
  .compile();
```

This is similar to your Python `DependencyOverrideRegistrar`.

## E2E Test Shape With supertest

This repo already uses this style for GraphQL.

```ts
import type { INestApplication } from "@nestjs/common";
import request from "supertest";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

describe("GraphQL bookings", () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createApp();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it("returns bookings", async () => {
    const response = await request(app.getHttpServer())
      .post("/graphql")
      .send({
        query: `{
          bookings {
            id
            customerName
          }
        }`,
      });

    expect(response.status).toBe(200);
    expect(response.body.errors).toBeUndefined();
    expect(response.body.data.bookings).toHaveLength(2);
  });
});
```

This is the TypeScript/Nest equivalent of creating an app and testing through a client.

## When To Use What

Use a plain function test when:

- the code is pure domain logic
- there is no dependency lifecycle
- setup is tiny

Use a factory function when:

- object setup is repetitive
- most tests need "a valid booking with one field changed"

Use a fake when:

- a dependency has behavior
- state across calls matters
- you want to avoid a real database, queue, HTTP service, or clock

Use a stub when:

- the dependency just needs to return one fixed value
- behavior is irrelevant to the test

Use a spy/mock when:

- the dependency is an external boundary
- the behavior is "send this email/event/HTTP request"
- you need to assert a retry or failure path

Use a Nest `TestingModule` when:

- you want to test dependency wiring
- you want to override providers
- you want to test a resolver/controller with Nest involved

Use an e2e test when:

- you want to verify real request/response behavior
- routing, GraphQL schema, validation, serialization, and DI should all work together

## Fake-First Testing Rules

These are the rules I would turn into an AI testing skill later:

1. Prefer real domain objects and real application services.
2. Put dependency boundaries behind small interfaces.
3. Build reusable in-memory fakes for repositories, queues, clocks, and external clients.
4. Use mocks/spies only at hard outbound boundaries or to test exceptional paths.
5. Do not assert private implementation details unless the interaction is the behavior.
6. Keep DI wiring tests small.
7. Keep e2e tests fewer, but make them meaningful.
8. If a fake becomes complicated, check whether the real dependency should be used in a thin integration test instead.

## Common File Layout

A practical layout for this repo could be:

```text
movie-reservation-service/
  test/
    unit/
      application/
      config/
      domain/
      infrastructure/
    integration/
      api/
      application/
      di/
      infrastructure/
      schema/
    e2e/
      postgres-movie-reservations.test.ts
```

Do not create this whole structure upfront.

Add `support/` only when duplication starts showing up in real tests.

## Current Repo Anchor

The current `BookingsService` test already follows the fake-first style:

- production code depends on `BookingRepository`
- the test provides `createFakeRepository()`
- the service is tested directly
- there is no broad mocking framework involved

That is the right direction for this codebase.

The next incremental improvement would be extracting reusable test support only after two or three tests need the same fake repository or booking factory.
