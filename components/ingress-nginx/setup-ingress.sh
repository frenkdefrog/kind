#!/usr/bin/env bash

echo -e "Deploying the nginx ingress, please, wait...."


kubectl apply -f $(dirname "$0")/deploy.yaml

if [ "$?" -ne "0" ]; then 
    echo -e "Ooops, something bad happend. Please check the logs..... Exiting"
fi

echo -e "Successfull deployment, plesae wait...."

for i in {1..60};
    do
        sleep 1
        echo "Waiting for being ready... : $i"
    done

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
