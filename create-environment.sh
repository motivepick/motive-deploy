#!/usr/bin/env bash

# init

RESOURCE_GROUP_NAME=MotiveResourceGroup
ACR_NAME=motivecr
AKS_NAME=MotiveAks
KUBERNETES_NAMESPACE=motive
AZURE_REGION=westeurope

# create ACR and AKS

az group create -l $AZURE_REGION -n $RESOURCE_GROUP_NAME
az acr create -n $ACR_NAME -g $RESOURCE_GROUP_NAME --sku basic
az aks create -n $AKS_NAME -g $RESOURCE_GROUP_NAME --generate-ssh-keys --attach-acr $ACR_NAME

# import necessary Docker images into the ACR

CONTROLLER_REGISTRY=k8s.gcr.io
CONTROLLER_IMAGE=ingress-nginx/controller
CONTROLLER_TAG=v0.48.1
PATCH_REGISTRY=docker.io
PATCH_IMAGE=jettech/kube-webhook-certgen
PATCH_TAG=v1.5.1
DEFAULT_BACK_END_REGISTRY=k8s.gcr.io
DEFAULT_BACK_END_IMAGE=defaultbackend-amd64
DEFAULT_BACK_END_TAG=1.5
CERT_MANAGER_REGISTRY=quay.io
CERT_MANAGER_TAG=v1.3.1
CERT_MANAGER_IMAGE_CONTROLLER=jetstack/cert-manager-controller
CERT_MANAGER_IMAGE_WEBHOOK=jetstack/cert-manager-webhook
CERT_MANAGER_IMAGE_CA_INJECTOR=jetstack/cert-manager-cainjector

az acr import --name $ACR_NAME --source $CONTROLLER_REGISTRY/$CONTROLLER_IMAGE:$CONTROLLER_TAG --image $CONTROLLER_IMAGE:$CONTROLLER_TAG
az acr import --name $ACR_NAME --source $PATCH_REGISTRY/$PATCH_IMAGE:$PATCH_TAG --image $PATCH_IMAGE:$PATCH_TAG
az acr import --name $ACR_NAME --source $DEFAULT_BACK_END_REGISTRY/$DEFAULT_BACK_END_IMAGE:$DEFAULT_BACK_END_TAG --image $DEFAULT_BACK_END_IMAGE:$DEFAULT_BACK_END_TAG
az acr import --name $ACR_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG
az acr import --name $ACR_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG
az acr import --name $ACR_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CA_INJECTOR:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CA_INJECTOR:$CERT_MANAGER_TAG

# create public IP

STATIC_IP_RESOURCE_GROUP="MC_${RESOURCE_GROUP_NAME}_${AKS_NAME}_${AZURE_REGION}"
STATIC_IP=$(az network public-ip create --resource-group $STATIC_IP_RESOURCE_GROUP --name motivepublicip --sku standard --allocation-method static --query publicIp.ipAddress -o tsv)

# install Nginx Ingress

az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $AKS_NAME

kubectl create namespace $KUBERNETES_NAMESPACE

ACR_URL=$(az acr show -n $ACR_NAME --query loginServer -o tsv)
DNS_LABEL=motivedns

# use "helm search repo ingress-nginx/ingress-nginx -l" to find chart version that corresponds to CONTROLLER_TAG
CHART_VERSION=3.35.0

helm install nginx-ingress ingress-nginx/ingress-nginx --version $CHART_VERSION \
  --namespace $KUBERNETES_NAMESPACE \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.image.registry=$ACR_URL \
  --set controller.image.image=$CONTROLLER_IMAGE \
  --set controller.image.tag=$CONTROLLER_TAG \
  --set controller.image.digest="" \
  --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.admissionWebhooks.patch.image.registry=$ACR_URL \
  --set controller.admissionWebhooks.patch.image.image=$PATCH_IMAGE \
  --set controller.admissionWebhooks.patch.image.tag=$PATCH_TAG \
  --set controller.admissionWebhooks.patch.image.digest="" \
  --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
  --set defaultBackend.image.registry=$ACR_URL \
  --set defaultBackend.image.image=$DEFAULT_BACK_END_IMAGE \
  --set defaultBackend.image.tag=$DEFAULT_BACK_END_TAG \
  --set controller.service.loadBalancerIP=$STATIC_IP \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-dns-label-name"=$DNS_LABEL

# install cert-manager

kubectl label namespace $KUBERNETES_NAMESPACE cert-manager.io/disable-validation=true

helm repo add jetstack https://charts.jetstack.io

helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace $KUBERNETES_NAMESPACE \
  --version $CERT_MANAGER_TAG \
  --set installCRDs=true \
  --set nodeSelector."kubernetes\.io/os"=linux \
  --set image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CONTROLLER \
  --set image.tag=$CERT_MANAGER_TAG \
  --set webhook.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_WEBHOOK \
  --set webhook.image.tag=$CERT_MANAGER_TAG \
  --set cainjector.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CA_INJECTOR \
  --set cainjector.image.tag=$CERT_MANAGER_TAG

# create CA cluster issuer

kubectl apply -f cluster-issuer.yaml --namespace $KUBERNETES_NAMESPACE

# create demo applications (temporary)

kubectl apply -f aks-hello-world.yaml --namespace $KUBERNETES_NAMESPACE
kubectl apply -f ingress-demo.yaml --namespace $KUBERNETES_NAMESPACE

# create Kubernetes Ingress

kubectl apply -f motive-ingress.yaml --namespace $KUBERNETES_NAMESPACE
