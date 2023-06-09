# kafka


## Automatically Generate Kafka certificates
### Usage:
./auto-generate-certificates.sh


## Optional step: (If you are using in Kubernetes)
### Apply the auto-generated secrets yaml to your cluster:
kubectl apply -f output/secrets.yaml
