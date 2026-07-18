# LLM Inference Platform on AWS EKS

Production-style, **infrastructure-as-code** deployment of a self-hosted LLM on
Amazon EKS — a quantized **Llama 3.2** model served on **GPU** compute through an
OpenAI-compatible REST API, fronted by an auto-provisioned Application Load
Balancer. Built end-to-end with **Terraform** and **Kubernetes**.

<p>
  <img alt="Terraform"  src="https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=white">
  <img alt="AWS"        src="https://img.shields.io/badge/AWS-232F3E?logo=amazonwebservices&logoColor=white">
  <img alt="Amazon EKS" src="https://img.shields.io/badge/Amazon%20EKS-FF9900?logo=amazoneks&logoColor=white">
  <img alt="Kubernetes" src="https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white">
  <img alt="Helm"       src="https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white">
  <img alt="Docker"     src="https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white">
  <img alt="NVIDIA GPU" src="https://img.shields.io/badge/NVIDIA%20GPU-76B900?logo=nvidia&logoColor=white">
  <img alt="Python"     src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white">
</p>

> **Why I built this:** to demonstrate end-to-end cloud and DevOps skills —
> designing, provisioning, and operating a real GPU-backed ML service on AWS
> entirely through infrastructure-as-code, with the security, cost, and
> observability trade-offs a production system actually requires.
>
> **Status:** Terraform + Kubernetes manifests and the GitHub Actions CI/CD
> pipeline are complete and validated. Prometheus/Grafana monitoring is designed
> and documented as the next step.

---

## What this solves

Running your own LLM instead of calling a hosted API raises a stack of
infrastructure problems. This project solves each one as reusable IaC:

| Problem | How this project solves it |
| --- | --- |
| **"I want to self-host an LLM but don't want to hand-manage servers."** | A managed **EKS** cluster runs the model as a normal Kubernetes workload — declarative, self-healing, reproducible from Terraform. |
| **GPUs are expensive and easy to waste.** | Inference is isolated on a **tainted GPU node group** (only inference pods land there), the group can **scale to zero** when idle, and a **CloudWatch billing alarm** warns on cost. |
| **Exposing a model to the internet safely.** | Worker nodes sit in **private subnets** with no public IP; traffic enters only through an **ALB** the cluster provisions itself from a Kubernetes `Ingress`. |
| **Shipping a new model version shouldn't be manual or risky.** | A **CI/CD pipeline** builds the image, pushes an immutable `sha-<gitsha>` tag to **ECR**, and rolls the Deployment — with a manual-approval gate in front of any infrastructure change. |
| **No long-lived cloud credentials in CI.** | GitHub Actions authenticates via **OIDC** and assumes a least-privilege IAM role — there are no static AWS keys stored anywhere. |
| **Keeping image pulls fast, private, and cheap.** | **VPC endpoints** (ECR/S3/CloudWatch) keep pulls on the AWS backbone and off the NAT gateways, cutting data-processing cost. |
| **Knowing when something breaks or overspends.** | **CloudWatch** alarms (billing, node CPU/memory, ALB 5xx) notify an **SNS** email topic. |

It's built as a **portfolio-grade reference** for deploying GPU ML workloads on
AWS the way a production team would: modular Terraform, least-privilege IAM,
cost controls, and an automated delivery pipeline.

---

## Skills demonstrated

| Area | What this project shows |
| --- | --- |
| **Infrastructure as Code** | Modular **Terraform** (4 composable modules) provisioning a full VPC + EKS stack; remote-state backend on S3 |
| **Kubernetes / EKS** | Managed cluster with separate CPU + **GPU node groups**, taints/tolerations, DaemonSets, add-ons, Ingress |
| **AWS cloud architecture** | Multi-AZ VPC, public/private subnets, NAT, **VPC endpoints** (S3/ECR/CloudWatch), IAM least-privilege via **Pod Identity** |
| **Containers & registries** | CUDA `llama.cpp` **Docker** image, private **ECR** with immutable tags + scan-on-push |
| **Networking / load balancing** | AWS Load Balancer Controller provisioning an **ALB from a K8s Ingress** (no hand-built LB) |
| **Observability** | **CloudWatch** alarms + **SNS** for cost/node/5xx signals; Container Insights; Prometheus/Grafana design |
| **Cost & security engineering** | Scale-to-zero GPU option, private-subnet-only nodes, cost alarms, spot-ready node groups |

---

## Architecture at a glance

![aws-llm architecture](docs/architecture.png)

The diagram shows four color-coded flows: the **request path ①②③**, the **CI/CD
path ⒶⒷⒸⒹ**, the private **image pull**, and **observability**. Here's each key
part and why it's there:

- **Client → ALB (request entry).** External requests hit an internet-facing
  **Application Load Balancer**. The ALB isn't hand-built in Terraform — the
  **AWS Load Balancer Controller** running in-cluster creates it from a
  Kubernetes `Ingress`, so the cluster owns its own L7 entrypoint and discovers
  subnets via `kubernetes.io/*` tags.
- **VPC · public vs. private subnets.** The VPC spans **2 AZs** for
  availability. Only the ALB and NAT gateways live in **public** subnets; every
  worker node lives in a **private** subnet with no public IP. That means
  nothing schedulable is directly reachable from the internet — a core security
  boundary.
- **GPU node group (`g5.xlarge`, A10G) — tainted.** The inference pod runs here.
  The node group is **tainted `nvidia.com/gpu`** so *only* pods that tolerate it
  (the inference workload) land on the expensive GPU nodes; everything else is
  kept off. The **NVIDIA device plugin** advertises the GPU as a schedulable
  resource. This is what keeps GPU cost tied strictly to inference.
- **`llm-inference` pod — `llama-server` + CUDA.** Serves the quantized
  **Llama-3.2-1B GGUF** model over an OpenAI-compatible API on `:8080`. It's a
  **CUDA `llama.cpp`** build (not the CPU image), so the A10G actually
  accelerates inference instead of sitting idle.
- **system node group (`m5.xlarge`).** A separate cheap CPU pool runs cluster
  add-ons (CoreDNS, the LB Controller, NVIDIA plugin, EBS CSI, CloudWatch
  Observability) — deliberately *off* the GPU nodes to avoid wasting GPU money
  on housekeeping.
- **VPC endpoints (S3 · ECR api/dkr · CW logs).** Image pulls and log shipping
  go through **interface/gateway endpoints** on the AWS backbone rather than out
  through the NAT gateways — faster, private, and cheaper (no NAT data-processing
  charges for that traffic).
- **ECR (private).** The model image registry: **immutable tags** (a tag can't
  be overwritten) plus **scan-on-push** for CVEs. Nodes pull with no
  `imagePullSecret` — the node IAM role already has read access.
- **CloudWatch → SNS.** Alarms for billing/cost, node CPU/memory, and ALB 5xx
  notify an **SNS** email topic — basic operational + cost awareness.
- **IAM OIDC role + S3 remote state.** Support the CI/CD pipeline (below):
  GitHub Actions assumes the role via OIDC, and Terraform state lives in a
  locked S3 bucket so CI runs share consistent state.

**Request flow in one line:** a client sends `POST /v1/chat/completions` → the
ALB forwards to the pod's IP (`target-type: ip`, via the VPC CNI) → the A10G
runs inference → an OpenAI-format response streams back.

📐 **[Full architecture, request flow, and design rationale → DESIGN.md](DESIGN.md)**

---

## CI/CD pipeline

Two path-filtered **GitHub Actions** workflows deliver changes safely: one for
the container image + Kubernetes deploy, one for the Terraform infrastructure.
Both authenticate to AWS with **OIDC** (no stored keys).

### Pipeline overview

![CI/CD overview](docs/cicd-overview.png)

Each key part of the overview:

- **Developer → GitHub Actions (path-filtered trigger).** A push or PR fires the
  workflows, but **path filters** mean only the relevant one runs: changes under
  `infra/**` trigger `infra.yml`; changes under `llm/**` or `k8s/**` trigger
  `app.yml`. The two lifecycles never step on each other.
- **OIDC → IAM role (keyless auth).** Instead of long-lived AWS access keys,
  Actions requests a short-lived OIDC token and assumes
  **`aws-llm-github-actions`**. That role is **least-privilege**: ECR push, EKS
  access to the `llm` namespace only, and read/write on the Terraform state
  bucket — nothing more.
- **`app.yml` (image + deploy).** On a **PR** it builds the image only (no push)
  to catch breakage. On **push to `main`** it pushes an immutable
  `sha-<gitsha>` image to **ECR**, then deploys to **EKS**.
- **`infra.yml` (Terraform).** On a **PR** it runs `fmt`/`validate`/`plan` and
  posts the plan as a comment. On **push to `main`** it applies — behind a gate.
- **Guards & gates (the 🔒 diamonds).** Three checkpoints make the pipeline safe:
  an **immutable-tag skip** (don't re-push an image that already exists), a
  **cluster-ACTIVE check** (skip deploy when the GPU cluster is torn down for
  cost), and a **manual-approval gate** before any `terraform apply`.

### Full decision flow

![CI/CD flowchart](docs/cicd.png)

The flowchart traces every branch. The parts that matter most:

- **`terraform fmt → init → validate → plan`.** The infra job runs these in
  order; `plan` uses `-detailed-exitcode` so the pipeline can *tell whether the
  plan actually changes anything* (exit `2` = changes, `0` = none).
- **Plan-changes gate → `production-infra` approval.** `apply` only runs when
  the plan reported changes **and** a human approves via the `production-infra`
  GitHub Environment. It then applies the *exact* plan that was reviewed (passed
  between jobs as an artifact) — so what you approve is what runs. This puts a
  person in front of any change to live infrastructure (including a ~$730/mo GPU
  node group).
- **PR plan comment.** On pull requests the Terraform plan is posted straight
  into the PR, so infrastructure diffs are reviewable inline like code.
- **Image idempotency guard.** ECR tags are **immutable**, so re-running the
  build on the same commit would fail. The job first checks whether
  `sha-<gitsha>` already exists; if so it **skips build/push** and goes straight
  to deploy. Re-runs are safe.
- **Graceful "no cluster" skip.** Because the GPU cluster is deliberately torn
  down between sessions to save money, the deploy step checks
  `cluster.status == ACTIVE`. If the cluster is down, the image is still pushed
  and the deploy is **skipped without failing** the run.
- **Deploy via `kustomize` + `kubectl apply -k`.** When the cluster is up,
  `kustomize edit set image` pins the freshly pushed tag and `kubectl apply -k`
  applies it — **idempotent**: it creates the namespace/Service/Ingress/
  Deployment on a fresh cluster, or performs a rolling update on an existing one.

📐 **[Pipeline walkthrough + rationale → docs/cicd.md](docs/cicd.md)**

---

## Tech stack

- **Cloud / IaC:** AWS (EKS, VPC, ECR, IAM, S3, CloudWatch, SNS), Terraform (`~> 6.0` AWS provider), upstream `terraform-aws-modules`
- **Orchestration:** Kubernetes 1.33, Helm, AWS Load Balancer Controller, NVIDIA device plugin, EBS CSI
- **Compute / ML serving:** NVIDIA A10G GPU (`g5.xlarge`), `llama.cpp` (`llama-server`), quantized Llama 3.2 (GGUF)
- **App / tooling:** Docker (CUDA), Python (OpenAI SDK client)

---

## Quickstart

```bash
# 1. Provision the VPC + EKS cluster (~15-20 min)
cd infra && terraform init && terraform apply

# 2. Point kubectl at the cluster
aws eks update-kubeconfig --name aws-llm-eks --region us-east-1

# 3. Build + push the inference image, then deploy the workload
cd ../llm && ./build-and-push.sh      # prints the image URI (…/aws-llm-ecr:sha-<gitsha>)
cd ../k8s
kustomize edit set image llm-inference=<pushed-image-uri>   # pin the tag CI would deploy
kubectl apply -k .                    # (CI does steps 3-4 automatically on push to main)
cd ..

# 4. Get the public ALB URL
kubectl get ingress llm-inference -n llm \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Then talk to the model:

```bash
cp client/.env.example client/.env      # set LLM_ENDPOINT=http://<alb-hostname>
pip install -r client/requirements.txt
python client/chat.py
```

Full prerequisites, deploy walkthrough, CI/CD design, and monitoring design live
in **[DESIGN.md](DESIGN.md)**.

---

## Repository layout

| Path | Contents |
| --- | --- |
| `infra/` | Terraform root + 4 modules (`networking`, `compute`, `storage`, `monitoring`) |
| `infra/bootstrap/` | Standalone config that creates the S3 remote-state bucket |
| `llm/` | CUDA `llama.cpp` Dockerfile + `build-and-push.sh` |
| `k8s/` | Namespace, Deployment, Service, Ingress manifests |
| `client/` | `chat.py` — streaming CLI client (OpenAI SDK) |

---

## Contact

**Lavale Butterfield**

- 💼 LinkedIn: _add your LinkedIn URL_
- 📧 Email: lavale889@gmail.com
- 🌐 Portfolio: _add your portfolio/site URL_

_Open to cloud engineering, DevOps, and platform/infrastructure roles._
