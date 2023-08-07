# kafka


## Automatically Generate Kafka certificates
### Usage:
./auto-generate-certificates.sh
###
Files are generated to the newly created 'output' directory

### Apply the auto-generated secrets yaml to your cluster:
kubectl apply -f output/secrets.yaml

### Create ingress
bash ./ingress-create.sh

### Create Kafka and Zookeeper
kubectl apply -f kafka_and_zookeeper.yaml

### Create test client
bash ./client.sh

### Get ingress IP
INGRESSIP=$(kubectl --namespace kafka get services -o json dca0kafka-ingress-ingress-nginx-controller | jq -r '.status.loadBalancer.ingress[0].ip');echo $INGRESSIP

## From inside client
### Producer
kafka-console-producer.sh --producer.config /tmp/output/client.properties --broker-list ${INGRESSIP}:9094 --topic test
### Consumer
kafka-console-consumer.sh --consumer.config /tmp/output/client.properties --bootstrap-server ${INGRESSIP}:9094 --topic test --from-beginning

