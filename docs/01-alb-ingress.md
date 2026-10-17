# Optional: Expose the Website with an ALB and Ingress

The main lab uses a `Service` of `type: LoadBalancer`, which gives each service its own load
balancer. In production you usually use one **Application Load Balancer (ALB)** for many
services, configured through a Kubernetes **Ingress** and the
**AWS Load Balancer Controller**.

Do this **after** finishing Step 6 of the main guide.

## 1. Create an IAM policy for the controller

```bash
curl -fsSLo iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.2/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

## 2. Create a service account with that role (IRSA)

The cluster was created with `withOIDC: true`, so this works out of the box:

```bash
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME --region $AWS_REGION \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

## 3. Install the controller with Helm

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION \
  --query cluster.resourcesVpcConfig.vpcId --output text)

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$VPC_ID

kubectl get deployment -n kube-system aws-load-balancer-controller
```

## 4. Switch the Service to ClusterIP and add an Ingress

```bash
kubectl patch svc website -n website -p '{"spec":{"type":"ClusterIP"}}'
```

Save as `ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: website
  namespace: website
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /health
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: website
                port:
                  number: 80
```

```bash
kubectl apply -f ingress.yaml
kubectl get ingress website -n website -w   # wait for ADDRESS (2-3 min)
```

Open `http://<ADDRESS>`. `target-type: ip` sends traffic straight to pod IPs (thanks to the
VPC CNI), skipping NodePorts.

## 5. Clean up

Delete the Ingress **before** deleting the cluster so the controller removes the ALB:

```bash
kubectl delete ingress website -n website
helm uninstall aws-load-balancer-controller -n kube-system
eksctl delete iamserviceaccount --cluster $CLUSTER_NAME --region $AWS_REGION \
  --namespace kube-system --name aws-load-balancer-controller
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy
```
