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
      cluster["ECS cluster"]
      service["Fargate service<br/>desired count: 1"]
      cluster -->|"hosts"| service
    end

    subgraph vpc["VPC: one Availability Zone, no NAT Gateway"]
      direction LR
      igw["Internet Gateway"]

      subgraph publicSubnet["Public subnet"]
        alb["Internet-facing<br/>Application Load Balancer"]
      end

      subgraph isolatedSubnet["Private isolated subnet"]
        direction TB
        task["Running Fargate task<br/>movie-reservation-service<br/>TCP port 3000<br/>no public IP"]
        interfaceEndpoints["Interface VPC endpoints<br/>ECR API + ECR Docker<br/>CloudWatch Logs<br/>SSM Messages optional"]
        s3Endpoint["S3 gateway endpoint"]

        task -->|"HTTPS 443"| interfaceEndpoints
        task -->|"image layers"| s3Endpoint
      end

      igw -->|"HTTP 80<br/>restricted source CIDR"| alb
      alb -->|"HTTP 3000<br/>application + health checks"| task
    end

    ecr["Amazon ECR<br/>application image"]
    s3["Amazon S3<br/>ECR image layers"]
    logs["CloudWatch Logs<br/>application log group"]
    ssm["SSM Messages<br/>optional ECS Exec"]

    service -->|"maintains one task"| task
    interfaceEndpoints --> ecr
    interfaceEndpoints --> logs
    interfaceEndpoints -.->|"when ECS Exec is enabled"| ssm
    s3Endpoint --> s3
  end

  classDef network fill:#eaf4ff,stroke:#2563eb,color:#111827
  classDef compute fill:#edf7ed,stroke:#238636,color:#111827
  classDef awsService fill:#fff4e5,stroke:#c2410c,color:#111827
  classDef optional fill:#f5f5f5,stroke:#6b7280,color:#111827,stroke-dasharray: 5 5

  class igw,alb,interfaceEndpoints,s3Endpoint network
  class cluster,service,task compute
  class ecr,s3,logs awsService
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
      ecr["Amazon ECR<br/>CDK asset repository<br/>application image"]
      s3["Amazon S3<br/>ECR image layers"]
      cloudwatch["CloudWatch Logs<br/>application log group<br/>7-day retention"]
      ssm["SSM Messages<br/>ECS Exec channels"]
    end

    subgraph ecsResources["Amazon ECS / Fargate resources"]
      direction LR
      cluster["ECS cluster<br/>Container Insights disabled"]
      service["Fargate service<br/>desired count: 1<br/>deployment rollback enabled<br/>health grace: 60s"]
      taskDefinition["Fargate task definition<br/>256 CPU units / 512 MiB<br/>app container: TCP 3000<br/>awslogs driver"]
      executionRole["Task execution role<br/>image pull + log delivery"]
      taskRole["Task role<br/>application permissions<br/>+ ECS Exec when enabled"]

      cluster -->|"hosts"| service
      taskDefinition -->|"used by"| service
      taskDefinition --> executionRole
      taskDefinition --> taskRole
    end

    subgraph vpc["VPC: one Availability Zone, no NAT Gateway"]
      direction TB
      igw["Internet Gateway"]

      subgraph publicSubnet["Public subnet /24"]
        direction LR
        publicRoute["Public route table<br/>0.0.0.0/0 to IGW"]
        alb["Internet-facing<br/>Application Load Balancer"]
        listener["HTTP listener<br/>port 80"]
        targetGroup["IP target group<br/>HTTP port 3000<br/>health: GET /health every 30s<br/>deregistration delay: 30s"]

        publicRoute --> igw
        alb --> listener --> targetGroup
      end

      subgraph isolatedSubnet["Private isolated subnet /24: no public IP or internet route"]
        direction TB
        isolatedRoute["Isolated route table<br/>VPC-local routes"]
        task["Fargate task ENI<br/>movie-reservation-service<br/>TCP port 3000"]

        subgraph endpointEnis["Private AWS-service access"]
          direction LR
          ecrApiEndpoint["ECR API<br/>interface endpoint"]
          ecrDockerEndpoint["ECR Docker<br/>interface endpoint"]
          logsEndpoint["CloudWatch Logs<br/>interface endpoint"]
          s3Endpoint["S3<br/>gateway endpoint"]
          ssmEndpoint["SSM Messages<br/>interface endpoint<br/>optional"]
        end

        isolatedRoute -->|"S3 prefix-list route"| s3Endpoint
        task -->|"HTTPS 443<br/>auth + metadata"| ecrApiEndpoint
        task -->|"HTTPS 443<br/>image manifest"| ecrDockerEndpoint
        task -->|"image layers"| s3Endpoint
        task -->|"HTTPS 443<br/>application logs"| logsEndpoint
        task -.->|"HTTPS 443<br/>enableEcsExec=true"| ssmEndpoint
      end

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
      endpointSg -. "attached when enabled" .-> ssmEndpoint
    end

    service -->|"runs and replaces task<br/>min 100% / max 200%"| task
    taskDefinition -->|"defines container"| task

    ecrApiEndpoint --> ecr
    ecrDockerEndpoint --> ecr
    s3Endpoint --> s3
    logsEndpoint --> cloudwatch
    ssmEndpoint -.-> ssm

    executionRole -. "permits image pull" .-> ecr
    executionRole -. "permits log writes" .-> cloudwatch
    taskRole -. "permits Exec when enabled" .-> ssm
  end

  classDef network fill:#eaf4ff,stroke:#2563eb,color:#111827
  classDef compute fill:#edf7ed,stroke:#238636,color:#111827
  classDef awsService fill:#fff4e5,stroke:#c2410c,color:#111827
  classDef security fill:#fff1f2,stroke:#be123c,color:#111827
  classDef optional fill:#f5f5f5,stroke:#6b7280,color:#111827,stroke-dasharray: 5 5

  class igw,publicRoute,alb,listener,targetGroup,isolatedRoute,ecrApiEndpoint,ecrDockerEndpoint,logsEndpoint,s3Endpoint network
  class cluster,service,taskDefinition,executionRole,taskRole,task compute
  class ecr,s3,cloudwatch,ssm awsService
  class albSg,serviceSg,endpointSg security
  class ssmEndpoint optional
```

## Main Boundaries

- **Public ingress:** the Internet Gateway and public route make the ALB
  internet-facing. Its security group still restricts port 80 to
  `allowedIngressCidr`.
- **Private compute:** the Fargate task receives an ENI in the isolated subnet,
  has no public IP, and accepts port 3000 only from the ALB security group.
- **No-NAT service access:** ECR API, ECR Docker, CloudWatch Logs, and optional
  SSM Messages use interface endpoint ENIs. ECR image layers use the S3 gateway
  endpoint attached to the isolated route table.
- **ECS control resources:** the cluster, service, task definition, and IAM roles
  are regional resources. The running Fargate task is the part placed in the
  selected VPC subnet.
- **Health and deployment:** the target group calls `GET /health` every 30
  seconds. The ECS service keeps one desired task, gives startup a 60-second
  grace period, and rolls back failed deployments.

Both diagrams show one public and one isolated subnet because the current
`PlatformConfig` fixes `maxAzs` to `1`. Security groups use CDK's default
outbound allowance; the rules shown above are the explicit inbound rules.
