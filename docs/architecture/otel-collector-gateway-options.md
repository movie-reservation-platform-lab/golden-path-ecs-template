# OpenTelemetry Collector Gateway Options

Status: exploratory. No gateway topology is selected or scheduled.

Last reviewed: 2026-07-20

This note records the main AWS ECS options for replacing the current
per-application-task ADOT sidecar with a shared OpenTelemetry collector gateway.
It is decision input, not an ADR or an implementation plan. The work remains
tracked in the
[platform follow-up tasks](../plans/platform-follow-up-tasks.md#telemetry-platform-debt).

## Current Context

The current ECS task contains both the application and a nonessential ADOT
collector. The application sends OTLP/HTTP to `http://127.0.0.1:4318`, and the
collector exports traces to X-Ray.

This shape is useful for proving the first private OTLP-to-X-Ray path because
loopback provides discovery and network isolation without another AWS service.
It should not be copied into every future microservice without revisiting the
cost and ownership model:

- collector CPU and memory are repeated in every application task;
- collector configuration and policy can drift between services;
- the application and collector share one ECS task role, so X-Ray write
  permissions are technically available to the application;
- collector deployment and scaling are coupled to application deployment and
  scaling.

## Target Shape

The likely future shape is one logical collector gateway service per environment
or other chosen failure domain, with multiple collector task replicas when high
availability is required:

```text
application ECS services
          |
          | OTLP/HTTP :4318
          v
stable private endpoint
          |
          v
ADOT gateway ECS service
  collector task A
  collector task B
          |
          v
X-Ray VPC endpoint
```

"One per cluster" should mean one ECS service, not exactly one running task. An
ECS cluster is a scheduling boundary rather than a network boundary, so the
actual scope could be per environment, VPC, cluster, Region, or trust boundary.
That choice should follow ownership, failure isolation, traffic volume, and
cost rather than the cluster count alone.

All gateway alternatives should preserve these invariants:

- applications emit vendor-neutral OTLP and do not receive X-Ray permissions;
- collector availability does not gate application startup, health, or
  readiness;
- collector failure can lose telemetry, but must not cause an application
  outage;
- the gateway has its own task role, logs, health checks, deployment policy,
  sizing, and scaling controls;
- telemetry delivery health is monitored separately from application health;
- OTLP ingress is private and restricted to authorized application tasks.

## Stable Endpoint Alternatives

The collector service needs both a stable name and a way to select a healthy
replica. Service discovery and load balancing solve related but different
problems: discovery identifies possible destinations, while a load balancer or
proxy selects and routes to one of them.

| Alternative | Endpoint seen by applications | Discovery and routing behavior | Main tradeoff |
| --- | --- | --- | --- |
| AWS Cloud Map private DNS | `http://otel-gateway.telemetry.internal:4318` | DNS returns registered collector task private IPs | Lowest infrastructure overhead, but DNS is not active per-request load balancing |
| Internal Network Load Balancer | NLB DNS name or private Route 53 alias | NLB health-checks and routes TCP connections to ECS task IP targets | Strong general-purpose default, with additional fixed cost and another network hop |
| ECS Service Connect | `http://otel-gateway:4318` inside the namespace | Managed proxies provide discovery, round-robin routing, retries, and outlier detection | Useful as a platform-wide service networking choice, but adds a proxy sidecar to participating tasks |
| Internal Application Load Balancer | Internal ALB DNS name or private alias | Layer 7 HTTP routing and health checks | Useful only when OTLP/HTTP routing features are required; otherwise more machinery than this path needs |

### Alternative A: Cloud Map Private DNS

ECS service discovery registers each collector task private IP in an AWS Cloud
Map private DNS namespace. The application exports directly to the returned task
address.

In CDK, this would add a private DNS namespace and enable Cloud Map on the
collector `ecs.FargateService`. CloudFormation would create the corresponding
`AWS::ServiceDiscovery` resources and attach a service registry to the
`AWS::ECS::Service`.

Advantages:

- no load balancer or per-application proxy;
- simple private DNS name;
- ECS updates registrations as collector tasks start, stop, and change health;
- appropriate for a small, cost-sensitive environment.

Costs and risks:

- DNS returns a set of task IPs but does not actively balance every export;
- connection reuse and DNS caching can produce uneven traffic or delayed
  failover;
- client retry and DNS refresh behavior become part of availability;
- direct task ingress requires a collector security-group rule from authorized
  application task security groups.

This is the leanest acceptable first gateway when NLB cost is not justified.

### Alternative B: Internal Network Load Balancer

An internal Network Load Balancer provides one stable private endpoint and
routes TCP connections to healthy collector task replicas. For Fargate's
`awsvpc` networking, the target group registers task IPs rather than EC2 instance
IDs.

In CDK, this would add an internal `NetworkLoadBalancer`, TCP listener, network
target group, and collector service attachment. CloudFormation would create
`AWS::ElasticLoadBalancingV2` resources, while ECS would manage collector task
registration and deregistration.

Advantages:

- health-aware routing and task replacement integration;
- stable endpoint independent of collector task IP and DNS-cache behavior;
- no managed proxy in each application task;
- supports the current OTLP/HTTP transport and a later OTLP/gRPC listener.

Costs and risks:

- fixed load-balancer cost and an additional network hop;
- listener, target health, connection draining, security groups, and
  Availability Zone behavior must be configured deliberately;
- long-lived connections can still produce imperfect traffic distribution;
- the NLB must be created with a security group if later rules should restrict
  clients and targets by security-group identity.

This is the leading production-shaped option for this repository if a shared
gateway is introduced without adopting a broader service mesh.

### Alternative C: ECS Service Connect

Service Connect uses an AWS Cloud Map namespace plus an ECS-managed proxy in
each participating service task. Applications use a stable alias, and the proxy
provides round-robin routing, retries, passive outlier detection, and traffic
metrics.

Advantages:

- ECS-native service naming and routing behavior;
- managed retry, balancing, and unhealthy-target avoidance;
- useful when the platform wants one consistent approach for all internal
  service-to-service communication.

Costs and risks:

- participating application tasks receive another proxy sidecar;
- AWS recommends reserving additional task CPU and memory for that proxy;
- services must be redeployed into the namespace before using its endpoints;
- adopting a service networking layer only for OTLP is disproportionate to the
  problem.

Service Connect should be selected only as part of a wider east-west networking
decision. Using it solely to remove the ADOT sidecar would exchange one per-task
component for another.

### Alternative D: Internal Application Load Balancer

An internal ALB can receive OTLP/HTTP and provide HTTP-aware health checks,
TLS termination, and path- or host-based routing.

Advantages:

- appropriate if several HTTP endpoints must share listener infrastructure;
- Layer 7 routing and HTTP observability;
- familiar ECS integration.

Costs and risks:

- unnecessary Layer 7 behavior for a single private OTLP endpoint;
- more protocol-specific than a TCP NLB;
- creates temptation to share a load balancer across unrelated platform
  failure domains merely to save cost.

There is no current requirement that makes an ALB preferable for this gateway.

## Topology Alternative: Agent Plus Gateway

A later design may keep a small local collector agent and forward from that
agent to the shared gateway:

```text
application -> local agent -> shared gateway -> X-Ray
```

This can retain task-local enrichment, buffering, redaction, or protocol
translation while centralizing credentials and backend export policy. It also
retains some per-task resource and configuration overhead, so it should be used
only when those local responsibilities are concrete.

The simplest future topology remains direct application-to-gateway OTLP until a
local-agent requirement is demonstrated.

## Availability And Scaling Requirements

A shared gateway removes repeated sidecars but creates a shared failure domain.
Its availability work is therefore part of the migration, not optional polish.

- Use at least two collector tasks for an availability-oriented environment.
- Place replicas in at least two workload subnets across two Availability
  Zones. Two replicas in one Availability Zone do not provide zone resilience.
- Keep `memory_limiter` and `batch` processing, and define bounded sending queues
  and retry behavior deliberately.
- Scale initially from CPU and memory, then include collector queue, refusal,
  drop, and exporter-error metrics when those signals are available.
- Alarm on collector task health, exporter failures, refused or dropped spans,
  and an end-to-end trace smoke signal.
- Keep application exporters bounded and fail-open when the endpoint is
  unreachable.

The current AWS demo selects only one workload Availability Zone. That is valid
for its cost-conscious learning scope, but the gateway implementation must
revisit the subnet count before claiming high availability.

## Networking And IAM Requirements

The current collector receiver binds to loopback. A gateway receiver must bind
to a task-reachable address such as `0.0.0.0:4318`, while its local process health
check may remain on loopback. If load-balancer HTTP health checks use the
collector health extension, that endpoint needs a separately restricted network
listener.

The intended security boundary is:

- application tasks may send OTLP to the gateway endpoint;
- the collector task security group accepts OTLP only through the chosen client
  or load-balancer security group path;
- only the collector task role receives X-Ray write actions;
- only the collector security group can reach the X-Ray interface endpoint for
  this path;
- no OTLP listener is exposed publicly.

Internal plaintext OTLP may be acceptable within the current private VPC threat
model. TLS or mTLS should be decided explicitly if the gateway crosses VPC,
account, or trust boundaries.

## Stateful Processing Caveat

The current `memory_limiter -> batch -> awsxray` trace pipeline does not require
all spans from one trace to reach the same collector replica, so ordinary TCP or
DNS distribution is sufficient.

Future tail sampling or trace-derived aggregation can be stateful. Those
processors may require all spans for one trace or service to reach the same
collector instance. At that point, use a two-tier design with the OpenTelemetry
load-balancing exporter and an appropriate routing key instead of expecting an
NLB, Cloud Map, or Service Connect to understand trace identity.

## Decision Guidance

If the decision were required for the current repository shape:

- choose Cloud Map private DNS for the smallest cost-conscious learning step;
- choose an internal NLB with at least two collector replicas across two
  Availability Zones for the leading production-shaped design;
- choose Service Connect only if it becomes the platform-wide internal service
  networking standard;
- choose an internal ALB only after an actual Layer 7 requirement appears;
- keep a local agent only after identifying processing that must occur beside
  each application task.

Before implementation, confirm the failure-domain scope, expected telemetry
volume, Availability Zone count, endpoint cost, TLS boundary, autoscaling
signals, deployment rollback behavior, and whether stateful processing is in
scope. Record the selected topology as an ADR and create a scoped implementation
plan.

## References

- [OpenTelemetry gateway deployment pattern](https://opentelemetry.io/docs/collector/deploy/gateway/)
- [Amazon ECS service discovery](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-discovery.html)
- [Amazon ECS Service Connect concepts](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect-concepts.html)
- [Amazon ECS Service Connect components](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect-concepts-deploy.html)
- [Network Load Balancers for Amazon ECS](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/nlb.html)
- [Network Load Balancer security groups](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-security-groups.html)
