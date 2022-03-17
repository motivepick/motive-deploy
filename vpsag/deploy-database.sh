#!/usr/bin/env bash

helm repo add bitnami https://charts.bitnami.com/bitnami

helm repo update

kubectl apply -f database/postgres-pv.yaml -n app
kubectl apply -f database/postgres-pvc.yaml -n app

# Note: you should do it in app namespace!
helm install motive-postgres bitnami/postgresql --set primary.persistence.existingClaim=postgres-pvc --set primary.resources.requests.cpu=0 --set volumePermissions.enabled=true

# helm uninstall motive-postgres