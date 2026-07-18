# ECS/Fargate AWS Resource Architecture

This page shows the deployed AWS architecture modeled by `GoldenPathDemoStack`
in `ecs-infra/lib/infra-stack.ts` at two levels:

- the **high-level runtime architecture** shows the major components, placement,
  and communication paths;
- the **detailed resource topology** shows the supporting AWS resources and
  control relationships behind that runtime.

CDK synthesis, deployment, CI, and user workflows are intentionally outside
both diagrams.

## High-Level Runtime Architecture

Use this view to understand where the application runs and how network traffic
reaches it. This is closest to what is usually called an AWS architecture
diagram.

```mermaid
flowchart TB
  subgraph region["AWS Region"]
    direction TB

    subgraph ecs["Amazon ECS"]
      direction LR
      cluster["Application ECS cluster<br/>movie-reservation-platform-aws-demo"]
      service["Fargate service<br/>desired count: 1"]
      cluster -->|"hosts"| service
    end

    subgraph vpc["VPC: two Availability Zones, no NAT Gateway"]
      direction TB
      igw["Internet Gateway"]

      subgraph publicSubnets["Public subnets: AZ A + AZ B"]
        alb["Internet-facing Application Load Balancer<br/>network interfaces in both AZs"]
      end

      subgraph workloadSubnet["Selected private isolated workload subnet: AZ A"]
        direction TB
        subgraph task["Running Fargate task: 512 CPU / 1024 MiB, no public IP"]
          direction LR
          app["Essential app<br/>TCP 3000<br/>384 CPU / 640 MiB"]
          adot["Nonessential ADOT<br/>128 CPU / 384 MiB<br/>health 13133"]
          app -->|"OTLP/HTTP traces<br/>127.0.0.1:4318"| adot
        end
        interfaceEndpoints["Interface VPC endpoints<br/>ECR API + ECR Docker<br/>CloudWatch Logs + X-Ray<br/>SSM Messages optional"]
        s3Endpoint["S3 gateway endpoint"]

        app -->|"HTTPS 443"| interfaceEndpoints
        adot -->|"HTTPS 443"| interfaceEndpoints
        task -->|"image layers"| s3Endpoint
      end

      standbySubnet["Second private isolated subnet: AZ B<br/>no task or endpoint ENIs in the current demo"]

      igw -->|"HTTP 80<br/>restricted source CIDR"| alb
      alb -->|"HTTP 3000<br/>application + health checks"| app
    end

    ecr["Amazon ECR<br/>app + ADOT CDK assets"]
    s3["Amazon S3<br/>ECR image layers"]
    logs["CloudWatch Logs<br/>app + ADOT log groups"]
    xray["AWS X-Ray<br/>trace segments"]
    ssm["SSM Messages<br/>optional ECS Exec"]

    service -->|"maintains one task"| task
    interfaceEndpoints --> ecr
    interfaceEndpoints --> logs
    interfaceEndpoints --> xray
    interfaceEndpoints -.->|"when ECS Exec is enabled"| ssm
    s3Endpoint --> s3
  end

  classDef network fill:#eaf4ff,stroke:#2563eb,color:#111827
  classDef compute fill:#edf7ed,stroke:#238636,color:#111827
  classDef awsService fill:#fff4e5,stroke:#c2410c,color:#111827
  classDef optional fill:#f5f5f5,stroke:#6b7280,color:#111827,stroke-dasharray: 5 5

  class igw,alb,interfaceEndpoints,s3Endpoint network
  class cluster,service,task,app,adot compute
  class ecr,s3,logs,xray awsService
  class ssm optional
```

The task definition is deliberately absent here. It configures how ECS creates
a task, but it is not a running component, a network hop, or something placed in
a subnet.

## Detailed AWS Resource Topology

Use this view when reasoning about the CDK and CloudFormation resources,
networking controls, health checks, or IAM relationships. The task definition
belongs here because the ECS service references it to create the running task.

```mermaid
flowchart TB
  subgraph region["AWS Region"]
    direction TB

    subgraph regionalServices["Regional AWS services"]
      direction LR
      ecr["Amazon ECR<br/>CDK asset repository<br/>app + ADOT images"]
      s3["Amazon S3<br/>ECR image layers"]
      cloudwatch["CloudWatch Logs<br/>app + ADOT log groups<br/>7-day retention"]
      xray["AWS X-Ray<br/>trace segments"]
      ssm["SSM Messages<br/>ECS Exec channels"]
    end

    subgraph ecsResources["Amazon ECS / Fargate resources"]
      direction LR
      cluster["Application ECS cluster<br/>movie-reservation-platform-aws-demo<br/>Container Insights disabled"]
      service["Fargate service<br/>desired count: 1<br/>deployment rollback enabled<br/>health grace: 60s"]
      taskDefinition["Fargate task definition<br/>512 CPU units / 1024 MiB<br/>essential app + nonessential ADOT<br/>separate awslogs drivers"]
      executionRole["Task execution role<br/>image pull + log delivery"]
      taskRole["Shared task role<br/>X-Ray writes<br/>+ ECS Exec when enabled"]

      cluster -->|"hosts"| service
      taskDefinition -->|"used by"| service
      taskDefinition --> executionRole
      taskDefinition --> taskRole
    end

    subgraph vpc["VPC: two Availability Zones, no NAT Gateway"]
      direction TB
      igw["Internet Gateway"]

      subgraph publicSubnets["Public subnets /24: AZ A + AZ B"]
        direction LR
        publicRoute["Public route table<br/>0.0.0.0/0 to IGW"]
        alb["Internet-facing Application Load Balancer<br/>attached to both public subnets"]
        listener["HTTP listener<br/>port 80"]
        targetGroup["IP target group<br/>HTTP port 3000<br/>health: GET /health every 30s<br/>deregistration delay: 30s"]

        publicRoute --> igw
        alb --> listener --> targetGroup
      end

      subgraph workloadSubnet["Selected private isolated workload subnet /24: AZ A"]
        direction TB
        isolatedRoute["Isolated route table<br/>VPC-local routes"]
        task["Fargate task ENI<br/>app TCP 3000<br/>ADOT loopback 4318/13133"]

        subgraph endpointEnis["Private AWS-service access"]
          direction LR
          ecrApiEndpoint["ECR API<br/>interface endpoint"]
          ecrDockerEndpoint["ECR Docker<br/>interface endpoint"]
          logsEndpoint["CloudWatch Logs<br/>interface endpoint"]
          xrayEndpoint["X-Ray<br/>interface endpoint<br/>write-only policy"]
          s3Endpoint["S3<br/>gateway endpoint"]
          ssmEndpoint["SSM Messages<br/>interface endpoint<br/>optional"]
        end

        isolatedRoute -->|"S3 prefix-list route"| s3Endpoint
        task -->|"HTTPS 443<br/>auth + metadata"| ecrApiEndpoint
        task -->|"HTTPS 443<br/>image manifest"| ecrDockerEndpoint
        task -->|"image layers"| s3Endpoint
        task -->|"HTTPS 443<br/>application logs"| logsEndpoint
        task -->|"HTTPS 443<br/>trace writes"| xrayEndpoint
        task -.->|"HTTPS 443<br/>enableEcsExec=true"| ssmEndpoint
      end

      standbySubnet["Second private isolated subnet /24: AZ B<br/>created for symmetric VPC topology<br/>unused by current workloads and endpoints"]

      subgraph securityGroups["Security groups"]
        direction LR
        albSg["ALB security group<br/>ingress TCP 80<br/>from allowedIngressCidr"]
        serviceSg["Service security group<br/>ingress TCP 3000<br/>from ALB security group"]
        endpointSg["Endpoint security group<br/>ingress TCP 443<br/>from service security group"]
      end

      igw -->|"HTTP 80"| alb
      targetGroup -->|"application traffic<br/>+ health checks"| task

      albSg -. "attached to" .-> alb
      serviceSg -. "attached to" .-> task
      endpointSg -. "attached to" .-> ecrApiEndpoint
      endpointSg -. "attached to" .-> ecrDockerEndpoint
      endpointSg -. "attached to" .-> logsEndpoint
      endpointSg -. "attached to" .-> xrayEndpoint
      endpointSg -. "attached when enabled" .-> ssmEndpoint
    end

    service -->|"runs and replaces task<br/>min 100% / max 200%"| task
    taskDefinition -->|"defines container"| task

    ecrApiEndpoint --> ecr
    ecrDockerEndpoint --> ecr
    s3Endpoint --> s3
    logsEndpoint --> cloudwatch
    xrayEndpoint --> xray
    ssmEndpoint -.-> ssm

    executionRole -. "permits image pull" .-> ecr
    executionRole -. "permits log writes" .-> cloudwatch
    taskRole -. "permits Exec when enabled" .-> ssm
    taskRole -. "permits two write actions" .-> xray
  end

  classDef network fill:#eaf4ff,stroke:#2563eb,color:#111827
  classDef compute fill:#edf7ed,stroke:#238636,color:#111827
  classDef awsService fill:#fff4e5,stroke:#c2410c,color:#111827
  classDef security fill:#fff1f2,stroke:#be123c,color:#111827
  classDef optional fill:#f5f5f5,stroke:#6b7280,color:#111827,stroke-dasharray: 5 5

  class igw,publicRoute,alb,listener,targetGroup,isolatedRoute,ecrApiEndpoint,ecrDockerEndpoint,logsEndpoint,xrayEndpoint,s3Endpoint network
  class cluster,service,taskDefinition,executionRole,taskRole,task compute
  class ecr,s3,cloudwatch,xray,ssm awsService
  class albSg,serviceSg,endpointSg security
  class ssmEndpoint optional
```

## Main Boundaries

- **Public ingress:** the Internet Gateway and public route make the ALB
  internet-facing. Its security group still restricts port 80 to
  `allowedIngressCidr`, and the config boundary rejects `0.0.0.0/0` as an
  ingress value. The public route table's `0.0.0.0/0 -> Internet Gateway` route
  is different: it makes the public subnet internet-routable, but it does not
  itself authorize inbound connections through the ALB security group.
- **Private compute:** the Fargate task receives an ENI in the isolated subnet,
  has no public IP, and accepts port 3000 only from the ALB security group.
- **Availability Zone split:** the VPC and internet-facing ALB span two
  Availability Zones. The demo task, S3 endpoint route, and interface endpoint
  ENIs are explicitly pinned to one workload subnet to avoid paying for a
  duplicate endpoint set before high availability is required. Target-group
  ALB cross-zone load balancing is explicitly enabled so both nodes can route
  to the healthy target in the selected workload AZ.
- **No-NAT service access:** ECR API, ECR Docker, CloudWatch Logs, X-Ray, and
  optional SSM Messages use interface endpoint ENIs. ECR image layers use the
  S3 gateway endpoint attached only to the selected workload subnet's route
  table.
- **ECS control resources:** the cluster, service, task definition, and IAM roles
  are regional resources. The running Fargate task is the part placed in the
  selected VPC subnet.
- **ECS Exec:** enabling Exec adds the SSM Messages endpoint and grants the task
  role permission to open control and data channels. The operator invoking
  `execute-command` still needs separate identity-side IAM permission.
- **Health and deployment:** the target group calls `GET /health` every 30
  seconds. The ECS service keeps one desired task, gives startup a 60-second
  grace period, and rolls back failed deployments. ADOT has its own non-gating
  `/healthcheck` command and restart policy; collector failure does not make the
  app container or task unhealthy.
- **Telemetry boundary:** the application emits standard OTLP and W3C context.
  ADOT owns AWS credentials and X-Ray translation. There are no task security
  group rules for ports 4318 or 13133 because both listeners use task loopback.
- **Trace privacy:** the X-Ray exporter keeps `index_all_attributes: false` and
  configures no indexed attributes. The current `enduser.id` span attribute is
  nevertheless stable/linkable and maps to X-Ray's dedicated `user` field; the
  indexing setting does not anonymize it. The ECS demo currently uses a fixed
  fake user. Before production auth, revisit whether traces need this field and
  prefer a keyed HMAC/pseudonym over a plain enumerable hash when they do.

Both diagrams show the fixed demo compromise represented by `PlatformConfig`:
`vpcMaxAzs` is `2`, while `workloadAzCount` is `1`. These values are not exposed
through CDK context. Security groups use CDK's default outbound allowance; the
rules shown above are the explicit inbound rules.

The cluster construct ID is `ApplicationCluster`, and its physical name is
`movie-reservation-platform-aws-demo`. The cluster is named for the platform and
environment because it can later host multiple independently deployed ECS
services. Service-owned resources such as the ECS service, task-definition
family, and log groups retain the `movie-reservation-service` identity. The
`workload` subnet name remains role-based so it can host task and endpoint ENIs
for more than one application service. `Project`, `Platform`, and `Environment`
tags apply across the stack, while the `Service` tag is limited to
service-owned compute, ingress, and logging resources.
