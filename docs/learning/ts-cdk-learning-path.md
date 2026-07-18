# 35-Day TypeScript & CDK Learning Path

> Historical learning schedule. It records the project's original daily plan
> and is not the current delivery tracker. Use
> [`../plans/movie-reservation-platform-roadmap.md`](../plans/movie-reservation-platform-roadmap.md)
> for current status and sequencing. Repository paths below have been updated to
> their current names, but day-level status is preserved as learning history.

This plan is designed for someone with a full-time job and a family.
The goal is not perfection. The goal is steady, compounding progress and one strong project that makes you feel dangerous on day 1.

## Ground rules

- Target **60–120 minutes on weekdays**
- Target **2–4 hours total on weekends**
- Prefer consistency over heroics
- Every day should end with one tiny output: a commit, a note, a diagram, or a passing test
- Keep running notes in `docs/learning/my-learning-notes.md` with:
  - what I learned
  - what confused me
  - what I would standardize as a platform engineer

## Weekly themes

- **Week 1:** TypeScript + Node backend foundations
- **Week 2:** CDK foundations + AWS mental model
- **Week 3:** ECS/Fargate + deployment + observability
- **Week 4:** Turn the project into a platform-style golden path
- **Week 5:** Cert lens + polish + confidence building

---

## Day 1

✅ **COMPLETED**

Read:

- `Learning TypeScript`: introduction + first practical chapter
- Skim TypeScript Handbook sections: "The Basics" and "Everyday Types"

Do:

- Create the repo
- Create folders:
  - `movie-reservation-service/`
  - `ecs-infra/`
  - `docs/`
- Add `docs/learning/my-learning-notes.md`
- Write 5–10 lines on what you think a platform team should provide

Deliverable:

- Empty repo scaffold committed

---

## Day 2

⏳ **IN PROGRESS**

Read:

- `You Don't Know JS Yet`: scope/closures or the JS fundamentals you feel weakest on
  - ✅ Reviewed: polyfill, transpilation, wasm basics, strict mode
  - ✅ Reviewed: call, apply, bind concepts
- TypeScript Handbook: functions, objects
  - ✅ Studied: `keyof`, `typeof` utility types
  - ✅ Studied: types vs interfaces distinction
  - ✅ Studied: composition over inheritance

Do:

- ✅ Initialize a Node + TypeScript backend
- ✅ Add package manager, tsconfig, lint, format, test runner
- ✅ Add a tiny `GET /health` endpoint (pending verification)

Deliverable:

- ✅ Service starts locally with TypeScript

**Notes:** Strong foundational work on TypeScript concepts. Used Trello for tracking individual topics (keyof, typeof, types vs interfaces). Reviewed core JS fundamentals from "You Don't Know JS Yet" to solidify closure and binding concepts before moving to async patterns.

## Day 3

Read:

- `Learning TypeScript`: unions, interfaces, narrowing, type inference

Do:

- Add request/response types
- Add runtime validation with Zod
- Add `/ready`
- Add one example endpoint like `GET /bookings/:id`

Deliverable:

- Typed endpoint with validation

## Day 4

Read:

- `Learning TypeScript`: classes/modules or whatever chapter covers project organization
- Small skim of Node docs on TypeScript if useful

Do:

- Add config module for env vars
- Add structured logging
- Add error handling middleware
- Add graceful shutdown

Deliverable:

- Backend skeleton feels production-ish

## Day 5

Read:

- `You Don’t Know JS Yet`: async/closures/event loop related material
- TypeScript Handbook: modules

Do:

- Add tests for health/config/example endpoint
- Refactor anything ugly
- Write `docs/architecture/service-architecture.md` with 10-15 lines

Deliverable:

- First clean backend milestone

## Day 6

Weekend light day.

Read:

- `Platform Engineering`: first chapter
- Write down every phrase that feels directly relevant

Do:

- In `notes.md`, answer:
  - What is the product of a platform team?
  - Who are its users?
  - What defaults should a platform own?

Deliverable:

- 1 page of platform notes

## Day 7

Weekend build day.

Do:

- Containerize the service with Docker
- Run it locally in a container
- Add `Makefile` or task runner commands:
  - install
  - test
  - run
  - docker-build
  - docker-run

Deliverable:

- Local dockerized backend

---

## Day 8

Read:

- AWS CDK TypeScript getting started docs
- Skim CDK concepts: app, stack, construct

Do:

- Initialize `ecs-infra/` as a CDK TypeScript app
- Run `cdk synth`
- Learn the generated project structure

Deliverable:

- Working CDK app committed

## Day 9

Read:

- AWS CDK guide on constructs and stacks
- `Platform Engineering`: next chapter

Do:

- Create your first stack
- Add tags and naming conventions
- Decide repo conventions:
  - stage names
  - stack naming
  - config strategy

Deliverable:

- Basic stack with conventions written down

## Day 10

Read:

- AWS Prescriptive Guidance for CDK in TypeScript
- Focus on project organization and reusability

Do:

- Add a VPC stack or networking section
- Add outputs where helpful
- Add `docs/architecture/infra-overview.md`

Deliverable:

- Networking scaffold in CDK

## Day 11

Read:

- `Learning TypeScript`: generics or advanced practical types
- Only enough to understand CDK typing patterns

Do:

- Add ECR repository in CDK
- Add CloudWatch log group
- Add IAM basics if needed
- Document what each resource is for

Deliverable:

- Infra starts looking real

## Day 12

Read:

- `Platform Engineering`: chapters on self-service, platform as product, golden paths

Do:

- Write `docs/architecture/golden-path.md`
- Answer:
  - What should be standardized?
  - What should be customizable?
  - What should be forbidden?

Deliverable:

- First version of your platform philosophy

## Day 13

Weekend light day.

Read:

- `Team Topologies`: intro + team types

Do:

- Write half a page:
  - stream-aligned team
  - platform team
  - enabling team
  - complicated subsystem team
- Note where your future role sits

Deliverable:

- Team Topologies notes

## Day 14

Weekend build day.

Do:

- Wire container image reference from app to infra
- Build deployment flow mentally even if not fully automated yet
- Clean up repo readme with:
  - what this project is
  - why you are building it
  - current status

Deliverable:

- Repo has a clear narrative

---

## Day 15

Read:

- ECS Developer Guide overview
- Learn cluster, task definition, service, task role, execution role

Do:

- Add ECS cluster to CDK
- Add task definition
- Add execution role
- Add task role

Deliverable:

- ECS resources defined in code

## Day 16

Read:

- ECS Fargate basics
- Health checks and container definitions

Do:

- Add Fargate service
- Add container settings
- Add health endpoint integration
- Make sure logs flow to CloudWatch

Deliverable:

- Service deployable shape exists

## Day 17

Read:

- ALB and target group basics
- ECS service exposure patterns

Do:

- Add ALB
- Add listener and target group
- Add health check path
- Document request flow in `docs/architecture/request-flow.md`

Deliverable:

- Internet-facing service architecture defined

## Day 18

Read:

- ECS autoscaling docs
- CloudWatch alarms basics

Do:

- Add autoscaling policies
- Add CPU and memory alarms
- Add one availability-style alarm if possible

Deliverable:

- Service has basic operations posture

## Day 19

Read:

- Secrets Manager / Parameter Store basics
- Review IAM least-privilege thinking

Do:

- Add one secret or parameter
- Consume it in the app
- Make sure task role permissions are explicit

Deliverable:

- App uses managed config/secrets

## Day 20

Weekend light day.

Read:

- `Platform Engineering`: chapter on measurement, adoption, or interfaces
- `Team Topologies`: interaction modes

Do:

- Write:
  - What would make a product team love this platform?
  - What would make them avoid it?

Deliverable:

- 1 page of product-thinking notes

## Day 21

Weekend build day.

Do:

- Get the service fully deployed end-to-end
- Hit the deployed health endpoint
- Take screenshots or write down outputs for later README use

Deliverable:

- First end-to-end deployed milestone

---

## Day 22

Read:

- AWS Prescriptive Guidance on reusable CDK patterns
- Skim CDK construct-level abstraction guidance

Do:

- Extract a reusable construct: `PlatformHttpService`
- Inputs should include:
  - service name
  - image
  - cpu/memory
  - env/secrets
  - desired count
- Outputs should expose useful handles

Deliverable:

- First reusable platform abstraction

## Day 23

Read:

- TypeScript chapter on API design, generics, or utility types
- Only what helps your construct code

Do:

- Clean up construct props and defaults
- Add tags and conventions
- Add log retention / naming defaults
- Add comments and types

Deliverable:

- Construct feels usable by another engineer

## Day 24

Read:

- ECS Service Connect or internal service-to-service communication docs
- Or SQS basics if you prefer async service design

Do:

- Decide on second workload:
  - worker service
  - scheduled task
  - queue consumer
- Start the second workload

Deliverable:

- Architecture expands beyond one HTTP app

## Day 25

Read:

- SQS and event-driven basics, or scheduled ECS task patterns

Do:

- Implement second workload
- Example: booking-sync worker consuming jobs
- Add local stub or fake downstream system

Deliverable:

- Async processing path exists

## Day 26

Read:

- `Team Topologies`: cognitive load, boundaries, team APIs

Do:

- Write `docs/architecture/platform-api.md`
- Explain how a service team would consume your abstraction:
  - what they must provide
  - what they get automatically
  - what they can customize

Deliverable:

- Consumer-facing platform API doc

## Day 27

Weekend light day.

Do:

- Refactor code ruthlessly
- Rename unclear things
- Remove accidental complexity
- Add tests for construct logic if practical

Deliverable:

- Cleaner codebase

## Day 28

Weekend build day.

Do:

- Add CI:
  - lint
  - test
  - build
  - synth
- Add separate stage config:
  - staging
  - prod
- Document deployment commands

Deliverable:

- Repo now looks like real team-owned code

---

## Day 29

Read:

- SAA exam guide domains
- Focus on architecture, resilience, security, cost, performance tradeoffs

Do:

- Map your project to SAA topics:
  - networking
  - IAM
  - compute
  - observability
  - scaling
  - storage
- Write a short self-review

Deliverable:

- SAA lens notes

## Day 30

Read:

- CloudOps Associate exam guide domains
- Focus on monitoring, reliability, incident response, operations

Do:

- Review alarms, dashboards, logs
- Ask:
  - What breaks first?
  - How would I detect it?
  - How would I recover?

Deliverable:

- CloudOps lens notes

## Day 31

Read:

- AWS Well-Architected Operational Excellence + Reliability ideas
- Just enough to evaluate your project

Do:

- Add one dashboard or dashboard notes
- Add one runbook in `docs/operations/runbook.md`
- Include:
  - common alarms
  - first checks
  - rollback ideas

Deliverable:

- Basic operational maturity

## Day 32

Do:

- Write `docs/architecture/architecture-decisions.md`
- Include 5–8 decisions:
  - Why ECS over Lambda
  - Why CDK over raw Terraform/CloudFormation here
  - Why these defaults
  - Why this logging and scaling setup
  - What you would change at larger scale

Deliverable:

- ADR-style notes

## Day 33

Do:

- Polish README
- Add architecture diagram
- Add “how to create a new service”
- Add “what the platform gives you”
- Add “known gaps / next iterations”

Deliverable:

- Strong top-level repo documentation

## Day 34

Do:

- Pretend it is your first week at a team using this platform
- Write a mock onboarding plan for yourself:
  - what questions to ask
  - what dashboards to inspect
  - what platform pain points to look for
  - what quick wins you might target

Deliverable:

- Confidence-building onboarding notes

## Day 35

Do:

- Review everything
- Make one final cleanup pass
- Record a short text summary for yourself:
  - what I learned
  - what I still don’t know
  - why I am still qualified
  - what I can ramp on quickly

Deliverable:

- Final prep checkpoint and confidence document

---

## Minimal daily fallback plan

When life gets busy, do this instead of skipping:

- 15 min reading
- 20 min coding
- 5 min notes

That still counts.

## Nice-to-have extras

If you have extra energy:

- add GitHub Actions
- add a small DynamoDB table
- add synthetic checks
- add canary deployment notes
- add cost notes
- add an internal service template generator

## What “done enough” looks like

By the end, you should have:

- a TypeScript backend you understand
- a CDK app in TypeScript
- an ECS/Fargate deployment
- observability basics
- a reusable platform abstraction
- documentation written like a platform team
- enough AWS cert context to sound structured and calm
