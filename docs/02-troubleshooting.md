# Troubleshooting

Start with these three commands. They explain most problems:

```bash
kubectl get pods -n website
kubectl describe pod -n website -l app=website      # read the Events at the bottom
kubectl get events -n website --sort-by=.lastTimestamp
```

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `kubectl get nodes` → `error: You must be logged in to the server (Unauthorized)` | Your IAM identity isn't the cluster creator / has no access entry | Use the same AWS profile that created the cluster, or add an access entry: `eksctl create accessentry --cluster $CLUSTER_NAME --principal-arn <your-arn>`, then associate `AmazonEKSClusterAdminPolicy` |
| `couldn't get current server API group list` / connection refused | Kubeconfig points at the wrong cluster | `aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION` |
| Pod `ImagePullBackOff` / `ErrImagePull` | Wrong image URI/tag, or the image is in another region | `kubectl describe pod ...` shows the URI; check `aws ecr list-images --repository-name eks-website` |
| Pod `CrashLoopBackOff`, logs show `exec format error` | Image built for ARM (Apple Silicon) | Rebuild with `docker build --platform linux/amd64 ...` and push again |
| Pod `CreateContainerConfigError: container has runAsNonRoot and image has non-numeric user` | Image sets a user name, not a UID | Keep `USER 101` (numeric) in the Dockerfile |
| Pods `Pending` with `Insufficient cpu` | Nodes are full | `kubectl scale deployment/website -n website --replicas=2`, or raise the node group size |
| Pods `Running` but `READY 0/1` | Readiness probe failing | `kubectl logs ...`; make sure `/health` answers on port 8080 |
| Service `EXTERNAL-IP` stays `<pending>` | Load balancer still provisioning, or subnets missing ELB tags | Wait 3 min; `kubectl describe svc website -n website` shows errors. eksctl-created VPCs are tagged correctly |
| URL doesn't load right away | DNS for the new ELB not propagated yet | Wait 1–2 minutes; try `curl` again |
| HPA shows `<unknown>/60%` | metrics-server not running, or pods have no CPU requests | `kubectl get deployment metrics-server -n kube-system`; the Deployment already sets requests |
| `eksctl delete cluster` hangs or VPC stack fails to delete | A load balancer created by Kubernetes is still attached | Delete the `website` namespace (or Service/Ingress) first, then delete leftover ELBs in the EC2 console and retry |
| `envsubst: command not found` | gettext not installed | `brew install gettext` / `sudo apt install gettext-base` |
