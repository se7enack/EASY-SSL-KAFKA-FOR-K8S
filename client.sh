
client() {
  echo """security.protocol=SSL
ssl.keystore.location=/tmp/output/kafka.keystore.jks
ssl.keystore.password=$PASSWD
ssl.key.password=$PASSWD
ssl.truststore.password=$PASSWD
ssl.truststore.location=/tmp/output/kafka.client.truststore.jks
ssl.endpoint.identification.algorithm=""" > output/client.properties
  kubectl run kafka-client --restart='Never' --image ubuntu/kafka:edge --namespace kafka --command -- sleep infinity 2>/dev/null || true
  sleep 5
  kubectl cp --namespace kafka `pwd`/output kafka-client:/tmp/.
}

x=$(kubectl --namespace kafka get services -o json dca0kafka-ingress-ingress-nginx-controller | jq -r '.status.loadBalancer.ingress[0].ip')
PASSWD=$(cat output/cert-password.txt)
client
echo $x
