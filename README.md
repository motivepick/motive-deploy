# Motive Deploy

In order to deploy Motive infrastructure into a new Azure Managed Kubernetes Service, run `azure/create-environment.sh`.

In order to deploy Motive infrastructure into a new Kubernetes cluster, run `kubernetes/deploy.sh`.

### Configuring VPS.AG

1. Purchase the servers with Ubuntu.
2. Make backups of every service immediately.
3. Install Kubernetes cluster on the servers.

### Connecting To Kubernetes Database From Local Machine

```shell
kubectl port-forward --namespace motive svc/motive-database-postgresql 5432:5432
```
