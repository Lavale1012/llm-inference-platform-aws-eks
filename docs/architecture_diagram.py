#!/usr/bin/env python3
"""Render the aws-llm architecture with official AWS service icons.

Requires:  brew install graphviz   &&   pip install diagrams
Run:       python3 docs/architecture_diagram.py
Output:    docs/architecture.png

The graph is grounded in the Terraform under infra/ and the workflows under
.github/. Two flows are drawn:
  • the request path (client → ALB → llama-server pod), solid edges
  • the CI/CD path (developer → GitHub Actions → AWS), dashed blue edges
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EKS, EC2, ECR
from diagrams.aws.network import (
    ElbApplicationLoadBalancer,
    NATGateway,
    InternetGateway,
    VPC,
    Endpoint,
)
from diagrams.aws.storage import S3
from diagrams.aws.management import Cloudwatch
from diagrams.aws.integration import SimpleNotificationServiceSns as SNS
from diagrams.aws.security import IdentityAndAccessManagementIamRole as IAMRole
from diagrams.onprem.client import Users
from diagrams.onprem.ci import GithubActions

# Global graph styling: left-to-right, roomy spacing, readable fonts.
# Generous nodesep/ranksep keep node labels from colliding; bigger fonts make
# the diagram legible when embedded or exported.
graph_attr = {
    "fontsize": "26",
    "labelloc": "t",
    "fontname": "Helvetica-Bold",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "1.1",
    "ranksep": "1.9",
    "splines": "spline",
    "concentrate": "false",
}
# Bigger node text + margin so multi-line labels don't touch neighbours.
node_attr = {"fontname": "Helvetica", "fontsize": "15", "margin": "0.3,0.2"}
cluster_fontsize = "18"

# Edge styles for the four distinct flows (bigger, readable labels).
REQ = {"color": "#2d6a4f", "penwidth": "2.6", "fontname": "Helvetica-Bold", "fontsize": "14", "fontcolor": "#1b4332"}
CICD = {"color": "#2088ff", "penwidth": "2.4", "style": "dashed", "fontname": "Helvetica-Bold", "fontsize": "14", "fontcolor": "#0b5cff"}
PULL = {"color": "#b45f18", "penwidth": "2.0", "fontname": "Helvetica", "fontsize": "13", "fontcolor": "#8a4712"}
OBS = {"color": "#e7157b", "penwidth": "1.8", "style": "dotted", "fontname": "Helvetica", "fontsize": "13", "fontcolor": "#a30d57"}

with Diagram(
    "aws-llm — LLM Inference Platform on AWS EKS\n"
    "Request path ①②③ (green)   ·   CI/CD path ⒶⒷⒸⒹ (blue)   ·   "
    "image pull (orange)   ·   observability (pink)",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    node_attr=node_attr,
):
    client = Users("Client\n(chat.py / curl)")
    dev = Users("Developer\n(git push / PR)")

    with Cluster("CI/CD", graph_attr={"fontsize": cluster_fontsize}):
        # why GitHub Actions + OIDC: no long-lived AWS keys in the repo.
        gha = GithubActions("GitHub Actions\napp.yml · infra.yml\n"
                            "why: keyless CI via OIDC")

    with Cluster("AWS · us-east-1", graph_attr={"fontsize": cluster_fontsize}):
        # Supporting / regional services (outside the VPC).
        oidc = IAMRole("OIDC role\naws-llm-github-actions\n"
                      "why: short-lived, scoped creds")
        ecr = ECR("ECR (private)\naws-llm-ecr\n"
                 "why: in-region, immutable\n+ scan-on-push")
        tfstate = S3("S3 remote state\naws-llm-tfstate-us-east-1\n"
                    "why: shared state + locking")

        with Cluster("CloudWatch", graph_attr={"fontsize": cluster_fontsize}):
            cw = Cloudwatch("Alarms\nbilling · node CPU/mem · 5xx")
            sns = SNS("SNS\nemail")
            cw >> Edge(**OBS) >> sns

        with Cluster("VPC · 10.0.0.0/16 · 2 AZs (us-east-1a/b)", graph_attr={"fontsize": cluster_fontsize}):
            with Cluster("Public subnets · 10.0.10-11.0/24", graph_attr={"fontsize": cluster_fontsize}):
                igw = InternetGateway("Internet Gateway")
                # why LB Controller (not a static aws_lb): the cluster owns its
                # own L7 entrypoint via a K8s Ingress.
                alb = ElbApplicationLoadBalancer("Application Load Balancer\n"
                                                "why: cluster-managed L7\n(from a K8s Ingress)")
                # why NAT + private nodes: nodes have no public IP; egress only.
                nat = NATGateway("NAT gateways ×2\nwhy: private-node egress")

            with Cluster("Private subnets · 10.0.1-2.0/24", graph_attr={"fontsize": cluster_fontsize}):
                # why endpoints: image pulls stay on the AWS backbone, off NAT.
                vpce = Endpoint("VPC endpoints\nS3 · ECR api/dkr · CW logs\n"
                               "why: private, cheaper pulls")

                with Cluster("EKS · aws-llm-eks · v1.33", graph_attr={"fontsize": cluster_fontsize}):
                    with Cluster("system node group · m5.xlarge", graph_attr={"fontsize": cluster_fontsize}):
                        # why a separate CPU pool: keep add-ons off costly GPUs.
                        system = EC2("CoreDNS · LB Controller\nNVIDIA plugin · EBS CSI\n"
                                    "CW Observability\nwhy: cheap CPU for add-ons")

                    with Cluster("gpu node group · g5.xlarge (A10G)\ntaint nvidia.com/gpu", graph_attr={"fontsize": cluster_fontsize}):
                        # why GPU + llama.cpp CUDA: A10G runs the quantized model
                        # fast; taint reserves the pricey node for inference only.
                        llm = EC2("llm-inference pod\nllama-server :8080\n"
                                 "Llama-3.2-1B GGUF (CUDA)\nwhy: GPU-accelerated inference")

    # ---- Request path (solid green): client → ALB → llama-server pod ---------
    client >> Edge(label="① HTTPS :80  /v1/chat/completions", **REQ) >> igw
    igw >> Edge(label="②", **REQ) >> alb
    alb >> Edge(label="③ forward to pod IP\n(target-type: ip, via VPC CNI)", **REQ) >> llm

    # ---- Image pull (orange): pod pulls from ECR privately via endpoints -----
    llm >> Edge(label="pulls image via", **PULL) >> vpce
    vpce >> Edge(label="", **PULL) >> ecr

    # ---- Egress (orange, dashed): pod → NAT → internet -----------------------
    llm >> Edge(label="egress →", style="dashed", **{k: v for k, v in PULL.items() if k != "style"}) >> nat
    nat >> Edge(label="", style="dashed", **{k: v for k, v in PULL.items() if k != "style"}) >> igw

    # ---- CI/CD path (dashed blue): developer → GitHub Actions → AWS ----------
    # One consolidated arrow into AWS (via the OIDC role, the pipeline's entry
    # point) instead of four long edges fanning out to ECR/S3/pod — the label
    # spells out the sequence, so the flow stays clear without the sprawl.
    dev >> Edge(label="git push / PR", **CICD) >> gha
    gha >> Edge(
        label=("CI/CD pipeline (via OIDC role):\n"
               "Ⓐ assume-role  →  Ⓑ push image sha-<gitsha> to ECR\n"
               "Ⓒ terraform plan/apply (gated on main)\n"
               "Ⓓ kubectl apply -k  →  rolls Deployment (if cluster up)"),
        **CICD,
    ) >> oidc

    # ---- Observability (dotted pink): cluster → CloudWatch alarms → SNS ------
    llm >> Edge(label="", **OBS) >> cw
    system >> Edge(label="metrics / logs", **OBS) >> cw
