docker image build -t yaskovdev/motive-back-end -f ../motive-back-end/Dockerfile ../motive-back-end
docker image push yaskovdev/motive-back-end

export APP_NAMESPACE_NAME="motive"
export APP_DATABASE_NAME="motive-database"
export DATABASE_JDBC_URL="jdbc:postgresql://$APP_DATABASE_NAME-postgresql.motive.svc.cluster.local:5432/motive"
export DATABASE_USERNAME="postgres"

envsubst <kubernetes/back-end-deployment.yaml | kubectl apply -f - -n $APP_NAMESPACE_NAME
