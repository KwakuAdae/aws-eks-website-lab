# Lab: Deploy a Website to Amazon EKS (Elastic Kubernetes Service)

A hands-on lab that takes a static website, packages it as a Docker image, pushes it to
**Amazon ECR**, and runs it on a **Kubernetes cluster in Amazon EKS**. The site sits behind
an AWS load balancer and has health checks, zero-downtime rolling updates and autoscaling.

```
 ┌────────────┐ docker build ┌─────────────┐ docker push ┌────────────┐
 │ app/ (HTML,│ ───────────▶ │ Docker image│ ──────────▶ │ Amazon ECR │
 │ CSS, nginx)│              │ (nginx)     │             └─────┬──────┘
 └────────────┘              └─────────────┘                   │ image pulled by nodes
                                                               ▼
                    ┌───────────────────── Amazon EKS cluster ─────────────────────┐
 ┌─────────┐  HTTP  │  ┌──────────────┐     ┌───────────────────────────────────┐  │
 │ Browser │ ─────▶ │  │ AWS Load     │ ──▶ │ Service (type: LoadBalancer)      │  │
 └─────────┘   :80  │  │ Balancer     │     │   ├─▶ Pod (website) on node 1     │  │
                    │  └──────────────┘     │   └─▶ Pod (website) on node 2     │  │
                    │                       └───────────────────────────────────┘  │
                    │  Deployment (2-6 replicas, scaled by HPA)  · namespace: website │
                    │  Managed node group: 2 × t3.medium (EC2)                       │
                    └────────────────────────────────────────────────────────────────┘
```

## What you will learn

- Containerizing a website with **non-root nginx** and a `/health` endpoint
- Creating an EKS cluster and managed node group with **eksctl**
- Pushing an image to **ECR** and letting EKS nodes pull it
- Writing Kubernetes **Namespace, Deployment, Service and HorizontalPodAutoscaler** manifests
- Readiness/liveness probes, resource requests/limits and security context
- Exposing an app to the internet with a `LoadBalancer` Service
- Rolling updates, rollbacks, scaling, logs and cleanup

## Project structure

```
aws-eks-website-lab/
├── app/
│   ├── Dockerfile          # nginx-unprivileged image (port 8080, non-root)
│   ├── nginx.conf          # site config + /health endpoint
│   ├── entrypoint.sh       # injects the pod name into the page
│   ├── index.html
│   └── styles.css
├── eks/
│   └── cluster.yaml        # eksctl cluster + managed node group definition
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 01-deployment.yaml  # 2 replicas, probes, limits, rolling update
│   ├── 02-service.yaml     # type LoadBalancer → AWS ELB
│   └── 03-hpa.yaml         # autoscale 2-6 pods on CPU
├── scripts/
│   ├── config.sh           # shared settings
│   ├── 01-create-cluster.sh
│   ├── 02-push-to-ecr.sh
│   ├── 03-deploy-to-eks.sh
│   └── 04-cleanup.sh
└── docs/
    ├── 01-alb-ingress.md       # optional: ALB + Ingress via AWS Load Balancer Controller
    ├── 02-troubleshooting.md
    └── 03-kubectl-cheatsheet.md
```

## Prerequisites

| Tool | Check | Install |
|------|-------|---------|
| AWS account | — | ⚠️ EKS is **not** free tier, see [Cost](#cost-estimate) |
| AWS CLI v2 | `aws --version` | [docs](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), then `aws configure` |
| eksctl | `eksctl version` | `brew install eksctl` or [eksctl.io](https://eksctl.io/installation/) |
| kubectl | `kubectl version --client` | `brew install kubectl` or [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| Docker | `docker --version` | Docker Desktop |
| envsubst | `envsubst --version` | `brew install gettext` / `sudo apt install gettext-base` |

Your IAM user/role needs permissions for EKS, EC2, IAM, CloudFormation (eksctl uses it), ECR
and Elastic Load Balancing. For a personal lab account, `AdministratorAccess` is simplest.

```bash
aws sts get-caller-identity
```

---

## Quick start (automated)

```bash
git clone https://github.com/KwakuAdae/aws-eks-website-lab.git
cd aws-eks-website-lab

./scripts/01-create-cluster.sh   # ~15-20 min
./scripts/02-push-to-ecr.sh
./scripts/03-deploy-to-eks.sh    # prints the website URL
./scripts/04-cleanup.sh          # IMPORTANT: delete everything when done
```

The rest of this guide does every step **by hand** so you understand what the scripts do.

---

## Step 0: Set variables

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME=eks-website-lab
export ECR_REPO=eks-website
export IMAGE_TAG=v1
export ECR_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO
```

## Step 1: Create the EKS cluster

[`eks/cluster.yaml`](eks/cluster.yaml) describes the cluster: Kubernetes 1.31, an OIDC
provider (for IAM roles for service accounts), a **managed node group** of 2 × `t3.medium`
instances, and the `metrics-server` add-on used by the autoscaler.

```bash
eksctl create cluster -f eks/cluster.yaml
```

eksctl builds a new VPC (public + private subnets in several AZs), the EKS control plane, and
the node group, all through CloudFormation. This takes **15–20 minutes**.

> Using a region other than `us-east-1`? Edit `metadata.region` in `eks/cluster.yaml` first
> (the script does this for you).

eksctl writes your kubeconfig automatically. On another machine, run:

```bash
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
```

✅ **Checkpoint:**

```bash
kubectl get nodes
# NAME                             STATUS   ROLES    AGE   VERSION
# ip-192-168-12-34.ec2.internal    Ready    <none>   2m    v1.31.x
# ip-192-168-56-78.ec2.internal    Ready    <none>   2m    v1.31.x
```

## Step 2: Build and test the image locally

```bash
docker build --platform linux/amd64 -t $ECR_URI:$IMAGE_TAG app
docker run --rm -d -p 8080:8080 -e POD_NAME=my-laptop --name web $ECR_URI:$IMAGE_TAG
curl http://localhost:8080/health    # -> OK
curl -s http://localhost:8080 | grep "pod:"
docker stop web
```

> **Why port 8080 and non-root?** The `nginx-unprivileged` image runs as UID 101 and can't
> bind to ports below 1024. Running containers as non-root is a Kubernetes security best
> practice, and the Deployment enforces it with `runAsNonRoot: true`.

## Step 3: Push the image to ECR

```bash
aws ecr create-repository --repository-name $ECR_REPO \
  --image-scanning-configuration scanOnPush=true --region $AWS_REGION

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker push $ECR_URI:$IMAGE_TAG
```

The node group's IAM role already has `AmazonEC2ContainerRegistryReadOnly` (eksctl attaches it),
so the nodes can pull from ECR without any image pull secret.

## Step 4: Understand the Kubernetes manifests

| File | Kind | What it does |
|------|------|--------------|
| `00-namespace.yaml` | Namespace | Isolates the lab's resources in `website` |
| `01-deployment.yaml` | Deployment | Runs 2 replicas of the container, with readiness/liveness probes on `/health`, CPU/memory requests and limits, and a rolling update with `maxUnavailable: 0` |
| `02-service.yaml` | Service | `type: LoadBalancer` makes EKS provision an AWS load balancer that forwards port 80 → pod port 8080 |
| `03-hpa.yaml` | HorizontalPodAutoscaler | Keeps average CPU ≈ 60% by scaling between 2 and 6 pods |

The Deployment uses the **Downward API** to pass the pod's name into the container as
`POD_NAME`, so each page shows which pod served it. Refresh the page and you'll see the load
balancer spreading requests across pods.

## Step 5: Deploy to EKS

The Deployment's image is a placeholder (`${ECR_URI}:${IMAGE_TAG}`); `envsubst` fills it in:

```bash
for f in k8s/*.yaml; do envsubst '${ECR_URI} ${IMAGE_TAG}' < $f; echo "---"; done | kubectl apply -f -

kubectl rollout status deployment/website -n website
kubectl get all -n website
```

## Step 6: Open the website

```bash
kubectl get svc website -n website
# NAME      TYPE           CLUSTER-IP     EXTERNAL-IP                                  PORT(S)
# website   LoadBalancer   10.100.x.x     a1b2c3...us-east-1.elb.amazonaws.com         80:3xxxx/TCP

export LB=$(kubectl get svc website -n website -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$LB"
curl http://$LB/health
```

The load balancer takes **1–3 minutes** to provision and its DNS name another minute or two to
resolve. Then open the URL in your browser. 🎉

Watch requests spread across pods:

```bash
for i in $(seq 1 6); do curl -s http://$LB | grep -o 'pod: <code>[^<]*'; done
```

## Step 7: Self-healing

Delete a pod and watch Kubernetes replace it:

```bash
kubectl get pods -n website -w &
kubectl delete pod -n website $(kubectl get pods -n website -o name | head -1 | cut -d/ -f2)
# a new pod appears within seconds; press Ctrl+C / `kill %1` to stop watching
```

## Step 8: Roll out a new version (and roll back)

1. Edit `app/index.html` (change `v1` to `v2`, or change the heading).
2. Build, push and deploy with a new tag:

```bash
export IMAGE_TAG=v2
./scripts/02-push-to-ecr.sh
./scripts/03-deploy-to-eks.sh

kubectl rollout history deployment/website -n website
```

Made a mistake? Roll back instantly:

```bash
kubectl rollout undo deployment/website -n website
```

## Step 9: Scaling

Manual scaling (the HPA will bring it back within its 2–6 range):

```bash
kubectl scale deployment/website -n website --replicas=4
kubectl get pods -n website
```

Autoscaling: generate load and watch the HPA react:

```bash
kubectl run load -n website --image=busybox:1.36 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://website; done"

kubectl get hpa website -n website -w     # TARGETS climbs; REPLICAS increases
kubectl delete pod load -n website        # stop the load
```

## Step 10: Logs and debugging

```bash
kubectl logs -n website -l app=website --tail=20
kubectl describe pod -n website -l app=website
kubectl top pods -n website                 # uses metrics-server
kubectl get events -n website --sort-by=.lastTimestamp
```

## Step 11: Clean up (very important!)

An EKS cluster costs money **every hour**, even when idle. Delete everything:

```bash
./scripts/04-cleanup.sh
```

or by hand, **in this order** (deleting the Service first removes the AWS load balancer;
otherwise it can block VPC deletion):

```bash
kubectl delete namespace website
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION --wait
aws ecr delete-repository --repository-name $ECR_REPO --force --region $AWS_REGION
```

Double-check in the console that the **CloudFormation stacks** `eksctl-eks-website-lab-*` are
gone and no **load balancers** remain under EC2 → Load Balancers.

---

## Cost estimate

| Resource | Approx. cost (us-east-1) |
|----------|--------------------------|
| EKS control plane | $0.10 / hour |
| 2 × t3.medium nodes | ~$0.083 / hour |
| Classic Load Balancer | ~$0.025 / hour |
| NAT gateway (created by eksctl) | ~$0.045 / hour + data |
| EBS volumes, ECR, public IPs | a few cents |

**About $0.25–0.30 per hour.** A 2-hour lab session costs well under $1. Leaving the cluster
running for a month costs **~$200**, so always clean up.

## Going further

- **ALB + Ingress** with the AWS Load Balancer Controller → [docs/01-alb-ingress.md](docs/01-alb-ingress.md)
- HTTPS with an ACM certificate and a Route 53 domain
- Package the manifests as a **Helm chart** or with **Kustomize** overlays (dev/prod)
- GitOps with **Argo CD** or **Flux**
- CI/CD: GitHub Actions → ECR → `kubectl set image`
- Cluster autoscaling with **Karpenter**
- Compare with the sister lab: [ECS Fargate lab](https://github.com/KwakuAdae/aws-ecr-ecs-fargate-lab)

## Troubleshooting

See [docs/02-troubleshooting.md](docs/02-troubleshooting.md) and the
[kubectl cheat sheet](docs/03-kubectl-cheatsheet.md).

## Author

**Kwaku Adae**: [github.com/KwakuAdae](https://github.com/KwakuAdae)

Feedback and reviews are welcome. Open an issue or a pull request!
