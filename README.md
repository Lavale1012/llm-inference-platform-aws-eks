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
> **Status:** Terraform + Kubernetes manifests are complete and validated.
> CI/CD and Prometheus/Grafana are designed and documented as next steps.

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

Four color-coded flows: the **request path ①②③** (client → ALB → GPU pod), the
**CI/CD path ⒶⒷⒸⒹ** (GitHub Actions → OIDC → ECR / Terraform / deploy), the
private **image pull** (pod → VPC endpoints → ECR), and **observability**
(CloudWatch → SNS). Each node is annotated with _why_ that service was chosen.

A client sends `POST /v1/chat/completions` to the ALB → the request routes to
the `llama-server` pod on a GPU node → inference runs on the NVIDIA A10G and
streams back an OpenAI-format response.

📐 **[Full architecture, request flow, and design rationale → DESIGN.md](DESIGN.md)**

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
cd ../llm && ./build-and-push.sh      # prints the image URI → set it in k8s/deployment.yaml
cd .. && kubectl apply -f k8s/

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
