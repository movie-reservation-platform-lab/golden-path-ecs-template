# Frontend Follow-Up Triage

Last reviewed: 2026-07-17

## Current State

Issue [#23](https://github.com/patex1987/golden-path-ecs-template/issues/23)
is delivered. The repository now has a React/Vite workspace with:

- a feature-first domain/application/adapters/UI structure;
- a GraphQL client and runtime response parsers;
- bounded reservation polling and stale-request cancellation;
- trace, correlation, and request header propagation;
- user-facing error mapping and focused Vitest coverage;
- a separate credential-free GitHub Actions web check.

The delivered implementation records are:

- [`d8a-rebase-frontend-spike.md`](delivered/d8a-rebase-frontend-spike.md);
- [`movie-reservation-web-orchestrator-refactor.md`](delivered/movie-reservation-web-orchestrator-refactor.md);
- [`movie-reservation-web-clean-architecture-refactor.md`](delivered/movie-reservation-web-clean-architecture-refactor.md);
- [`movie-reservation-web-stabilization-review-findings.md`](delivered/movie-reservation-web-stabilization-review-findings.md).

## Recommended Order

1. Reconcile #24 with the delivered baseline. Close it if its workspace/client
   acceptance criteria are already met; otherwise implement only the remaining
   gap.
2. Reconcile #25 with the existing reservation workflow, then finish the
   customer-facing product and state gaps.
3. Complete #26 by verifying propagation and the end-to-end local observability
   workflow outside the customer UI.
4. Complete #27 with final docs, accessibility/responsive checks, and at least
   one Playwright booking smoke test.
5. Close parent issue #5 only after the product requirements are met.

Use
[`movie-reservation-frontend-product-requirements.md`](movie-reservation-frontend-product-requirements.md)
as the D8 product and UX acceptance bar.

## Open D8 Issues

- [#24 D8b: Add frontend workspace foundation and GraphQL client](https://github.com/patex1987/golden-path-ecs-template/issues/24)
- [#25 D8c: Build reservation workflow UI with polling states](https://github.com/patex1987/golden-path-ecs-template/issues/25)
- [#26 D8d: Verify frontend observability propagation and demo workflow](https://github.com/patex1987/golden-path-ecs-template/issues/26)
- [#27 D8e: Add frontend verification, docs, and CI wiring](https://github.com/patex1987/golden-path-ecs-template/issues/27)

The issue descriptions predate the broad #23 delivery, so review the actual
code before implementing them. Do not duplicate already-delivered workspace,
client, workflow, or CI work merely to match the old issue split.

The `demo-multi-service-observability` branch also contains an agent client,
agent workflow panel, and reserved-seat UI changes that are not on current
`main`. Reconcile those changes through the separate
[`distributed observability adoption plan`](distributed-observability-demo-platform.md).
They may satisfy parts of #25 through #27, but the agent and technical
diagnostics must remain behind an explicit local/demo mode rather than becoming
the normal D8 customer UI.

## Related Follow-Ups

- [#28](https://github.com/patex1987/golden-path-ecs-template/issues/28): make protected reservation read outcomes explicit.
- [#29](https://github.com/patex1987/golden-path-ecs-template/issues/29): move catalog read-model assembly into the application query layer and address frontend overfetch.
- [#31](https://github.com/patex1987/golden-path-ecs-template/issues/31): add scalable CI, Playwright, and Docker/Postgres e2e strategy.
- [#32](https://github.com/patex1987/golden-path-ecs-template/issues/32): add reservation command idempotency before production-like retries.

Create a separate GraphQL code-generation issue when D8 resumes. It should
decide generated artifact policy, schema-drift validation, and whether generated
runtime validators replace the current hand-written boundary parsers.

## Deferred Until Needed

- Frontend containerization for repeatable Compose demos. Production AWS hosting
  may still use static S3/CloudFront delivery.
- Stylesheet decomposition after a second page, feature, or repeated component
  pattern makes ownership unclear.
- Recommendations, agent workflows, OIDC, and scenario controls are not part of
  D8 acceptance. Existing demo-branch implementations belong to the parallel
  distributed-demo adoption workstream.
