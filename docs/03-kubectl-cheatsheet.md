# kubectl Cheat Sheet for This Lab

Tip: set the default namespace so you can drop `-n website`:

```bash
kubectl config set-context --current --namespace=website
```

## Inspect

```bash
kubectl get nodes -o wide                 # cluster nodes
kubectl get all -n website                # everything in the namespace
kubectl get pods -n website -o wide       # pods + which node they run on
kubectl describe deployment website -n website
kubectl get svc website -n website        # load balancer hostname
kubectl get hpa -n website
kubectl top nodes && kubectl top pods -n website
```

## Logs and shell

```bash
kubectl logs -n website deploy/website              # one pod of the deployment
kubectl logs -n website -l app=website -f           # follow all pods
kubectl exec -it -n website deploy/website -- sh    # shell inside a pod
kubectl port-forward -n website svc/website 8080:80 # test locally at http://localhost:8080
```

## Deploy and update

```bash
kubectl apply -f k8s/                               # (after filling the image placeholder)
kubectl set image deployment/website website=$ECR_URI:v3 -n website
kubectl rollout status deployment/website -n website
kubectl rollout history deployment/website -n website
kubectl rollout undo deployment/website -n website
kubectl rollout restart deployment/website -n website
kubectl scale deployment/website --replicas=3 -n website
```

## Clean up

```bash
kubectl delete -f k8s/
kubectl delete namespace website
```
