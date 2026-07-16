# Design & Architecture

Deep-dive documentation for the [LLM Inference Platform on AWS EKS](README.md).
This file holds the full architecture, request flow, CI/CD design, monitoring
design, and engineering trade-offs. The top-level [README](README.md) is the
short version.

> **Status:** Terraform + Kubernetes manifests are complete and validated.
> Sections marked _(planned)_ describe the intended design and are not yet
> applied.

---

## Architecture

```text
                              Internet
                                 │
                                 ▼
                   ┌──────────────────────────┐
                   │  Application Load Balancer│  (internet-facing, HTTP :80)
                   │  created by LB Controller │
                   │  from a K8s Ingress       │
                   └────────────┬──────────────┘
                                │  target-type: ip
   ┌────────────────────────────┼──────────────────────────────────┐
   │  VPC (10.0.0.0/16, multi-AZ)                                    │
   │                                                                 │
   │   Public subnets ──► ALB, NAT gateways                          │
   │                                                                 │
   │   Private subnets ─────────────────────────────────────────┐   │
   │   ┌───────────────────────┐   ┌───────────────────────────┐│   │
   │   │  system node group    │   │  gpu node group           ││   │
   │   │  (m5.xlarge, on-demand)│  │  (g5.xlarge, NVIDIA A10G) ││   │
   │   │                       │   │  taint: nvidia.com/gpu    ││   │
   │   │  • CoreDNS            │   │  ┌─────────────────────┐  ││   │
   │   │  • LB Controller      │   │  │ llm-inference pod    │  ││   │
   │   │  • NVIDIA dev plugin  │   │  │  llama-server :8080  │  ││   │
   │   │  • EBS CSI / CW agent │   │  │  Llama-3.2-1B GGUF   │  ││   │
   │   └───────────────────────┘   │  └─────────────────────┘  ││   │
   │                               └───────────────────────────┘│   │
   │                                                            │   │
   │   VPC endpoints: S3 (gw) · ECR api/dkr · CW logs ──────────┘   │
   └─────────────────────────────────────────────────────────────────┘
        │                          │                         │
        ▼                          ▼                         ▼
   Private ECR              CloudWatch + SNS          Prometheus + Grafana
   (image registry)         (alarms, live)            (metrics, planned)
```

### Request flow

1. A client calls `POST /v1/chat/completions` against the ALB DNS name.
2. The ALB forwards to the `llm-inference` pod IPs (registered directly via the
   VPC CNI, `target-type: ip`).
3. `llama-server` runs inference on the g5 node's GPU and streams back an
   OpenAI-format response.

### Design decisions worth calling out

- **The ALB is created by Kubernetes, not Terraform.** The AWS Load Balancer
  Controller runs in-cluster and provisions the ALB from an `Ingress` resource,
  discovering subnets via `kubernetes.io/role/*` tags. This keeps L7 routing in
  the same declarative surface as the workload instead of a hand-built
  `aws_lb`.
- **Controller IAM comes from EKS Pod Identity, not IRSA.** A Pod Identity
  association binds an IAM role to the `aws-load-balancer-controller` service
  account — the newer, simpler alternative to OIDC-federated IRSA.
- **Nodes run in private subnets only.** Egress is via NAT gateways; ingress is
  via the ALB in the public subnets. Nothing schedulable is internet-reachable
  directly.
- **GPU nodes are isolated by taint.** `nvidia.com/gpu=true:NoSchedule` keeps
  system pods off the expensive g5 nodes; only inference pods with a matching
  toleration land there. The NVIDIA device plugin (a DaemonSet) advertises the
  GPU as a schedulable resource.
- **ECR pulls need no imagePullSecret.** The managed node group role carries
  `AmazonEC2ContainerRegistryReadOnly`; push access is scoped to the Terraform
  caller plus any CI role added to `ecr_push_role_arns`.

---

## Repository layout

| Path | Contents |
| --- | --- |
| `infra/` | Terraform root wiring four modules together |
| `infra/modules/networking/` | VPC, subnets, NAT, EIPs, VPC endpoints, LB-controller subnet tags |
| `infra/modules/compute/` | EKS cluster, `system` + `gpu` node groups, add-ons, LB Controller, NVIDIA device plugin, ECR |
| `infra/modules/storage/` | S3 bucket for ALB access logs |
| `infra/modules/monitoring/` | CloudWatch alarms (billing, node CPU/mem, ALB 5xx) + SNS |
| `infra/bootstrap/` | Standalone config that creates the S3 remote-state bucket |
| `llm/` | `Dockerfile` (CUDA llama.cpp + baked model) and `build-and-push.sh` |
| `k8s/` | Namespace, Deployment, Service, Ingress manifests |
| `client/` | `chat.py` — streaming CLI client using the OpenAI SDK |

---

## Prerequisites

- Terraform, AWS CLI (configured), `kubectl`, `helm`, Docker
- An AWS account with permission to create VPC/EKS/ECR/IAM resources
- Python 3.9+ for the CLI client

---

## Deploy

```bash
# 1. Provision infrastructure (~15-20 min: control plane + node groups)
cd infra
terraform init
terraform apply

# 2. Point kubectl at the new cluster
aws eks update-kubeconfig --name aws-llm-eks --region us-east-1

# 3. Build the inference image and push it to ECR
cd ../llm
./build-and-push.sh          # prints the pushed image URI

# 4. Set that image URI in k8s/deployment.yaml, then deploy
cd ..
kubectl apply -f k8s/

# 5. Get the ALB URL (takes ~2-3 min to provision)
kubectl get ingress llm-inference -n llm \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Talk to the model

```bash
# Configure the client (copy the template, fill in the ALB URL)
cp client/.env.example client/.env
# edit client/.env → set LLM_ENDPOINT=http://<alb-hostname>

pip install -r client/requirements.txt
python client/chat.py

# or plain curl:
curl "http://<alb-hostname>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}'
```

---

## CI/CD pipeline _(planned — described, not yet implemented)_

The intended pipeline (e.g. GitHub Actions) separates the image lifecycle from
the infrastructure lifecycle:

```text
   push to main / PR
          │
          ├─────────────► llm/** changed ──────────────┐
          │                                             ▼
          │                                   ┌──────────────────┐
          │                                   │ build image      │
          │                                   │ (linux/amd64)    │
          │                                   │ scan → push ECR  │
          │                                   │ tag = git SHA    │
          │                                   └────────┬─────────┘
          │                                            ▼
          │                                   kubectl set image
          │                                   (rolling deploy)
          │
          └─────────────► infra/** changed ───────────┐
                                                       ▼
                                          ┌────────────────────────┐
                                          │ terraform fmt -check   │
                                          │ terraform validate     │
                                          │ terraform plan (PR)    │
                                          │ terraform apply (main) │
                                          └────────────────────────┘
```

- **Image path:** build → scan (ECR scan-on-push is already enabled) → push
  with the immutable git-SHA tag → roll the Deployment.
- **Infra path:** `fmt`/`validate`/`plan` on PRs; gated `apply` on merge to
  `main`.
- **Auth:** GitHub OIDC → an IAM role added to `ecr_push_role_arns`
  (the variable already exists in the compute module for exactly this).

---

## Monitoring

**Live today — CloudWatch + SNS** (`infra/modules/monitoring/`):

- Billing/cost alarm, EKS node CPU and memory alarms, and a conditional ALB 5xx
  alarm, all notifying an SNS topic with an email subscription.
- The CloudWatch Observability add-on feeds Container Insights so the node
  alarms have data.

**Planned — Prometheus + Grafana** (intended design; not yet applied):

```text
   ┌─────────────────────────────────────────────┐
   │  monitoring namespace                        │
   │                                              │
   │  ┌────────────┐   scrapes   ┌─────────────┐  │
   │  │ Prometheus │◄────────────│ node-exporter│  │
   │  │  (TSDB)    │◄────────────│ kube-state   │  │
   │  │            │◄────────────│ llama-server │  │
   │  └─────┬──────┘             │ /metrics     │  │
   │        │                    └─────────────┘  │
   │        ▼                                      │
   │  ┌────────────┐                               │
   │  │  Grafana   │  dashboards: GPU util, tokens │
   │  │            │  /sec, request latency, node  │
   │  └────────────┘  CPU/mem                      │
   └─────────────────────────────────────────────┘
```

The plan is to deploy the `kube-prometheus-stack` Helm chart into a dedicated
`monitoring` namespace, scraping cluster metrics plus `llama-server`'s own
metrics endpoint, with Grafana dashboards for GPU utilization, inference
latency, and throughput. CloudWatch alarms remain for AWS-level cost and
infrastructure signals.

---

## Notes & trade-offs

- **GPU cost:** the `gpu` node group defaults to one `g5.xlarge` on-demand
  (~$730/mo running 24/7). Set `gpu_desired_size = 0` to scale to zero when
  idle, or switch to spot for a large discount.
- **HTTP only:** the Ingress serves plain HTTP. Add an ACM certificate and an
  HTTPS listener before exposing anything real.
- **Remote state:** state is local by default. `infra/bootstrap/` +
  `infra/backend.tf` migrate it to an S3 backend when you're ready.
- **Model packaging:** the ~773 MB quantized model is baked into the image
  (simple, self-contained). For larger models, load weights from S3 to an EBS
  volume at runtime instead.
