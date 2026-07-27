# Implementation Plan: ECS ADOT To X-Ray Tracing

> Status: delivered by issue #37 / PR #39. Preserved as implementation
> history. Do not use this as the active #38 metrics/Grafana plan.

Issue: [#37](https://github.com/patex1987/golden-path-ecs-template/issues/37)

Branch: `37-ecs-adot-collector-xray`

Status: Delivered on `main`

Last reviewed: 2026-07-26

## 1. Summary

Extend the delivered ECS backend stack with a repository-owned AWS Distro for
OpenTelemetry (ADOT) collector image and a nonessential sidecar. The existing
NestJS service sends W3C OpenTelemetry traces over OTLP/HTTP to the sidecar on
task-local loopback; ADOT batches and exports them through a private X-Ray VPC
endpoint.

This issue establishes one managed signal path only:

```text
movie-reservation-service
  -> OTLP/HTTP on 127.0.0.1:4318
  -> ADOT sidecar
  -> private X-Ray VPC endpoint
  -> AWS X-Ray
```

The application remains independent from AWS telemetry APIs and remains
available when telemetry fails. Metrics, Amazon Managed Service for
Prometheus (AMP), Amazon Managed Grafana (AMG), Container Insights, alerts,
RDS, migrations, and deployment automation stay outside issue #37.

The first deployment remains laptop-driven: build, diff, deploy, run a
deterministic X-Ray smoke check, inspect diagnostics, and destroy the stack.

## 2. Goals

- Build and publish a custom ADOT image as a CDK Docker image asset.
- Run ADOT beside the existing in-memory NestJS service in one Fargate task.
- Export application traces to X-Ray without adding AWS telemetry SDKs to the
  application.
- Use W3C `traceparent`, `tracestate`, and baggage plus OTLP as the application
  contract.
- Keep the app independent from collector startup, health, and export success.
- Make collector process health and logs visible in AWS without allowing
  collector health to determine application availability.
- Keep the task in its current isolated workload subnet with no NAT Gateway.
- Add the least-privilege private network and IAM path required for X-Ray
  writes.
- Disable application metrics and OTel logs in ECS while preserving local OTel
  traces and metrics.
- Add credential-free CI validation for the custom image and collector config.
- Add an executable laptop smoke check that proves a known sampled W3C trace
  reaches X-Ray.
- Preserve a straightforward future move to a shared OpenTelemetry gateway by
  keeping the application endpoint-driven and vendor-neutral.

## 3. Non-goals

- Do not implement issue #38 resources or pipelines:
  - no application metric export in ECS;
  - no CloudWatch custom metric exporter;
  - no ECS container metrics receiver;
  - no AMP workspace or remote write;
  - no AMG workspace or dashboards;
  - no Container Insights.
- Do not add collector or trace-delivery alarms. Collector health metrics and
  on-call alerts belong to #38 and #30.
- Do not send application logs through OTLP. JSON stdout continues through the
  ECS `awslogs` driver.
- Do not add RDS, a Postgres sidecar, a migration container, or an ECS migration
  task. RDS and deployment-time migration `RunTask` orchestration belong to #7.
- Do not enable the reservation worker or failure injection in the ECS service.
- Do not add production OIDC/JWKS.
- Do not add GitHub AWS credentials or automated CDK deployment to public CI.
- Do not add a full Docker app-to-collector integration test to public CI.
- Do not add a persistent collector queue, EFS volume, or file-storage
  extension. This slice accepts lost spans during outages and restarts.
- Do not add X-Ray SDKs, AWS SDK trace calls, X-Ray propagators, or AWS-specific
  span APIs to NestJS, Python, Rust, or frontend application code.
- Do not add an `enableAdotTracing` CDK context flag. Managed tracing becomes
  part of this stack's baseline after #37.
- Do not build a generic sidecar/gateway CDK construct before a repeated
  infrastructure pattern exists.
- Do not add ECS resource detection, tail sampling, attribute transforms,
  debug exporters, or advanced collector routing.
- Do not implement the future frontend Playwright smoke. That test will place
  its `traceparent` in the browser test report/artifacts after the frontend
  workflow is ready.

## 4. Current State

### Delivered AWS Baseline

`ecs-infra/lib/infra-stack.ts` currently creates:

- a two-AZ VPC with public and isolated workload subnets;
- no NAT Gateway;
- one selected workload subnet for the disposable service and paid interface
  endpoint ENIs;
- S3, ECR API, ECR Docker, and CloudWatch Logs VPC endpoints;
- an optional SSM Messages endpoint for ECS Exec;
- a private Fargate task behind a CIDR-restricted public ALB;
- one essential `movie-reservation-service` container;
- a CDK Docker image asset for the app;
- a one-week application CloudWatch log group;
- an ECS deployment circuit breaker with rollback.

The stack was deployed successfully from a laptop and destroyed on 2026-07-17.
The current task has 256 CPU units and 512 MiB. Application observability is
disabled in ECS.

### Application Observability

`movie-reservation-service/src/infrastructure/observability/instrumentation.ts`
is preloaded before NestJS. It currently:

- constructs the Node OTel SDK explicitly;
- constructs OTLP trace and metric exporters in TypeScript;
- configures HTTP, Express, GraphQL, Knex, and PostgreSQL instrumentation;
- derives `deployment.environment.name` from `NODE_ENV`;
- starts both traces and metrics when `OBSERVABILITY_ENABLED` is true;
- calls SDK shutdown from signal handlers without bounded error handling.

Local profiles export traces and metrics to the local collector. ECS uses the
in-memory `local-fixed-user` composition profile with its worker disabled.

The application already depends on OpenTelemetry rather than AWS telemetry
libraries. Business-specific telemetry is behind the application-owned
`MovieReservationObservability` port. Presentation and infrastructure code may
use the generic OTel API directly where another application abstraction would
only duplicate it.

### Trace Data

The manual GraphQL operation span currently includes:

- bounded operation type/name and business operation fields;
- bounded `movie.provider.code`;
- `enduser.id`.

The GraphQL instrumentation does not opt into values, and HTTP instrumentation
does not opt into header capture. The X-Ray exporter maps `enduser.id` to the
X-Ray segment `user` field. This plan intentionally retains it for the demo,
with the privacy and retention consequences documented below.

### Existing Tests And Operations

- `ecs-infra/test/infra.test.ts` uses Jest and CDK assertions.
- `.github/workflows/ci.yml` has a credential-free `infra` job for CDK build,
  tests, and synth.
- `docs/operations/aws-cdk-local-deployment.md` is the canonical laptop
  deploy/destroy runbook.
- The existing local smoke script checks HTTP and GraphQL behavior but does not
  query AWS.

## 5. Requirements And Assumptions

### Confirmed Requirements

#### Signal Boundary

- #37 exports traces only.
- ECS sets `OTEL_TRACES_EXPORTER=otlp`.
- ECS sets `OTEL_METRICS_EXPORTER=none`.
- ECS sets `OTEL_LOGS_EXPORTER=none`.
- Local development keeps OTLP traces and metrics and keeps application logs on
  structured stdout.
- The Node SDK uses standard OTel environment variables to select exporters.
  Code retains explicit resources and the curated instrumentation list.
- Keep the existing `OBSERVABILITY_ENABLED` master switch for compatibility;
  ECS sets it to `true`.

#### Availability And Durability

- Application availability takes priority over telemetry completeness.
- The ADOT container is `essential: false`.
- The app has no ECS container dependency on ADOT, including no `START` or
  `HEALTHY` dependency.
- The app and collector start independently. Missing startup spans are
  acceptable.
- OTel SDK construction/start failure must fail open, perform best-effort
  cleanup of any partially created SDK, and emit one sanitized diagnostic.
  When no global provider was installed, generic OTel calls naturally use the
  no-op provider.
- SDK flush/shutdown is bounded and best effort. It must not change the app's
  exit status or hold shutdown indefinitely.
- The collector uses only bounded in-memory batching and the X-Ray exporter's
  bounded worker, request-timeout, and retry controls. It has no durable
  storage. Drops during outages, memory pressure, task replacement, and
  process restart are accepted.
- Audit logs are a separate reliability problem. Strong, nonblocking audit
  delivery would require a durable buffer/outbox and an explicit failure
  policy; it is not implemented here.

#### Packaging And Supply Chain

- Add `ecs-infra/adot-collector/Dockerfile` and
  `ecs-infra/adot-collector/adot-config.yaml`.
- Base the image on the official Public ECR ADOT collector image.
- Pin both an explicit release tag and its immutable digest. Do not use
  `latest` or a mutable tag alone.
- Resolve the tag/digest from the official ADOT release and Public ECR at
  implementation time. Record the verified value in the Dockerfile and the
  operational docs; do not invent a digest in this plan.
- Verify that the pinned distribution contains the OTLP receiver,
  `memory_limiter`, `batch`, `awsxray`, `health_check`, and `/healthcheck`
  executable.
- Build the collector locally as a CDK Docker image asset. At runtime Fargate
  pulls the resulting private CDK ECR asset through the existing ECR/S3
  endpoints; it does not pull from Public ECR.

#### Sampling

- ECS sets `OTEL_TRACES_SAMPLER=parentbased_always_on` for deterministic,
  low-traffic smoke validation.
- Add a code comment beside this CDK environment setting: sample-all is a demo
  choice and must be revisited before production, high traffic, or meaningful
  trace cost.
- A sampled incoming W3C parent remains sampled; an explicitly unsampled remote
  parent remains unsampled because the sampler is parent-based.
- Do not use X-Ray centralized sampling APIs or grant sampling-read actions.

#### Task Resources

- Fargate task: 512 CPU units and 1024 MiB.
- App container: 384 CPU units and hard limit 640 MiB.
- ADOT container: 128 CPU units and hard limit 384 MiB.
- Collector memory limiter: `limit_mib: 256`, `spike_limit_mib: 64`, and a
  short check interval.
- Treat these as deterministic demo starting limits, not production capacity.
  Record observed usage during the AWS smoke.

#### Lifecycle And Health

- Enable the ECS ADOT container restart policy with
  `restartAttemptPeriod: 60 seconds`.
- A collector that ran for at least 60 seconds and then exits may restart
  without replacing the app task.
- A bad config that exits immediately should remain stopped instead of entering
  a tight restart loop; its logs and container status provide the diagnosis.
- Configure ADOT `health_check` on `127.0.0.1:13133`.
- Add an ECS container health check that invokes the image's `/healthcheck`
  executable.
- Because ADOT is nonessential, its `HEALTHY/UNHEALTHY` state is visible in the
  ECS console/API but does not determine task/service health or app
  availability.
- An unhealthy process that does not exit is not automatically restarted in
  #37. The end-to-end smoke is the authoritative functional check.

#### IAM And Networking

- Add an X-Ray interface VPC endpoint in the selected workload subnet with
  private DNS.
- Reuse the endpoint security group; it accepts HTTPS only from the task
  security group.
- Bind the OTLP/HTTP receiver only to `127.0.0.1:4318`.
- Add no ADOT port mapping and no security-group ingress for OTLP or health.
- Add exactly these X-Ray writes to the shared task role:
  - `xray:PutTraceSegments`;
  - `xray:PutTelemetryRecords`.
- X-Ray write actions require `Resource: "*"`.
- Restrict the X-Ray endpoint policy to the same two actions and
  `Resource: "*"`.
- Add no X-Ray sampling-read actions and no STS endpoint.
- ECS task roles are task-wide, not per-container. Both the app and ADOT can
  obtain these two permissions. Accept that limitation for the sidecar slice;
  a future gateway can isolate collector credentials.

#### Resource Identity And Privacy

- Keep `NODE_ENV=development` because the ECS demo uses local auth.
- Do not derive `deployment.environment.name` from `NODE_ENV`.
- Set standard resource attributes from CDK:
  `deployment.environment.name=aws-demo,service.namespace=movie-reservation-platform`.
- Keep `service.name=movie-reservation-service`.
- Treat `movie-reservation-service/package.json` as the source of truth for
  `service.version`; it is currently `1.0.0`.
- Do not overload `service.version` with a Git SHA. A future private deployment
  pipeline can add revision/build metadata separately.
- Explicitly configure GraphQL instrumentation with `allowValues: false`.
- Do not configure HTTP header/body capture.
- Do not export bearer tokens, cookies, raw GraphQL variables, request bodies,
  or raw headers.
- Configure `index_all_attributes: false` and no `indexed_attributes` in the
  X-Ray exporter.
- Retain `enduser.id` for #37. Document that it is a stable, linkable identifier
  and is mapped to the X-Ray `user` field.
- Before production auth, revisit `enduser.id`. If traces do not need the raw
  identifier, prefer a deliberately designed keyed HMAC/pseudonym rather than
  a plain hash that may be enumerable.

#### Configuration And Rollback

- Managed tracing is always present in the post-#37 stack. Do not add a CDK
  enable/disable context.
- Runtime collector failure is isolated through nonessential lifecycle and
  app-side fail-open behavior.
- Deployment failure is handled by the existing ECS circuit breaker.
- Operational rollback is redeploying the previous known-good revision or
  destroying the disposable stack.

#### Verification

- Public CI builds the collector image and performs basic collector/image
  validation without AWS credentials.
- Real trace delivery remains a laptop deployment smoke for #37.
- A future private deployment workflow will run deploy/system smoke/rollback
  gates with AWS credentials.
- The future browser Playwright smoke will include its W3C `traceparent` in the
  test report/artifacts; it is not part of #37.

### Assumptions

- The deployment Region supports both ECS/Fargate and the X-Ray interface VPC
  endpoint. The previously validated target is `eu-central-1`, but CDK remains
  Region-aware rather than hard-coding it into application code.
- The selected official ADOT release supports W3C trace IDs. X-Ray requires
  X-Ray exporter 0.86.0 or newer, included in ADOT collector 0.34.0 or newer.
- The Fargate Linux platform supports container restart policies and container
  health checks.
- The operator's deployment profile can create the added endpoint/IAM/task
  resources and can call `xray:BatchGetTraces` for smoke verification.
- The demo ALB remains HTTP-only and CIDR-restricted. It carries no production
  credentials or sensitive customer traffic.

### Resolved Implementation Facts

No design or product questions remain for implementation. The image preflight
was completed on 2026-07-18:

1. The official ADOT release used here is `v0.48.0`.
2. Its Public ECR multi-architecture digest is
   `sha256:9b28046359054b414f4ba76056ba4e8cffda2d53fbcee06171d7eeecd71326c3`.
3. The image contains the required collector components and the bundled
   `/healthcheck` executable.
4. This release has no standalone config-validation command. The CI gate starts
   the exact pinned image with the baked config and requires `/healthcheck` to
   succeed, proving that the referenced components parsed and started.

## 6. Proposed Design

### AWS Resource Shape

```text
restricted laptop CIDR
  |
  v
public ALB (two public subnets)
  |
  | HTTP :3000
  v
Fargate task (one isolated workload subnet, no public IP)
  +-- essential app
  |     - in-memory/local-fixed-user profile
  |     - stdout JSON -> app CloudWatch log group
  |     - OTLP/HTTP traces -> 127.0.0.1:4318
  |
  +-- nonessential ADOT
        - OTLP/HTTP receiver on loopback only
        - memory limiter -> batch -> awsxray
        - stdout/stderr -> ADOT CloudWatch log group
        - health endpoint on 127.0.0.1:13133
        - HTTPS -> X-Ray interface endpoint -> X-Ray
```

The CDK `FargateTaskDefinition` synthesizes one CloudFormation task definition
with two container definitions and one shared task role. The new
`InterfaceVpcEndpointAwsService.XRAY` construct synthesizes the regional X-Ray
PrivateLink endpoint and ENI in the selected workload subnet.

### Vendor-neutral Application Boundary

The application owns only:

- OTel APIs/SDKs and semantic conventions;
- W3C propagation;
- OTLP endpoint/protocol configuration;
- stable business span names and attributes;
- application-owned observability ports for business semantics.

The application does not know that X-Ray is the destination. ADOT owns format
translation, AWS credential use, retry, and X-Ray export. CDK owns task role,
network endpoint, security group, image, and environment selection.

The existing `X-Amzn-Trace-Id` request field may remain as secondary ALB edge
metadata in logs. It must not replace W3C context or cause application code to
construct X-Ray traces.

### Collector Image And Config

Use a minimal repository-owned image:

```dockerfile
FROM public.ecr.aws/aws-observability/aws-otel-collector:<verified-tag>@sha256:<verified-digest>
COPY adot-config.yaml /etc/adot/adot-config.yaml
CMD ["--config=/etc/adot/adot-config.yaml"]
```

The exact entrypoint/config path must match the verified image. Preserve the
upstream entrypoint instead of wrapping the collector with a shell process.

The traces-only config has this logical shape:

```yaml
extensions:
  health_check:
    endpoint: 127.0.0.1:13133

receivers:
  otlp:
    protocols:
      http:
        endpoint: 127.0.0.1:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 256
    spike_limit_mib: 64
  batch:
    timeout: 5s
    send_batch_size: 256
    send_batch_max_size: 512

exporters:
  awsxray:
    region: ${env:AWS_REGION}
    index_all_attributes: false
    num_workers: 2
    request_timeout_seconds: 5
    max_retries: 2

service:
  telemetry:
    logs:
      level: info
  extensions: [health_check]
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [awsxray]
```

The v0.48.0 X-Ray exporter rejects the generic exporter-helper
`sending_queue` and `retry_on_failure` keys. Its supported X-Ray-specific
worker, request-timeout, and retry settings above were verified by starting the
pinned collector and reaching its health extension. Keep all transient state in
memory only. Do not add a `file_storage` extension.

There is intentionally no gRPC receiver, metrics pipeline, logs pipeline,
resource detector, transform/filter processor, or debug exporter.

### Application OTel Bootstrap

Retain the preload order and explicit instrumentations, but let `NodeSDK` read
standard exporter selection from the environment. Do not pass `traceExporter`
or `metricReaders` manually.

Local profile contract:

```text
OBSERVABILITY_ENABLED=true
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=none
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_METRIC_EXPORT_INTERVAL=5000
OTEL_PROPAGATORS=tracecontext,baggage
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=local,service.namespace=movie-reservation-platform
```

ECS profile contract:

```text
OBSERVABILITY_ENABLED=true
OTEL_TRACES_EXPORTER=otlp
OTEL_METRICS_EXPORTER=none
OTEL_LOGS_EXPORTER=none
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_PROPAGATORS=tracecontext,baggage
OTEL_TRACES_SAMPLER=parentbased_always_on
OTEL_RESOURCE_ATTRIBUTES=deployment.environment.name=aws-demo,service.namespace=movie-reservation-platform
```

Keep `OTEL_SERVICE_NAME` and `SERVICE_VERSION` explicit. Remove the implicit
`NODE_ENV -> deployment.environment.name` resource mapping.

Make startup lifecycle testable through a small OTel-bootstrap helper with an
injectable SDK factory/diagnostic sink, while keeping production imports free
of NestJS/application modules. Required behavior:

1. If disabled/test, do not create the SDK.
2. Construct/start the SDK inside `try/catch`.
3. On failure, write one sanitized structured diagnostic containing a stable
   event name and error type, not environment values, tokens, headers, or a raw
   stack dump.
4. Return without installing a provider; generic OTel calls then use no-op
   providers.
5. On `SIGTERM`/`SIGINT`, request SDK shutdown with a short fixed upper bound
   such as three seconds.
6. Catch shutdown rejection/timeout, emit a sanitized diagnostic, and never
   call `process.exit()` or alter the app exit code from telemetry code.

Set `GraphQLInstrumentation({ allowValues: false, depth: 2, mergeItems: true })`
explicitly. Leave HTTP header capture unset.

Remove direct exporter/metric-reader dependencies only if they are unused after
the refactor and the build proves the Node SDK's environment-driven path works.
Do not remove generic OTel API/SDK or instrumentation dependencies.

### Service Version

Read `movie-reservation-service/package.json` through a structured JSON path and
validate that `version` is a nonempty string. Use it for:

- ECS `SERVICE_VERSION`;
- the OTel `service.version` resource attribute;
- structured application log version;
- committed local environment templates/defaults.

Do not shell out to Git during synth and do not make a dirty worktree change the
synthesized template nondeterministically.

### ECS Container Definitions

App container:

- `essential: true`;
- `cpu: 384`;
- `memoryLimitMiB: 640`;
- existing port 3000 mapping and ALB health path;
- existing app log group;
- traces-only ECS OTel environment above;
- no `dependsOn` entry for ADOT.

ADOT container:

- image from the new Docker image asset;
- `containerName: adot-collector`;
- `essential: false`;
- `cpu: 128`;
- `memoryLimitMiB: 384`;
- `enableRestartPolicy: true`;
- `restartAttemptPeriod: 60 seconds`;
- `stopTimeout` long enough for the short in-memory batch shutdown, but no more
  than the existing task shutdown budget;
- no port mappings;
- `AWS_REGION` set from the stack Region if the pinned exporter config requires
  it;
- ECS health check command `CMD /healthcheck`, with a reasonable start period,
  30-second interval, short timeout, and three retries;
- separate ADOT `awslogs` configuration.

Task definition:

- `cpu: 512`;
- `memoryLimitMiB: 1024`;
- current `awsvpc` network mode;
- no database/migration containers.

The app and ADOT share task loopback under `awsvpc`, so `127.0.0.1:4318` works
without a security-group rule or port mapping. See the
[ECS task networking documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking-awsvpc.html).

### Collector Health And Diagnostics

Create:

```text
/golden-path/aws-demo/movie-reservation-service/adot
```

with one-week retention and `RemovalPolicy.DESTROY`. Use stream prefix `adot`
and collector `info` logging. Do not enable the debug exporter or permanent
debug logging.

Operational signals in #37 are:

- ADOT container `lastStatus`, `healthStatus`, exit code, and reason in ECS;
- the ECS restart policy and task/container metadata restart count;
- ADOT startup, config, retry, permission, and export errors in its log group;
- standard aggregate Fargate service CPU/memory metrics;
- deterministic end-to-end X-Ray smoke success/failure.

Without #38 Container Insights there is no dedicated collector health metric or
alarm. Enhanced Container Insights later can expose container restart and
unhealthy-status metrics.

### IAM

Add one explicit task-role statement:

```json
{
  "Effect": "Allow",
  "Action": [
    "xray:PutTraceSegments",
    "xray:PutTelemetryRecords"
  ],
  "Resource": "*"
}
```

Do not attach the broader AWS managed X-Ray write policy. Do not add
`GetSamplingRules`, `GetSamplingTargets`, `GetSamplingStatisticSummaries`, or
read/query permissions to the task.

The execution role remains responsible for ECR image pull and CloudWatch Logs.
The operator profile, not the task role, owns `xray:BatchGetTraces` for the
smoke script.

### X-Ray Private Network Path

Add `InterfaceVpcEndpointAwsService.XRAY` with:

- selected workload subnet only;
- private DNS enabled;
- existing endpoint security group;
- no automatic open ingress;
- endpoint policy allowing only the two X-Ray write actions.

No NAT Gateway, public task IP, STS endpoint, or public OTLP endpoint is added.
The extra interface endpoint has hourly and data-processing cost, so the
runbook must call it out and retain immediate destroy guidance.

### AWS Trace Smoke

Add `ecs-infra/scripts/xray-smoke.sh`. It uses existing local tools (`bash`,
`curl`, AWS CLI, and Node or another already-required structured JSON helper),
not an AWS SDK dependency in `ecs-infra`.

The script must:

1. Require explicit `AWS_PROFILE` and `AWS_REGION` and default the stack name to
   `GoldenPathDemoStack`.
2. Resolve the ALB DNS name from the CloudFormation output unless an explicit
   base URL is supplied.
3. Generate a valid sampled W3C header:
   `00-<32 hex trace id>-<16 hex parent id>-01`.
4. Generate explicit correlation and request IDs.
5. Send a named, read-only GraphQL operation such as
   `ObservabilitySmokeMovies` through the ALB with those headers.
6. Require HTTP success and a GraphQL response without errors.
7. Convert the W3C trace ID to X-Ray format:
   `1-<first 8 hex>-<remaining 24 hex>`.
8. Poll `aws xray batch-get-traces` for a bounded eventual-consistency window.
9. Require a segment for `movie-reservation-service`; an empty trace is a
   failure even when the HTTP request succeeded.
10. Emit a machine-readable result containing:
    - result and failure stage;
    - W3C `traceparent`;
    - X-Ray trace ID;
    - correlation ID;
    - request ID;
    - stack, Region, target, start/end time, and duration;
    - no account ID, auth material, response body, or user ID.
11. Exit nonzero on failure and support an explicit report output path for
    future private-CI artifact collection.

X-Ray accepts W3C IDs after conversion when using a sufficiently recent
exporter. See the [AWS W3C trace ID guidance](https://docs.aws.amazon.com/xray/latest/devguide/xray-api-sendingdata.html).

### Future Gateway Evolution

The likely later topology is the OpenTelemetry
[gateway deployment pattern](https://opentelemetry.io/docs/collector/deploy/gateway/):

```text
app -> shared collector gateway
```

or, if local agent processing remains valuable:

```text
app -> sidecar agent -> shared collector gateway
```

Preserve that option by keeping the app endpoint-driven and by keeping AWS
exporters/IAM outside the app. Do not create a speculative gateway/sidecar CDK
abstraction in #37. The concrete follow-up debt is tracked in
[`platform-follow-up-tasks.md`](platform-follow-up-tasks.md#telemetry-platform-debt).

Gateway-dependent follow-ups include:

- gateway placement, discovery, HA, and load balancing;
- whether ECS resource enrichment runs in an agent or gateway;
- centralized filtering/redaction;
- tail sampling;
- persistent queue/durable transport choices;
- collector credential isolation from app tasks;
- telemetry failure alerts and SLOs;
- an X-Ray `indexed_attributes` allowlist for low-cardinality, nonsecret fields
  if AWS trace search needs more than X-Ray's built-in service, status, and user
  fields.

## 7. Alternatives Considered

### Alternative A: AWS X-Ray SDK In The Application

- Pros: direct AWS integration and X-Ray-native controls.
- Cons: vendor-specific code and dependencies in each language; harder backend
  replacement; X-Ray SDKs/daemon are in maintenance mode.
- Decision: Rejected. Applications use OTel and OTLP only.

### Alternative B: Essential ADOT With App Startup Dependency

- Pros: more deterministic collector-first startup and fewer missing startup
  spans.
- Cons: collector crash, health failure, or bad config can replace/block the app
  task and turn telemetry into an application outage.
- Decision: Rejected. Availability is more important than complete trace
  capture.

### Alternative C: Shared Collector Gateway Now

- Pros: isolates AWS credentials, amortizes collector resources, centralizes
  policy, and supports tail sampling.
- Cons: introduces service discovery, HA, scaling, network ingress, and a new
  shared runtime before one AWS export path is proven.
- Decision: Deferred. Preserve endpoint portability and revisit after the
  sidecar path works.

### Alternative D: Public Tasks Or NAT Gateway

- Pros: fewer VPC endpoint resources and simpler outbound connectivity.
- Cons: changes the delivered private/no-NAT learning shape and either exposes
  tasks or adds NAT cost.
- Decision: Rejected for #37. Add the single X-Ray endpoint and re-evaluate the
  aggregate endpoint cost before #38.

### Alternative E: ADOT Config In SSM

- Pros: update config without rebuilding the image.
- Cons: adds SSM endpoint/IAM/runtime failure modes and weakens immutable image
  review for a small static config.
- Decision: Rejected. Bake the reviewed config into the pinned image.

### Alternative F: Persistent Collector Queue

- Pros: better survival through exporter/backend outages and restarts.
- Cons: requires durable volume/storage design, lifecycle ownership, capacity
  controls, and recovery testing.
- Decision: Rejected for the demo. Use bounded in-memory batches plus the
  X-Ray exporter's bounded workers/retries and accept loss.

### Alternative G: `enableAdotTracing` CDK Toggle

- Pros: quick infrastructure off-switch.
- Cons: creates two stack shapes and a larger test matrix even though tracing is
  the purpose of the new baseline.
- Decision: Rejected. Roll back to the previous revision or destroy the stack.

### Alternative H: Full Local Trace Integration In Public CI

- Pros: proves app-to-collector OTLP behavior before AWS.
- Cons: requires a test exporter/config and duplicates the delivered local OTel
  stack without proving X-Ray/IAM/PrivateLink.
- Decision: Deferred. CI builds and validates the image/config; the laptop AWS
  smoke proves the real path.

### Alternative I: Hash `enduser.id` In #37

- Pros: reduces direct identifier exposure.
- Cons: a plain hash may remain enumerable/linkable; a keyed pseudonym needs
  key ownership, rotation, and incident/debugging requirements.
- Decision: Retain the existing ID for the fixed-user demo, document the risk,
  and revisit before production auth.

## 8. API / Interface Changes

### Public Application API

None. GraphQL schema, REST health endpoints, auth behavior, and reservation
behavior remain unchanged.

### Application Runtime Contract

Add/use these standard OTel variables in committed templates and ECS:

- `OTEL_TRACES_EXPORTER`
- `OTEL_METRICS_EXPORTER`
- `OTEL_LOGS_EXPORTER`
- `OTEL_TRACES_SAMPLER`
- existing OTLP endpoint/protocol, propagator, service name, and resource
  attributes.

`OBSERVABILITY_ENABLED` remains the existing application master switch.

### Infrastructure Configuration

No new caller-controlled CDK context. `allowedIngressCidr` remains required and
`enableEcsExec` remains optional.

### Operational Interface

Add the credentialed `xray-smoke.sh` command and its machine-readable report
contract. Public CI invokes only the credential-free collector image validation
command.

## 9. Data Model / Persistence Changes

None.

- No database schema or migration.
- No new persistent store.
- No collector durable queue.
- The service remains in-memory and disposable.

## 10. Security, Privacy, And Abuse Considerations

- The app container contains no AWS telemetry SDK and sends only OTLP to
  loopback.
- The task role is shared by both containers. Limit its added authority to the
  two unavoidable X-Ray writes; document that a compromised app container can
  also use them.
- X-Ray write actions cannot be resource-scoped, so use `Resource: "*"` and
  combine task IAM, endpoint policy, isolated subnet, and security groups.
- The OTLP and collector health listeners bind to loopback and have no ECS port
  mapping.
- Pin the official ADOT tag and digest. Verify components and health binary in
  public CI.
- Keep `index_all_attributes: false`; do not configure indexed attributes.
- Explicitly prohibit GraphQL values, raw headers/bodies, auth tokens, cookies,
  and environment dumps in traces or diagnostics.
- Retained `enduser.id` is linkable identity data and maps to X-Ray `user`. The
  ECS demo currently uses a fixed fake user, which lowers immediate risk but
  does not establish a production policy.
- X-Ray's dedicated `user` mapping remains independently meaningful even when
  generic span attributes are not indexed; `index_all_attributes: false` is not
  a way to anonymize `enduser.id`.
- X-Ray trace data is retained for 30 days and is not deleted by
  `cdk destroy`. See [AWS X-Ray retention](https://docs.aws.amazon.com/xray/latest/devguide/xray-concepts.html).
- The smoke report must not contain account ID, tokens, full responses, or user
  identity.
- The public ALB is HTTP-only and therefore demo-only. Keep the explicit source
  CIDR restriction and send no production credentials/data.
- Application logs retain their existing `user_id` behavior; changing the log
  privacy contract is outside #37.

## 11. Performance, Scalability, And Reliability Considerations

- The 512 CPU/1024 MiB task doubles the delivered task resources. This affects
  Fargate cost and must appear in `cdk diff` review.
- CPU values are relative shares under contention. Hard memory limits prevent
  the collector from consuming all task memory.
- The collector memory limiter starts refusing/drop behavior before the 384 MiB
  container OOM boundary.
- Batch processing and bounded X-Ray exporter workers/retries reduce call
  overhead and absorb short failures, but do not provide durability.
- ADOT is nonessential and independent, so failure after task start does not
  replace the healthy app.
- An image pull or invalid task definition is still a deployment failure; the
  ECS circuit breaker handles service rollback.
- Immediate invalid collector config exits are intentionally not restart-looped.
  Config validation should catch these before deploy.
- `parentbased_always_on` maximizes determinism and cost per request. It is not a
  production sampling recommendation.
- A desired count of one and one workload AZ remain demo limitations.
- No collector health alarm exists until #38/#30. A manual smoke failure or
  ADOT log error is the #37 signal.
- The sidecar adds per-task cost. A future gateway may be more efficient at
  larger task/service counts.

## 12. Implementation Steps

### 1. Verify And Pin The ADOT Distribution

- Change:
  - Verify the current supported official release and Public ECR digest.
  - Verify target architecture, required components, `/healthcheck`, config
    validation syntax, and W3C-capable X-Ray exporter.
  - Record the tag and digest in the Dockerfile and runbook.
- Files/modules likely affected:
  - `ecs-infra/adot-collector/Dockerfile`
  - `ecs-infra/README.md`
- Notes:
  - The official repository listed v0.48.0 when this plan was written, but the
    implementation must verify rather than copy that observation blindly.
  - Do not use `latest` as a temporary implementation shortcut.
- Verification:
  - Image inspection shows the expected immutable digest and architecture.
  - Required collector components and `/healthcheck` are present.

### 2. Make The OTel Bootstrap Signal-selectable And Fail-open

- Change:
  - Remove manually supplied trace exporter and metric reader from `NodeSDK`.
  - Keep explicit resource and instrumentation configuration.
  - Let standard OTel env vars choose traces/metrics/logs exporters.
  - Remove `NODE_ENV`-derived deployment environment.
  - Set `allowValues: false` explicitly.
  - Add fail-open startup and bounded best-effort shutdown behavior.
  - Align service version with service package metadata.
- Files/modules likely affected:
  - `movie-reservation-service/src/infrastructure/observability/instrumentation.ts`
  - a small helper under
    `movie-reservation-service/src/infrastructure/observability/`
  - `movie-reservation-service/src/config.ts`
  - `movie-reservation-service/package.json`
  - `package-lock.json`
  - committed files under `movie-reservation-service/env_files/templates/`
  - relevant local env examples/documentation
- Notes:
  - Keep the preload free of NestJS/application imports.
  - Remove dependencies only when imports are gone and checks prove they are
    unused.
  - Do not add AWS packages.
- Verification:
  - Unit tests prove startup exception is swallowed with one sanitized event.
  - Unit tests prove shutdown rejection/timeout cannot become an unhandled
    failure or process exit.
  - Template tests prove local traces+metrics and logs `none`.
  - Service typecheck, lint, unit, and integration checks pass.

### 3. Add The Traces-only Collector Image And Config

- Change:
  - Add the pinned Dockerfile and minimal config.
  - Configure loopback OTLP/HTTP and health endpoints.
  - Configure memory limiter, batch, bounded X-Ray workers/retries, and the
    X-Ray exporter.
  - Keep all metric/log pipelines and advanced processors absent.
- Files/modules likely affected:
  - `ecs-infra/adot-collector/Dockerfile`
  - `ecs-infra/adot-collector/adot-config.yaml`
- Notes:
  - Keep config in the image instead of SSM.
  - Keep collector log level `info`.
- Verification:
  - Docker image builds without AWS credentials.
  - Pinned collector validates the exact baked config.
  - Validation asserts `/healthcheck` exists.

### 4. Add X-Ray Network, IAM, Image, And Log Resources

- Change:
  - Add the ADOT Docker image asset.
  - Add the one-week ADOT log group.
  - Add the X-Ray interface endpoint and narrow endpoint policy.
  - Add the exact two-action task-role policy.
- Files/modules likely affected:
  - `ecs-infra/lib/infra-stack.ts`
  - optional small structured package-metadata helper under `ecs-infra/lib/`
  - `ecs-infra/test/infra.test.ts`
- Notes:
  - Reuse the selected workload subnet and endpoint security group.
  - Keep X-Ray permissions on the task role, not execution role.
  - Do not add STS, AMP, Grafana, Container Insights, or NAT.
- Verification:
  - CDK assertions prove endpoint placement/policy and exact task actions.
  - Negative assertions prove forbidden resources/actions are absent.

### 5. Add The Nonessential ADOT Sidecar And Traces-only App Environment

- Change:
  - Resize the task and set exact container resource limits.
  - Add ADOT with nonessential lifecycle, restart policy, health check, and
    separate logging.
  - Enable application observability and set the standard traces-only OTel env.
  - Use service package version and standard resource attributes.
  - Keep app and ADOT independent.
- Files/modules likely affected:
  - `ecs-infra/lib/infra-stack.ts`
  - `ecs-infra/test/infra.test.ts`
- Notes:
  - Add the sampling TODO/comment beside `parentbased_always_on`.
  - Add no ADOT port mapping and no app `dependsOn` entry.
- Verification:
  - Synthesized task definition has exact task/container CPU/memory.
  - ADOT is nonessential with restart and health settings.
  - App is essential, points to loopback, and disables metrics/logs.
  - No task security-group ingress exposes collector ports.

### 6. Add Credential-free Collector Validation To CI

- Change:
  - Add a repeatable infra workspace command/script that builds the image,
    validates config, and checks `/healthcheck`.
  - Invoke it from the existing public `infra` CI job.
- Files/modules likely affected:
  - `ecs-infra/package.json`
  - `ecs-infra/scripts/validate-adot-image.sh`
  - `.github/workflows/ci.yml`
  - `docs/workflows/ci-workflow.md`
- Notes:
  - No AWS credentials, deployment, trace export, registry push, or artifacts.
  - Keep this a basic image/config gate, not an app integration environment.
- Verification:
  - Command passes locally with Docker.
  - CI syntax and the public infra job pass.

### 7. Add The Deterministic X-Ray Smoke Script

- Change:
  - Add sampled W3C request generation, GraphQL request, X-Ray ID conversion,
    bounded polling, service assertion, and machine-readable report.
- Files/modules likely affected:
  - `ecs-infra/scripts/xray-smoke.sh`
  - `ecs-infra/package.json` if an npm wrapper is useful
  - tests for pure ID/report helpers if extracted
- Notes:
  - Use AWS CLI rather than adding AWS SDK dependencies to infra runtime code.
  - Keep smoke read permissions operator-side.
- Verification:
  - Static/shell validation passes.
  - W3C-to-X-Ray conversion has deterministic test vectors.
  - Failure cases exit nonzero and still produce a sanitized report.

### 8. Update Architecture And Operations Documentation

- Change:
  - Document new task topology, X-Ray endpoint/IAM, collector health/logs,
    image validation, deploy smoke, troubleshooting, rollback, costs, and
    destroy behavior.
  - Record vendor-neutral OTel and fail-open boundaries as durable decisions.
  - Document that X-Ray data outlives stack destruction for its retention
    period.
- Files/modules likely affected:
  - `ecs-infra/README.md`
  - `docs/architecture/ecs-fargate-deployment.md`
  - `docs/architecture/architecture-decisions.md`
  - `docs/operations/aws-cdk-local-deployment.md`
  - `docs/operations/runbook.md`
  - `docs/workflows/ci-workflow.md`
- Notes:
  - Keep the local observability workflow backend-neutral.
  - Preserve laptop deployment until the private promotion workflow exists.
- Verification:
  - Commands and resource names match synthesized output.
  - Docs clearly separate #37 from #38 and #7.

### 9. Run The Laptop AWS Acceptance And Destroy

- Change:
  - Build/test/validate, inspect `cdk diff`, deploy, wait for service stability,
    run HTTP and X-Ray smoke, inspect collector health/logs/resources, then
    destroy.
- Files/modules likely affected:
  - no production source unless validation exposes a defect;
  - optional sanitized smoke report outside committed source.
- Notes:
  - Stop if diff opens ingress, adds NAT, adds #38 resources, or grants broader
    IAM.
  - Record app/collector task CPU and memory observations available from the
    console; do not claim production capacity from one smoke.
- Verification:
  - A service runtime test starts the app with an unreachable loopback OTLP
    endpoint and proves `/health` and a named GraphQL query still succeed.
  - CDK assertions prove ADOT is nonessential and the app has no collector
    dependency.
  - ECS shows collector health state.
  - ADOT logs arrive in its separate log group.
  - Exact smoke trace appears in X-Ray.
  - Stack deletion removes the endpoint, service/task, and log groups.
  - Operator understands that ingested X-Ray traces remain for AWS retention.

## 13. Testing Strategy

### Service Unit Tests

- Standard exporter selection does not create explicit metric readers when ECS
  sets metrics to `none`.
- OTel bootstrap start exception fails open and emits one sanitized diagnostic.
- Shutdown reject/timeout is handled and cannot exit the process.
- Explicit GraphQL instrumentation keeps values disabled.
- Deployment environment is not derived from `NODE_ENV`.
- Service version comes from the service package metadata.
- Existing span/log/metric behavior tests remain green.

### Service Runtime Availability Test

- Start the service with observability enabled and an unused loopback OTLP port.
- Prove startup, `/health`, and a named GraphQL query complete normally while
  export fails in the background.
- Bound the test duration and cleanly stop the SDK/app so unavailable telemetry
  cannot hang the test process.

### Environment Contract Tests

- Local templates specify OTLP traces and metrics, OTel logs `none`, the current
  five-second metric export interval, and local resource identity.
- ECS synthesized env specifies OTLP traces, metrics/logs `none`, W3C
  propagators, sample-all parent-based sampler, and `aws-demo` resource
  identity.
- Production/test defaults do not accidentally activate exporters.

### Collector Image Tests

- Docker build succeeds from the intended context.
- Base image is tag+digest pinned.
- Config validation succeeds using the built collector.
- Required components and `/healthcheck` exist.
- Config has exactly one traces pipeline and no metrics/logs pipelines.
- Listener strings remain loopback rather than `0.0.0.0`.

### CDK Assertion Tests

- Task definition CPU/memory is `512`/`1024`.
- Exactly app and ADOT application containers are present.
- App is essential with `384` CPU and `640` MiB.
- ADOT is nonessential with `128` CPU and `384` MiB.
- No app dependency on ADOT exists.
- ADOT restart policy is enabled with 60 seconds.
- ADOT health check invokes `/healthcheck`.
- App OTLP endpoint is `127.0.0.1:4318` and signals are traces-only.
- No collector port mapping exists.
- App and ADOT use separate named log groups with one-week retention.
- X-Ray interface endpoint exists in one workload subnet with private DNS.
- Endpoint security group accepts 443 only from the task security group.
- Task role and endpoint policy contain only the two X-Ray write actions.
- No X-Ray sampling-read permissions exist.
- No NAT Gateway, STS endpoint, AMP workspace, Grafana workspace, Container
  Insights, database container, or migration container exists.
- ECS Exec remains independently controlled by its existing flag.

### Smoke Script Tests

- Known W3C IDs map to expected X-Ray IDs.
- Invalid prerequisites/inputs fail before making requests.
- HTTP/GraphQL failure, trace timeout, and wrong service segment fail with
  distinct stages.
- Result output is valid structured data and excludes sensitive fields.

### Real AWS Acceptance

1. `GET /health` succeeds through the restricted ALB.
2. Named GraphQL smoke succeeds with explicit trace/correlation/request IDs.
3. `BatchGetTraces` finds the exact converted X-Ray ID.
4. Trace contains `movie-reservation-service` with expected service namespace,
   environment, version, operation, and user behavior.
5. Collector is visible as healthy and has separate info logs.
6. Live task definition and container details match the tested nonessential,
   independent collector lifecycle.
7. Destroy and inspect for expected cleanup.

### Verification Commands

Use the exact scripts added by implementation. The expected command groups are:

```bash
npm -w movie-reservation-service run check
npm -w ecs-infra run build
npm -w ecs-infra test -- --runInBand
npm -w ecs-infra run validate:adot-image
npm -w ecs-infra run cdk -- synth -c allowedIngressCidr=203.0.113.10/32
```

Then follow the credentialed diff/deploy/smoke/destroy commands in
`docs/operations/aws-cdk-local-deployment.md`.

## 14. Rollout / Migration Plan

There is no data migration.

### Pre-deploy

1. Verify AWS identity, Region, bootstrap, Docker, and source CIDR.
2. Run service checks, infra build/tests, collector validation, and synth.
3. Inspect `cdk diff` for:
   - task replacement and resource increase;
   - one ADOT asset/log group/container;
   - one X-Ray interface endpoint;
   - exact task-role and endpoint actions;
   - no NAT, database, metrics, AMP, AMG, or unexpected ingress.

### Deploy

1. Deploy interactively with IAM approval review.
2. Let the ECS circuit breaker roll back a task definition that cannot become
   service-healthy.
3. Wait for the app target to become healthy; collector health does not gate
   this step.
4. Inspect ADOT status/logs.
5. Run deterministic X-Ray smoke.

### Runtime Degradation

- Collector exit after 60 seconds: ECS may restart only ADOT.
- Collector immediate config failure: app stays running; ADOT remains stopped;
  inspect the ADOT log and container reason.
- X-Ray endpoint/IAM/backend failure: app continues; collector logs retries and
  drops after bounded in-memory limits.
- App OTel bootstrap failure: app continues with no-op telemetry and writes one
  sanitized diagnostic.

### Rollback

- For a failed deployment, rely on the ECS circuit breaker and inspect events.
- For a bad but service-healthy tracing revision, redeploy the previous
  known-good commit/task definition. There is no runtime feature toggle.
- For cost, permission, or network uncertainty, destroy
  `GoldenPathDemoStack`.
- Stack destroy does not delete already ingested X-Ray trace data; it expires
  under the AWS retention policy.

## 15. Risks And Mitigations

| Risk | Impact | Likelihood | Mitigation |
|---|---:|---:|---|
| ADOT tag moves or supply chain changes | High | Low | Pin official tag and immutable digest; validate exact image in CI. |
| Pinned release lacks expected config or `/healthcheck` | High | Low | Make component/binary checks an implementation preflight and CI gate. |
| Collector failure blocks/replaces app | High | Low | Nonessential container, no dependency, app fail-open bootstrap. |
| Collector consumes app memory | High | Medium | Hard per-container limits plus memory limiter below ADOT OOM limit. |
| Invalid config exits before restart window | Medium | Medium | Credential-free validation; separate logs/status; intentional no tight loop. |
| Collector is live but export path is broken | High | Medium | Deterministic end-to-end X-Ray smoke; #38 later adds metrics/alerts. |
| Private task cannot reach X-Ray | High | Medium | X-Ray endpoint, endpoint SG/policy assertions, no STS dependency. |
| IAM is broader than needed | High | Low | Exact two-action inline task and endpoint policies; negative tests. |
| App can use collector X-Ray permissions | Medium | Medium | ECS task-role limitation documented; actions are write-only; gateway later isolates credentials. |
| Sample-all raises trace cost | Medium | Medium | Demo traffic/CIDR restriction, explicit code comment, destroy promptly, revisit sampling. |
| In-memory queue drops traces | Medium | High during outage | Accepted availability tradeoff; bounded queue/retry; future durability review. |
| Raw identity or request data reaches X-Ray | High | Low | Values/headers/bodies prohibited, no blanket indexing, privacy checks, fixed demo user. |
| `enduser.id` remains linkable for 30 days | Medium | Medium | Document mapping/retention; no real users; revisit keyed pseudonym before production auth. |
| Sidecar cost multiplies with task count | Medium | Low now | One demo task; measure; evaluate gateway at scale. |
| Endpoint inventory becomes costlier than NAT | Medium | Medium in #38 | Add only X-Ray now; explicit cost checkpoint before AMP/AMG. |
| Public CI becomes credentialed deployment CI | High | Low | CI only builds/validates image; AWS smoke stays laptop-driven. |
| Old umbrella plan overrides focused decisions | High | Medium | Link this document as #37 source of truth and mark umbrella plan non-executable for #37. |

## 16. Done Criteria

- Focused #37 plan is the documented implementation source of truth.
- Official ADOT base image is pinned by verified tag and digest.
- Public CI builds the ADOT image and validates config/health binary without AWS
  credentials.
- App contains no AWS telemetry SDK/import and exports via standard OTel/OTLP.
- Local traces and metrics continue to work; local OTel logs remain disabled.
- ECS application metrics and OTel logs are explicitly disabled.
- OTel bootstrap and shutdown fail open as specified.
- Task has exact 512 CPU/1024 MiB and container limits.
- ADOT is nonessential, independent, restart-enabled, and health-checked.
- ADOT health is visible in ECS but does not determine task/service health.
- Collector has only the loopback traces pipeline and separate one-week logs.
- X-Ray endpoint, security group path, endpoint policy, and task IAM are least
  privilege and tested.
- No NAT, STS, database, migration, #38 resources, or public collector ports are
  introduced.
- Service resource identity uses `aws-demo`, platform namespace, and service
  package version without deriving environment from `NODE_ENV`.
- Trace privacy rules are explicit and tested where practical.
- Laptop smoke proves the exact sampled W3C trace appears in X-Ray and emits a
  sanitized machine-readable report.
- Runtime availability test proves an unreachable telemetry endpoint does not
  block app startup, health, or GraphQL behavior; CDK proves collector
  lifecycle independence.
- Runbook documents deploy, diagnostics, smoke, rollback, costs, destroy, and
  X-Ray retention.
- Relevant service and infra checks pass.
- The deployed stack is destroyed after acceptance.

## 17. Review Checklist

- [x] Scope is traces-only and tied to #37.
- [x] Application vendor neutrality is explicit.
- [x] Availability and telemetry-loss tradeoffs are explicit.
- [x] Sidecar lifecycle and task resource isolation are concrete.
- [x] Image provenance and validation are defined.
- [x] IAM and private networking are least privilege.
- [x] Privacy, identity mapping, and X-Ray retention are documented.
- [x] Public CI and credentialed AWS smoke have separate responsibilities.
- [x] Rollout, degradation, rollback, and destroy are defined.
- [x] #38, #7, gateway, alerting, and Playwright follow-ups are separated.
- [x] Implementation verifies the ADOT tag/digest, required components, config,
  and health binary.
- [x] Credential-free service, infrastructure, collector, smoke-tool, and synth
  checks pass.
- [x] Laptop AWS acceptance and teardown pass.

## 18. Historical Handoff Prompt

```text
Historical prompt preserved from the #37 implementation branch.

Implement docs/plans/delivered/ecs-adot-xray-tracing.md on the
37-ecs-adot-collector-xray branch for GitHub issue #37.

Treat that focused plan as the source of truth. Do not implement #37 from the
older umbrella docs/plans/ecs-adot-managed-observability.md where it conflicts.

Hard constraints:

- Stay traces-only: no CloudWatch custom metrics, Container Insights, AMP, AMG,
  metrics pipeline, alerts, RDS, migrations, worker, or failure injection.
- Keep applications AWS-telemetry-neutral: OTel APIs/SDK, W3C propagation, and
  OTLP only. Add no X-Ray/AWS telemetry SDK to NestJS.
- Verify and pin the current official ADOT tag and immutable Public ECR digest
  before writing the Dockerfile. Verify required components and /healthcheck.
- ADOT is nonessential and the app has no startup/health dependency on it.
- OTel startup/shutdown fails open; telemetry failure cannot block app startup,
  request handling, or termination.
- ECS uses traces=otlp, metrics=none, logs=none, parentbased_always_on, and
  loopback OTLP/HTTP.
- Use exact task/container resource limits, memory limiter, restart period,
  health check, log group, X-Ray endpoint, and two-action IAM policies from the
  plan.
- Keep enduser.id for this demo, prohibit raw values/headers/bodies/tokens, and
  keep X-Ray attribute indexing disabled.
- Add credential-free collector image/config validation to public CI.
- Add the AWS CLI/curl X-Ray smoke and update the laptop runbook.
- Preserve unrelated existing worktree changes. Do not revert the documentation
  cleanup already present.

Implement incrementally in the order given. Run narrow checks while iterating,
then the full affected service and infra checks. Inspect synthesized
CloudFormation for negative requirements as well as expected resources.

Do not claim completion until the telemetry-unavailable runtime test and the
laptop X-Ray smoke pass and the stack has been destroyed. If AWS acceptance
cannot be run, report that explicitly and leave the issue incomplete rather
than treating synth as end-to-end proof.
```

## Primary References

- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [OpenTelemetry agent deployment](https://opentelemetry.io/docs/collector/deploy/agent/)
- [OpenTelemetry gateway deployment](https://opentelemetry.io/docs/collector/deploy/gateway/)
- [ADOT on ECS](https://aws-otel.github.io/docs/setup/ecs/)
- [ADOT X-Ray exporter](https://aws-otel.github.io/docs/getting-started/x-ray/)
- [ECS task networking](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-networking-awsvpc.html)
- [ECS container restart policy](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/container-restart-policy.html)
- [ECS container health](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/healthcheck.html)
- [X-Ray VPC endpoint](https://docs.aws.amazon.com/xray/latest/devguide/xray-security-vpc-endpoint.html)
- [ADOT AWS permissions](https://aws-otel.github.io/docs/setup/permissions/)
- [X-Ray W3C trace IDs](https://docs.aws.amazon.com/xray/latest/devguide/xray-instrumenting-your-app.html)
- [X-Ray trace ID conversion](https://docs.aws.amazon.com/xray/latest/devguide/xray-api-sendingdata.html)
