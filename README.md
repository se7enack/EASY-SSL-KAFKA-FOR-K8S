<img src="https://github.com/se7enack/Easy-SSL-Kafka-for-K8S/blob/main/logo.png?raw=true"  width="33%" height="33%">


## Made-Easy Scalable SSL Kafka for Kubernetes
An extremely easy and scalable way to deploy SSL enabled Kafka to Kubernetes

### Automatically Generate Kafka certificates
```
bash ./auto-generate-certificates.sh
```
*Those files are generated to the newly created 'output' directory

### Create ingress
```
bash ./ingress-create.sh
```

### Create Kafka and Zookeeper
```
kubectl apply -f kafka_and_zookeeper.yaml
```

### Create a test client in the namespace
```
bash ./client.sh
```

### View ingress IP (take note of the IP returned)
```
kubectl --namespace kafka get services -o json kafka-ingress-ingress-nginx-controller | jq -r '.status.loadBalancer.ingress[0].ip'
```

## From inside the client
### Export var for Ingress IP
```
export INGRESS_IP=REPLACE-WITH-IP-FROM-ABOVE-STEP
```

### Producer
```
kafka-console-producer.sh --producer.config /tmp/output/client.properties --broker-list ${INGRESS_IP}:942,${INGRESS_IP}:941,${INGRESS_IP}:940 --topic test
```

### Consumer
```
kafka-console-consumer.sh --consumer.config /tmp/output/client.properties --bootstrap-server ${INGRESS_IP}:942,${INGRESS_IP}:941,${INGRESS_IP}:940 --topic test --from-beginning
```

#
<img src="https://github.com/se7enack/Easy-SSL-Kafka-for-K8S/blob/main/example.png?raw=true"  width="100%" height="100%">
