#!/usr/bin/env bash

export APP_NAMESPACE_NAME="motive"
export APP_INGRESS_NAME="motive-ingress"
export APP_DATABASE_NAME="motive-database"
export APP_INGRESS_CONTROLLER_REPLICA_COUNT=1
export BACK_END_PUBLIC_IP="185.203.117.158"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

echo "Creating namespace $APP_NAMESPACE_NAME..."
envsubst <namespace.yaml | kubectl apply -f -

echo "Creating ingress $APP_INGRESS_NAME..."
helm install $APP_INGRESS_NAME ingress-nginx/ingress-nginx \
  --version 3.35.0 \
  --namespace $APP_NAMESPACE_NAME \
  --create-namespace \
  --set "controller.service.externalIPs[0]=$BACK_END_PUBLIC_IP" \
  --set controller.replicaCount=$APP_INGRESS_CONTROLLER_REPLICA_COUNT \
  --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
  --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux

# TODO: you may need to wait a bit here otherwise you may have connection refused on the ingress.yaml creation. How to automate this?
# TODO: solve the issue described here: https://stackoverflow.com/a/64872084/1862286
kubectl apply -f ingress.yaml -n $APP_NAMESPACE_NAME

echo "Creating database..."
# TODO: even though you create new PV here, files from the old one still may persist on the node file system and contain old password PostgreSQL
# will reuse. Find a way to remove old PV together with the files.
kubectl apply -f database-pv.yaml -n $APP_NAMESPACE_NAME
kubectl apply -f database-pvc.yaml -n $APP_NAMESPACE_NAME

helm install $APP_DATABASE_NAME bitnami/postgresql \
  --namespace $APP_NAMESPACE_NAME \
  --set primary.persistence.existingClaim=database-pvc \
  --set primary.resources.requests.cpu=0 \
  --set volumePermissions.enabled=true

helm uninstall $APP_DATABASE_NAME
kubectl delete pvc database-pvc -n $APP_NAMESPACE_NAME
kubectl delete pv database-pv -n $APP_NAMESPACE_NAME

# motive-database-postgresql.motive.svc.cluster.local

export DATABASE_JDBC_URL="jdbc:postgresql://$APP_DATABASE_NAME-postgresql.motive.svc.cluster.local:5432/motive"
export DATABASE_USERNAME="postgres"
export POSTGRES_PASSWORD=$(kubectl get secret --namespace $APP_NAMESPACE_NAME $APP_DATABASE_NAME-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
kubectl run $APP_DATABASE_NAME-postgresql-client --rm --tty -i --restart='Never' --namespace $APP_NAMESPACE_NAME --image docker.io/bitnami/postgresql:14.2.0-debian-10-r31 \
  --command -- psql postgresql://$DATABASE_USERNAME:"$POSTGRES_PASSWORD"@$APP_DATABASE_NAME-postgresql:5432 -c "CREATE DATABASE motive ENCODING 'UTF8' TEMPLATE template0;"

# TODO create database itself
