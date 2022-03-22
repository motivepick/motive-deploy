#!/usr/bin/env bash

export APP_NAMESPACE_NAME="motive"
export APP_INGRESS_NAME="motive-ingress"
export APP_DATABASE_NAME="motive-database"
export APP_INGRESS_CONTROLLER_REPLICA_COUNT=1
export BACK_END_PUBLIC_IP="185.203.117.158"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add jetstack https://charts.jetstack.io
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
kubectl apply -f database-pv.yaml -n $APP_NAMESPACE_NAME
kubectl apply -f database-pvc.yaml -n $APP_NAMESPACE_NAME

helm install $APP_DATABASE_NAME bitnami/postgresql \
  --version 11.1.7 \
  --namespace $APP_NAMESPACE_NAME \
  --set primary.persistence.existingClaim=database-pvc \
  --set primary.resources.requests.cpu=0 \
  --set volumePermissions.enabled=true

kubectl apply -f config-map.yaml -n $APP_NAMESPACE_NAME

# kubectl port-forward --namespace motive svc/motive-database-postgresql 5432:5432
export DATABASE_JDBC_URL="jdbc:postgresql://$APP_DATABASE_NAME-postgresql.motive.svc.cluster.local:5432/motive"
DATABASE_USERNAME=$(kubectl get configmap --namespace $APP_NAMESPACE_NAME motive-config -o jsonpath="{.data.postgres-username}")
POSTGRES_PASSWORD=$(kubectl get secret --namespace $APP_NAMESPACE_NAME $APP_DATABASE_NAME-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
# TODO create database in a more robust way
kubectl run $APP_DATABASE_NAME-postgresql-client --rm --tty -i --restart='Never' --namespace $APP_NAMESPACE_NAME --image docker.io/bitnami/postgresql:14.2.0-debian-10-r31 \
  --command -- psql postgresql://"$DATABASE_USERNAME":"$POSTGRES_PASSWORD"@$APP_DATABASE_NAME-postgresql:5432 -c "CREATE DATABASE motive ENCODING 'UTF8' TEMPLATE template0;"

echo "Creating back end service..."
kubectl apply --namespace $APP_NAMESPACE_NAME -f back-end-service.yaml

echo "Creating back end deployment..."
envsubst <back-end-deployment.yaml | kubectl apply -f - -n $APP_NAMESPACE_NAME

echo "Configuring HTTPS..."
helm install cert-manager jetstack/cert-manager \
  --namespace $APP_NAMESPACE_NAME \
  --version v1.3.1 \
  --set installCRDs=true

kubectl apply --namespace $APP_NAMESPACE_NAME -f ssl-tls-cluster-issuer.yaml

kubectl apply --namespace $APP_NAMESPACE_NAME -f ssl-tls-ingress.yaml

# TODO: automate checking for the "The certificate has been successfully issued" event
# kubectl describe cert app-web-cert --namespace $APP_NAMESPACE_NAME
