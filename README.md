# kafka


## Automatically Generate Kafka certificates
### Usage:
./auto-generate-certificates.sh
###
Files are generated to the newly created 'output' directory


## Optional step: (If you are using in Kubernetes)
### Apply the auto-generated secrets yaml to your cluster:
kubectl apply -f output/secrets.yaml
### Create Kafka and Zookeeper
kubectl apply -f kafka_and_zookeeper.yaml


