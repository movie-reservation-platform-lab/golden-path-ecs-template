# Implementation Plan: Issue #38 ECS Managed Metrics And Grafana

Status: in progress (PR 1 of 3)

Issue: [#38](https://github.com/patex1987/golden-path-ecs-template/issues/38)

Last reviewed: 2026-07-26

## 1. Summary

Extend the delivered ECS/ADOT/X-Ray deployment with managed metrics and the
first AWS-hosted Grafana dashboard. Keep the application on its existing
vendor-neutral OpenTelemetry boundary and fan application metrics out inside
ADOT:

```text
NestJS OpenTelemetry metrics
  -> OTLP/HTTP on task loopback
  -> ADOT
     -> CloudWatch Embedded Metric Format
     -> Prometheus remote write with SigV4
        -> Amazon Managed Service for Prometheus (AMP)

ECS platform metrics
  -> ECS Container Insights with enhanced observability
     -> CloudWatch

ADOT ECS task/container receiver
  -> Prometheus remote write with SigV4
     -> AMP

Amazon Managed Grafana
  -> AMP for application and ADOT-collected ECS metrics
  -> CloudWatch for ALB and Container Insights metrics
```

The work is intentionally split into three sequential pull requests against
`main`:

1. CloudWatch application metrics.
2. AMP plus ECS task/container metrics.
3. Amazon Managed Grafana, the dashboard, and the complete runbook.

Each pull request must remain independently deployable and reviewable. The first
two pull requests reference #38; the third closes it.

The implementation stays in the existing disposable `GoldenPathDemoStack` in
`eu-central-1`. It does not change domain or application-layer code, add metric
instruments, introduce a NAT Gateway, or automate Grafana through a second IaC
provider.

## 2. Goals

- Export the service's existing bounded application metrics to CloudWatch
  custom metrics through ADOT's `awsemf` exporter.
- Export the same application metrics to AMP through ADOT's
  `prometheusremotewrite` exporter with SigV4 authentication.
- Prove the intentional dual-routing design by querying the same application
  metric in CloudWatch and AMP.
- Enable ECS Container Insights with enhanced observability for detailed
  CloudWatch task and container metrics.
- Export an explicit allowlist of ADOT-collected ECS task and container metrics
  to AMP.
- Keep the no-NAT task private by adding only the AMP workspace and regional STS
  interface endpoints required for remote write.
- Provision an AMP workspace, an Amazon Managed Grafana workspace, a
  customer-managed Grafana data-access role, and a Grafana client prefix list
  through CDK.
- Use an organization instance of IAM Identity Center with its built-in
  directory for one personal Grafana administrator.
- Restrict Grafana network access to the existing `allowedIngressCidr`.
- Store a focused 15-panel dashboard JSON artifact in the repository.
- Generate meaningful demonstration data by enabling the existing fake
  in-process worker and deterministic 40% unexpected-error injection in the
  development-only ECS profile.
- Keep public CI credential-free while automating AWS acceptance from the
  developer laptop.
- Preserve the delivered X-Ray path and prove it still works.
- Make teardown remove all stack-owned paid resources and stop all metric
  publication.

## 3. Non-goals

- Do not add new application metric instruments or labels.
- Do not change domain, application, GraphQL, or HTTP behavior.
- Do not add Node.js runtime, event-loop, database-pool, queue-depth, or worker
  backlog metrics. Those remain part of issue #30.
- Do not build service-specific health dashboards, DORA dashboards, SLOs, or
  engineering-performance reporting.
- Do not add CloudWatch alarms, AMP rule groups, Alertmanager configuration,
  notification channels, or paging.
- Do not add X-Ray or CloudWatch Logs as Grafana data sources in this slice.
  Trace and log investigation remains a runbook workflow in the AWS consoles.
- Do not automate IAM Identity Center user creation, Grafana user assignment,
  Grafana data-source creation, or dashboard import.
- Do not use Terraform, a Grafana provider, a CDK custom resource, or a Grafana
  API token in #38.
- Do not add SAML or an external identity provider. A future migration to Google
  Workspace, Microsoft Entra ID, or another workforce IdP is a separate identity
  project.
- Do not make the observability resources persistent across
  `cdk destroy`.
- Do not split `GoldenPathDemoStack` in this issue. Follow the existing platform
  stack-boundary backlog instead.
- Do not move ADOT to a cluster-level collector service in this issue. Preserve
  the OTLP boundary so that migration can happen later without business-code
  changes.
- Do not introduce a NAT Gateway, public task IP, public OTLP receiver, or
  Grafana PrivateLink endpoint.
- Do not add RDS, SQS, a separate worker service, or production authentication
  to the application.

## 4. Current State

### Infrastructure

- `ecs-infra/lib/infra-stack.ts` defines one explicit CDK stack with a two-AZ
  VPC, one workload AZ, no NAT Gateway, a CIDR-restricted public ALB, and one
  private Fargate task.
- The task has an essential application container at 384 CPU units and 640 MiB
  plus a restartable, nonessential ADOT sidecar at 128 CPU units and 384 MiB.
- The application sends OTLP/HTTP traces to `127.0.0.1:4318`; no collector port
  is exposed through a security group or task port mapping.
- The task uses S3, ECR API, ECR Docker, CloudWatch Logs, and X-Ray VPC
  endpoints. SSM Messages is optional for ECS Exec.
- The ECS cluster explicitly has Container Insights disabled.
- `ecs-infra/lib/config/platform-config.ts` validates untrusted CDK context once
  and passes a typed `PlatformConfig` into the stack.
- App and ADOT log groups have one-week retention and `DESTROY` removal
  policies.
- The task role currently grants only the X-Ray write actions, plus ECS Exec
  actions when that feature is enabled.

### Collector And Application Metrics

- `ecs-infra/adot-collector/adot-config.yaml` currently has only an OTLP trace
  receiver and X-Ray exporter.
- The pinned ADOT image is validated by
  `ecs-infra/scripts/validate-adot-image.sh`; validation starts the real image
  and waits for its health extension.
- The ECS application currently sets `OTEL_METRICS_EXPORTER=none`.
- `movie-reservation-service/src/infrastructure/observability/instrumentation.ts`
  already delegates exporter selection and export cadence to standard
  OpenTelemetry environment variables.
- The service already emits ten metric instruments:
  - `http_request_total`
  - `http_request_duration_ms`
  - `graphql_operation_total`
  - `graphql_operation_duration_ms`
  - `graphql_operation_exceptions_total`
  - `reservation_request_created_total`
  - `reservation_processor_claim_total`
  - `reservation_processor_outcome_total`
  - `reservation_processor_duration_ms`
  - `reservation_processor_exceptions_total`
- Existing labels are bounded HTTP method/route/status-family, GraphQL business
  operation/type/outcome, reservation outcome/reason, and classified exception
  type. Request, trace, user, and reservation IDs are not metric labels.
- The existing worker and stable-random unexpected-error policy are already
  implemented and tested. #38 only enables them through ECS environment
  variables.

### Verification And Documentation

- `ecs-infra/test/infra.test.ts` uses CDK assertions against synthesized
  CloudFormation.
- `ecs-infra/scripts/xray-smoke.sh` is the established laptop-driven AWS smoke
  pattern and has credential-free self-tests.
- `ecs-infra/package.json` combines TypeScript build, Jest, ADOT image
  validation, smoke self-tests, and CDK synth in `npm run ci`.
- `docs/operations/aws-cdk-local-deployment.md` owns the laptop deployment and
  teardown workflow.
- `docs/operations/runbook.md` owns runtime investigation procedures.
- `docs/architecture/ecs-fargate-deployment.md` shows the deployed resource and
  telemetry topology.
- `docs/plans/production-observability-dashboard.md` owns the deeper production
  dashboard and saturation follow-up under issue #30.

### Reusable Dashboard Evidence

The sibling
`/home/patex1987/development/fastapi_otel_prometheus_grafana_poc` repository has
a pushed `demo-multi-service-observability` branch with a 25-panel reservation
dashboard. Reuse its traffic, error, latency, and saturation row structure plus
the PromQL for the existing application metrics. Do not copy its Loki, Tempo,
multi-service, log, trace, fault, or placeholder saturation panels into #38.

## 5. Requirements And Assumptions

### Confirmed Requirements

- The target Region is `eu-central-1`.
- Application metrics are exported to both CloudWatch and AMP.
- AMP is the primary Grafana source for application metrics.
- ECS metrics take both paths:
  - Container Insights with enhanced observability to CloudWatch.
  - ADOT `awsecscontainermetrics` to AMP.
- The default application and ECS metric collection cadence is 30 seconds.
- Cadence is configurable through the typed CDK configuration boundary.
- Metric label and CloudWatch dimension allowlists are fixed safety policy, not
  caller-configurable lists.
- CloudWatch automatic dimension rollups are disabled.
- The application-metric EMF log group uses seven-day retention and is destroyed
  with the stack.
- The AMP workspace uses seven-day retention and is destroyed with the stack.
- The ADOT sidecar remains nonessential and telemetry failures fail open.
- The current task CPU and memory allocation remains unchanged until acceptance
  data shows that it is insufficient.
- The AWS demo enables `RESERVATION_WORKER_MODE=fake-in-process`.
- The AWS demo enables deterministic
  `stable-random-unexpected-error` injection at rate `0.4` with a fixed,
  nonsecret salt.
- The first Grafana dashboard has 15 panels and stays metrics-focused.
- Logs and X-Ray remain external drill-down procedures.
- The first dashboard does not create alerts.
- Grafana uses organization-level IAM Identity Center with the built-in
  directory and one assigned Admin user.
- Grafana network access is restricted by a customer-managed prefix list that
  contains the existing `allowedIngressCidr`.
- CDK owns AWS resources and the Grafana read role. Identity Center setup,
  Grafana user assignment, data-source configuration, and dashboard import are
  manual.
- Grafana/dashboard automation is explicitly deferred for later comparison of
  the Grafana API, Terraform Grafana provider, and a CDK custom resource.
- Pull requests are sequential against `main`, not stacked.
- Public CI remains credential-free.
- The laptop acceptance workflow automates traffic generation and CloudWatch/AMP
  queries; Grafana visual acceptance remains manual.

### Assumptions

- The personal AWS account is the AWS Organizations management account, or can
  become one, and the operator can enable an organization instance of IAM
  Identity Center.
- IAM Identity Center is enabled in `eu-central-1`, because AWS managed
  applications normally require Identity Center in the same Region.
- The built-in directory user email, password enrollment, MFA, and Grafana
  assignment are deliberately not represented in CloudFormation.
- The deployment principal has permission to pass the customer-managed Grafana
  role and create the new APS, Grafana, IAM, EC2, ECS, and Logs resources.
- The pinned ADOT image contains `awsemf`, `awsecscontainermetrics`,
  `prometheusremotewrite`, and `sigv4auth`. The real-image validation is the
  merge gate for this assumption.
- Managed Grafana's `grafanaVersion` is omitted so AWS selects the latest
  supported version when the disposable workspace is created. Acceptance
  records the deployed version.
- AWS-managed encryption at rest is sufficient for this personal demo. No
  customer-managed KMS key is added.
- CloudWatch datapoints cannot be explicitly deleted. Teardown removes emitters
  and paid resources; historical datapoints age out according to CloudWatch
  retention and do not continue custom-metric publication charges.
- At the last plan review, AWS Organizations and IAM Identity Center were
  offered at no additional charge. Resources used through the account and
  connected applications remain billable, so recheck current AWS pricing before
  enabling them.
- IAM Identity Center and AWS Organizations outlive the application stack.
- No blocking design questions remain.

## 6. Proposed Design

### 6.1 Ownership And Signal Flow

Keep the existing clean-architecture boundary:

- Domain and application code define business behavior and remain unchanged.
- Existing infrastructure observability adapters emit vendor-neutral OTel
  metrics.
- ECS environment variables select OTLP export.
- The task-local ADOT sidecar owns AWS-specific routing, signing, filtering,
  retries, and destination configuration.
- CDK owns deployed AWS resources, IAM, networking, retention, outputs, and
  lifecycle.
- The repository-owned dashboard JSON is a presentation artifact and does not
  become application code.

ADOT must use destination-specific metric pipelines instead of one opaque
combined pipeline:

```text
metrics/application/cloudwatch:
  OTLP -> memory limiter -> CloudWatch label/dimension shaping -> batch -> awsemf

metrics/application/amp:
  OTLP -> memory limiter -> AMP label shaping -> batch -> prometheusremotewrite

metrics/ecs/amp:
  awsecscontainermetrics -> memory limiter -> metric allowlist
  -> resource-label allowlist -> batch -> prometheusremotewrite
```

The traces pipeline remains unchanged. Reusing the OTLP receiver in two
application metric pipelines makes the double route explicit while allowing
destination-specific dimension policy.

### 6.2 Typed Configuration

Add `metricsExportIntervalSeconds` to `PlatformConfig` and
`PlatformConfigContext`:

- Context key: `metricsExportIntervalSeconds`.
- Default: `30`.
- Runtime validation: integer from `5` through `300`.
- Application environment:
  `OTEL_METRIC_EXPORT_INTERVAL=<seconds * 1000>`.
- ADOT environment:
  `METRICS_COLLECTION_INTERVAL=<seconds>s`.

The conversion happens once in CDK. The Node SDK receives milliseconds while
the collector receives an OTel duration string. This is analogous to parsing
untrusted input into one typed value before passing destination-specific
representations inward.

Keep the following as deliberate demo constants rather than new caller-facing
toggles:

```text
RESERVATION_WORKER_MODE=fake-in-process
RESERVATION_FAILURE_INJECTION_MODE=stable-random-unexpected-error
RESERVATION_FAILURE_INJECTION_RATE=0.4
RESERVATION_FAILURE_INJECTION_SALT=aws-demo-managed-observability
```

The salt is deterministic configuration, not a credential.

### 6.3 CloudWatch Application Metrics

Create a stack-owned log group:

```text
/golden-path/aws-demo/movie-reservation-service/metrics
```

Use seven-day retention and `RemovalPolicy.DESTROY`. Grant the shared ECS task
role write access with the CDK log-group grant instead of attaching a broad
CloudWatch agent managed policy.

Configure `awsemf` with:

- Namespace:
  `GoldenPath/aws-demo/movie-reservation-service`.
- The explicit metrics log group.
- `NoDimensionRollup`.
- Disabled resource-to-telemetry conversion; add only the two curated identity
  dimensions with the attributes processor.
- Metric declarations for the ten known application instruments.

Create stable `ServiceName` and `Environment` dimensions from the same typed
CDK service/environment identity used to configure `service.name` and
`deployment.environment.name`. The pinned ADOT `v0.48.0` image does not include
the transform processor, as proven by real-image validation during PR 1.
Therefore, pass the two validated values to ADOT and add them with the supported
attributes processor while keeping EMF resource-to-telemetry conversion
disabled. This avoids promoting unrelated host/process resource attributes.
Use these metric-specific dimensions:

| Metric family | Additional CloudWatch dimensions |
| --- | --- |
| HTTP count/duration | `http_method`, `http_route`, `status_family` |
| GraphQL count/duration | `business_operation`, `graphql_operation_type`, `outcome` |
| GraphQL exceptions | `business_operation`, `exception_type` |
| Reservation request created | `business_operation` |
| Reservation claim | none |
| Reservation outcome/duration | `outcome` |
| Reservation exceptions | `exception_type` |

Do not include `reason` in CloudWatch dimensions because it is optional on
successful outcomes. AMP can retain the bounded `reason` label without forcing
CloudWatch to publish multiple dimension shapes.

Do not add a CloudWatch Metrics VPC endpoint. `awsemf` writes EMF events through
the existing CloudWatch Logs endpoint; CloudWatch derives custom metrics from
those events.

### 6.4 AMP And ECS Metrics

Create `AWS::APS::Workspace` through `aws_aps.CfnWorkspace` because the
installed CDK version exposes the service as an L1 CloudFormation construct.
Configure:

- Alias derived from platform and environment.
- Seven-day retention through `workspaceConfiguration`.
- Stack tags where supported.
- `RemovalPolicy.DESTROY`.

Pass the workspace's `attrPrometheusEndpoint` plus `remote_write` to ADOT
through an environment variable. Do not hardcode a workspace ID or endpoint.

Configure `prometheusremotewrite` with:

- `sigv4auth` service `aps`.
- The stack Region.
- `add_metric_suffixes: false` so existing dashboard metric names remain stable.
- Resource-to-telemetry conversion enabled for curated labels.
- Explicit bounded retry, sending queue, and timeout settings validated against
  the pinned ADOT image.

Grant only `aps:RemoteWrite` on the workspace ARN to the ECS task role.

Add one interface endpoint in the selected workload subnet for each of:

- `ec2.InterfaceVpcEndpointAwsService.PROMETHEUS_WORKSPACES`, the
  Prometheus-compatible AMP data plane.
- `ec2.InterfaceVpcEndpointAwsService.STS`, required for SigV4 remote write in a
  VPC without internet egress.

Set `AWS_STS_REGIONAL_ENDPOINTS=regional` for ADOT. Endpoint policies permit only
the required AMP remote-write and STS identity operations. Do not add the AMP
control-plane endpoint because the running task does not create or manage
workspaces.

Enable `awsecscontainermetrics` with the configured 30-second interval. Export
only task and container CPU/memory reserved and utilized metrics:

```text
ecs.task.cpu.reserved
ecs.task.cpu.utilized
ecs.task.memory.reserved
ecs.task.memory.utilized
container.cpu.reserved
container.cpu.utilized
container.memory.reserved
container.memory.utilized
```

Preserve bounded labels needed for aggregation:

```text
aws.ecs.cluster.name
aws.ecs.service.name
aws.ecs.task.family
container.name
cloud.region
```

Drop task ARN/ID, container ID, image ID/tag, timestamps, and other
instance-churn labels before remote write.

### 6.5 Container Insights

Change the ECS cluster to
`containerInsightsV2: ecs.ContainerInsights.ENHANCED`. This synthesizes the
cluster setting value `enhanced`.

Precreate the conventional performance log group:

```text
/aws/ecs/containerinsights/movie-reservation-platform-aws-demo/performance
```

Use seven-day retention and `RemovalPolicy.DESTROY`. Ensure creation/deletion
ordering leaves the log group in place while the cluster can publish and
deletes it after ECS publication stops.

Container Insights and ADOT intentionally duplicate CPU/memory coverage:

- CloudWatch proves the AWS-native platform view and supplies AWS-managed
  dimensions.
- AMP proves the Prometheus/OpenTelemetry path and remains available for PromQL.

The dashboard need not duplicate every graph from both sources. The smoke test,
not duplicated panels, proves that both routes work.

### 6.6 Amazon Managed Grafana

Create a customer-managed data-access role trusted by
`grafana.amazonaws.com`. Protect the trust policy with:

- `aws:SourceAccount` equal to the current account.
- `aws:SourceArn` matching
  `arn:<partition>:grafana:<region>:<account>:/workspaces/*`.

The wildcard avoids a CloudFormation cycle because the workspace needs the role
ARN during creation. The role grants:

- `aps:QueryMetrics`
- `aps:GetLabels`
- `aps:GetSeries`
- `aps:GetMetricMetadata`

Scope AMP data actions to the workspace ARN where the IAM action supports
resource scoping. Grant only the CloudWatch metric query/list operations and
`ec2:DescribeRegions` on `*`, because those APIs do not provide useful
resource-level scoping. Do not grant Logs, X-Ray, alarm, SNS, or write actions.

Create a one-entry IPv4 `AWS::EC2::PrefixList` containing
`platformConfig.allowedIngressCidr`. Use its ID in the Grafana workspace network
access control.

Create `AWS::Grafana::Workspace` through `aws_grafana.CfnWorkspace` with:

- `accountAccessType: CURRENT_ACCOUNT`
- `authenticationProviders: [AWS_SSO]`
- `permissionType: CUSTOMER_MANAGED`
- the customer-managed role ARN
- the customer-managed prefix-list ID
- no `dataSources` property, because CloudFormation-created,
  customer-managed workspaces do not use the console's service-managed
  provisioning property
- no `vpcConfiguration`, because the data sources are regional AWS managed
  services rather than private VPC endpoints
- no notification destinations
- no plugin administration

Output the workspace ID and HTTPS URL.

Human access is a separate layer from AWS data access:

1. Identity Center proves the human identity.
2. Managed Grafana assigns that user the Admin workspace role.
3. The Grafana service assumes the customer-managed IAM role to query metrics.

One layer does not substitute for another.

### 6.7 Manual Identity And Grafana Procedure

Before the first PR 3 deployment:

1. Enable AWS Organizations if the personal account is still standalone.
2. Enable an organization instance of IAM Identity Center in `eu-central-1`.
3. Keep the built-in Identity Center directory.
4. Create one named personal user, enroll a password and MFA, and avoid using
   root for normal access.

After deployment:

1. Open the Managed Grafana workspace authentication settings.
2. Assign the Identity Center user and make it Admin.
3. Sign in through the workspace's Identity Center button.
4. Add an Amazon Managed Service for Prometheus data source:
   - Region: `eu-central-1`
   - Workspace: the stack output workspace ID/endpoint
   - Authentication: workspace IAM role/default AWS SDK path
5. Add a CloudWatch data source for the current account and `eu-central-1`.
6. Test both data sources before importing the dashboard.
7. Import the repository dashboard and map its two data-source inputs.

Identity Center and Organizations are account-level foundations. They are not
removed by `cdk destroy`. Migrating to Google Workspace or Microsoft Entra ID
later is a change of Identity Center identity source with user/group and
assignment migration, not an extra social-login button.

### 6.8 Dashboard Contract

Store the source artifact at:

```text
ecs-infra/grafana/dashboards/movie-reservation-aws-overview.json
```

Use stable dashboard UID `movie-reservation-aws-overview`, a one-hour default
time range, 30-second refresh, and import-time inputs for the AMP and CloudWatch
data-source UIDs.

Build exactly 15 data panels under an overview row and four golden-signal rows:

| Row | Panels |
| --- | --- |
| Overview | GraphQL request rate; GraphQL error ratio; GraphQL p95 latency |
| Traffic | HTTP rate by route/status; GraphQL rate by business operation/outcome; reservation created/claimed/completed rate |
| Errors | HTTP 5xx rate; GraphQL error rate; reservation failures and diagnostic exception rate |
| Latency | HTTP p50/p95/p99; GraphQL p50/p95/p99; reservation processor p50/p95/p99 |
| Saturation | ECS CPU reserved/utilized; ECS memory reserved/utilized; running/desired task and ALB target-health state |

Rows are layout elements and do not count toward the 15 data panels.

Use AMP for application panels and ADOT ECS CPU/memory PromQL. Use CloudWatch for
running/desired task count, ALB health, and Container Insights evidence where
the AWS-native dimensions are more useful. Do not include tutorial text panels,
logs, traces, Loki, Tempo, X-Ray, DORA metrics, or placeholder metric-discovery
queries.

### 6.9 Outputs And Naming

Add CloudFormation outputs needed by humans and smoke tooling:

```text
CloudWatchApplicationMetricsNamespace
AmpWorkspaceId
AmpWorkspaceArn
AmpPrometheusEndpoint
GrafanaWorkspaceId
GrafanaWorkspaceUrl
```

Derive names from `platformName`, `serviceName`, and `environmentName`. Use
explicit physical names only for human-facing namespaces, log groups, workspace
aliases, and the prefix list. Allow CDK/CloudFormation to name internal roles,
policies, and endpoints unless a stable external workflow requires otherwise.

### 6.10 Failure Behavior

- The application remains essential and does not wait for ADOT startup.
- ADOT remains nonessential with its existing health check and ECS restart
  policy.
- CloudWatch, AMP, STS, or collector failures must not fail application health
  checks.
- Memory limiting occurs before batching.
- Export retries and queues are bounded; there is no persistent queue or WAL.
- A collector crash can leave a running task without telemetry after restart
  attempts are exhausted. The runbook must identify replacement/redeploy as the
  recovery action.
- Keep the existing task size for the first deployment. Inspect ADOT CPU,
  memory, restart count, health, and exporter errors under smoke traffic before
  changing task resources.

The future cluster-level collector service should provide a stable OTLP
endpoint, independent scaling, and a deliberate availability design. It is not
implemented here.

## 7. Alternatives Considered

### Alternative A: One Large Pull Request

- Pros: one deployment and one issue-closing review.
- Cons: combines three metric paths, IAM, networking, identity, Grafana, and a
  dashboard in one review.
- Decision: rejected. The review and rollback surface is too broad.

### Alternative B: More Than Three Small Pull Requests

- Pros: very narrow diffs.
- Cons: excessive branch/PR coordination and several slices that have little
  standalone value.
- Decision: rejected. Three PRs are the maximum useful split.

### Alternative C: AMP Only

- Pros: one application metric backend and PromQL everywhere.
- Cons: does not prove the AWS-native EMF route requested by #38.
- Decision: rejected. Application metrics intentionally use both destinations.

### Alternative D: CloudWatch Only

- Pros: fewer resources and lower setup complexity.
- Cons: does not prove Prometheus remote write or establish AMP as Grafana's
  primary application-metric source.
- Decision: rejected.

### Alternative E: SAML Or External IdP Now

- Pros: resembles an enterprise workforce federation setup.
- Cons: adds a directory tenant, SAML metadata/certificates, provisioning, and
  migration work for one personal user.
- Decision: rejected. Use the Identity Center directory now and migrate later
  only when a real external directory exists.

### Alternative F: Automate Grafana With Terraform Or API Calls

- Pros: repeatable data sources and dashboard provisioning.
- Cons: introduces a second state owner, tokens, or custom-resource lifecycle
  before the manual workflow is proven.
- Decision: deferred. Record a follow-up and compare options with explicit
  ownership and secret-lifecycle criteria.

### Alternative G: Essential ADOT Sidecar

- Pros: collector failure replaces the whole task and restores telemetry.
- Cons: collector/configuration failure can reduce application availability.
- Decision: rejected for the demo. Telemetry fails open.

### Alternative H: PrivateLink-Only Grafana Access

- Pros: no public Grafana workspace path.
- Cons: the laptop has no VPN or other path into the VPC.
- Decision: deferred with the broader networking redesign. Use CIDR-restricted
  public access plus Identity Center.

## 8. API / Interface Changes

### TypeScript/CDK Configuration

`PlatformConfig` and `PlatformConfigContext` gain
`metricsExportIntervalSeconds`. `resolvePlatformConfig` validates and defaults
the value. `ecs-infra/bin/infra.ts` reads the matching CDK context key.

### ECS Environment

The application changes from:

```text
OTEL_METRICS_EXPORTER=none
```

to:

```text
OTEL_METRICS_EXPORTER=otlp
OTEL_METRIC_EXPORT_INTERVAL=30000
RESERVATION_WORKER_MODE=fake-in-process
RESERVATION_FAILURE_INJECTION_MODE=stable-random-unexpected-error
RESERVATION_FAILURE_INJECTION_RATE=0.4
RESERVATION_FAILURE_INJECTION_SALT=aws-demo-managed-observability
```

ADOT receives Region, namespace, log-group, AMP endpoint, STS behavior, and
collection-interval environment variables from CDK. No secret values are
introduced.

### CloudFormation Outputs

The outputs in section 6.9 become the stable interface used by the smoke script
and manual Grafana setup.

### Smoke Script

Add `ecs-infra/scripts/managed-metrics-smoke.sh` with:

- `--self-test`
- `--stack STACK`
- `--base-url URL`
- `--report PATH`

Require explicit `AWS_PROFILE` and `AWS_REGION`, following the X-Ray smoke
script. The report is JSON and contains no credentials or request bodies.

### Application API

No HTTP, GraphQL, domain, or persistence contract changes.

## 9. Data Model / Persistence Changes

No application schema, migration, repository, or persistence changes.

Telemetry persistence changes are external:

- AMP retains metrics for seven days while the workspace exists.
- EMF and Container Insights log groups retain events for seven days.
- Grafana stores dashboard state only while the disposable workspace exists;
  the source JSON remains in Git.
- CloudWatch metric datapoints cannot be explicitly deleted. After publication
  stops they age out under AWS retention.

## 10. Security, Privacy, And Abuse Considerations

- Bind OTLP and collector health endpoints to task loopback only.
- Keep the application task in the isolated subnet without a public IP or NAT
  route.
- Add only AMP data-plane and regional STS endpoints required by the running
  collector.
- Restrict endpoint ingress to HTTPS from the service security group.
- Apply endpoint policies in addition to task-role IAM policies.
- Scope `aps:RemoteWrite` to the one AMP workspace.
- Scope EMF Logs writes to the explicit application metrics log group.
- The ECS task role is shared by app and sidecar because ECS applies one task
  role to the task. Document that the app process can technically use the
  sidecar's AWS permissions.
- Give the Grafana role read-only metric permissions and protect its trust with
  SourceAccount and SourceArn conditions.
- Keep human authentication, Grafana workspace role, and AWS data-source IAM
  permissions as distinct controls.
- Require Identity Center assignment; do not enable anonymous Grafana access.
- Restrict the Grafana endpoint with the same `/32`-style CIDR already used for
  ALB ingress.
- Do not place credentials, identity-store IDs, emails, tokens, API keys, or
  local `.env` values in Git.
- Never convert `trace_id`, `request_id`, `correlation_id`,
  `reservation_request_id`, `user_id`, raw GraphQL names, exception messages,
  task IDs, or container IDs into metric labels/dimensions.
- The single personal account becomes an Organizations management account. That
  is acceptable for this learning demo but is not the target multi-account
  production topology.
- Identity Center and Organizations have a broader lifecycle than
  `GoldenPathDemoStack`; teardown documentation must say so explicitly.

## 11. Performance, Scalability, And Reliability Considerations

- Dual application export intentionally duplicates ingestion and storage.
- Container Insights and ADOT ECS metrics intentionally duplicate selected
  platform signals.
- CloudWatch treats every unique dimension combination as a separate custom
  metric. Explicit metric declarations and `NoDimensionRollup` limit that
  multiplication.
- AMP series are bounded through instrument, resource-label, and ECS metric
  allowlists.
- A 30-second cadence balances demonstration feedback with ingestion volume.
  Dashboard CloudWatch queries should use periods supported by the stored
  resolution.
- Interface VPC endpoints add hourly per-endpoint/AZ cost. Keep them in the one
  workload AZ used by the service.
- Enhanced Container Insights and custom/embedded CloudWatch metrics incur
  usage charges only while data is published. The runbook must make prompt
  teardown normal.
- AMP uses a seven-day retention period instead of the 150-day service default.
- The nonessential sidecar prevents telemetry outages from cascading into
  application outages but permits silent telemetry loss after unrecovered
  collector failure.
- Bounded retry queues absorb short destination failures but deliberately drop
  data instead of exhausting task memory during a long outage.
- The current 128 CPU/384 MiB ADOT allocation is an assumption to measure, not a
  production sizing claim.
- One workload AZ and one task are accepted demo limitations.
- A future shared collector service needs service discovery, network policy,
  horizontal scaling, rollout compatibility, and high-availability decisions.

## 12. Implementation Steps

### PR 1: CloudWatch Application Metrics

Suggested branch: keep the existing
`issue-38_infra_managed-metrics-grafana` branch and placeholder PR for this
package.

PR issue link: `Refs #38`

1. Add typed metric cadence configuration.
   - Change: add/default/validate `metricsExportIntervalSeconds` and pass it from
     CDK context.
   - Files/modules likely affected:
     `ecs-infra/lib/config/platform-config.ts`,
     `ecs-infra/bin/infra.ts`, `ecs-infra/test/infra.test.ts`.
   - Notes: default 30; integer range 5 through 300.
   - Verification: focused config tests plus synth assertion for
     `OTEL_METRIC_EXPORT_INTERVAL=30000`.

2. Enable the existing demo worker and failure injection.
   - Change: set the five confirmed ECS environment values from section 8.
   - Files/modules likely affected: `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: no service source change; keep `NODE_ENV=development`.
   - Verification: task-definition assertions prove the worker, mode, rate, and
     nonsecret salt.

3. Add the EMF log group and least-privilege task permission.
   - Change: create the one-week disposable metrics log group and grant it write
     access to the task role.
   - Files/modules likely affected: `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: do not attach broad AWS-managed agent policies.
   - Verification: assertions cover name, retention, removal policy, role
     actions, and resource scope.

4. Add the CloudWatch application metric pipeline.
   - Change: enable OTLP metrics in the app; add destination shaping, batching,
     and `awsemf` to the collector.
   - Files/modules likely affected:
     `ecs-infra/adot-collector/adot-config.yaml`,
     `ecs-infra/scripts/validate-adot-image.sh`,
     `ecs-infra/lib/infra-stack.ts`.
   - Notes: preserve the trace pipeline exactly; use the explicit metric and
     dimension declarations from section 6.3.
   - Verification: the real ADOT image parses the combined trace/metric config
     and becomes healthy.

5. Add CloudWatch smoke support.
   - Change: generate bounded reservation traffic, poll terminal outcomes, then
     query a known application metric through CloudWatch.
   - Files/modules likely affected:
     `ecs-infra/scripts/managed-metrics-smoke.sh`,
     a focused script test if useful, `ecs-infra/package.json`.
   - Notes: self-tests remain credential-free; use CloudFormation outputs rather
     than hardcoded names.
   - Verification: self-test in CI; deployed smoke sees metric datapoints plus
     confirmed and failed/rejected reservation outcomes.

6. Update PR 1 documentation.
   - Change: document context, cost, deploy, smoke, diagnostics, rollback, and
     destroy for the CloudWatch-only intermediate state.
   - Files/modules likely affected:
     `docs/operations/aws-cdk-local-deployment.md`,
     `docs/operations/runbook.md`,
     `docs/architecture/ecs-fargate-deployment.md`.
   - Verification: inspect the documentation diff and any changed local links.

PR 1 merge gate:

- Credential-free infra CI passes.
- A laptop deployment sees the application metric in CloudWatch.
- Demo traffic produces useful reservation outcomes.
- X-Ray smoke still passes.
- `cdk destroy` removes the EMF log group and stops publication.

### PR 2: AMP And ECS Metrics

Suggested branch:
`issue-38_infra_amp-ecs-metrics`, created from updated `main` after PR 1 merges.

PR issue link: `Refs #38`

1. Provision AMP and outputs.
   - Change: add the L1 APS workspace, seven-day retention, removal policy, and
     outputs.
   - Files/modules likely affected: `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: construct the remote-write URL from the CloudFormation endpoint
     attribute.
   - Verification: assertions cover `AWS::APS::Workspace`, retention, deletion,
     and outputs.

2. Add the private AMP and STS network paths.
   - Change: add one-AZ interface endpoints, HTTPS ingress, private DNS, and
     narrow endpoint policies.
   - Files/modules likely affected: `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: use the installed CDK service constants; do not add the AMP control
     plane.
   - Verification: synthesized endpoints are `aps-workspaces` and regional STS,
     each in one workload subnet.

3. Add SigV4 remote write and task IAM.
   - Change: add `sigv4auth`, application AMP pipeline, bounded queue/retry, and
     workspace-scoped `aps:RemoteWrite`.
   - Files/modules likely affected:
     `ecs-infra/adot-collector/adot-config.yaml`,
     `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/scripts/validate-adot-image.sh`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: disable Prometheus metric suffix addition and preserve bounded
     application labels.
   - Verification: real-image validation plus IAM/resource assertions.

4. Add AMP ECS task/container metrics.
   - Change: configure `awsecscontainermetrics`, its eight-metric allowlist, and
     its bounded resource-label policy.
   - Files/modules likely affected:
     `ecs-infra/adot-collector/adot-config.yaml`,
     `ecs-infra/scripts/validate-adot-image.sh`.
   - Notes: drop per-task/container identity labels before remote write.
   - Verification: image validation and deployed PromQL for task and container
     CPU/memory.

5. Enable enhanced Container Insights.
   - Change: enable the enhanced cluster setting and own the one-week
     performance log group.
   - Files/modules likely affected: `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: preserve deletion ordering so publication stops before log-group
     deletion.
   - Verification: assertions show `containerInsights=enhanced`; deployed
     CloudWatch queries return task/container data.

6. Extend managed metric smoke and docs.
   - Change: verify the same application metric in CloudWatch and AMP, ECS
     metrics in AMP and CloudWatch, outcomes, and the existing X-Ray trace.
   - Files/modules likely affected:
     `ecs-infra/scripts/managed-metrics-smoke.sh`,
     `ecs-infra/package.json`,
     `docs/operations/aws-cdk-local-deployment.md`,
     `docs/operations/runbook.md`,
     `docs/architecture/ecs-fargate-deployment.md`.
   - Verification: self-tests plus deployed dual-route acceptance.

PR 2 merge gate:

- PR 1 CloudWatch and X-Ray checks still pass.
- The same application metric is queryable from CloudWatch and AMP.
- ECS task/container CPU and memory are queryable from AMP.
- Enhanced Container Insights data is queryable from CloudWatch.
- No unexpected high-cardinality labels appear in AMP.
- Destroy removes AMP, endpoints, performance logs, and stops all publishers.

### PR 3: Managed Grafana, Dashboard, And Final Operations

Suggested branch:
`issue-38_infra_managed-grafana-dashboard`, created from updated `main` after
PR 2 merges.

PR issue link: `Closes #38`

1. Document and perform the Identity Center prerequisite.
   - Change: add the organization-instance, built-in-directory, one-user,
     assignment, MFA, persistence, and future-migration procedure.
   - Files/modules likely affected:
     `docs/operations/aws-cdk-local-deployment.md`.
   - Notes: Identity Center enablement is manual and persists after stack
     destroy.
   - Verification: the user can sign into the Identity Center portal before the
     Grafana assignment step.

2. Add the Grafana customer-managed IAM role.
   - Change: create the trust policy and least-privilege AMP/CloudWatch read
     policies.
   - Files/modules likely affected: `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: no Logs, X-Ray, alarm, SNS, or write permissions.
   - Verification: CDK assertions inspect trust conditions, actions, and
     resource scopes.

3. Add CIDR-restricted Managed Grafana.
   - Change: create the one-entry prefix list, L1 Grafana workspace, network
     access control, Identity Center auth, customer-managed permission mode,
     and outputs.
   - Files/modules likely affected: `ecs-infra/lib/infra-stack.ts`,
     `ecs-infra/test/infra.test.ts`.
   - Notes: omit `vpcConfiguration`, `dataSources`, and alerts.
   - Verification: assertions cover all workspace properties and reject
     internet-wide ingress through the existing config boundary.

4. Add and validate the dashboard JSON.
   - Change: adapt the useful PoC golden-signal panels into the exact contract
     in section 6.8.
   - Files/modules likely affected:
     `ecs-infra/grafana/dashboards/movie-reservation-aws-overview.json`,
     a dashboard validation script, `ecs-infra/package.json`.
   - Notes: use import-time data-source inputs; do not hardcode workspace IDs or
     local data-source UIDs.
   - Verification: `jq` parsing and semantic checks for UID, panel count,
     allowed data-source types, and absence of Loki/Tempo/X-Ray references.

5. Complete the manual Grafana setup and visual acceptance.
   - Change: assign the Admin user, configure AMP and CloudWatch, import the
     dashboard, and check every panel under generated traffic.
   - Files/modules likely affected:
     `docs/operations/aws-cdk-local-deployment.md`,
     `docs/operations/runbook.md`.
   - Notes: record the deployed Grafana version and any manual setup caveats.
   - Verification: all 15 panels render expected data or an explicitly valid
     zero state; datasource test buttons pass.

6. Complete lifecycle documentation and archive the plan.
   - Change: document destroy checks, historical CloudWatch datapoint retention,
     and persistent Identity Center/Organizations resources.
   - Files/modules likely affected:
     `docs/index.md`,
     `docs/plans/movie-reservation-platform-roadmap.md`,
     `docs/plans/ecs-adot-managed-observability.md`,
     `docs/plans/production-observability-dashboard.md`,
     `docs/plans/delivered/README.md`,
     this plan moved to `docs/plans/delivered/`.
   - Notes: update #30's prerequisite as satisfied; do not claim CloudWatch
     datapoints can be deleted.
   - Verification: validate changed local links and inspect the documentation
     diff.

PR 3 merge gate:

- Identity Center user can authenticate and is assigned Grafana Admin.
- Grafana endpoint rejects clients outside the configured CIDR.
- AMP and CloudWatch data sources pass connection tests.
- The repository dashboard imports and all 15 panels are reviewed.
- Managed metric and X-Ray smoke checks pass.
- `cdk destroy` removes AMP, Grafana, prefix list, endpoints, roles, and owned
  log groups.
- No ECS/ADOT publisher remains.
- Identity Center/Organizations persistence and CloudWatch metric expiry are
  explicitly acknowledged.

## 13. Testing Strategy

### Credential-Free CI

Run on every PR:

```bash
npm -w ecs-infra run build
npm -w ecs-infra test -- --runInBand
npm -w ecs-infra run validate:adot-image
npm -w ecs-infra run validate:xray-smoke
npm -w ecs-infra run validate:managed-metrics-smoke
npm -w ecs-infra run validate:grafana-dashboard
npm -w ecs-infra run cdk -- synth \
  -c allowedIngressCidr=203.0.113.10/32
```

Add new validation scripts incrementally; a script appears in the command list
only after its PR introduces it.

Tests must cover:

- metric cadence default, valid override, noninteger, and range rejection;
- application metric environment values;
- worker/failure-injection environment values;
- EMF and Container Insights log-group retention/removal;
- cluster enhanced Container Insights setting;
- APS/Grafana/prefix-list resource properties;
- AMP/STS endpoint count, service names, subnet count, security groups, and
  endpoint policies;
- task-role and Grafana-role least privilege;
- Grafana trust-policy confused-deputy conditions;
- no NAT Gateway, public task IP, public collector port, RDS, or alarm resources;
- X-Ray exporter/IAM regression;
- ADOT image startup with every referenced receiver, processor, exporter, and
  extension;
- smoke helper parsing and failure messages without AWS calls;
- dashboard JSON syntax and semantic contract.

### Laptop AWS Acceptance

Use explicit `AWS_PROFILE` and `AWS_REGION=eu-central-1`:

1. Deploy the current PR's stack.
2. Confirm the ECS service and ADOT container are healthy.
3. Generate bounded GraphQL traffic using discovered screenings/seats.
4. Poll requests until terminal outcomes include both a confirmed result and a
   failure/rejection signal; fail with diagnostics if either is absent after the
   bounded attempt limit.
5. Wait through at least two export intervals.
6. Query `graphql_operation_total` in CloudWatch.
7. From PR 2 onward, query the same metric in AMP.
8. Query task and container CPU/memory in AMP.
9. Query enhanced Container Insights task/container metrics in CloudWatch.
10. Run the existing X-Ray smoke.
11. In PR 3, visually inspect every Grafana panel.
12. Inspect ADOT logs for permission, endpoint, retry, dropped-data, or OOM
    errors.
13. Save the smoke JSON report outside Git if evidence is needed.
14. Destroy the stack and execute the teardown checks.

The smoke must use bounded request counts and timeouts. It must not become a
load test.

### Regression Scope

No service tests are required solely for environment wiring because the worker,
failure injection, and metric instruments already have service coverage. Run
the service check if implementation changes service source or configuration
logic unexpectedly; such a change requires plan review first.

## 14. Rollout / Migration Plan

### Pull Request Sequence

1. Convert the existing placeholder PR into PR 1 and merge it to `main`.
2. Create PR 2's branch from the updated `main`; do not stack it on the PR 1
   branch.
3. Create PR 3's branch from the updated `main`; do not stack it on the PR 2
   branch.
4. Use `Refs #38` on PRs 1 and 2.
5. Use `Closes #38` only on PR 3.

### Deployment Sequence

- Deploy PR 1 and prove CloudWatch before introducing AMP.
- Deploy PR 2 and prove both metric paths before introducing Grafana.
- Complete Identity Center prerequisite before deploying PR 3.
- Deploy PR 3, assign the user, configure data sources, import the dashboard,
  and run visual acceptance.

### Rollback

- For a failed deployment, rely on the existing ECS deployment circuit breaker
  for task revisions, then inspect CloudFormation events.
- For a collector configuration failure, revert the relevant PR, redeploy the
  previous task definition, and confirm X-Ray/application health.
- For AMP export problems, remove the AMP pipeline/endpoints/workspace by
  reverting PR 2 or destroy the stack; CloudWatch PR 1 remains the last known
  metric path.
- For Grafana problems, remove/revert PR 3 without changing ingestion.
- For unexpected cost or an abandoned session, run `cdk destroy` immediately.

No application data migration or backward-compatibility shim is required.

### Teardown Acceptance

After `cdk destroy`:

- CloudFormation reports `GoldenPathDemoStack` absent.
- No AMP or Grafana workspace from the stack remains.
- No #38 VPC endpoints, prefix list, IAM role/policies, or owned log groups
  remain.
- No ECS task or ADOT collector remains to publish data.
- Identity Center and AWS Organizations remain intentionally.
- Under the pricing checked for this plan, Identity Center and Organizations
  have no standalone service charge; all resources and applications used
  through them remain subject to their own pricing.
- CloudWatch historical metric datapoints may remain queryable until AWS
  retention expires. They cannot be deleted and are not evidence of an active
  publisher.

## 15. Risks And Mitigations

| Risk | Impact | Likelihood | Mitigation |
| --- | ---: | ---: | --- |
| High-cardinality labels multiply CloudWatch/AMP cost | High | Medium | Fixed instrument, dimension, ECS metric, and resource-label allowlists; no caller-controlled labels |
| Dual routing duplicates ingestion cost | Medium | Certain | Accepted design; 30-second cadence, bounded traffic, seven-day AMP retention, prompt destroy |
| Enhanced Container Insights adds CloudWatch cost | Medium | Certain | One task, short-lived demos, explicit runbook warnings, destroy checks |
| ADOT image component/config incompatibility | High | Medium | Validate the pinned real image in every PR before deploy |
| AMP remote write fails in no-NAT VPC | High | Medium | `aps-workspaces` plus regional STS endpoints, regional STS mode, endpoint-policy tests |
| Task role becomes too broad | High | Low | Resource-scoped `aps:RemoteWrite`, log-group grant, no managed observability write policies |
| Shared task role lets app use sidecar permissions | Medium | Certain | Document ECS limitation; keep actions narrow; future collector service separates runtime identity |
| Grafana role can be assumed for another workspace/account | High | Low | `grafana.amazonaws.com` plus SourceAccount and wildcarded same-account workspace SourceArn |
| Grafana endpoint exposed beyond intended laptop | High | Low | Reuse validated non-world CIDR through a managed prefix list plus Identity Center auth |
| Public IP changes and locks out Grafana/ALB | Low | Medium | Refresh `allowedIngressCidr` and redeploy; revisit networking in follow-up |
| Identity Center Region conflicts with Grafana Region | High | Low | Enable the organization instance in `eu-central-1` before workspace deployment |
| Identity Center/Organizations mistaken for disposable resources | Medium | Medium | Explicit preflight and teardown warnings |
| Collector consumes more than 384 MiB | High | Medium | Memory limiter, bounded queues, smoke observation, measure before resizing |
| Nonessential collector dies while app remains healthy | Medium | Medium | ECS restart policy, collector health/log diagnostics, replacement procedure |
| Dashboard JSON hardcodes local data sources | Medium | Medium | Import-time data-source inputs and semantic JSON validation |
| Manual Grafana setup drifts | Medium | Medium | Versioned JSON plus exact runbook; automation follow-up after workflow is proven |
| CloudWatch metrics remain after destroy | Low | Certain | Explain non-deletable retention; verify publication stopped and paid resources removed |
| Management-account deployment does not model production isolation | Medium | Certain | Accept for personal demo; future multi-account/network redesign |

## 16. Done Criteria

- [ ] PR 1 is merged independently and proves application metrics in
  CloudWatch.
- [ ] PR 2 is merged independently and proves application plus ECS metrics in
  AMP and enhanced ECS metrics in CloudWatch.
- [ ] PR 3 is merged independently and closes #38.
- [ ] The application sends one OTLP metric stream and ADOT owns destination
  fan-out.
- [ ] All ten existing application instruments are available in CloudWatch and
  AMP with bounded dimensions/labels.
- [ ] The same application metric is queried successfully from both backends.
- [ ] ECS task/container CPU and memory are queryable from AMP.
- [ ] Enhanced Container Insights task/container metrics are queryable from
  CloudWatch.
- [ ] No forbidden high-cardinality identifiers are metric labels.
- [ ] The no-NAT topology has only the required new AMP and STS endpoints.
- [ ] Task IAM and endpoint policies are least privilege.
- [ ] The application remains available when telemetry export fails.
- [ ] Existing X-Ray smoke still passes.
- [ ] Identity Center uses the built-in directory in `eu-central-1`.
- [ ] One personal user can sign in to Grafana as Admin.
- [ ] Grafana network access is restricted to `allowedIngressCidr`.
- [ ] Grafana's IAM role can query only the required AMP/CloudWatch metric APIs.
- [ ] Both Grafana data sources pass connection tests.
- [ ] The 15-panel dashboard imports from versioned JSON and renders expected
  data.
- [ ] Public CI needs no AWS credentials.
- [ ] Laptop smoke automates traffic, CloudWatch, AMP, ECS metric, and outcome
  checks.
- [ ] No alarms, log/trace panels, SAML, Grafana API automation, RDS, NAT, or
  application metric additions entered scope.
- [ ] `cdk destroy` removes every stack-owned paid resource and publisher.
- [ ] Documentation explains persistent Identity Center/Organizations state and
  non-deletable CloudWatch metric history.
- [ ] The final plan is archived under `docs/plans/delivered/` and roadmap/index
  status is updated.

## 17. Review Checklist

- [x] Requirements are explicit.
- [x] Non-goals are explicit.
- [x] Existing code and documentation conventions were checked.
- [x] The three PR boundaries are independently deployable.
- [x] Alternatives were considered.
- [x] Security, identity, networking, IAM, and cardinality were reviewed.
- [x] Performance, cost, scalability, and reliability implications were
  reviewed.
- [x] Credential-free and deployed testing strategies are complete.
- [x] Rollout, rollback, and teardown are defined.
- [x] CloudWatch's non-deletable metric lifecycle is explicit.
- [x] No blocking open questions remain.

## 18. Handoff Prompt For Implementation Agent

```text
Implement the next uncompleted pull-request package in
docs/plans/ecs-adot-managed-metrics-grafana.md.

Important sequencing:
- Implement only one PR package in this branch.
- PR 1 uses the existing issue-38_infra_managed-metrics-grafana branch.
- PR 2 and PR 3 must each start from updated main after the previous PR merges.
- PR 1 and PR 2 use "Refs #38"; PR 3 uses "Closes #38".

Constraints:
- Stay within the selected PR package and the confirmed design.
- Do not introduce new dependencies unless the plan explicitly allows it.
- Do not change domain, application, GraphQL, HTTP, or persistence behavior.
- Preserve the existing X-Ray pipeline and no-NAT/private-task topology.
- Keep all metric labels/dimensions bounded and explicitly allowlisted.
- Keep ADOT nonessential and telemetry fail-open.
- Keep public CI credential-free.
- Use the installed CDK types and validate the pinned real ADOT image.
- Update only the tests and docs owned by the selected PR package.
- Do not automate Identity Center or Grafana APIs in #38.
- If AWS/CDK/ADOT behavior differs from the plan, stop and update the plan or ask
  for approval before expanding scope.

Primary files/modules:
- ecs-infra/lib/config/platform-config.ts
- ecs-infra/bin/infra.ts
- ecs-infra/lib/infra-stack.ts
- ecs-infra/adot-collector/adot-config.yaml
- ecs-infra/scripts/validate-adot-image.sh
- ecs-infra/scripts/managed-metrics-smoke.sh
- ecs-infra/test/infra.test.ts
- ecs-infra/package.json
- ecs-infra/grafana/dashboards/movie-reservation-aws-overview.json
- docs/architecture/ecs-fargate-deployment.md
- docs/operations/aws-cdk-local-deployment.md
- docs/operations/runbook.md

Run the narrowest checks while iterating. Before handoff, run all
credential-free checks introduced up to the selected PR and report which laptop
AWS acceptance steps were or were not run.
```

## Primary References

- [ADOT CloudWatch metrics](https://aws-otel.github.io/docs/getting-started/cloudwatch-metrics/)
- [ADOT Prometheus remote write for AMP](https://aws-otel.github.io/docs/getting-started/prometheus-remote-write-exporter/)
- [ADOT ECS container metrics receiver](https://aws-otel.github.io/docs/components/ecs-metrics-receiver/)
- [AMP interface VPC endpoints](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-and-interface-VPC.html)
- [ECS enhanced Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-enhanced-observability-metrics-ECS.html)
- [Managed Grafana network access control](https://docs.aws.amazon.com/grafana/latest/userguide/AMG-configure-nac.html)
- [Managed Grafana customer-managed permissions](https://docs.aws.amazon.com/grafana/latest/userguide/AMG-manage-permissions.html)
- [Managed Grafana confused-deputy prevention](https://docs.aws.amazon.com/grafana/latest/userguide/cross-service-confused-deputy-prevention.html)
- [Managed Grafana with IAM Identity Center](https://docs.aws.amazon.com/grafana/latest/userguide/authentication-in-AMG-SSO.html)
- [IAM Identity Center pricing FAQ](https://aws.amazon.com/iam/identity-center/faqs/)
- [AWS Organizations pricing](https://docs.aws.amazon.com/organizations/latest/userguide/pricing.html)
- [CloudWatch metric lifecycle](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html)

Planning also used the local Programming KB notes `AWS VPC Endpoints`,
`ECS Task Definitions and Container Definitions`, `AWS IAM Identity Center`,
`Identity Federation`, and
`Prefer the IAM Identity Center Directory for Personal AWS Access`.
