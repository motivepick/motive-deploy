#!/usr/bin/env bash

TAG=$(git -C ../motive-back-end rev-parse --short HEAD)
IMAGE=yaskovdev/motive-back-end:$TAG
docker image build -t "$IMAGE" -f ../motive-back-end/Dockerfile ../motive-back-end
docker image push "$IMAGE"

export FULL_IMAGE=docker.io/$IMAGE
export APP_NAMESPACE_NAME="motive"
export APP_DATABASE_NAME="motive-database"
export DATABASE_JDBC_URL="jdbc:postgresql://$APP_DATABASE_NAME-postgresql.motive.svc.cluster.local:5432/motive"

envsubst <kubernetes/back-end-deployment.yaml | kubectl apply -f - -n $APP_NAMESPACE_NAME
