#!/usr/bin/env bash

set -Eeo pipefail


##########################################################################################
EPOC=`date +%s`
EXPIREDAYS=3650
CITY="Boston"
STATE="MA"
COUNTRY="US"
EMAIL="noreply@getburke.com"
COMPANY="ACME Corporation"
USER=`whoami`
PASSWD=password
KUBENAMESPACE="kafka"
FQDN="kafka.${KUBENAMESPACE}.svc.cluster.local"
##########################################################################################


keygen() {
  rm -rf output
  mkdir -p output
  cd output
  expect <<- DONE
  set timeout -1
  spawn keytool -keystore kafka.keystore.jks -alias localhost -keyalg RSA -validity $EXPIREDAYS -genkey -storepass $PASSWD
  expect "*Unknown*"
  send -- "${USER}\r"
  expect "*Unknown*"
  send -- "SRE\r"
  expect "*Unknown*"
  send -- "${COMPANY}\r"
  expect "*Unknown*"
  send -- "${CITY}\r" 
  expect "*Unknown*"
  send -- "${STATE}\r"
  expect "*Unknown*"
  send -- "${COUNTRY}\r" 
  expect "*no*"
  send -- "yes\r"
  spawn openssl req -new -x509 -keyout ca-key -out ca-cert -days $EXPIREDAYS
  expect "*pass*"
  send -- "${PASSWD}\r"
  expect "*pass*"
  send -- "${PASSWD}\r"
  expect "Country*"
  send -- "${COUNTRY}\r"
  expect "State*"
  send -- "${STATE}\r"
  expect "*city*"
  send -- "${CITY}\r"
  expect "*company*"
  send -- "${COMPANY}\r" 
  expect "*section*"
  send -- "SRE\r"
  expect "*qualified*"
  send -- "${FQDN}\r" 
  expect "Email*"
  send -- "${EMAIL}\r" 
  expect "*no*"
  send -- "yes\r"
  spawn keytool -keystore kafka.client.truststore.jks -alias CARoot -importcert -file ca-cert -storepass $PASSWD
  expect "*no*"
  send -- "yes\r"
  spawn keytool -keystore kafka.truststore.jks -alias CARoot -importcert -file ca-cert -storepass $PASSWD
  expect "*no*"
  send -- "yes\r"
  spawn keytool -keystore kafka.keystore.jks -alias localhost -certreq -file cert-file -storepass $PASSWD
  expect eof
DONE
  expect <<- DONE
  set timeout -1
  spawn openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days $EXPIREDAYS -CAcreateserial
  expect "*pass*"
  send -- "${PASSWD}\r"
  spawn keytool -keystore kafka.keystore.jks -alias CARoot -importcert -file ca-cert -storepass $PASSWD
  expect "*no*"
  send -- "yes\r"
  spawn keytool -keystore kafka.keystore.jks -alias localhost -importcert -file cert-signed -storepass $PASSWD
  expect eof
DONE
  cd ..
}


yamlobject() {
  cd output
  KEYSTORE_B64=$(base64 kafka.keystore.jks)
  TRUSTSTORE_B64=$(base64 kafka.truststore.jks)
  CA_CERT_B64=$(base64 ca-cert)
  CA_KEY_B64=$(base64 ca-key)
  TRUSTSTORE_B64=$(base64 kafka.truststore.jks)
  CLIENT_TRUSTSTORE_B64=$(base64 kafka.client.truststore.jks)
  PASSWORD_B64=$(echo ${PASSWD} | base64)
  
  echo """
apiVersion: v1
kind: Namespace
metadata:
    name: $KUBENAMESPACE
---
apiVersion: v1
kind: Secret
metadata:
    name: kafka-store
    namespace: $KUBENAMESPACE
data:
    kafka.keystore.jks: $KEYSTORE_B64
    kafka.truststore.jks: $TRUSTSTORE_B64
    kafka.client.truststore.jks: $CLIENT_TRUSTSTORE_B64
    ca-cert: $CA_CERT_B64
    ca-key: $CA_KEY_B64
    truststore-creds: $PASSWORD_B64
    keystore-creds: $PASSWORD_B64
    key-creds: $PASSWORD_B64
---
apiVersion: v1
kind: StatefulSet
apiVersion: apps/v1
metadata:
  name: kafka
  namespace: $KUBENAMESPACE
  labels:
    app: kafka
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      volumes:  
        - name: secrets
          secret:
            secretName: 'kafka-store'
            items:
              - key: kafka.keystore.jks
                path: kafka.keystore.jks
              - key: kafka.client.truststore.jks
                path: kafka.client.truststore.jks
              - key: kafka.truststore.jks
                path: kafka.truststore.jks
              - key: key-creds
                path: key-creds
              - key: truststore-creds
                path: truststore-creds
              - key: keystore-creds
                path: keystore-creds
      initContainers:
      - name: look-for-zookeeper-service
        image: ubuntu:latest
        command: ['sh', '-c', 'until getent hosts zookeeper; do echo waiting for zookeeper; sleep 2; done;']
      containers:
      - name: kafka
        volumeMounts:     
        - name: secrets
          mountPath: /bitnami/kafka/config/certs
          readOnly: true           
        image: bitnami/kafka:3.4.1
        ports:
        - containerPort: 9094
        env:
        - name: POD
          valueFrom:
            fieldRef:
              fieldPath: metadata.name  
        - name: EPOC
          value: \"$EPOC\"
        - name: KAFKA_ZOOKEEPER_PROTOCOL
          value: 'PLAINTEXT://0.0.0.0:9092'
        - name: BITNAMI_DEBUG
          value: 'true'
        - name: ALLOW_PLAINTEXT_LISTENER
          value: 'true'
        - name: KAFKA_ENABLE_KRAFT
          value: 'false'
        - name: KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM
          value: ''
        - name: KAFKA_ADVERTISED_LISTENERS
          value: \"PLAINTEXT://kafka.${KUBENAMESPACE}.svc.cluster.local:9092,SSL://kafka.${KUBENAMESPACE}.svc.cluster.local:9094\"
        - name: KAFKA_LISTENERS
          value: 'SSL://0.0.0.0:9094,PLAINTEXT://0.0.0.0:9092'
        - name: KAFKA_AUTO_CREATE_TOPICS_ENABLE
          value: 'true'
        - name: KAFKA_SSL_KEYSTORE_CREDENTIALS
          value: \"${PASSWD}\"
        - name: KAFKA_SSL_KEY_CREDENTIALS
          value: \"${PASSWD}\"
        - name: KAFKA_SSL_TRUSTSTORE_CREDENTIALS
          value: \"${PASSWD}\"        
        - name: KAFKA_ZOOKEEPER_CONNECT
          value: \"zookeeper.${KUBENAMESPACE}.svc.cluster.local:2181\"
        - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
          value: SSL:SSL,PLAINTEXT:PLAINTEXT
        - name: KAFKA_SSL_CLIENT_AUTH
          value: 'required'
        - name: KAFKA_SECURITY_INTER_BROKER_PROTOCOL
          value: 'SSL'
        - name: KAFKA_SSL_KEYSTORE_FILENAME
          value: '/bitnami/kafka/config/certs/kafka.keystore.jks'   
        - name: KAFKA_SSL_TRUSTSTORE_FILENAME
          value: '/bitnami/kafka/config/certs/kafka.truststore.jks'
        - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
          value: '1'
        - name: KAFKA_TRANSACTION_STATE_LOG_MIN_ISR
          value: '1'
        - name: KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
          value: '1'
        - name: KAFKA_SSL_KEYSTORE_LOCATION
          value: '/bitnami/kafka/config/certs/kafka.keystore.jks'
        - name: KAFKA_SSL_TRUSTSTORE_LOCATION
          value: '/bitnami/kafka/config/certs/kafka.truststore.jks'
        - name: KAFKA_SSL_KEYSTORE_PASSWORD
          value: \"${PASSWD}\"
        - name: KAFKA_SSL_KEY_PASSWORD
          value: \"${PASSWD}\"
---
apiVersion: v1
kind: Deployment
apiVersion: apps/v1
metadata:
  name: zookeeper
  namespace: $KUBENAMESPACE
  labels:
    app: zookeeper
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zookeeper
  template:
    metadata:
      labels:
        app: zookeeper
    spec:          
      containers:
      - name: zookeeper
        image: bitnami/zookeeper:3.8.1
        ports:
        - containerPort: 2181
        env:
        - name: EPOC
          value: \"$EPOC\"        
        - name: ZOOKEEPER_CLIENT_PORT
          value: '2181'
        - name: ZOOKEEPER_TICK_TIME
          value: '2000'
        - name: ZOO_ENABLE_AUTH
          value: 'no'
        - name: ALLOW_ANONYMOUS_LOGIN
          value: 'yes'
---
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: $KUBENAMESPACE
spec:
  selector:
    app: kafka
  ports:
    - name: http
      protocol: TCP
      port: 9092
      targetPort: 9092
    - name: https
      protocol: TCP
      port: 9094
      targetPort: 9094
---
apiVersion: v1
kind: Service
metadata:
  name: zookeeper
  namespace: $KUBENAMESPACE
spec:
  selector:
    app: zookeeper
  ports:
    - name: http
      protocol: TCP
      port: 2181
      targetPort: 2181
    - name: https
      protocol: TCP
      port: 2000
      targetPort: 2000
""" > ssl-kafka-zookeeper.yaml
  cd ..
}


keygen && yamlobject && \
kubectl apply -f output/ssl-kafka-zookeeper.yaml && \
echo $PASSWD > output/cert-password.txt && \
echo;echo 'All set! Certs + Password are located in the output folder';echo
 
mkdir -p /tmp/client
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."ca-cert"' | base64 -d  > /tmp/client/ca-cert
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."ca-key"' | base64 -d  > /tmp/client/ca-key
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."kafka.keystore.jks"' | base64 -d  > /tmp/client/kafka.keystore.jks
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."kafka.truststore.jks"' | base64 -d  > /tmp/client/kafka.truststore.jks
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."ca-cert.srl"' | base64 -d  > /tmp/client/ca-cert.srl
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."cert-signed"' | base64 -d  > /tmp/client/cert-signed
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."cert-file"' | base64 -d  > /tmp/client/cert-file
kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."kafka.client.truststore.jks"' | base64 -d  > /tmp/client/kafka.client.truststore.jks
TRUSTSTORECREDS=$(kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."truststore-creds"' | base64 -d)
KEYSTORECREDS=$(kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."keystore-creds"' | base64 -d)
KEYCREDS=$(kubectl get secret kafka-store -n $KUBENAMESPACE -o json | jq -r '."data"."key-creds"' | base64 -d)

echo """security.protocol=SSL
ssl.keystore.location=/tmp/client/kafka.keystore.jks
ssl.keystore.password=$KEYSTORECREDS
ssl.key.password=$KEYCREDS
ssl.truststore.password=$TRUSTSTORECREDS
ssl.truststore.location=/tmp/client/kafka.client.truststore.jks
ssl.endpoint.identification.algorithm=""" > /tmp/client/client.properties
kubectl run kafka-client --restart='Never' --image docker.io/bitnami/kafka:3.4.1 --namespace $KUBENAMESPACE --command -- sleep infinity 2>/dev/null || true
sleep 5
kubectl cp --namespace $KUBENAMESPACE /tmp/client kafka-client:/tmp/.
rm -rf /tmp/client
