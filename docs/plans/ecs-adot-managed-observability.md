# Umbrella Design: ECS ADOT Managed Observability

> **Status notice:**
> This document is background material, not an executable implementation
> handoff. Issue #37 is delivered; its historical plan lives in
> [`delivered/ecs-adot-xray-tracing.md`](delivered/ecs-adot-xray-tracing.md).
> Before implementing #38, extract a focused CloudWatch/AMP/Managed Grafana plan
> from the still-relevant sections below.

Status update, 2026-07-26:

- Wave 1 failure injection and Wave 2 ECS backend skeleton are delivered.
- The Wave 2 stack was deployed successfully from a laptop and destroyed.
- [Issue #37](https://github.com/patex1987/golden-path-ecs-template/issues/37)
  is delivered by PR #39: ADOT collector sidecar and X-Ray traces are now part
  of the ECS baseline.
- [Issue #38](https://github.com/patex1987/golden-path-ecs-template/issues/38)
  is the current planned slice: CloudWatch metrics, AMP, and Amazon Managed
  Grafana.
- The AWS observability slices use the existing in-memory service. A Postgres
  sidecar is no longer part of this plan. RDS and deployment-time migrations via
  a separate ECS `RunTask` remain under issue #7.
- CDK deployments remain laptop-driven. The private promotion workflow from ADR
  015 is a later platform task.

## 1. Summary

Build an AWS CDK deployment path for `movie-reservation-service` that can build
the service image, publish it through CDK-managed image assets, run it on
ECS/Fargate behind an ALB, add an AWS Distro for OpenTelemetry collector
sidecar, and export:

- traces to AWS X-Ray;
- application metrics to CloudWatch custom metrics;
- application and ECS task metrics to Amazon Managed Service for Prometheus;
- dashboards and exploration through Amazon Managed Grafana.

Also add demo-only reservation failure injection so roughly 40% of reservation
requests fail as a production-looking `unexpected-error`. The goal is an
on-call style investigation scenario, not a clearly labelled demo fault.

Recommended next slice: create a focused #38 plan, then extend the delivered
ADOT/X-Ray baseline with bounded metrics. Prove the simplest CloudWatch
application-metric path first, then add AMP remote write, ECS/container metric
coverage, and Managed Grafana dashboarding once cost, regional support, and
identity choices are explicit. Keep RDS, production OIDC, full CI/CD deployment
automation, and the multi-service agent/MCP infrastructure as later slices.

Recommended follow-up slice: add CI observability for GitHub Actions with a
separate `workflow_run` telemetry workflow. Emit low-cardinality CloudWatch
metrics and summarized structured CI events for the existing CI workflow. Use
GitHub OIDC with a narrow AWS role. Do not expose a public OTLP collector for
GitHub runners and do not ship full GitHub job logs into AWS.

## 2. Goals

- Add an implementation-ready CDK path in `ecs-infra/` for the movie
  reservation API.
- Make `cdk deploy` build and upload the app image and ADOT collector image.
- Deploy an ECS/Fargate service behind an Application Load Balancer.
- Use Option C for the first AWS network path: public ALB, private Fargate
  tasks, VPC endpoints for AWS service access, and no NAT Gateway.
- Keep the managed-observability slices on the existing in-memory composition
  profile; do not couple telemetry delivery to database work.
- Configure `/health` as the ALB target health check path.
- Keep app logs as JSON stdout routed through the ECS `awslogs` driver.
- Export traces from the existing Node OpenTelemetry SDK to ADOT, then X-Ray.
- Export application metrics to CloudWatch custom metrics and AMP.
- Export ECS task/container metrics to AMP and enable ECS Container Insights
  enhanced observability for platform metrics.
- Provision AMP and AMG through CDK where CloudFormation support is reasonable.
- Document any AMG data source steps that remain manual.
- Add demo-only production-looking reservation failure injection at a default
  40% rate.
- Keep failure injection out of default production-shaped behavior.
- Make failure injection available in both local Docker rehearsal and the AWS
  demo stack through environment variables.
- Add a follow-up CI observability phase that emits bounded CloudWatch metrics
  and structured CI events from GitHub Actions.
- Correlate CI, infrastructure, and runtime by passing CI-generated
  correlation/request context into post-deploy smoke requests.

## 3. Non-goals

- Do not port the full `demo-multi-service-observability` branch to `main`.
- Do not deploy the Python agent, MCP services, Rust recommendation service, or
  local Grafana/Tempo/Loki stack in this plan.
- Do not add SQS or a separate worker service yet.
- Do not add production OIDC/JWKS auth in this plan.
- Do not add full RDS/Aurora production persistence in the first ECS slice.
- Do not add a Postgres sidecar or migration container to issues #37 or #38.
- Do not run database migrations from the API task or application startup.
- Do not add a new failed reservation reason for failure injection. The
  injected path intentionally uses the existing `unexpected-error` reason.
- Do not add a NAT Gateway in the recommended first ECS slice.
- Do not make GitHub Actions deploy the service in the first implementation
  wave. CI observability is a separate phase from CI/CD deployment automation.
- Do not create a generic platform abstraction before the first ECS service
  works end to end.
- Do not expose ADOT ports outside the task security group.
- Do not use high-cardinality ids as metric labels.
- Do not expose a public OTLP endpoint for GitHub-hosted runners.
- Do not ship raw GitHub Actions logs, environment dumps, synthesized templates,
  secrets, or tokens into CloudWatch.

## 4. Current State

- Root `package.json` is an npm workspace repo with `movie-reservation-service`,
  `ecs-infra`, and `movie-reservation-web`.
- Wave 1 failure injection is implemented with a stable hash/salt policy,
  disabled default, `unexpected-error`, and bounded diagnostic exception type.
- Wave 2 is delivered on `main`: the explicit backend stack contains a VPC,
  ALB, Fargate service, app image asset, log group, and the minimum no-NAT
  endpoints. It has been deployed successfully from a laptop and destroyed.
- Issue #37 is delivered on `main`: the stack has a repo-managed ADOT collector
  sidecar, app OTLP trace export, a private X-Ray endpoint, least-privilege
  X-Ray write policies, validation scripts, trace smoke tooling, and runbook
  updates.
- CloudWatch metrics, AMP, and AMG remain active #38 planning and
  implementation work.
- `ecs-infra/package.json` already has `aws-cdk-lib`, `constructs`, Jest,
  TypeScript, and scripts for `build`, `test`, `cdk`, and `ci`.
- `movie-reservation-service/Dockerfile` already builds the compiled NestJS
  service and starts `npm run start`.
- `movie-reservation-service/package.json` starts production code with
  `node --import ./dist/src/infrastructure/observability/instrumentation.js`.
- `movie-reservation-service/src/infrastructure/observability/instrumentation.ts`
  already starts the OpenTelemetry Node SDK when observability is enabled. It
  uses OTLP HTTP trace and metric exporters, HTTP/Express/GraphQL/Knex/pg
  instrumentation, and bounded service resource attributes.
- `movie-reservation-service/src/config.ts` already validates OTLP endpoint,
  protocol, propagators, service name, and resource attributes with Zod.
- `observability/otel-collector.yaml` is a local collector config. It receives
  OTLP, exposes local Prometheus metrics, and forwards traces/metrics to an
  external local stack over OTLP/gRPC.
- `docs/workflows/local-observability.md` defines the existing local signal
  contract: JSON stdout logs, OpenTelemetry traces, OpenTelemetry metrics, W3C
  `traceparent`, optional `tracestate`, `X-Correlation-Id`, and `X-Request-Id`.
- `docs/architecture/observability-log-contract.md` defines stable log fields
  and warns against logging secrets, raw headers, request bodies, GraphQL
  variables, or tokens.
- Current service metrics have bounded labels:
  - HTTP: method, route, status family.
  - GraphQL: business operation, operation type, outcome.
  - Reservation processor: outcome, bounded reason, diagnostic exception type.
- `docs/architecture/platform-api.md` already sketches a future
  `PlatformHttpService` construct with inputs for image/build context,
  container port, health path, environment, secrets, autoscaling, alarms, and
  OpenTelemetry settings.
- The `demo-multi-service-observability` branch mostly adds local demo/MCP
  orchestration and runbooks. Its `ecs-infra` stack is also blank, so it is a
  useful signal-contract reference, not an AWS CDK implementation to copy.
  The useful portable contract from that branch is the propagation of
  `traceparent`, optional `tracestate`, `X-Correlation-Id`, `X-Request-Id`,
  service names, JSON logs, and bounded fault labels.
- `.github/workflows/ci.yml` already runs service quality, service tests,
  service build, infra build/test/synth, and web checks. It currently has
  `contents: read` permissions only and intentionally does not use AWS
  credentials.
- `docs/workflows/ci-workflow.md` documents the current CI foundation as
  deployment-free. CI observability should extend that contract without turning
  every pull request into a deployment pipeline.
- Issue #37 delivered the repo-managed ADOT image, collector sidecar, app OTLP
  enablement, X-Ray IAM/networking, tests, and AWS trace smoke check.
- Issue #38 owns CloudWatch metric export, AMP remote write, Managed Grafana,
  bounded dimensions, tests, and the managed-metrics smoke check.
- Issue #7 owns RDS and a separate deployment-time ECS migration `RunTask`.
- The reservation processor already has a retryable and terminal internal
  failure path. `InProcessReservationRequestProcessor.handleUnexpectedFailure`
  records failed attempts and eventually marks the reservation request failed.
- Postgres persistence currently constrains failed processing attempt reasons
  to `unexpected-error` or `lease-timeout`.
- Because the injected failure will reuse `unexpected-error`, the failure
  injection feature should not require a Postgres check-constraint migration.

Used local Programming KB notes:

- `/home/patex1987/Documents/programming_kb/patterns/NestJS Request Context Middleware.md`
- `/home/patex1987/Documents/programming_kb/patterns/GraphQL Operation Logging Plugin.md`
- `/home/patex1987/Documents/programming_kb/decisions/Keep GraphQL Lifecycle Instrumentation at Presentation Boundary.md`
- `/home/patex1987/Documents/programming_kb/concepts/AsyncLocalStorage Request Context.md`

KB freshness note: the local KB has useful application-observability boundary
guidance, but it does not currently have focused ADOT on ECS, AMP, or AMG notes.
AWS-specific details in this plan were checked against current official AWS
documentation.

Official AWS sources checked:

- ECS ADOT X-Ray sidecar:
  `https://docs.aws.amazon.com/AmazonECS/latest/developerguide/trace-data.html`
  and
  `https://docs.aws.amazon.com/AmazonECS/latest/developerguide/trace-data-containerdefinitions.html`
- ECS ADOT application metrics to CloudWatch:
  `https://docs.aws.amazon.com/AmazonECS/latest/developerguide/application-metrics-cloudwatch.html`
- ECS ADOT application metrics to AMP:
  `https://docs.aws.amazon.com/AmazonECS/latest/developerguide/application-metrics-prometheus.html`
- AMP ADOT ECS ingestion:
  `https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-onboard-ingest-metrics-OpenTelemetry-ECS.html`
- AMP workspace creation:
  `https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-create-workspace.html`
- AMP interface VPC endpoint note:
  `https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-and-interface-VPC.html`
- AMG overview, data sources, permissions, and CloudFormation:
  `https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Service-Grafana.html`,
  `https://docs.aws.amazon.com/grafana/latest/userguide/AMG-data-sources-builtin.html`,
  `https://docs.aws.amazon.com/grafana/latest/userguide/AMG-manage-permissions.html`,
  and
  `https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-resource-grafana-workspace.html`
- CDK Docker image assets and ECS container images:
  `https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_ecr_assets.DockerImageAsset.html`
  and
  `https://docs.aws.amazon.com/cdk/api/v2/python/aws_cdk.aws_ecs/ContainerImage.html`
- GitHub Actions OIDC to AWS and default CI metadata:
  `https://docs.github.com/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services`
  and
  `https://docs.github.com/en/actions/reference/workflows-and-actions/variables`
- CloudWatch custom metric publishing:
  `https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/put-metric-data.html`
- CloudFront-to-ALB origin restriction and custom headers:
  `https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/restrict-access-to-load-balancer.html`
- CloudFront managed prefix list:
  `https://docs.aws.amazon.com/vpc/latest/userguide/working-with-aws-managed-prefix-lists.html`
- GitHub Actions `workflow_run` and secure workflow usage:
  `https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions`
  and
  `https://docs.github.com/en/actions/reference/security/secure-use`

## 5. Requirements and Assumptions

### Confirmed Requirements

- Build a CDK solution for service image build and ECS/Fargate deployment.
- Add an AWS ADOT sidecar.
- Route traces to X-Ray.
- Route metrics to CloudWatch metrics.
- Route metrics to a Grafana stack, preferably Amazon Managed Grafana plus
  Amazon Managed Service for Prometheus.
- Use the existing local observability/demo work as reference, but do not merge
  the full vibe-coded demo branch.
- Make seat reservation fail randomly in at least 40% of cases.
- Failure injection should simulate a real on-call scenario. It must not use a
  distinguishable business reason such as `demo-random-failure`; it should use
  the existing `unexpected-error` reason plus a bounded diagnostic exception
  type.
- Keep the first AWS implementation on the Option C cost/security path:
  public ALB, private ECS tasks, VPC endpoints, and no NAT Gateway.
- Keep the delivered #37 baseline and current #38 work on the in-memory ECS
  composition profile.
- Add RDS later under #7 and execute migrations as a separate ECS `RunTask`
  during deployment, analogous to a Kubernetes Job.
- Start with only `movie-reservation-service` in AWS. Add MCP services, agents,
  and recommendation services incrementally later.
- Include the frontend in Phase 2 using S3 and CloudFront, not in the first
  backend ECS deploy.
- The Phase 2 frontend should call the backend through relative `/graphql`,
  routed by CloudFront to the ALB.
- Add observability to CI so GitHub Actions checks and future deploy/smoke
  workflows can be correlated with runtime telemetry.
- Produce a detailed plan before implementation.

### Assumptions

- The first AWS target is a demo environment, not a hardened production service.
- CDK Docker image assets are acceptable for the first slice. That means
  `cdk deploy` builds locally or in a CI runner and uploads images to
  CDK-managed ECR asset repositories.
- A later CI/CD slice can promote explicit ECR repositories and image tags.
- The ECS observability demo can use local/demo auth and in-memory persistence;
  reservations are intentionally disposable across task replacement.
- A separate ECS task does not share another task's loopback interface. The
  future migration `RunTask` therefore requires a separately reachable RDS
  endpoint and belongs in issue #7.
- Private tasks without NAT require VPC endpoints for image pulls, logs, X-Ray,
  AMP remote write, SigV4/STSesque credential flow, and optional ECS Exec.
- The public ALB should be treated as demo internet exposure and restricted by
  source IP where practical.
- AWS IAM Identity Center is available for Amazon Managed Grafana access. If it
  is not available, AMG workspace creation and authentication need an explicit
  SAML/customer-managed alternative.
- The ADOT sidecar will use a custom collector image so the collector config is
  versioned in this repo and deployed as a CDK image asset.
- The application container will send OTLP HTTP to the sidecar on
  `http://127.0.0.1:4318` inside the ECS task.
- The failure injection requirement is about final reservation request outcomes,
  not individual retry attempts. Per-attempt random exceptions can be masked by
  retries and would not reliably produce 40% failed requests.
- The injected failure type can be suggestive but must not be labelled as a demo
  fault. Use a bounded production-looking exception type such as
  `SeatReservationCommitError`.
- CI observability should use low-cardinality metric dimensions such as
  repository, workflow, job, branch family, result, stack, and environment. It
  must put high-cardinality values such as run id, attempt, commit SHA, PR
  number, trace id, and correlation id into logs or job summaries, not metric
  dimensions.
- GitHub Actions should use OIDC and short-lived AWS credentials. No static AWS
  keys should be stored in GitHub secrets for CI telemetry.

### Open Questions

1. For #38, should Amazon Managed Grafana be fully provisioned with
   customer-managed IAM roles in CDK, or is a CDK-created workspace plus
   documented console data source setup acceptable for the first iteration?
2. What AWS Region should be used for #38? AMG and AMP are regional services,
   and AMG Region availability must be checked before choosing.
3. Should #38 enable Amazon Managed Grafana immediately or
   create AMP/CloudWatch/X-Ray first and add AMG after those signals are
   verified?

## 6. Proposed Design

### High-Level AWS Shape

Create an AWS demo platform stack in `ecs-infra`:

```text
Internet or developer
  -> Application Load Balancer
  -> ECS Fargate service
       task:
         movie-reservation-service container
           uses the in-memory composition profile
           stdout JSON logs -> CloudWatch Logs
           OTLP traces/metrics -> localhost:4318
         aws-otel-collector sidecar
           OTLP receiver
           awsecscontainermetrics receiver
           traces -> awsxray exporter
           metrics -> awsemf exporter -> CloudWatch custom metrics
           metrics -> prometheusremotewrite exporter -> AMP
           sidecar logs -> CloudWatch Logs
  -> X-Ray, CloudWatch, AMP
  -> Amazon Managed Grafana data sources
```

Use Option C for the first AWS stack:

- ALB in public subnets.
- ECS tasks in private subnets.
- No NAT Gateway.
- The VPC and public ALB subnets span two Availability Zones.
- The single demo task and interface endpoint ENIs are pinned to one selected
  workload subnet to avoid paying for duplicate endpoint coverage before HA is
  required.
- Required AWS service traffic goes through VPC gateway/interface endpoints.
- The service stayed in-memory for #37 and stays in-memory for #38. RDS and
  migrations are a later deployment concern under #7.
- The ALB must be source-IP restricted with an explicit `allowedIngressCidr`
  config value for the Phase 1 backend-only demo.
- ECS Exec should be controlled by an explicit `enableEcsExec` config flag.

Start with an explicit stack-first CDK implementation:

- Put the first working resource graph mostly in `ecs-infra/lib/infra-stack.ts`.
- Add a small typed config loader in
  `ecs-infra/lib/config/platform-config.ts`.
- Defer reusable constructs such as `PlatformHttpService`,
  `AdotCollectorSidecar`, `ManagedObservability`, and `FrontendStaticSite`
  until after the first successful deploy.
- Keep future construct names in docs as extraction targets, not first-pass
  implementation requirements.

This maps to CDK and CloudFormation as follows:

- A CDK stack synthesizes to a CloudFormation stack.
- `ec2.Vpc` becomes VPC, public subnets for the ALB, private subnets for ECS
  tasks, route tables, and gateway/interface endpoints. The recommended path
  does not create NAT Gateway resources.
- `ecs.Cluster` becomes an ECS cluster. Keep Container Insights disabled for the
  delivered #37 baseline; #38 may enable enhanced observability after its cost
  and metric scope are reviewed.
- `ecs.FargateTaskDefinition` becomes an ECS task definition with task and
  execution IAM roles.
- `taskDefinition.addContainer` creates app and ADOT container definitions.
- In the delivered #37 baseline, the app and nonessential collector start
  independently, with no ECS container dependency. The app's `/health` check
  remains the service health boundary; collector health is visible separately
  and end-to-end trace delivery is verified by smoke test.
- The app and collector `awslogs` drivers use separate CloudWatch log groups.
- `ApplicationLoadBalancedFargateService` can create the ALB, listener, target
  group, security groups, and Fargate service, or the plan can use lower-level
  ECS/ELB constructs once sidecar control gets too awkward.
- `aps.CfnWorkspace` creates an AMP workspace.
- `grafana.CfnWorkspace` creates an AMG workspace.

Use fixed, readable names for the learning stack:

- Stack: `GoldenPathDemoStack`.
- Platform name: `movie-reservation-platform`.
- Environment name: `aws-demo`.
- ECS application cluster: `movie-reservation-platform-aws-demo`.
- Service name: `movie-reservation-service`.
- CloudWatch log groups:
  - `/golden-path/aws-demo/movie-reservation-service/app`
  - `/golden-path/aws-demo/movie-reservation-service/adot`
- CloudWatch metric namespaces:
  - `GoldenPath/MovieReservationService`
  - `GoldenPath/CI`
- AMP workspace alias: `golden-path-aws-demo`.
- AMG workspace name: `golden-path-aws-demo`.
- Use generic resource names and project/environment tags rather than embedding
  a personal username in resource names.

### Build And Image Publishing

Use CDK Docker image assets first:

- App image: build from repository root with
  `movie-reservation-service/Dockerfile`, because the Dockerfile expects root
  `package.json`, `package-lock.json`, and workspace metadata.
- ADOT image: build from `ecs-infra/adot-collector/` with a Dockerfile based on
  an official ADOT release pinned by both explicit tag and immutable digest.
  Never use `latest` for the #37 implementation.

CDK assets are appropriate for the first implementation because they make the
learning path direct: `cdk deploy` builds, uploads, and wires the image into the
task definition. A later production path can switch to explicit ECR
repositories and GitHub Actions image promotion.

### ADOT Collector Configuration

Add a repo-owned collector config, likely:

```text
ecs-infra/adot-collector/Dockerfile
ecs-infra/adot-collector/adot-config.yaml
```

The following collector responsibilities describe the combined #37/#38 target.
#37 delivered the traces pipeline described in
[`delivered/ecs-adot-xray-tracing.md`](delivered/ecs-adot-xray-tracing.md).
Metrics receivers and exporters remain #38 work.

Combined target responsibilities:

- Receive traces and metrics from the app over OTLP HTTP and gRPC.
- Receive ECS task/container metrics through `awsecscontainermetrics`.
- Batch all outgoing telemetry.
- Export traces to X-Ray with `awsxray`.
- Export app metrics to CloudWatch with `awsemf`.
- Export app and ECS metrics to AMP with `prometheusremotewrite` using
  `sigv4auth` configured for service `aps`.

The CloudWatch and AMP metric pipelines should use bounded resource attributes
and metric labels only. Do not include `trace_id`, `request_id`,
`correlation_id`, `reservation_request_id`, `user_id`, or raw GraphQL names as
metric labels.

### Application Container Configuration

Set ECS environment variables for the app container:

- `PORT=3000`
- `HOST=0.0.0.0`
- `NODE_ENV=development` for the first demo-only slice, or a future
  production-shaped profile after auth and persistence are addressed.
- `LOG_LEVEL=info`
- `SERVICE_VERSION=<movie-reservation-service package version>`
- `COMPOSITION_PROFILE=local-fixed-user` for the disposable in-memory ECS demo.
- `RESERVATION_WORKER_MODE=disabled` unless a later demo explicitly needs
  reservation processing/failure injection.
- `OBSERVABILITY_ENABLED=true`
- `OTEL_TRACES_EXPORTER=otlp`
- `OTEL_METRICS_EXPORTER=none` for #37; #38 changes this deliberately
- `OTEL_LOGS_EXPORTER=none`
- `OTEL_SERVICE_NAME=movie-reservation-service`
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318`
- `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`
- `OTEL_PROPAGATORS=tracecontext,baggage`
- `OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=aws-demo,service.namespace=movie-reservation-platform`
- failure injection env vars described below.

No database or migration environment is required by #37 or #38. Under #7, the
deployment orchestrator must run a dedicated migration task against RDS and
wait for its terminal exit code before updating the service. Initially that
orchestration can run from the developer laptop; the later private deployment
workflow will reuse the same contract.

### IAM

Use separate task execution and task roles:

- Execution role:
  - Pull CDK asset images from ECR.
  - Write container stdout/stderr to CloudWatch Logs.
  - Read Secrets Manager or SSM values if used by ECS secret injection.
- Task role:
  - X-Ray write permissions for ADOT trace export.
  - CloudWatch metric/log permissions required by the ADOT CloudWatch metrics
    path.
  - `AmazonPrometheusRemoteWriteAccess` or least-privilege `aps:RemoteWrite`
    permissions scoped to the AMP workspace for remote write.
  - `ssm:GetParameters` only if the collector config or app config is read from
    SSM.
  - ECS Exec `ssmmessages` channel permissions only when
    `enableEcsExec=true`; these actions require `Resource: "*"` because they do
    not support resource-scoped ARNs.

Prefer explicit inline IAM policies in CDK for learning, then factor them into
helpers after the permissions stabilize.

### Networking

For the first learning/demo stack:

- Use a VPC with public subnets for the ALB and private subnets for Fargate
  tasks.
- Configure `vpcMaxAzs: 2` and `workloadAzCount: 1` as fixed internal values,
  not caller-controlled CDK context.
- Do not create a NAT Gateway in the recommended path.
- Allow inbound traffic from the ALB security group to the app container port
  only.
- Allow inbound ALB traffic only from the required configured demo source CIDR.
  Reject the internet-wide `0.0.0.0/0` value at the config boundary.
- Do not allow inbound traffic to collector ports from outside the task.
- Allow outbound HTTPS from tasks only to the endpoint security group and
  required AWS service endpoints where practical.
- Add an S3 gateway endpoint for ECR image layer downloads.
- Attach the S3 endpoint route and every interface endpoint ENI only to the
  selected workload subnet in the first demo.
- Add interface endpoints for:
  - `ecr.api`;
  - `ecr.dkr`;
  - `logs`;
  - `xray`;
  - `aps-workspaces`;
  - `sts`;
  - `ssmmessages` if ECS Exec is enabled;
  - `secretsmanager` or `ssm` only if runtime secrets/config are read that way;
  - `kms` only if encrypted secrets/logging paths require direct KMS calls.
- Attach endpoint security groups that allow inbound `443` only from the task
  security group.
- Add endpoint policies where useful, especially for ECR and CloudWatch Logs.
- Before Wave 4 adds X-Ray, AMP, or STS endpoints, compare the complete
  region-specific endpoint cost with NAT and document the selected continuation
  path.

### CDK Configuration

Use a small typed config boundary rather than scattering raw context lookups:

```ts
export interface PlatformConfig {
  readonly platformName: "movie-reservation-platform";
  readonly serviceName: "movie-reservation-service";
  readonly environmentName: "aws-demo";
  readonly allowedIngressCidr: string;
  readonly vpcMaxAzs: 2;
  readonly workloadAzCount: 1;
  readonly enableEcsExec: boolean;
}
```

Config rules:

- `platformName` is fixed at `movie-reservation-platform`. It names shared
  platform-level resources such as the ECS application cluster and is not
  caller-controlled CDK context.
- `allowedIngressCidr` is required for real deploys. Wave 2 tests and public CI
  synth temporarily use the documentation CIDR `203.0.113.10/32`; this is a
  credential-free validation convention, not a deployment default. Replace the
  convention when the private promotion workflow from
  [ADR 015](../architecture/architecture-decisions.md#adr-015-keep-public-ci-credential-free-and-deploy-from-a-private-promotion-workflow)
  owns real environment configuration and AWS deployment authority.
- Reject `allowedIngressCidr=0.0.0.0/0`; the backend-only demo must use an
  explicit restricted source range.
- `vpcMaxAzs` is fixed at `2` so the internet-facing ALB can attach to two
  public subnets.
- `workloadAzCount` is fixed at `1` so the disposable task and paid interface
  endpoint ENIs remain in one Availability Zone. Production-shaped deployment
  should use at least two workload AZs and two desired tasks.
- `enableEcsExec` is explicit. When false, do not create the `ssmmessages`
  endpoint or ECS Exec permissions.
- Do not add broad configuration knobs before there is a real use case.

### Managed Grafana And Managed Prometheus

Create an AMP workspace in CDK and output:

- workspace ID;
- workspace ARN;
- remote write URL;
- query URL.

Create an AMG workspace in CDK if IAM Identity Center or SAML requirements are
known. AMG can use service-managed permissions or customer-managed permissions:

- For fastest first slice, use `SERVICE_MANAGED`, `CURRENT_ACCOUNT`, and data
  sources for CloudWatch, X-Ray, and AMP where CloudFormation supports the
  intended behavior.
- If service-managed data source provisioning is not reliable from
  CloudFormation in the target account, provision the workspace in CDK and
  document the manual data source steps.
- For tighter IaC, use `CUSTOMER_MANAGED` and create a Grafana workspace role
  in CDK with CloudWatch read, X-Ray read, and AMP query permissions.

AMG should be treated as the dashboard/explore surface:

- CloudWatch data source for logs, custom app metrics, Container Insights, and
  alarms.
- X-Ray data source for traces.
- AMP data source for Prometheus metrics and future alerting.

Dashboards should carry forward the useful model from the
`demo-multi-service-observability` branch:

- Four golden-signal rows: Traffic, Errors, Latency, Saturation.
- Each row should include both platform signals and business workflow signals
  where available.
- Example business signals:
  - GraphQL operation count and duration.
  - reservation request count.
  - reservation processor success/failure count.
  - failure reason `unexpected-error`.
  - bounded diagnostic exception type such as `SeatReservationCommitError`.
- Example platform signals:
  - ALB request count and target response time.
  - ECS CPU/memory.
  - task health/restart indicators.
  - ADOT collector health/logs if useful.
- Logs remain stdout JSON through CloudWatch Logs. Do not add OTLP log export in
  this plan.

### Frontend Phase 2 Design

Frontend hosting is Phase 2, after the backend ECS learning loop works.

Target shape:

```text
Browser
  -> CloudFront distribution
       default behavior -> S3 frontend bucket
       /graphql behavior -> ALB backend origin
  -> ALB
       -> private ECS backend task
```

Frontend delivery split:

- CDK owns infrastructure: S3 bucket, CloudFront distribution, origins, cache
  behaviors, permissions, outputs, and teardown behavior.
- CI/CD owns the frontend artifact: build `movie-reservation-web`, upload
  `dist/` to S3, and invalidate CloudFront.
- The frontend should call the API with a relative `/graphql` URL.

Cheap first-pass ALB origin restriction for Phase 2:

- Allow ALB ingress from the AWS-managed CloudFront origin-facing prefix list.
- Configure CloudFront to add a custom origin verification header when calling
  the ALB.
- Configure the ALB listener/rules to require that header before forwarding to
  the backend target group.
- Defer AWS WAF for cost reasons. WAF can be added later for stronger public
  edge protection.
- Document that the header value must be treated as secret-ish configuration,
  even though this is not equivalent to full application authentication.

### CI Observability Design

Add CI telemetry with a separate workflow, for example
`.github/workflows/ci-telemetry.yml`, triggered by `workflow_run` after the
existing `CI` workflow completes. This keeps normal CI jobs free of AWS
credentials while still allowing CI results, including pull request results, to
be emitted to CloudWatch from trusted workflow code.

Use a narrow GitHub OIDC role:

- GitHub workflow permission: `id-token: write` only in the CI observability
  telemetry workflow that needs AWS access.
- AWS role trust: restrict to this repository, expected branch/environment, and
  workflow where possible.
- IAM permissions:
  - `cloudwatch:PutMetricData` scoped by namespace condition if practical;
  - optional `logs:CreateLogStream` and `logs:PutLogEvents` for a dedicated
    `/golden-path/ci` log group;
  - no deploy permissions in the CI observability role.

Emit metrics to the `GoldenPath/CI` namespace:

| Metric                | Dimensions                                                         | Notes                                                                       |
| --------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `WorkflowRun`         | `Repository`, `Workflow`, `EventName`, `Source`, `Result`          | Count one per completed workflow run.                                       |
| `JobDurationMs`       | `Repository`, `Workflow`, `Job`, `EventName`, `Source`, `Result`   | Duration of CI jobs such as service, web, and infra.                        |
| `CdkSynthDurationMs`  | `Repository`, `Workflow`, `Stack`, `EventName`, `Source`, `Result` | Duration of `npm -w ecs-infra run cdk -- synth` when job data is available. |
| `CdkSynthSuccess`     | `Repository`, `Workflow`, `Stack`, `EventName`, `Source`, `Result` | Count success/failure for synth.                                            |
| `DeploymentSuccess`   | `Repository`, `Environment`, `Stack`, `Result`                     | Add only when a deploy workflow exists.                                     |
| `SmokeTestDurationMs` | `Repository`, `Environment`, `Stack`, `Result`                     | Add with post-deploy smoke tests.                                           |

Use bounded values for:

- `EventName`: `pull_request`, `push`, `workflow_dispatch`, or `schedule`.
- `Source`: `base_repo` or `fork`.

Keep high-cardinality values out of metric dimensions:

- Do not use GitHub run id, run attempt, SHA, PR number, trace id, request id,
  correlation id, or branch names with many short-lived values as dimensions.
- Put those values in structured CI events, GitHub step summaries, and
  post-deploy smoke request headers instead.

Emit summarized structured CI events, not raw job logs:

```json
{
  "event": "ci.cdk_synth.completed",
  "repository": "golden-path-ecs-template",
  "workflow": "CI",
  "job": "infra",
  "github_run_id": "123456",
  "github_run_attempt": "1",
  "git_sha": "abc123",
  "stack_name": "GoldenPathDemoStack",
  "result": "success",
  "duration_ms": 42000
}
```

The structured event may include run id, run attempt, SHA, PR number, branch,
and exact GitHub URLs because those values are in logs/events rather than metric
dimensions.

Do not add OTLP CI traces in the first pass. Marketplace/OpenTelemetry GitHub
Actions exist, but they introduce endpoint, supply-chain, and data-handling
questions. Start with custom CloudWatch metrics because this project needs
custom dimensions and AWS/Grafana visibility anyway.

For future deploy/smoke workflows, generate a workflow correlation id:

```text
ci-<github_run_id>-<github_run_attempt>
```

Pass it into the deployed service smoke request:

```text
X-Correlation-Id: ci-<github_run_id>-<github_run_attempt>
X-Request-Id: ci-smoke-<job>
traceparent: <generated W3C traceparent>
```

That creates the intended join path:

```text
GitHub workflow run
  -> CI CloudWatch metric/event
  -> post-deploy smoke request
  -> ECS app logs
  -> X-Ray trace
  -> CloudWatch/AMP metrics
  -> Grafana dashboard
```

### Failure Injection Design

Add a small application port instead of putting randomness in the domain model
or resolver. The injected failure is intentionally production-looking: it should
surface as the existing `unexpected-error` reason, with a bounded diagnostic
exception type that gives on-call engineers a clue without labelling the error
as a demo fault.

```text
movie-reservation-service/src/application/movie-reservations/ports/reservation-processing-failure-policy.ts
movie-reservation-service/src/application/movie-reservations/disabled-reservation-processing-failure-policy.ts
movie-reservation-service/src/infrastructure/movie-reservations/stable-random-reservation-processing-failure-policy.ts
```

Suggested contract:

```ts
export interface ReservationProcessingFailurePolicy {
  shouldFail(input: {
    readonly reservationRequestId: ReservationRequestId;
    readonly sequence: ReservationRequestSequence;
  }): boolean;
}
```

Use a stable pseudo-random decision based on `reservationRequestId` plus a
configurable salt. That gives random-looking distribution while keeping the
decision stable for a request. This matters because pure per-attempt randomness
can be hidden by retries and can make tests flaky.

Add config:

- `RESERVATION_FAILURE_INJECTION_MODE=disabled|stable-random-unexpected-error`
- `RESERVATION_FAILURE_INJECTION_RATE=0.4`
- `RESERVATION_FAILURE_INJECTION_SALT=<optional stable string>`

When enabled, the processor should evaluate the policy after a request is
claimed and before confirmation. If the policy says fail, raise or record a
suggestive production-looking exception such as `SeatReservationCommitError`.
The existing unexpected-failure path should persist the failure with reason
`unexpected-error`, record the normal processor failure metrics/logs/spans, and
return the existing failed processing result shape.

This design means:

- no GraphQL schema change is required;
- clients still see the existing reservation request status eventually become
  `FAILED`;
- Grafana can show the failure as a business/process outcome without an obvious
  "demo fault" label;
- tests can use a deterministic fake policy;
- no Postgres check-constraint migration is needed for a new failure reason;
- production defaults remain disabled.

## 7. Alternatives Considered

### Alternative A: CDK Docker Image Assets First

- Pros:
  - Fastest path from current repo to ECS.
  - No separate CI/CD design needed before the stack works.
  - Official CDK support builds and uploads Docker images during deploy.
  - Good for learning how CDK assets, ECR, ECS, and CloudFormation connect.
- Cons:
  - Less production-like image promotion.
  - Local or CI deploy environment must have Docker.
  - Harder to share one promoted immutable image across environments.
- Decision:
  - Recommended for the first implementation.

### Alternative B: Explicit ECR Repositories Plus GitHub Actions

- Pros:
  - Better production promotion model.
  - Clear image tags by git SHA.
  - Allows image scanning and deployment approvals.
  - Natural place to add deployment metrics later.
- Cons:
  - More moving parts before the first ECS service works.
  - Requires GitHub OIDC/IAM and workflow design.
- Decision:
  - Defer until the ECS/ADOT stack works.

### Alternative C: Private Tasks With NAT Gateway

- Pros:
  - Easiest private-task outbound connectivity.
  - Fewer VPC endpoint resources and endpoint policies to reason about.
  - Less chance of missing an AWS service endpoint during the first deploy.
- Cons:
  - Fixed NAT hourly cost if the stack is forgotten.
  - NAT allows broad outbound internet access unless separately controlled.
  - Does not teach the no-NAT/private-service pattern the user wants to explore.
- Decision:
  - Keep as a fallback if endpoint complexity blocks the first deploy. Do not
    use it in the recommended path.

### Alternative D: Public Tasks Without NAT Or Endpoints

- Pros:
  - Lowest moving-part count.
  - Cheapest short-lived network shape.
  - Image pulls and AWS API calls are straightforward.
- Cons:
  - ECS task receives a public IP.
  - Weaker default security story for a platform template.
  - Easy for learners to confuse "ALB public" with "task public".
- Decision:
  - Reject for the recommended plan. Use only as an emergency spike if CDK/ECS
    basics need to be isolated from private networking.

### Alternative E: Full CI/CD Deployment Pipeline First

- Pros:
  - Produces a production-like image promotion and deploy story earlier.
  - CI/deploy metrics naturally appear as part of the first implementation.
- Cons:
  - Adds GitHub OIDC, IAM deploy roles, ECR promotion, environment approvals,
    and rollback design before the ECS/ADOT shape is proven.
  - Expands the blast radius of the first implementation.
- Decision:
  - Reject for the first wave. Add CI observability as a thin layer, then add
    deployment automation after the stack has been deployed manually.

### Alternative F: CI OpenTelemetry Traces Directly To The Collector

- Pros:
  - Makes CI look like another traced service.
  - Could provide span-level timing for every CI step.
- Cons:
  - Requires a reachable collector or vendor endpoint from GitHub-hosted
    runners.
  - Public OTLP ingress creates authentication, abuse, and cost concerns.
  - Step-level tracing is higher effort than the value needed for the first
    observability loop.
- Decision:
  - Reject for now. Use CloudWatch metrics, structured CI events, GitHub step
    summaries, and post-deploy smoke-request correlation first.

### Alternative G: ADOT Sidecar Per Task

This is OpenTelemetry's
[agent deployment pattern](https://opentelemetry.io/docs/collector/deploy/agent/):
the collector runs alongside the application and receives telemetry over a
task-local endpoint.

- Pros:
  - Simple locality: app exports to `localhost`.
  - No service discovery needed for the first service.
  - Failure scope is one task.
  - Matches official ECS ADOT sidecar guidance.
- Cons:
  - Collector resource cost is paid per task.
  - Config updates require task redeploy.
- Decision:
  - Recommended for the first service.

### Alternative H: Shared Collector Service

This is OpenTelemetry's
[gateway deployment pattern](https://opentelemetry.io/docs/collector/deploy/gateway/):
applications send telemetry to a shared OTLP endpoint served by one or more
standalone collectors.

- Pros:
  - Fewer collector containers at higher scale.
  - Centralized collector config.
  - Better for many services once service discovery exists.
- Cons:
  - Needs service discovery, network policy, and careful scaling.
  - More complex failure and backpressure behavior.
- Decision:
  - Defer until multiple ECS services exist.

### Alternative I: Self-Hosted Grafana Stack On ECS

- Pros:
  - Closer to the existing local Grafana/Tempo/Loki/Prometheus demo.
  - Full control over plugins, provisioning, and dashboards.
  - Can include Loki and Tempo if AWS-native tracing/logging is not desired.
- Cons:
  - More infrastructure to own and operate.
  - Duplicates the managed services the user wants to learn.
- Decision:
  - Reject for the AWS managed observability path. Keep local stack for local
    development.

### Alternative J: Pure Per-Attempt Random Failure

- Pros:
  - Very small implementation.
  - Easy to explain as `Math.random() < 0.4`.
- Cons:
  - Retries can reduce final failed reservation cases below 40%.
  - Tests become flaky without extra injection.
  - A request might fail once and later succeed, which is confusing for a demo
    about failed reservations.
- Decision:
  - Reject for the main path. Use stable per-request failure decisions.

## 8. API / Interface Changes

### Public API

No GraphQL schema changes are required for the first implementation.

Reservation clients already submit a request and poll status. Failure injection
should surface through the existing status/result flow:

- request accepted;
- worker/processor claims it;
- processor marks it `FAILED`;
- polling shows failed status.

### Application Interfaces

Add:

- `ReservationProcessingFailurePolicy` application port.
- `DisabledReservationProcessingFailurePolicy` application implementation.
- `StableRandomReservationProcessingFailurePolicy` infrastructure
  implementation.
- A provider token in `movie-reservation.tokens.ts`.
- A new constructor dependency in `InProcessReservationRequestProcessor`.

Update:

- Processor flow so the injected failure is handled by the existing
  `unexpected-error` path.
- Processor observability log/span/metric fields so bounded diagnostic exception
  type `SeatReservationCommitError` is visible without adding a new business
  failure reason.

### Configuration

Add Zod-validated environment variables:

- `RESERVATION_FAILURE_INJECTION_MODE`
- `RESERVATION_FAILURE_INJECTION_RATE`
- `RESERVATION_FAILURE_INJECTION_SALT`

The default mode must be `disabled`.
The stable-random mode should be available in local Docker rehearsal and the
AWS demo stack.

### CDK Interfaces And Config

The first implementation should avoid broad reusable construct APIs. Use a
typed config object for deployment decisions:

- service name: `movie-reservation-service`;
- environment name: `aws-demo`;
- stack name: `GoldenPathDemoStack`;
- required `allowedIngressCidr`;
- fixed `vpcMaxAzs: 2`;
- fixed `workloadAzCount: 1`;
- `enableEcsExec`;
- log retention;
- optional toggles for AMG/AMP only if implementation sequencing requires them.

## 9. Data Model / Persistence Changes

The managed-observability slices use in-memory persistence, so there is no
database service to provision and no durable data-retention contract.

No Postgres migration is required for failure injection because it reuses the
existing `unexpected-error` failed-attempt reason. This is deliberate: the demo
simulates a real-looking bug rather than a labelled demo fault.

No schema or seed initialization is required by #37 or #38. Future RDS changes
must use a true one-off ECS migration task before deploying or updating the
service; that contract is owned by issue #7.

## 10. Security, Privacy, and Abuse Considerations

- Keep the first AWS stack tagged and named as demo because it uses local auth,
  in-memory persistence, public ALB exposure, and optional failure injection.
- Failure injection must default to disabled.
- Failure injection must be blocked or explicitly refused for staging and
  production profiles unless there is a deliberate chaos-testing decision.
- Do not expose a public runtime switch that lets arbitrary callers trigger
  failures unless auth and environment guardrails are in place.
- Do not log bearer tokens, cookies, raw GraphQL variables, request bodies, or
  raw headers.
- Continue using stdout JSON logs through CloudWatch Logs. Do not send logs
  through OTLP until there is a separate logs design.
- Task security group should allow inbound app traffic only from the ALB
  security group.
- ADOT receiver ports should be internal to the task.
- Scope AMP remote write permissions to the workspace ARN where possible.
- Use CDK-managed log retention to avoid unbounded CloudWatch Logs cost.
- Phase 1 public ALB must require an explicit `allowedIngressCidr`.
- Phase 2 CloudFront frontend should restrict ALB origin access using the
  CloudFront managed prefix list plus a CloudFront origin verification header
  required by the ALB listener/rules.
- Defer AWS WAF for cost reasons. Revisit it when the demo becomes
  production-shaped or internet-facing for longer periods.
- AMG authentication depends on IAM Identity Center or SAML. Do not create
  unmanaged public Grafana access.
- CI telemetry should use a separate OIDC-backed role from any future deploy
  role. The telemetry role should not have deploy permissions.

## 11. Performance, Scalability, and Reliability Considerations

- The delivered #37 task size is 512 task CPU units and 1024 MiB, partitioned
  as app 384 CPU/640 MiB and ADOT 128 CPU/384 MiB. Measure before changing it;
  do not use the older examples in this umbrella.
- Keep batch processors enabled in the collector to reduce export overhead.
- Use bounded metric labels. Current service metrics are mostly safe; keep ids
  out of metrics.
- Use CloudWatch Container Insights enhanced observability for infrastructure
  metrics under #38 rather than trying to recreate ECS task metrics in
  application code. It remains disabled in the delivered #37 baseline.
- Configure ECS deployment circuit breaker with rollback for failed deployments.
- Use ALB health checks against `/health`. Keep `/ready` for platform or
  dependency-aware readiness but avoid causing dependency outages to restart all
  API tasks.
- Set log retention explicitly.
- Use desired count 1 for the first demo, then 2 for production-shaped HA.
- Span the VPC across two AZs for the ALB, but use one workload AZ for the first
  demo. Production-shaped networking should use at least two workload AZs,
  endpoint coverage in both, and at least two tasks.
- If using RDS later, add true one-off migration tasks and database connection
  pool limits before scaling ECS tasks.
- Private subnets without NAT require AWS service VPC endpoints. Missing
  endpoints will usually surface as image pull, log delivery, X-Ray export, AMP
  remote write, or ECS Exec failures. AMP remote write with SigV4 may need an
  STS endpoint.
- Random failure at 40% can dominate dashboards and alarms. It should be
  disabled by default and enabled only for local/AWS demo rehearsals. Because
  the error is intentionally production-looking, dashboards should show it as
  `unexpected-error` with bounded diagnostic exception type rather than a demo
  label.

## 12. Implementation Steps

Split implementation into reviewable waves. Each wave should be its own PR or
small group of PRs unless the actual diff is tiny.

### Wave 1: Failure Injection, Local First (Delivered)

- Change: Add `ReservationProcessingFailurePolicy`, disabled default, stable
  hash/salt implementation, env config, and DI wiring.
- Files/modules likely affected:
  - `movie-reservation-service/src/application/movie-reservations/ports/reservation-processing-failure-policy.ts`
  - `movie-reservation-service/src/application/movie-reservations/disabled-reservation-processing-failure-policy.ts`
  - `movie-reservation-service/src/application/movie-reservations/in-process-reservation-request-processor.ts`
  - `movie-reservation-service/src/infrastructure/movie-reservations/stable-random-reservation-processing-failure-policy.ts`
  - `movie-reservation-service/src/config.ts`
  - `movie-reservation-service/src/di/movie-reservations/movie-reservation.tokens.ts`
  - `movie-reservation-service/src/di/movie-reservations/use-case.providers.ts`
  - local env templates and Docker Compose demo env where applicable
- Notes:
  - Use `RESERVATION_FAILURE_INJECTION_MODE=disabled|stable-random-unexpected-error`.
  - Use `unexpected-error` as the persisted failed reason.
  - Use bounded exception type `SeatReservationCommitError`.
  - Do not add a Postgres migration for a new reason.
- Verification:
  - `npm -w movie-reservation-service run check`
  - focused unit/integration tests for disabled, forced, and stable-random
    behavior.

### Wave 2: Backend CDK Skeleton (Delivered)

- Change: Replace the blank stack with an explicit first-pass
  `GoldenPathDemoStack` resource graph for the backend only.
- Files/modules likely affected:
  - `ecs-infra/lib/infra-stack.ts`
  - `ecs-infra/lib/config/platform-config.ts`
  - `ecs-infra/lib/assets/docker-build-context.ts`
  - `ecs-infra/bin/infra.ts`
  - `ecs-infra/test/infra.test.ts`
  - `ecs-infra/README.md`
  - `movie-reservation-service/Dockerfile`
  - `movie-reservation-service/Dockerfile.dockerignore`
  - root `package.json` and `package-lock.json` for workspace dependency
    ownership
  - `docs/architecture/ecs-fargate-deployment.md`
  - `docs/architecture/architecture-decisions.md`
- Notes:
  - Keep resources mostly explicit in `infra-stack.ts`.
  - Add typed config with required restricted `allowedIngressCidr`, fixed
    `vpcMaxAzs: 2`, fixed `workloadAzCount: 1`, and `enableEcsExec`.
  - Create public ALB, private ECS tasks, no NAT Gateway, app image asset,
    service log group, and minimum VPC endpoints for image pull/log delivery.
  - Pin the task and endpoint ENIs to one selected workload subnet.
  - Explicitly enable ALB cross-zone routing because the ALB spans two AZs
    while the Wave 2 target exists in one workload AZ.
  - When ECS Exec is enabled, add the `ssmmessages` endpoint and task-role
    message-channel permissions.
  - Keep CDK dependencies owned only by the `ecs-infra` workspace.
  - Keep the service Docker build context at repository root for the shared
    lockfile, but use a Dockerfile-specific allowlist so sibling workspaces and
    CDK dependencies cannot enter the runtime image.
  - Defer reusable constructs until after first successful deploy.
- Verification:
  - `npm -w ecs-infra run build`
  - `npm -w ecs-infra test`
  - `npm -w ecs-infra run cdk -- synth -c allowedIngressCidr=203.0.113.10/32`
  - clean service Docker build and `/health` runtime probe
  - verify `aws-cdk-lib` and `constructs` are absent from the runtime image

### Wave 3: ADOT Collector And X-Ray Traces (#37)

- Status: delivered by PR #39.
- Historical source:
  [`delivered/ecs-adot-xray-tracing.md`](delivered/ecs-adot-xray-tracing.md).
- Delivered change: Add the repo-owned ADOT image/config, collector sidecar, app OTLP
  configuration, X-Ray exporter permissions/connectivity, split log groups, and
  collector debugging instructions.
- Files/modules likely affected:
  - `ecs-infra/lib/infra-stack.ts`
  - `ecs-infra/lib/config/platform-config.ts`
  - `ecs-infra/test/infra.test.ts`
  - `ecs-infra/README.md`
  - `docs/operations/runbook.md`
- Notes:
  - Keep the app on the in-memory composition profile.
  - The app exports OTLP HTTP to the collector at `127.0.0.1:4318`.
  - Start with traces and X-Ray only; do not absorb #38 metrics resources.
  - Reuse the Wave 2 `enableEcsExec` service flag, task-role permissions, and
    `ssmmessages` endpoint when debugging the collector container.
- Verification:
  - CDK assertions for independent app/ADOT containers, nonessential collector
    lifecycle/health/restart behavior, X-Ray IAM/network path, split log groups,
    ECS Exec flag behavior, and absence of NAT Gateway and #38 resources.
  - Laptop deploy smoke proving an application trace reaches X-Ray, followed by
    `cdk destroy`.

### Wave 4: CloudWatch, AMP, And Managed Grafana Metrics (#38)

- Change: Extend the proven ADOT collector with CloudWatch metric export, AMP
  workspace/remote write, ECS task metrics, and an AMG workspace or documented
  minimal manual identity/data-source setup.
- Files/modules likely affected:
  - `ecs-infra/adot-collector/Dockerfile`
  - `ecs-infra/adot-collector/adot-config.yaml`
  - `ecs-infra/lib/infra-stack.ts`
  - `ecs-infra/test/infra.test.ts`
  - `docs/workflows/aws-ecs-observability.md`
  - `docs/operations/runbook.md`
- Notes:
  - Logs remain stdout JSON through CloudWatch Logs, not OTLP logs.
  - Dashboards should use Traffic, Errors, Latency, and Saturation rows with
    both platform and business signals.
  - Metric dimensions must stay bounded.
- Verification:
  - CDK assertions for metric exporters, task role policies, AMP workspace, AMG
    workspace when enabled, endpoints, and CloudWatch log retention.

### Wave 5: AWS Smoke, Teardown, And Cost Safety

- Change: Add deploy, smoke, ECS Exec debug, destroy, and panic cleanup docs.
- Files/modules likely affected:
  - `ecs-infra/README.md`
  - `docs/operations/runbook.md`
  - `docs/workflows/aws-ecs-observability.md`
  - `docs/index.md`
- Notes:
  - Fixed stack name should make the destroy command explicit:
    `npm -w ecs-infra run cdk -- destroy GoldenPathDemoStack`.
  - Include manual console/CLI checks for ALB, NAT gateways, VPC endpoints,
    public IPs/EIPs, ECS services/tasks, log groups, AMP, AMG, and later
    CloudFront/S3.
  - Recommend a small AWS Budget alert outside the first CDK stack.
- Verification:
  - Real AWS smoke: ALB `/health`, GraphQL query, X-Ray,
    CloudWatch Logs/Metrics, AMP/AMG queries, and post-destroy resource checks.

### Wave 6: Frontend Phase 2

- Change: Add S3 and CloudFront infrastructure for `movie-reservation-web`, then
  add CI/CD deployment of built static assets.
- Files/modules likely affected:
  - `ecs-infra/lib/infra-stack.ts` initially, later extracted after deploy
  - `ecs-infra/test/infra.test.ts`
  - `.github/workflows/<frontend-deploy>.yml`
  - `movie-reservation-web` environment/config docs if needed
  - `docs/workflows/aws-frontend-hosting.md`
- Notes:
  - Frontend calls relative `/graphql`.
  - CloudFront default behavior serves S3; `/graphql` routes to ALB.
  - ALB origin restriction uses CloudFront managed prefix list plus custom
    origin verification header. WAF is deferred for cost.
- Verification:
  - CloudFront URL serves frontend.
  - Browser GraphQL calls go through `/graphql`.
  - Direct ALB calls without the origin verification header do not reach the
    backend target group.

### Wave 7: CI Telemetry

- Change: Add `.github/workflows/ci-telemetry.yml` triggered by `workflow_run`
  for the existing `CI` workflow and emit CloudWatch metrics/events.
- Files/modules likely affected:
  - `.github/workflows/ci-telemetry.yml`
  - `docs/workflows/ci-workflow.md`
  - new `docs/workflows/ci-observability.md`
  - optional script if GitHub YAML becomes hard to read
- Notes:
  - Include PRs with bounded dimensions such as `EventName` and `Source`.
  - Do not put PR number, run id, SHA, branch, trace id, request id, or
    correlation id in metric dimensions.
  - Do not add OTLP CI traces in the first CI telemetry pass.
- Verification:
  - Manual/trusted workflow run emits `GoldenPath/CI` metrics.
  - Fork PRs do not receive AWS credentials.
  - GitHub summary/log event contains run links without creating
    high-cardinality metrics.

## 13. Testing Strategy

### Service Unit And Integration Tests

- Config tests:
  - failure injection defaults to disabled;
  - invalid rates fail Zod validation;
  - enabled mode requires a rate between 0 and 1;
  - production/staging guardrails reject failure injection unless explicitly
    allowed by a future chaos-test flag.
- Policy tests:
  - disabled policy always returns false;
  - stable random policy is deterministic for the same request id and salt;
  - threshold behavior can be tested with known ids or a hash helper.
- Processor tests:
  - disabled policy preserves current confirmation/rejection behavior;
  - forced failure marks the request failed;
  - forced failure emits `failed` outcome, `unexpected-error` reason, and
    bounded diagnostic exception type `SeatReservationCommitError`;
  - stable decision is made per request, not per retry attempt.
- Postgres/integration tests:
  - injected failures persist through the existing `unexpected-error` reason;
  - old reasons still read/write;
  - no migration is required for a new failure reason.

### CDK Tests

- Assert one ECS cluster exists.
- Assert Container Insights remains disabled in the delivered #37 baseline and
  is enabled/enhanced only when #38 implements that path.
- Assert the task definition includes:
  - app container;
  - ADOT collector container;
  - no app dependency on collector start or health;
  - nonessential collector health and restart configuration;
  - app OTLP endpoint points at localhost sidecar;
  - app and ADOT containers use split `awslogs` log groups;
  - no database or migration container exists in #37/#38.
- Assert no NAT Gateway resources are created in the recommended stack.
- Assert four VPC subnets are created across two AZs, the ALB uses two public
  subnets, and the ECS service plus interface endpoints use one workload
  subnet.
- Assert ALB cross-zone load balancing is enabled.
- Assert S3 gateway endpoint and required interface endpoints exist for the
  no-NAT private task path.
- Assert ALB target health check path is `/health`.
- Assert ALB ingress requires explicit source-CIDR restriction.
- Assert the ECS Exec service flag, `ssmmessages` endpoint, and task-role
  message-channel permissions are controlled by `enableEcsExec`.
- For the delivered #37 baseline, assert the task role contains only the
  required X-Ray writes for the trace path and no metric/AMP permissions.
- For #38, assert the later CloudWatch/AMP permissions and workspaces in that
  issue's focused plan.
- Assert CloudWatch log retention is set.

### AWS Smoke Tests

- `GET /health` through the ALB.
- GraphQL `movies` query through the ALB.
- GraphQL `requestReservation` plus status polling.
- Generate at least 20 reservation requests with failure injection enabled and
  verify a visible failed-request ratio near the configured threshold. For a
  deterministic threshold, exact ratio on a small sample is not guaranteed, but
  known test ids can prove both branches.
- X-Ray trace lookup by trace id.
- CloudWatch Logs Insights query by `correlation_id`.
- CloudWatch metric query for `graphql_operation_total` or equivalent EMF
  metric.
- AMP/AMG query for GraphQL or reservation processor metrics.
- Post-deploy smoke request includes `X-Correlation-Id` and `X-Request-Id` so
  logs/traces can be joined back to the smoke runner.

### CI Observability Tests

- Workflow syntax validation for any changed GitHub Actions YAML.
- Manual workflow run for the `workflow_run` CI observability path on a trusted
  branch.
- Verify the CI telemetry role can publish only the intended CloudWatch metrics
  and optional CI log events.
- Verify metric dimensions stay bounded and do not include run id, SHA, PR
  number, trace id, request id, or correlation id.
- Verify pull request metrics include bounded event/source dimensions.
- Verify fork pull requests cannot obtain AWS credentials in the original CI
  workflow.
- Verify GitHub step summary includes run id, SHA, stack, result, and duration
  for human navigation without creating high-cardinality metrics.

### Verification Commands

Local:

```sh
npm -w movie-reservation-service run check
npm -w ecs-infra run ci
npm run lint
```

AWS:

```sh
npm -w ecs-infra run cdk -- synth
npm -w ecs-infra run cdk -- diff
npm -w ecs-infra run cdk -- deploy
```

## 14. Rollout / Migration Plan

1. Keep all changes behind defaults that preserve current local behavior.
2. Merge service failure injection disabled by default.
3. Merge CDK stack with `cdk synth` and tests passing before real deploy.
4. Deploy to a named demo stack in one AWS Region using Option C networking.
5. Verify private tasks can pull images, write logs, export traces, and remote
   write metrics without NAT.
6. Verify ALB health and GraphQL smoke.
7. Verify ADOT sidecar logs and no crash loops.
8. Verify the delivered #37 X-Ray trace path still works after any #38 collector
   changes.
9. Destroy the stack after each trace or metric smoke check.
10. Add and verify CloudWatch metrics under #38.
11. Verify AMP ingestion and AMG data source access under #38.
12. Enable failure injection in the demo stack only when the in-memory worker is
    deliberately enabled for that rehearsal.
13. Generate demo traffic and check `unexpected-error` metrics/logs/traces with
    `SeatReservationCommitError` as bounded diagnostic exception type.
14. Run teardown using
    `npm -w ecs-infra run cdk -- destroy GoldenPathDemoStack`.
15. Run the panic cleanup checklist for expensive resources: ALB, NAT gateways,
    VPC endpoints, public IPs/EIPs, ECS services/tasks, CloudWatch log groups,
    AMP workspaces, AMG workspaces, and later CloudFront/S3.
16. Add CI observability role/workflow only after the AWS stack has stable
    names, namespaces, and smoke commands.
17. Run a manual CI observability workflow and verify CloudWatch metrics/events.
18. Document any manual AMG setup completed in AWS.
19. Destroy the stack whenever it is not in use to control cost.

Rollback:

- Disable failure injection by setting mode to `disabled` and redeploying.
- Roll back app code by deploying the previous image asset or reverting the CDK
  app asset hash.
- Remove the ADOT sidecar from the task definition only after confirming app
  startup does not require it.
- Use `cdk destroy` for the demo stack if AWS costs or permissions are wrong.
- Disable or remove the CI observability workflow/role independently from the
  ECS stack if telemetry permissions are wrong.

## 15. Risks and Mitigations

| Risk                                                   | Impact |                       Likelihood | Mitigation                                                                                                                                                                       |
| ------------------------------------------------------ | -----: | -------------------------------: | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| AMG auth prerequisites are missing                     |   High |                           Medium | Treat AMG workspace/data source setup as an explicit open question; document manual setup if needed.                                                                             |
| CDK asset deploy is slow or brittle in local Docker    | Medium |                           Medium | Use assets for first slice, then move to GitHub Actions/ECR promotion after stack works.                                                                                         |
| ADOT config works locally but not on ECS               |   High |                           Medium | Use official ECS ADOT patterns, add sidecar logs, deploy a minimal config first, then add exporters incrementally.                                                               |
| Metrics appear in CloudWatch but not AMP               | Medium |                           Medium | Separate CloudWatch and AMP pipelines; verify SigV4 auth, AMP endpoint, task role permissions, and Region.                                                                       |
| Missing VPC endpoint breaks private tasks              |   High |                           Medium | Add endpoint assertions, deploy incrementally, and check image pull/log/X-Ray/AMP paths separately.                                                                              |
| VPC endpoints cost as much as NAT if overused          | Medium |                           Medium | Keep endpoint list explicit, pin paid endpoint ENIs to one workload AZ, perform a cost checkpoint before Wave 4 expands the endpoint inventory, and destroy the stack when idle. |
| Metric cardinality grows too high                      |   High |                              Low | Keep ids out of labels; review every new metric attribute.                                                                                                                       |
| CI metrics create high-cardinality CloudWatch costs    | Medium |                           Medium | Keep run id, SHA, PR number, trace id, request id, and correlation id out of dimensions; put them in logs/summaries only.                                                        |
| GitHub OIDC role is too broad                          |   High |                           Medium | Separate CI observability and deploy roles; restrict trust policy and IAM actions; do not allow fork PRs to assume roles.                                                        |
| Raw CI logs leak secrets into CloudWatch               |   High |                              Low | Emit summarized structured events only; never upload full job logs or environment dumps.                                                                                         |
| Failure injection leaks into production                |   High |                              Low | Default disabled, config guardrails, demo stack naming, tests for forbidden production config.                                                                                   |
| Failure injection is too obvious for on-call rehearsal | Medium |                           Medium | Reuse `unexpected-error` and expose only bounded diagnostic exception type such as `SeatReservationCommitError`.                                                                 |
| Pure randomness makes tests flaky                      | Medium |                           Medium | Use stable hash-based decisions and fake policies in tests.                                                                                                                      |
| Retries reduce final failure rate below 40%            | Medium | High with per-attempt randomness | Make failure injection terminal per request or set demo retry budget deliberately.                                                                                               |
| Public demo ALB is left running                        | Medium |                           Medium | Add cost/security cleanup docs, stack tags, and `cdk destroy` runbook.                                                                                                           |
| Database work leaks into the observability slices      | Medium |                           Medium | Preserve the delivered #37 in-memory baseline, keep #38 in-memory, and add RDS plus the deployment-time migration `RunTask` together under #7.                                   |
| Phase 2 ALB is directly reachable despite CloudFront   | Medium |                           Medium | Use CloudFront managed prefix list plus CloudFront origin verification header; defer WAF only for cost reasons.                                                                  |
| RDS is deferred but later needed for realistic demo    | Medium |                           Medium | Keep RDS/migration as a clearly scoped follow-up with its own rollback path.                                                                                                     |

## 16. Done Criteria

- `ecs-infra` contains a non-blank CDK stack for the ECS demo.
- CDK builds and publishes the app image through Docker image assets.
- CDK builds and publishes a custom ADOT collector image asset.
- ECS task definition has app and ADOT sidecar containers and no database or
  migration container.
- Recommended CDK stack creates no NAT Gateway resources.
- Recommended CDK stack uses a fixed two-AZ VPC and one-AZ workload/endpoint
  placement for the demo default.
- Required VPC endpoints are present for private task operation without NAT.
- ALB ingress requires explicit `allowedIngressCidr` and rejects `0.0.0.0/0`.
- ALB `/health` check passes against the deployed service.
- Service emits JSON logs to CloudWatch Logs.
- Service traces arrive in X-Ray.
- Application metrics arrive in CloudWatch custom metrics.
- Metrics arrive in AMP and are queryable from AMG.
- Managed Grafana workspace is either provisioned in CDK or manual setup is
  documented with exact steps.
- Failure injection is disabled by default.
- Demo failure injection can be enabled at a 40% stable-random rate locally and
  in AWS.
- Injected failures use `unexpected-error` plus bounded diagnostic exception
  type `SeatReservationCommitError`; no new failure-reason migration is added.
- Failed demo reservations are visible in processor metrics/logs/traces.
- Frontend Phase 2 design is documented as S3 + CloudFront, relative `/graphql`,
  CI/CD asset deployment, and CloudFront-to-ALB restrictions.
- CI observability design is documented and ready as a separate follow-up slice.
- CI telemetry, when implemented, emits bounded CloudWatch metrics and
  summarized structured events without static AWS keys or high-cardinality
  dimensions.
- Service and infra checks pass.
- Runbook explains deploy, smoke, ECS Exec debug, verify, destroy, and panic
  cleanup.

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
- [ ] AWS service assumptions are documented
- [ ] No-NAT VPC endpoint assumptions are documented
- [ ] Two-AZ VPC and one-AZ workload compromise is documented in an ADR
- [ ] Endpoint-versus-NAT cost checkpoint is documented in an ADR
- [ ] In-memory observability scope versus future RDS migration-task behavior is documented
- [ ] CI observability dimensions avoid high-cardinality values
- [ ] Demo-only behavior is isolated from production defaults
- [ ] Failure injection is production-looking and does not add a labelled demo
      failure reason
- [ ] Metric labels avoid high-cardinality ids
- [ ] CDK resources have cost cleanup guidance

## 18. Handoff Prompt for Implementation Agent

This umbrella document no longer has one executable handoff because its work is
split across issues with different acceptance boundaries.

- For issue #37 history, read
  [`delivered/ecs-adot-xray-tracing.md`](delivered/ecs-adot-xray-tracing.md).
- Before issue #38 implementation, create a focused CloudWatch/AMP/AMG plan and
  handoff from the still-relevant design material in this document.
- Do not ask an implementation agent to deliver #37, #38, frontend hosting, CI
  telemetry, and failure-injection work from one branch.
