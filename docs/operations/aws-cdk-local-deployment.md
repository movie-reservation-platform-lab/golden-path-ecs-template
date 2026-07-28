# Local AWS CDK Deployment Runbook

This runbook deploys `GoldenPathDemoStack` from a developer laptop into an
existing personal AWS account, verifies the NestJS service, and removes the
deployed application resources afterward.

The current stack is a learning/demo environment, not a production deployment.
It creates resources that incur charges while they exist, including one Fargate
task, an Application Load Balancer, six interface VPC endpoints, CloudWatch
Logs/custom/enhanced Container Insights metrics, an AMP workspace, and an
Amazon Managed Grafana workspace.

## Identity recommendation

Do not create a dedicated IAM user or access key specifically for CDK
bootstrapping.

For this personal demo, use:

1. The **existing personal AWS account** that was created with your email
   address and payment details.
2. The root user only for initial account security and creation of a day-to-day
   administrator identity.
3. One IAM administrator user representing you, with console access and MFA but
   no access keys.
4. AWS CLI v2 `aws login`, which uses the IAM user's console login to give the
   laptop temporary credentials.
5. An organization instance of IAM Identity Center with its built-in directory
   for the one human who signs in to Managed Grafana.

The IAM user is your normal human administrator, not a special CDK identity.
CDK bootstrapping creates the deployment, asset-publishing, lookup, and
CloudFormation execution roles that CDK will use in the account and Region.

The default CDK bootstrap is powerful: its CloudFormation execution role has
`AdministratorAccess` unless it is explicitly constrained. That tradeoff is
acceptable for a personal learning account, but it is not the desired final
setup for a shared or production account. In a managed organization, ask the
platform/security owner to provide a constrained bootstrap and deployment role
instead of changing their existing `CDKToolkit` stack.

## CDK lifecycle mental model

| Phase       | Where it runs                      | What it does                                                                                                                                              |
| ----------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `synth`     | Laptop                             | Executes the TypeScript CDK app and writes a CloudFormation template and asset metadata under `ecs-infra/cdk.out/`. It changes no AWS resources.          |
| `bootstrap` | Laptop CLI plus AWS CloudFormation | Once per account/Region, deploys the `CDKToolkit` stack containing an S3 asset bucket, ECR asset repository, IAM roles, and an SSM version parameter.     |
| `deploy`    | Laptop CLI plus AWS CloudFormation | Builds the app and ADOT Docker images locally, publishes them to the bootstrap ECR repository, and asks CloudFormation to create or update `GoldenPathDemoStack`. |
| `destroy`   | Laptop CLI plus AWS CloudFormation | Deletes resources owned by `GoldenPathDemoStack`. It does not delete the separate `CDKToolkit` stack or all assets stored by that stack.                  |

The CDK code in
[`ecs-infra/lib/infra-stack.ts`](../../ecs-infra/lib/infra-stack.ts) is the model,
the synthesized template is the deployment contract, and CloudFormation owns
the deployed resource lifecycle.

## One-time AWS console setup

### 1. Select the account and Region

In this runbook, **the account** means the personal AWS account you already
have. You do not need to create another account. The final #38 slice does,
however, require that account to become the AWS Organizations management
account so it can host an organization instance of IAM Identity Center for
Managed Grafana login.

Sign in to the existing account and record its 12-digit account ID from the
account menu in the upper-right corner of the AWS console. This account ID will
be used as an explicit guard in the CDK bootstrap command.

Choose one deployment Region and keep using it. `eu-central-1` is a reasonable
example for Central Europe, but use the Region allowed by the account owner.
CDK bootstrapping is scoped to an account/Region pair, so a different Region
needs a separate bootstrap.

This stack uses fixed physical names such as `aws-demo-backend` and
`movie-reservation-platform-aws-demo`. Deploy only one copy in a given
account/Region unless the stack is first changed to parameterize those names.

### 2. Secure the root user

In each personally owned AWS account:

1. Sign in as root only for initial account security tasks that require it.
2. Open **Security credentials**.
3. Register MFA for the root user.
4. Confirm that the root user has no access keys.
5. Sign out and use the day-to-day IAM administrator for normal work.

Never configure root credentials on the laptop and never use root to run CDK.

### 3. Create your day-to-day administrator

Use the root user once to create an IAM identity for normal work:

1. Open **IAM > User groups** and create `PersonalAdministrators`.
2. Attach the AWS-managed `AdministratorAccess` and
   `SignInLocalDevelopmentAccess` policies to the group.
3. Open **IAM > Users** and create a user representing you.
4. Enable AWS Management Console access for the user and add it to
   `PersonalAdministrators`.
5. Do not create an access key for the user.
6. Sign out as root and sign in as the new IAM user.
7. Open the IAM user's **Security credentials** and register MFA.

`SignInLocalDevelopmentAccess` allows the browser-based `aws login` flow used
later. That flow supplies temporary CLI credentials, so no access key is stored
on the laptop.

`AdministratorAccess` is broad. It is the pragmatic starting point because the
first bootstrap creates IAM roles and the demo stack creates resources across
CloudFormation, IAM, ECS, EC2, ELB, Logs, ECR, S3, and SSM. Reducing these
permissions after the first deployment is a worthwhile follow-up exercise.

### 4. Add cost visibility before deploying

In **Billing and Cost Management > Budgets**:

1. Create a monthly cost budget for the personal account.
2. Choose a deliberately small amount appropriate for the experiment.
3. Add actual-spend notifications at useful thresholds, for example 50%, 80%,
   and 100%.
4. Add a forecasted-spend notification.
5. Send notifications to an email address that is actively monitored.

A budget is delayed cost telemetry, not a real-time spending cap or an
automatic substitute for `cdk destroy`.

### 5. Enable Organizations and IAM Identity Center

This is an account-level prerequisite, not part of
`GoldenPathDemoStack`. Complete it before the first Managed Grafana deployment:

1. In **AWS Organizations**, create an organization if the account is still
   standalone. Keep the existing personal account as its management account.
2. In Region `eu-central-1`, open **IAM Identity Center** and enable an
   organization instance.
3. Keep the built-in Identity Center directory; do not add SAML or an external
   identity provider for this one-user demo.
4. Create one named personal user with an actively monitored email address.
5. Complete password enrollment and require MFA for that user.
6. Sign in to the AWS access portal once before deploying Grafana. No Grafana
   application appears until the workspace exists and the user is assigned.

Do not use root as the Grafana user and do not put the Identity Store ID, user
email, enrollment link, password, or MFA material in Git. AWS Organizations,
IAM Identity Center, its directory user, and MFA enrollment persist after
`cdk destroy`; they have a broader lifecycle than this disposable stack.

## One-time laptop setup

The commands below assume macOS/Linux with Bash or Zsh and start at the
repository root.

Required tools:

- Node.js 24, matching `.nvmrc`;
- npm;
- AWS CLI v2 version 2.32.0 or newer, which supports browser-based
  `aws login`;
- Docker with a running daemon;
- `curl` for discovering the laptop's public IPv4 address and smoke checks;
- `awscurl` for SigV4-signed AMP acceptance queries with the named AWS profile.

Use the official AWS CLI v2 installation instructions for the laptop operating
system. Do not install a global CDK CLI; this repository pins the CLI through
the `ecs-infra` workspace. Install `awscurl` using the platform-supported method
from the official AMP instructions (`brew install awscurl` on macOS or a
Python package installation on Linux). The smoke passes only the named profile;
do not put raw access keys in its command line or report.

Install repository dependencies and inspect the tool versions:

```bash
nvm use
npm ci

node --version
npm --version
aws --version
docker --version
awscurl --help
npm -w ecs-infra run cdk -- --version
```

`deploy` requires the Docker daemon because
[`DockerImageAsset`](../../ecs-infra/lib/infra-stack.ts) builds the NestJS app
and repository-owned ADOT images on the laptop before publishing them to ECR.

### Configure a browser-login profile

Create a named AWS CLI profile and start the browser authentication flow:

```bash
aws login --profile movie-reservation-platform-cdk
```

When prompted, choose a default workload Region such as `eu-central-1`. The
browser should be signed in as the MFA-protected IAM administrator created in
the previous section, not as root.

AWS CLI caches temporary, automatically refreshed credentials for this login
session. It does not create a long-lived access key.

Verify the caller:

```bash
aws sts get-caller-identity --profile movie-reservation-platform-cdk
```

Read the returned `Account` and `Arn`. They must identify the intended personal
account and IAM user before continuing.

## Start a deployment session

Open a fresh shell at the repository root and set explicit session values:

```bash
export AWS_PROFILE=movie-reservation-platform-cdk
export AWS_REGION=eu-central-1
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID=123456789012

aws login --profile "$AWS_PROFILE"
aws sts get-caller-identity --profile "$AWS_PROFILE"
```

Replace the account ID and Region. Type the account ID that was independently
verified in the console and `get-caller-identity`; do not blindly derive the
deployment target from whichever credentials happen to be active.

Discover the current public IPv4 address and express it as a single-host CIDR:

```bash
export ALLOWED_INGRESS_CIDR="$(curl -4 --fail --silent --show-error https://checkip.amazonaws.com)/32"
printf 'Account: %s\nRegion: %s\nIngress: %s\n' \
  "$AWS_ACCOUNT_ID" "$AWS_REGION" "$ALLOWED_INGRESS_CIDR"
```

The current configuration rejects `0.0.0.0/0`. The `/32` lets only this public
IPv4 address reach the ALB listener on port 80. Refresh the value after changing
Wi-Fi networks, enabling or disabling a VPN, or receiving a new public IP.

Application metrics export every 30 seconds by default. The optional
`metricsExportIntervalSeconds` CDK context accepts an integer from `5` through
`300`; append, for example, `-c metricsExportIntervalSeconds=45` to every CDK
command in a session when testing a nondefault cadence. The value becomes
milliseconds for the Node.js OTel SDK and an OTel duration for ADOT. The
commands below intentionally use the default.

## Bootstrap the account and Region

Bootstrap once for each account/Region pair. If `CDKToolkit` already exists in
a centrally managed account, do not replace or reconfigure it without its
owner's approval.

For the personal learning account, make the broad default execution policy
explicit:

```bash
npm -w ecs-infra run cdk -- bootstrap \
  "aws://${AWS_ACCOUNT_ID}/${AWS_REGION}" \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR" \
  --cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess \
  --termination-protection
```

Expected shape:

```shell
 ⏳  Bootstrapping environment aws://123456789012/eu-central-1...
Trusted accounts for deployment: (none)
Trusted accounts for lookup: (none)
Execution policies: arn:aws:iam::aws:policy/AdministratorAccess
CDKToolkit: creating CloudFormation changeset...
 ✅  Environment aws://123456789012/eu-central-1 bootstrapped.
```

This context flag is required here even though bootstrapping creates the
account-level `CDKToolkit` stack, because the CDK CLI still starts this CDK app
before it performs the bootstrap operation. The app validates
`allowedIngressCidr` during startup.

Do not add `--trust` for this local, same-account workflow. That option grants
another account permission to use the bootstrap roles.

Bootstrapping is idempotent: running the same default bootstrap again updates
an old bootstrap template or makes no change. Verify it:

```bash
aws cloudformation describe-stacks \
  --stack-name CDKToolkit \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'Stacks[0].{Name:StackName,Status:StackStatus,Protection:EnableTerminationProtection}'

aws ssm get-parameter \
  --name /cdk-bootstrap/hnb659fds/version \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'Parameter.Value' \
  --output text
```

Keep termination protection enabled on `CDKToolkit`. The application stack is
the disposable unit, not the account-wide bootstrap foundation.

## Validate and synthesize

Run the narrow infrastructure checks:

```bash
npm -w ecs-infra run build
npm -w ecs-infra test -- --runInBand
npm -w ecs-infra run validate:adot-image
npm -w ecs-infra run validate:xray-smoke
npm -w ecs-infra run validate:managed-metrics-smoke
npm -w ecs-infra run validate:grafana-dashboard
```

List and synthesize the stack:

```bash
npm -w ecs-infra run cdk -- list \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR"

npm -w ecs-infra run cdk -- synth GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR"
```

Expected stack ID:

```text
GoldenPathDemoStack
```

The generated CloudFormation template is:

```text
ecs-infra/cdk.out/GoldenPathDemoStack.template.json
```

Synthesis changes no AWS resources. Review the template when learning which L2
constructs expand into VPC, subnet, route, security group, endpoint, ECS, IAM,
load balancer, and log resources.

## Review the deployment diff

```bash
npm -w ecs-infra run cdk -- diff GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR"
```

For the initial deployment, expect an entirely new stack. For the final #38
slice on top of PR #42, expect one Managed Grafana workspace, one single-entry
IPv4 managed prefix list containing `ALLOWED_INGRESS_CIDR`, one customer-managed
Grafana data-access role, and two Grafana outputs. The existing AMP, endpoint,
Container Insights, task-role, and task-definition resources should otherwise
remain stable.

Stop if the diff targets the wrong account/Region, opens the prefix list beyond
the intended `/32`, adds NAT or a Grafana VPC endpoint, configures Grafana
service-managed data sources, adds alarms, removes an unexpected resource, or
grants the Grafana role Logs, X-Ray, alarm, SNS, write, or wildcard-action
permissions. The intended role can query only the stack AMP workspace,
CloudWatch metrics, and the EC2 Region list.

## Deploy

Confirm Docker is running:

```bash
docker info
```

Then deploy:

```bash
npm -w ecs-infra run cdk -- deploy GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR" \
  --require-approval broadening
```

Read the approval prompt and CloudFormation changes before confirming. Do not
use `--require-approval never` for an interactive laptop deployment.

During deployment, CDK:

1. synthesizes the stack again;
2. builds the repository's app and pinned ADOT Docker images;
3. assumes the bootstrap image-publishing role and pushes both assets to the
   bootstrap ECR repository;
4. submits the CloudFormation change set;
5. waits while CloudFormation creates the network, endpoints, ECS service, ALB,
   and supporting resources.

The earlier stack was successfully deployed and destroyed from a laptop on
2026-07-17. That evidence predates the current AMP/ECS-metrics slice, whose
deployed acceptance must still be run. A successful deploy has this shape
(account-specific values are placeholders):

```shell
GoldenPathDemoStack: deploying... [1/1]
GoldenPathDemoStack: creating CloudFormation changeset...

 ✅  GoldenPathDemoStack

Outputs:
GoldenPathDemoStack.AmpPrometheusEndpoint = https://aps-workspaces.eu-central-1.amazonaws.com/workspaces/<workspace-id>/api/v1/
GoldenPathDemoStack.AmpWorkspaceArn = arn:aws:aps:eu-central-1:123456789012:workspace/<workspace-id>
GoldenPathDemoStack.AmpWorkspaceId = <workspace-id>
GoldenPathDemoStack.CloudWatchApplicationMetricsNamespace = GoldenPath/aws-demo/movie-reservation-service
GoldenPathDemoStack.EcsClusterName = movie-reservation-platform-aws-demo
GoldenPathDemoStack.EcsServiceName = movie-reservation-service
GoldenPathDemoStack.GrafanaWorkspaceId = <grafana-workspace-id>
GoldenPathDemoStack.GrafanaWorkspaceUrl = https://<grafana-workspace-endpoint>
GoldenPathDemoStack.LoadBalancerDnsName = <generated-alb-name>.eu-central-1.elb.amazonaws.com
Stack ARN:
arn:aws:cloudformation:eu-central-1:123456789012:stack/GoldenPathDemoStack/<generated-id>
```

## Verify the deployment

Confirm that the service reached a stable state:

```bash
aws ecs wait services-stable \
  --cluster movie-reservation-platform-aws-demo \
  --services movie-reservation-service \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

Read the ALB DNS name from the CloudFormation output:

```bash
export ALB_DNS_NAME="$(aws cloudformation describe-stacks \
  --stack-name GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerDnsName'].OutputValue | [0]" \
  --output text)"

export AMP_WORKSPACE_ID="$(aws cloudformation describe-stacks \
  --stack-name GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='AmpWorkspaceId'].OutputValue | [0]" \
  --output text)"

export GRAFANA_WORKSPACE_ID="$(aws cloudformation describe-stacks \
  --stack-name GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='GrafanaWorkspaceId'].OutputValue | [0]" \
  --output text)"

export GRAFANA_WORKSPACE_URL="$(aws cloudformation describe-stacks \
  --stack-name GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "Stacks[0].Outputs[?OutputKey=='GrafanaWorkspaceUrl'].OutputValue | [0]" \
  --output text)"

printf 'http://%s\n' "$ALB_DNS_NAME"
printf '%s\n' "$GRAFANA_WORKSPACE_URL"
curl --fail --show-error "http://${ALB_DNS_NAME}/health"
```

The endpoint is intentionally HTTP-only for this demo and is restricted to
`ALLOWED_INGRESS_CIDR`. It is not suitable for credentials or production data.

Expected health output:

```shell
http://<generated-alb-name>.eu-central-1.elb.amazonaws.com
{"status":"ok"}
```

### Inspect recent application logs

```bash
aws logs tail \
  /golden-path/aws-demo/movie-reservation-service/app \
  --since 10m \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

Use `--follow` while exercising the API, then press Ctrl-C to stop following.

Expected startup events include mapped `/health`, `/ready`, and `/graphql`
routes plus `Nest application successfully started`. A representative JSON log
line looks like:

```shell
<timestamp> app/movie-reservation-service/<task-id> {"level":30,"service_name":"movie-reservation-service","event":"nest.log","message":"Nest application successfully started"}
```

### Inspect collector health and logs

Read the running task and both container states:

```bash
export TASK_ARN="$(aws ecs list-tasks \
  --cluster movie-reservation-platform-aws-demo \
  --service-name movie-reservation-service \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'taskArns[0]' \
  --output text)"

aws ecs describe-tasks \
  --cluster movie-reservation-platform-aws-demo \
  --tasks "$TASK_ARN" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'tasks[0].containers[].{Name:name,Status:lastStatus,Health:healthStatus,ExitCode:exitCode,Reason:reason}' \
  --output table
```

The app must be `RUNNING`. ADOT should be `RUNNING` and `HEALTHY`, but it is
intentionally nonessential: its health does not gate task/service health. An
unhealthy live collector is not automatically restarted; the restart policy
applies after the collector process exits and ran for at least 60 seconds.

Tail collector diagnostics separately from application JSON logs:

```bash
aws logs tail \
  /golden-path/aws-demo/movie-reservation-service/adot \
  --since 10m \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

Expected startup entries name the OTLP and ECS container-metrics receivers,
memory limiter, filter/resource/attributes/batch processors, X-Ray, CloudWatch
EMF, and Prometheus remote-write exporters, SigV4 extension, and health
extension. Permission, endpoint, retry, and export failures also appear here.
The collector remains nonessential, so a healthy application does not prove
any telemetry destination is receiving data.

### Run the deterministic X-Ray smoke

```bash
npm -w ecs-infra run smoke:xray -- \
  --stack GoldenPathDemoStack \
  --report /tmp/golden-path-xray-smoke.json
```

The script sends the named read-only `ObservabilitySmokeMovies` GraphQL query,
then polls `BatchGetTraces` for the exact generated trace ID and requires a
`movie-reservation-service` segment. The structured report contains the W3C
`traceparent`, X-Ray trace ID, request/correlation IDs, target, and timing, but
no account ID, user ID, response body, or credentials. It exits nonzero for
HTTP, GraphQL, X-Ray query, trace timeout, or wrong-service-segment failures.

`BatchGetTraces` is the issue #37 smoke contract. If X-Ray Transaction Search
is enabled in the account, AWS documents that this API cannot retrieve those
traces; revisit the smoke query before enabling that account feature.

### Run the managed-metrics dual-route smoke

```bash
npm -w ecs-infra run smoke:managed-metrics -- \
  --stack GoldenPathDemoStack \
  --report /tmp/golden-path-managed-metrics-smoke.json
```

The script reads the ALB, CloudWatch namespace, AMP endpoint, ECS cluster, and
ECS service from stack outputs. It discovers a real screening and its seats and
submits at most 12 reservation requests. It rotates through seats until a
request confirms, then reuses that confirmed seat to produce either a failure
from the deterministic 40% injection policy or a rejection because the seat is
already reserved.

After two default export intervals, the smoke polls three contracts:

1. CloudWatch contains `graphql_operation_total`.
2. A profile-aware SigV4 `awscurl` query finds that application metric plus all
   eight allowlisted task/container CPU and memory metrics in AMP. It requires
   the stable application and ECS labels and rejects task/container identity,
   image, and timestamp labels.
3. CloudWatch contains task/container CPU and memory utilization through
   enhanced Container Insights.

The JSON report contains only aggregate outcome, datapoint, and series counts,
the namespace, metric name, target, Region, and timing. It excludes request
IDs, seat IDs, response bodies, account IDs, AMP series labels, and credentials.
A failure stage distinguishes stack output, traffic, CloudWatch application
metric, AMP query/contract, and Container Insights failures.

When deploying with a nondefault metric cadence, set the pre-query wait to at
least two intervals:

```bash
MANAGED_METRICS_SMOKE_SETTLE_SECONDS=90 \
  npm -w ecs-infra run smoke:managed-metrics -- --stack GoldenPathDemoStack
```

Run the existing X-Ray smoke separately; the two reports together are the
metric-ingestion acceptance evidence.

### Complete the manual Managed Grafana setup

CloudFormation creates the workspace and its AWS data-access role, but it does
not create a human assignment, data sources, or dashboard through the Grafana
API. Keep those control planes separate for this first proof.

First record the AWS-selected Grafana version and confirm the workspace is
active:

```bash
aws grafana describe-workspace \
  --workspace-id "$GRAFANA_WORKSPACE_ID" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'workspace.{Status:status,Version:grafanaVersion,Endpoint:endpoint}' \
  --output table
```

Then use the AWS console:

1. Open **Amazon Managed Grafana > All workspaces** and select the stack output
   workspace.
2. Under **Authentication**, assign the Identity Center user created during
   one-time setup.
3. Change that user's workspace role to **Admin**. Identity Center
   authentication and Grafana workspace authorization are separate controls.
4. Open `GRAFANA_WORKSPACE_URL`, choose the Identity Center sign-in path, and
   complete MFA.

Inside Grafana, add the two imported data sources:

1. Add a **Prometheus** data source for AMP.
   - URL: the `AmpPrometheusEndpoint` CloudFormation output.
   - Authentication provider: the workspace/default AWS SDK credentials.
   - Enable SigV4 authentication for service `aps`.
   - Default Region: `eu-central-1`.
2. Add a **CloudWatch** data source.
   - Authentication provider: the workspace/default AWS SDK credentials.
   - Default Region: `eu-central-1`.
   - Do not add CloudWatch Logs or X-Ray permissions to make unrelated query
     modes work; this role is metrics-only.
3. Use **Save & test** for AMP and require it to pass. Save the CloudWatch data
   source, then verify a metric query such as `RunningTaskCount` in **Explore**.
   Grafana's CloudWatch health check also probes CloudWatch Logs and can
   therefore report a Logs authorization error for this deliberately
   metrics-only role. Do not add Logs permissions to turn that health check
   green; a successful `GetMetricData` panel is the acceptance check.

Import
[`movie-reservation-aws-overview.json`](../../ecs-infra/grafana/dashboards/movie-reservation-aws-overview.json)
and map `DS_AMP` to the AMP Prometheus data source and `DS_CLOUDWATCH` to the
CloudWatch data source. The repository validator enforces the stable dashboard
UID, one-hour range, 30-second refresh, five golden-signal rows, exactly 15
data panels, and the absence of log/trace data sources.

Run the managed-metrics smoke immediately before visual acceptance so the
one-hour window contains bounded demo traffic. Review all 15 panels:

- overview shows GraphQL rate, error ratio, and p95 latency;
- traffic shows HTTP, GraphQL, and reservation workflow activity;
- errors may show a valid zero for a bounded series, but must not show a broken
  query or data-source error;
- latency shows p50, p95, and p99 for all three application boundaries;
- saturation shows AMP task CPU/memory plus CloudWatch desired/running task and
  ALB healthy/unhealthy target state.

If the account contains other ALBs, confirm the CloudWatch target-health series
labels belong to `aws-demo-backend`; the dashboard intentionally uses wildcard
dimension values because the ALB and target-group dimensions include
CloudFormation-generated suffixes.

Finally, prove both access-control layers:

1. From the laptop whose public IPv4 is in `ALLOWED_INGRESS_CIDR`, the workspace
   URL reaches Identity Center and the assigned user can sign in.
2. From a client outside that CIDR, the same workspace endpoint returns
   `403 Forbidden` before authentication. A phone on mobile data is sufficient
   for this manual negative check; do not add its CIDR to the prefix list.

## Redeploy after a change

For later iterations, start a new deployment session, verify the identity,
refresh `ALLOWED_INGRESS_CIDR`, and run:

```bash
npm -w ecs-infra run build
npm -w ecs-infra test -- --runInBand
npm -w ecs-infra run validate:adot-image
npm -w ecs-infra run validate:xray-smoke
npm -w ecs-infra run validate:managed-metrics-smoke
npm -w ecs-infra run validate:grafana-dashboard

npm -w ecs-infra run cdk -- diff GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR"

npm -w ecs-infra run cdk -- deploy GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR" \
  --require-approval broadening
```

CDK uses the Docker asset hash, so an unchanged image asset does not need to be
rebuilt and republished.

## Destroy the application stack

Destroy the stack as soon as the experiment is finished. First re-authenticate
and verify the target:

```bash
aws login --profile "$AWS_PROFILE"
aws sts get-caller-identity --profile "$AWS_PROFILE"
printf 'Destroy target: aws://%s/%s\n' "$AWS_ACCOUNT_ID" "$AWS_REGION"
```

Capture the generated Grafana role name before CloudFormation removes the
stack:

```bash
export GRAFANA_ROLE_NAME="$(aws cloudformation list-stack-resources \
  --stack-name GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "StackResourceSummaries[?ResourceType=='AWS::IAM::Role' && contains(LogicalResourceId, 'GrafanaDataAccessRole')].PhysicalResourceId | [0]" \
  --output text)"
```

Then request stack deletion:

```bash
npm -w ecs-infra run cdk -- destroy GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR"
```

The CIDR is still required because `destroy` executes the CDK app before it
selects the stack. Read the prompt carefully and confirm only
`GoldenPathDemoStack`.

CDK waits for CloudFormation, but this explicit waiter is useful after a
terminal disconnect (or use tmux):

```bash
aws cloudformation wait stack-delete-complete \
  --stack-name GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

Expected delete output:

```shell
Are you sure you want to delete: GoldenPathDemoStack (y/n) y
GoldenPathDemoStack: destroying... [1/1]

 ✅  GoldenPathDemoStack: destroyed
```

### Verify the known named resources no longer exist

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /golden-path/aws-demo/movie-reservation-service/ \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'logGroups[].logGroupName'

aws logs describe-log-groups \
  --log-group-name-prefix /aws/ecs/containerinsights/movie-reservation-platform-aws-demo/performance \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'logGroups[].logGroupName'

aws ecs describe-clusters \
  --clusters movie-reservation-platform-aws-demo \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'clusters[].{Name:clusterName,Status:status}'

aws amp list-workspaces \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "workspaces[?workspaceId=='${AMP_WORKSPACE_ID}'].workspaceId"

aws grafana list-workspaces \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query "workspaces[?id=='${GRAFANA_WORKSPACE_ID}'].id"

aws ec2 describe-managed-prefix-lists \
  --filters Name=prefix-list-name,Values=movie-reservation-platform-aws-demo-grafana-access \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'PrefixLists[].PrefixListId'

aws iam list-roles \
  --profile "$AWS_PROFILE" \
  --query "Roles[?RoleName=='${GRAFANA_ROLE_NAME}'].RoleName"
```

Both log-group queries should return empty lists, including the stack-owned
`metrics` EMF and Container Insights performance groups. The AMP, Grafana,
prefix-list, and IAM-role queries must also return empty lists. ECS can
temporarily report the deleted cluster as `INACTIVE`.
The successful CloudFormation stack deletion is the authoritative lifecycle
result for stack-owned resources. X-Ray retains ingested traces for 30 days
independently of this stack, so `cdk destroy` does not erase the smoke trace
immediately. CloudWatch custom and Container Insights metric datapoints also
cannot be deleted explicitly: removing the task, cluster, and log groups stops
new publication, while historical datapoints age out under CloudWatch's
service retention.

AWS Organizations, IAM Identity Center, its built-in directory user, MFA
enrollment, and the AWS access portal remain intentionally. They were created
outside `GoldenPathDemoStack` and must not be deleted as routine demo cleanup.

If deletion fails, inspect the first failing event before manually changing any
resource:

```bash
aws cloudformation describe-stack-events \
  --stack-name GoldenPathDemoStack \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceType,ResourceStatusReason]' \
  --output table
```

Fix the named cause and run `cdk destroy` again. Deleting arbitrary resources
manually first can make CloudFormation cleanup harder.

Expected verification shape:

```shell
[]

[]

[]

...

[
    {
        "Name": "movie-reservation-platform-aws-demo",
        "Status": "INACTIVE"
    }
]
```

## Bootstrap resources after destroy

Routine teardown must leave `CDKToolkit` in place. AWS recommends updating a
bootstrap stack rather than deleting and recreating it, and this runbook enables
termination protection for that reason.

The bootstrap S3 bucket and ECR repository can retain synthesized assets and
Docker layers after `GoldenPathDemoStack` is gone. They normally have small
storage cost compared with the running ALB, task, and interface endpoints.

The repository's CDK CLI supports garbage collection. First perform a read-only
inventory:

```bash
npm -w ecs-infra run cdk -- gc \
  "aws://${AWS_ACCOUNT_ID}/${AWS_REGION}" \
  --profile "$AWS_PROFILE" \
  --unstable=gc \
  --type=all \
  --action=print \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR"
```

For a personal account, unused assets can be tagged and deleted with rollback
buffers rather than removed manually:

```bash
npm -w ecs-infra run cdk -- gc \
  "aws://${AWS_ACCOUNT_ID}/${AWS_REGION}" \
  --profile "$AWS_PROFILE" \
  --unstable=gc \
  --type=all \
  --action=full \
  --created-buffer-days=1 \
  --rollback-buffer-days=7 \
  -c allowedIngressCidr="$ALLOWED_INGRESS_CIDR"
```

The command prompts before deletion. The rollback buffer preserves recently
orphaned assets so a recent deployment can still be rolled back. Do not run
garbage collection in a shared account without the bootstrap owner's approval.

Do not delete `CDKToolkit` merely to finish one demo. Only retire it when the
entire account/Region will no longer host any CDK application, and coordinate
that account-level operation with every CDK stack owner.

## Cost checklist

While `GoldenPathDemoStack` exists, review these cost categories for the chosen
Region:

- one continuously desired Fargate task at 0.5 vCPU and 1024 MiB;
- one Application Load Balancer, its capacity units, and public IPv4 usage;
- six interface endpoints, each deployed in one Availability Zone, plus data
  processing;
- CloudWatch Logs ingestion and retained app, collector, EMF, and Container
  Insights performance data;
- CloudWatch custom metrics created from the ten declared application
  instruments and their bounded dimension combinations;
- enhanced Container Insights task/container metrics;
- AMP ingestion, storage, and query samples for the application and eight
  curated ECS metrics, with seven-day workspace retention;
- Amazon Managed Grafana workspace usage and the assigned Admin active-user
  license;
- ECR and S3 storage for CDK assets;
- normal data transfer charges.

The S3 gateway endpoint has no hourly endpoint charge. The stack deliberately
uses no NAT Gateway. Setting `enableEcsExec=true` adds a seventh interface
endpoint and therefore another hourly endpoint cost.

After `cdk destroy`, the Fargate task, ALB, AMP and Grafana workspaces, Grafana
access prefix list and role, VPC endpoints, VPC, and all four log groups should
be gone. No emitter remains to publish new metric datapoints. The bootstrap
asset storage remains until its lifecycle rules or `cdk gc` remove unused
objects and images. X-Ray traces and historical CloudWatch metric datapoints
follow their service retention instead of CloudFormation lifecycle.
Organizations and Identity Center also remain because they are account-level
foundations. Billing data and budget notifications can lag behind resource
deletion.

## Common failures

### Browser-login credentials expired

```bash
aws login --profile "$AWS_PROFILE"
```

Repeat `get-caller-identity` after logging in.

### Environment is not bootstrapped

An error mentioning `/cdk-bootstrap/hnb659fds/version` means the selected
account/Region does not have the compatible bootstrap stack. Recheck the account
and Region before running the bootstrap command.

### Docker build or publish failed

Run `docker info` and confirm the daemon is available. Then rerun `deploy`; CDK
can reuse successfully published assets.

### Service did not stabilize

Inspect CloudFormation events, ECS service events, and application logs:

```bash
aws ecs describe-services \
  --cluster movie-reservation-platform-aws-demo \
  --services movie-reservation-service \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'services[0].events[0:10].[createdAt,message]' \
  --output table

aws logs tail \
  /golden-path/aws-demo/movie-reservation-service/app \
  --since 30m \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
```

The ECS deployment circuit breaker is enabled and should roll back a deployment
that cannot become healthy.

### ALB request times out

Compare the current public IPv4 address with `ALLOWED_INGRESS_CIDR`. If it
changed, refresh the variable and deploy the security group update. Also confirm
the ECS service is stable and the target group health check is passing.

### Collector is unhealthy or trace smoke times out

Confirm the ADOT container status and read its separate log group first. An
immediate config failure intentionally remains stopped because the 60-second
restart-attempt period prevents a tight loop. A later process exit may restart
inside the same task. Check the X-Ray endpoint, endpoint security group, task
role, and endpoint policy before changing app code; the app only knows the
loopback OTLP endpoint and remains available when export fails.

Rollback by redeploying the previous known-good revision or destroy the
disposable stack. Do not make ADOT essential as a workaround: that would turn a
telemetry failure into an application outage.

### Managed metrics smoke times out

Confirm the app and ADOT containers are running, then inspect the collector log
for `awsemf/application`, `prometheusremotewrite/application`,
`prometheusremotewrite/ecs`, credential, throttling, retry, or dropped-data
errors.

Use the report's `failure_stage` to narrow the path:

- `cloudwatch_metric` or `cloudwatch_query`: verify scoped
  `logs:CreateLogStream`/`logs:PutLogEvents` access to the named EMF log group
  and the CloudWatch Logs endpoint. No CloudWatch Metrics endpoint is required.
- `amp_query`: refresh the laptop's named-profile login and confirm `awscurl`
  can reach the stack-output query URL using Region `AWS_REGION` and service
  `aps`.
- `amp_metric` or `amp_contract`: verify the collector's regional STS mode, the
  private `sts` and `aps-workspaces` endpoints/policies, and workspace-scoped
  `aps:RemoteWrite` on the task role. Inspect returned labels before relaxing
  the contract; task/container IDs and image/timestamp labels must stay absent.
- `container_insights_query` or `container_insights_metric`: verify the cluster
  setting is `enhanced`, the service has a running task, and the conventional
  `/aws/ecs/containerinsights/movie-reservation-platform-aws-demo/performance`
  log group is receiving events.

If reservation outcome generation fails, inspect application logs for the fake
worker and failure-injection configuration before increasing attempt limits.
If outcomes pass but metrics are late, allow for the independent CloudWatch and
AMP ingestion delays. Roll back by redeploying the previous task definition or
destroy the stack; telemetry failure must not be worked around by making ADOT
essential.

### Managed Grafana cannot be reached or has no data

- A `403 Forbidden` before sign-in usually means the laptop's public IPv4 no
  longer matches the single prefix-list CIDR. Refresh
  `ALLOWED_INGRESS_CIDR`, review `cdk diff`, and redeploy the access update.
- An Identity Center login with no workspace access means the user exists but
  has not been assigned to this Grafana workspace, or has not been promoted to
  Admin.
- A failed AMP data-source test points to the workspace URL/Region/SigV4
  settings or the `aps:GetLabels`, `aps:GetMetricMetadata`, `aps:GetSeries`,
  and `aps:QueryMetrics` role statement.
- A failed CloudWatch data-source test or empty metric picker points to the
  Region or the metrics-only `cloudwatch:GetMetricData` and
  `cloudwatch:ListMetrics` permissions. A failure that names only CloudWatch
  Logs is expected from Grafana's combined metrics/logs health check; verify a
  metric in **Explore** instead of broadening this role.
- Imported panels with missing data sources mean the two dashboard inputs were
  not mapped during import. Reimport the versioned JSON instead of editing its
  UIDs in Git.

Do not solve these failures by broadening the workspace endpoint, adding
anonymous access, attaching AWS-managed administrator policies, or adding
Grafana API credentials.

## Official references

- [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Root user best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html)
- [Login for local development using console credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)
- [AWS CLI authentication options](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html)
- [AWS CDK bootstrapping](https://docs.aws.amazon.com/cdk/v2/guide/bootstrapping-env.html)
- [AWS CDK security best practices](https://docs.aws.amazon.com/cdk/v2/guide/best-practices-security.html)
- [Deploy AWS CDK applications](https://docs.aws.amazon.com/cdk/v2/guide/deploy.html)
- [`cdk destroy` reference](https://docs.aws.amazon.com/cdk/v2/guide/ref-cli-cmd-destroy.html)
- [`cdk gc` reference](https://docs.aws.amazon.com/cdk/v2/guide/ref-cli-cmd-gc.html)
- [Create an AWS cost budget](https://docs.aws.amazon.com/cost-management/latest/userguide/create-cost-budget.html)
- [AWS Fargate pricing](https://aws.amazon.com/fargate/pricing/)
- [Elastic Load Balancing pricing](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [AWS PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)
- [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/)
- [ADOT CloudWatch metrics](https://aws-otel.github.io/docs/getting-started/cloudwatch-metrics/)
- [CloudWatch Embedded Metric Format](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html)
- [Use `awscurl` with AMP Prometheus-compatible APIs](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-compatible-APIs.html)
- [AMP interface VPC endpoints](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-and-interface-VPC.html)
- [Enhanced ECS Container Insights metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-enhanced-observability-metrics-ECS.html)
- [Managed Grafana with IAM Identity Center](https://docs.aws.amazon.com/grafana/latest/userguide/authentication-in-AMG-SSO.html)
- [Managed Grafana customer-managed permissions](https://docs.aws.amazon.com/grafana/latest/userguide/AMG-manage-permissions.html)
- [Managed Grafana network access control](https://docs.aws.amazon.com/grafana/latest/userguide/AMG-configure-nac.html)
- [Grafana CloudWatch data-source troubleshooting](https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/troubleshooting/)
