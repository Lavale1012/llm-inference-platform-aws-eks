# LLM Inference Platform on AWS EKS

Infrastructure-as-code for deploying a quantized **Llama 3.2** model as a
containerized GPU-inference service on Amazon EKS. The model is served through
[llama.cpp](https://github.com/ggml-org/llama.cpp)'s `llama-server`, which
exposes an **OpenAI-compatible REST API** behind an Application Load Balancer
provisioned by the AWS Load Balancer Controller.

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
./build-and-push.sh          # prints the pushed image URI (…/aws-llm-ecr:sha-<gitsha>)

# 4. Pin that image and deploy (CI does this automatically; manual equivalent):
cd ../k8s
kustomize edit set image llm-inference=<pushed-image-uri>   # e.g. …/aws-llm-ecr:sha-<gitsha>
kubectl apply -k .
cd ..

# 5. Get the ALB URL (takes ~2-3 min to provision)
kubectl get ingress llm-inference -n llm \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Talk to the model

```bash
export LLM_ENDPOINT="http://<alb-hostname>"
pip install -r client/requirements.txt
python client/chat.py

# or plain curl:
curl "$LLM_ENDPOINT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}'
```

---

## CI/CD pipeline

Two path-filtered GitHub Actions workflows separate the image lifecycle from the
infrastructure lifecycle. Both authenticate to AWS via **GitHub OIDC** (no
long-lived access keys) by assuming the `aws-llm-github-actions` IAM role.

```text
   push to main / PR
          │
          ├─────────────► llm/** or k8s/** ────────────┐   (.github/workflows/app.yml)
          │                                             ▼
          │                                   ┌──────────────────────┐
          │                                   │ build image          │
          │                                   │ (linux/amd64, GHA     │
          │                                   │  layer cache)         │
          │                                   │ PR: build only        │
          │                                   │ main: push ECR        │
          │                                   │   tag = sha-<gitsha>  │
          │                                   └──────────┬───────────┘
          │                                              ▼
          │                                   kustomize set image +
          │                                   kubectl apply -k k8s/
          │                                   (skipped if no cluster)
          │
          └─────────────► infra/** ────────────────────┐   (.github/workflows/infra.yml)
                                                        ▼
                                          ┌─────────────────────────┐
                                          │ terraform fmt -check     │
                                          │ terraform validate       │
                                          │ terraform plan (PR       │
                                          │   → posts plan comment)  │
                                          │ terraform apply (main,   │
                                          │   manual-approval gate)  │
                                          └─────────────────────────┘
```

- **Image path (`app.yml`):** PRs build the image to catch breakage (no push).
  Merges to `main` push `sha-<gitsha>` to ECR (scan-on-push is enabled), then
  pin that image via kustomize and `kubectl apply -k k8s/`. The push is
  **idempotent** — re-running on the same commit detects the existing immutable
  tag and skips straight to deploy. The deploy step **skips gracefully** if the
  cluster isn't running (it's torn down between sessions to save GPU cost).
- **Infra path (`infra.yml`):** `fmt`/`validate`/`plan` on PRs (the plan is
  posted as a PR comment); on merge to `main`, `apply` runs behind a **manual
  approval gate** via the `production-infra` GitHub Environment.
- **Auth:** GitHub OIDC → the `aws-llm-github-actions` role (defined in
  [`infra/cicd.tf`](infra/cicd.tf)). Its ARN is fed into the compute module's
  `ecr_push_role_arns` (ECR repository policy) and a namespace-scoped EKS
  **access entry** (`kubectl` in the `llm` namespace only).

### One-time setup

The pipeline assumes remote state is active and the CI role exists. Bootstrap:

```bash
# 1. Activate S3 remote state (CI plan/apply needs shared state + locking)
cd infra/bootstrap && terraform init && terraform apply   # creates aws-llm-tfstate-us-east-1
cd ..                                                       # then uncomment the backend block in backend.tf
terraform init -migrate-state                               # moves local state → S3

# 2. Create the CI IAM role (chicken-and-egg: CI needs it before it can run).
#    First run `aws iam list-open-id-connect-providers` — if a GitHub OIDC
#    provider already exists in the account, import it instead of creating a
#    duplicate (see the note in infra/cicd.tf).
terraform apply
terraform output -raw github_actions_role_arn              # → set as GitHub repo variable AWS_CI_ROLE_ARN

# 3. In the GitHub repo: Settings → Environments → create "production-infra"
#    with a required reviewer (this is what makes the infra apply gate real).
```

CI uses **Terraform 1.14.6** (the config pins `required_version = "~> 1.9"`, so
local and CI stay compatible).

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
