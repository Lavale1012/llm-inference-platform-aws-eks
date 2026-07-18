#!/usr/bin/env python3
"""Render the aws-llm CI/CD pipeline with GitHub + AWS icons.

Companion to docs/cicd.mmd (the detailed decision flowchart) — this is the
icon-based overview, styled to match docs/architecture_diagram.py.

Requires:  brew install graphviz && pip install diagrams
Run:       python3 docs/cicd_diagram.py   ->  docs/cicd-overview.png
"""
from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.vcs import Github
from diagrams.onprem.ci import GithubActions
from diagrams.aws.compute import ECR, EKS
from diagrams.aws.storage import S3
from diagrams.aws.security import IdentityAndAccessManagementIamRole as IAMRole
from diagrams.programming.flowchart import Decision

graph_attr = {
    "fontsize": "24",
    "labelloc": "t",
    "fontname": "Helvetica-Bold",
    "bgcolor": "white",
    "pad": "1.4",
    "nodesep": "0.9",
    "ranksep": "1.5",
    "splines": "spline",
}
node_attr = {"fontname": "Helvetica", "fontsize": "14", "margin": "0.25,0.18"}
cluster_fs = {"fontsize": "18"}

PR = {"color": "#6b7280", "penwidth": "2.0", "style": "dashed", "fontname": "Helvetica-Bold", "fontsize": "13", "fontcolor": "#374151"}
MAIN = {"color": "#2088ff", "penwidth": "2.6", "fontname": "Helvetica-Bold", "fontsize": "13", "fontcolor": "#0b5cff"}
GATE = {"color": "#b45309", "penwidth": "2.4", "fontname": "Helvetica-Bold", "fontsize": "13", "fontcolor": "#b45309"}

with Diagram(
    "aws-llm — CI/CD pipeline (GitHub Actions)\n"
    "PR = checks only (dashed)   ·   push to main = build/apply (blue)   ·   "
    "🔒 = manual-approval / guard",
    filename="docs/cicd-overview",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    node_attr=node_attr,
):
    dev = Github("Developer\nPR / push to main")

    with Cluster("Trigger (path-filtered)", graph_attr=cluster_fs):
        gha = GithubActions("GitHub Actions\napp.yml · infra.yml\nOIDC → AWS role (no keys)")

    dev >> Edge(label="git event", **MAIN) >> gha

    # ---------------- app.yml : image + deploy ----------------
    with Cluster("app.yml  ·  llm/** or k8s/**", graph_attr=cluster_fs):
        img_guard = Decision("tag in ECR?\n(immutable → skip)")
        ecr = ECR("ECR (private)\nsha-<gitsha>")
        cluster_guard = Decision("cluster ACTIVE?\n(else skip deploy)")
        eks = EKS("EKS: kubectl apply -k\nrolls Deployment")

        gha >> Edge(label="PR: build only\n(no push)", **PR) >> ecr
        gha >> Edge(label="main: build →", **MAIN) >> img_guard
        img_guard >> Edge(label="push", **MAIN) >> ecr
        ecr >> Edge(label="deploy →", **MAIN) >> cluster_guard
        cluster_guard >> Edge(label="🔒 if up", **GATE) >> eks

    # ---------------- infra.yml : terraform ----------------
    with Cluster("infra.yml  ·  infra/**", graph_attr=cluster_fs):
        plan_guard = Decision("plan has\nchanges? (exit 2)")
        tfstate = S3("S3 remote state\nplan / apply")
        approval = Decision("🔒 production-infra\nmanual approval")

        gha >> Edge(label="PR: fmt/validate/plan\n→ PR comment", **PR) >> tfstate
        gha >> Edge(label="main: plan →", **MAIN) >> plan_guard
        plan_guard >> Edge(label="changes", **GATE) >> approval
        approval >> Edge(label="apply", **MAIN) >> tfstate

    # OIDC role both pipelines assume.
    with Cluster("IAM", graph_attr=cluster_fs):
        role = IAMRole("aws-llm-github-actions\nECR push · EKS (ns=llm) · tfstate")
    gha >> Edge(label="assume-role (OIDC)", **PR) >> role
