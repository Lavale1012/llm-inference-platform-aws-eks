# aws-llm — Architecture

![aws-llm architecture](architecture.png)

*Rendered with official AWS icons via the [`diagrams`](https://diagrams.mingrammer.com)
library. Regenerate with `python3 docs/architecture_diagram.py` (needs
`brew install graphviz && pip install diagrams`). Each node carries a short
`why:` note explaining the design choice; the four flows are color-coded and
listed in the diagram's title.*

## How it flows

- **Request path ①②③ (green):** a client calls `POST /v1/chat/completions` →
  the internet-facing **ALB** (provisioned by the AWS Load Balancer Controller
  from a Kubernetes `Ingress`) → forwarded straight to the **llama-server pod's
  IP** on a GPU node (`target-type: ip`, via the VPC CNI) → inference runs on the
  NVIDIA A10G and streams back an OpenAI-format response.
- **CI/CD path ⒶⒷⒸⒹ (blue):** a developer pushes / opens a PR → **GitHub
  Actions** assumes the `aws-llm-github-actions` role via OIDC (Ⓐ), pushes the
  image as `sha-<gitsha>` to **ECR** (Ⓑ), runs `terraform plan/apply` against
  **S3 remote state** with a gate on `main` (Ⓒ), and rolls the Deployment with
  `kubectl apply -k` when the cluster is up (Ⓓ).
- **Image pull (orange):** the pod pulls its image from ECR **privately** through
  the **VPC interface endpoints** (ECR api/dkr), keeping that traffic off the NAT
  gateways. Internet-bound egress goes pod → NAT → IGW.
- **Observability (pink):** the cluster ships metrics/logs to **CloudWatch**
  alarms (billing, node CPU/mem, ALB 5xx), which notify an **SNS** email topic.

---

## Mermaid version (editable / no-tooling fallback)

GitHub renders the block below inline. Export via
[mermaid.live](https://mermaid.live) or
`npx @mermaid-js/mermaid-cli -i docs/architecture.mmd -o docs/architecture-mermaid.png`.

```mermaid
flowchart TB
    user([Client<br/>chat.py / curl]):::ext
    dev([Developer<br/>git push / PR]):::ext
    gha["GitHub Actions<br/>app.yml · infra.yml"]:::cicd

    subgraph AWS["AWS · us-east-1"]
        direction TB

        oidc["IAM OIDC provider<br/>+ aws-llm-github-actions role"]:::iam
        ecr["ECR (private)<br/>aws-llm-ecr<br/>immutable · scan-on-push"]:::reg
        s3state["S3<br/>aws-llm-tfstate-us-east-1<br/>(remote state)"]:::store

        subgraph VPC["VPC · 10.0.0.0/16 · 2 AZs (us-east-1a/b)"]
            direction TB

            subgraph PUB["Public subnets · 10.0.10-11.0/24"]
                igw{{Internet Gateway}}:::net
                alb["Application Load Balancer<br/>(created by LB Controller<br/>from a K8s Ingress)"]:::net
                nat{{NAT gateways ×2}}:::net
            end

            subgraph PRIV["Private subnets · 10.0.1-2.0/24"]
                direction TB
                subgraph EKS["EKS cluster · aws-llm-eks · v1.33"]
                    direction TB
                    subgraph SYS["system node group · m5.xlarge"]
                        syspods["CoreDNS · kube-proxy<br/>AWS LB Controller<br/>NVIDIA device plugin<br/>EBS CSI · CW Observability"]:::pod
                    end
                    subgraph GPU["gpu node group · g5.xlarge (A10G)<br/>taint nvidia.com/gpu"]
                        llm["llm-inference Deployment<br/>llama-server :8080<br/>Llama-3.2-1B GGUF (CUDA)"]:::pod
                    end
                end
                vpce["VPC endpoints<br/>S3 (gw) · ECR api/dkr · CW logs"]:::net
            end
        end

        cw["CloudWatch alarms<br/>+ SNS (email)"]:::obs
    end

    user -->|"HTTP :80<br/>/v1/chat/completions"| igw --> alb
    alb -->|"target-type: ip<br/>(pod IPs via VPC CNI)"| llm

    llm -. egress .-> nat --> igw
    llm -->|pull image| vpce --> ecr

    dev --> gha
    gha -->|"OIDC assume-role"| oidc
    gha -->|"push sha-&lt;gitsha&gt;"| ecr
    gha -->|"terraform<br/>plan · apply"| s3state
    gha -->|"kubectl<br/>apply -k"| llm

    EKS -. metrics/logs .-> cw

    classDef ext   fill:#1f2937,stroke:#9ca3af,color:#fff;
    classDef cicd  fill:#2088ff,stroke:#0b5cff,color:#fff;
    classDef iam   fill:#dd344c,stroke:#a01b2f,color:#fff;
    classDef reg   fill:#f58536,stroke:#b45f18,color:#fff;
    classDef net   fill:#8c4fff,stroke:#5b2fb0,color:#fff;
    classDef pod   fill:#00a4a6,stroke:#00696b,color:#fff;
    classDef store fill:#3b48cc,stroke:#232f9e,color:#fff;
    classDef obs   fill:#e7157b,stroke:#a30d57,color:#fff;
```

## Legend

| Path | Flow |
| --- | --- |
| **Request** | Client → IGW → ALB → `llm-inference` pod (llama-server on GPU) → streamed response |
| **Image pull** | Pod pulls from ECR via the ECR VPC endpoints (off the NAT path) |
| **Egress** | Pod → NAT gateway → IGW for any internet-bound traffic |
| **CI/CD** | Developer → GitHub Actions → OIDC role → push image to ECR / terraform to S3 state / `kubectl apply -k` |
| **Observability** | EKS → CloudWatch alarms → SNS email |
