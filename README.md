# kafka


### Automatically Generate Kafka certificates
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

### View ingress IP
INGRESSIP=$(kubectl --namespace kafka get services -o json kafka-ingress-ingress-nginx-controller | jq -r '.status.loadBalancer.ingress[0].ip');echo $INGRESSIP

## From inside client
### Producer
kafka-console-producer.sh --producer.config /tmp/output/client.properties --broker-list ${INGRESSIP}:940 --topic test
### Consumer
kafka-console-consumer.sh --consumer.config /tmp/output/client.properties --bootstrap-server ${INGRESSIP}:940 --topic test --from-beginning

