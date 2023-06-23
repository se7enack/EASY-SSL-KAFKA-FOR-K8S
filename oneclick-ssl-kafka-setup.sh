#!/usr/bin/env bash

set -Eeo pipefail


##########################################################################################
EPOCH=`date +%s`
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
  kafka.truststore.jks: $TRUSTSTORE_B64
  kafka.keystore.jks: $KEYSTORE_B64
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
              - key: kafka.truststore.jks
                path: kafka.truststore.jks
              - key: key-creds
                path: key-creds
              - key: truststore-creds
                path: truststore-creds
              - key: keystore-creds
                path: keystore-creds
              - key: kafka.truststore.jks
                path: zookeeper.truststore.jks
              - key: kafka.keystore.jks
                path: zookeeper.keystore.jks
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
        - name: EPOCH
          value: \"$EPOCH\"
        - name: BITNAMI_DEBUG
          value: 'true'
        - name: KAFKA_SSL_KEYSTORE_FILENAME
          value: kafka.keystore.jks
        - name: KAFKA_SSL_TRUSTSTORE_FILENAME
          value: kafka.truststore.jks
        - name: KAFKA_SECURITY_INTER_BROKER_LISTENER_NAME
          value: SSL
        - name: KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM
          value: ' '
        - name: KAFKA_SSL_CLIENT_AUTH
          value: required
        - name: KAFKA_AUTHORIZER_CLASS_NAME
          value: kafka.security.auth.SimpleAclAuthorizer
        - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
          value: PLAINTEXT:PLAINTEXT,EXTERNAL:SSL
        - name: KAFKA_ALLOW_EVERYONE_IF_NO_ACL_FOUND
          value: 'true'
        - name: KAFKA_LISTENERS
          value: EXTERNAL://:9094,PLAINTEXT://:9092         
        - name: KAFKA_ADVERTISED_LISTENERS
          value: \"PLAINTEXT://kafka.${KUBENAMESPACE}.svc.cluster.local:9092,EXTERNAL://kafka.${KUBENAMESPACE}.svc.cluster.local:9094\"
        - name: KAFKA_ENABLE_KRAFT
          value: 'false'
        - name: KAFKA_ZOOKEEPER_CONNECT
          value: \"zookeeper.${KUBENAMESPACE}.svc.cluster.local:2181\"          
        - name: KAFKA_ZOOKEEPER_PROTOCOL
          value: PLAINTEXT
        - name: ALLOW_PLAINTEXT_LISTENER
          value: 'true'  
        - name: KAFKA_INTER_BROKER_LISTENER_NAME
          value: PLAINTEXT
        - name: KAFKA_CFG_SSL_KEYSTORE_PASSWORD
          value: ${PASSWD}
        - name: KAFKA_CFG_SSL_KEY_PASSWORD
          value: ${PASSWD}
        - name: KAFKA_CFG_SSL_TRUSTSTORE_PASSWORD
          value: ${PASSWD}   
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
        - name: EPOCH
          value: \"$EPOCH\"        
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
 
echo """security.protocol=SSL
ssl.keystore.location=/tmp/output/kafka.keystore.jks
ssl.keystore.password=$PASSWD
ssl.key.password=$PASSWD
ssl.truststore.password=$PASSWD
ssl.truststore.location=/tmp/output/kafka.client.truststore.jks
ssl.endpoint.identification.algorithm=""" > output/client.properties
kubectl run kafka-client --restart='Never' --image docker.io/bitnami/kafka:3.4.1 --namespace $KUBENAMESPACE --command -- sleep infinity 2>/dev/null || true
kubectl run ubuntu-client --restart='Never' --image ubuntu:latest --namespace $KUBENAMESPACE --command -- sleep infinity 2>/dev/null || true
sleep 5
kubectl cp --namespace $KUBENAMESPACE `pwd`/output kafka-client:/tmp/.
 
