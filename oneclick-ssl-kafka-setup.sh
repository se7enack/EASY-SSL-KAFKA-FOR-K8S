#!/usr/bin/env bash

set -Eeo pipefail

# You're Welcome! :) - SB

##########################################################################################
# This takes a best guess at getting the basics
# Comment this out if you want to provide your own
info=$(curl -s ipinfo.io)
CITY=$(echo $info | jq -r .city)
STATE=$(echo $info | jq -r .region)
COUNTRY=$(echo $info | jq -r .country)
EMAIL=$(echo $info | jq -r .hostname | rev | awk -F '.' '{print $1"."$2"@ylperon"}' | rev)
USER=`whoami`
KUBENAMESPACE=kafka
FQDN="kafka.${KUBENAMESPACE}.svc.cluster.local"
PASSWD=$(openssl rand -hex 8)
EXPIREDAYS=3650
# # Example:
# CITY="Boston"
# STATE="MA"
# COUNTRY="US"
# EMAIL="noreply@getburke.com"
# USER="ACME Corporation"
# FQDN="kafka.getburke.com"
# PASSWD="Str0ngerPwThanThis!"
# EXPIREDAYS=365
# KUBENAMESPACE="kafka"
##########################################################################################


keygen() {
    mkdir -p output
    cd output
    expect <<- DONE
    set timeout -1
    spawn screen keytool -keystore kafka.keystore.jks -alias localhost -keyalg RSA -validity ${EXPIREDAYS} -genkey
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "*Unknown*"
    send -- "${USER}\r"
    expect "*Unknown*"
    send -- "${USER}\r"
    expect "*Unknown*"
    send -- "${USER}\r"
    expect "*Unknown*"
    send -- "${CITY}\r" 
    expect "*Unknown*"
    send -- "${STATE}\r"
    expect "*Unknown*"
    send -- "${COUNTRY}\r" 
    expect "*no*"
    send -- "yes\r"
    expect eof
DONE
    echo "Success"
    expect <<- DONE
    set timeout -1
    spawn screen openssl req -new -x509 -keyout ca-key -out ca-cert -days ${EXPIREDAYS}
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
    send -- "${USER}\r"
    expect "*Unit*"
    send -- "${USER}\r"
    expect "*qualified*"
    send -- "${FQDN}\r"
    expect "Email*"
    send -- "${EMAIL}\r"
    expect eof
DONE
    echo "Success"
    expect <<- DONE
    set timeout -1  
    spawn screen keytool -keystore kafka.client.truststore.jks -alias CARoot -importcert -file ca-cert
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "Trust*"
    send -- "yes\r" 
    expect eof
DONE
    echo "Success"
    expect <<- DONE
    set timeout -1  
    spawn screen keytool -keystore kafka.truststore.jks -alias CARoot -importcert -file ca-cert
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "Trust*"
    send -- "yes\r" 
    expect eof
DONE
    echo "Success"
    expect <<- DONE
    set timeout -1  
    spawn screen keytool -keystore kafka.keystore.jks -alias localhost -certreq -file cert-file
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect eof
DONE
    echo "Success"
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days ${EXPIREDAYS} -CAcreateserial -passin pass:${PASSWD} 2> /dev/null
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days ${EXPIREDAYS} -CAcreateserial -passin pass:${PASSWD} 2> /dev/null
    expect <<- DONE
    set timeout -1  
    spawn screen keytool -keystore kafka.keystore.jks -alias CARoot -importcert -file ca-cert
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "Trust*"
    send -- "yes\r"
    expect eof
DONE
    echo "Success"
    expect <<- DONE
    set timeout -1  
    spawn screen keytool -keystore kafka.keystore.jks -alias localhost -importcert -file cert-signed
    expect "*pass*" 
    send -- "${PASSWD}\r"
    expect eof
DONE
    echo "Finished"
    cd ..
}


yamlobject() {
    cd output
    KEYSTORE_B64=$(base64 kafka.keystore.jks)
    TRUSTSTORE_B64=$(base64 kafka.truststore.jks)
    PASSWORD_B64=$(echo ${PASSWD} | base64)
    echo """apiVersion: v1
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
    truststore-creds: $PASSWORD_B64
    keystore-creds: $PASSWORD_B64
    key-creds: $PASSWORD_B64
---
apiVersion: v1
kind: Namespace
metadata:
  name: 'kafka'
---
apiVersion: v1
kind: Namespace
metadata:
  name: \"kafka\"
---
apiVersion: v1
kind: Deployment
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
            secretName: \"kafka-store\"
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
      containers:
      - name: zookeeper
        image: bitnami/zookeeper:3.8.1
        ports:
        - containerPort: 2181
        env:
        - name: ZOOKEEPER_CLIENT_PORT
          value: \"2181\"
        - name: ZOOKEEPER_TICK_TIME
          value: \"2000\"
        - name: ZOO_ENABLE_AUTH
          value: 'no'
        - name: ALLOW_ANONYMOUS_LOGIN
          value: 'yes'
      - name: kafka
        volumeMounts:
            - name: secrets
              mountPath: /bitnami/kafka/config/certs
              readOnly: true           
        image: bitnami/kafka:3.4.1
        ports:
        - containerPort: 9092
        env:
        - name: KAFKA_ZOOKEEPER_PROTOCOL
          value: 'PLAINTEXT://0.0.0.0:9092'
        - name: BITNAMI_DEBUG
          value: \"true\"
        - name: ALLOW_PLAINTEXT_LISTENER
          value: \"true\"
        - name: KAFKA_ENABLE_KRAFT
          value: \"false\"
        - name: KAFKA_SSL_ENDPOINT_IDENTIFICATION_ALGORITHM
          value: \"\"
        - name: KAFKA_ADVERTISED_LISTENERS
          value: 'PLAINTEXT://kafka.kafka.svc.cluster.local:9092,SSL://kafka.kafka.svc.cluster.local:9094'
        - name: KAFKA_LISTENERS
          value: 'SSL://0.0.0.0:9094,PLAINTEXT://0.0.0.0:9092'
        - name: KAFKA_AUTO_CREATE_TOPICS_ENABLE
          value: 'true'
        - name: KAFKA_SSL_KEYSTORE_CREDENTIALS
          value: keystore-creds
        - name: KAFKA_SSL_KEY_CREDENTIALS
          value: key-creds
        - name: KAFKA_SSL_TRUSTSTORE_CREDENTIALS
          value: truststore-creds          
        - name: KAFKA_BROKER_ID
          value: \"1\"
        - name: KAFKA_ZOOKEEPER_CONNECT
          value: 'zookeeper.${KUBENAMESPACE}.svc.cluster.local:2181'
        - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
          value: SSL:SSL,PLAINTEXT:PLAINTEXT
        - name: KAFKA_SSL_CLIENT_AUTH
          value: \"required\"
        - name: KAFKA_SECURITY_INTER_BROKER_PROTOCOL
          value: \"SSL\"
        - name: KAFKA_SSL_KEYSTORE_FILENAME
          value: kafka.keystore.jks    
        - name: KAFKA_SSL_TRUSTSTORE_FILENAME
          value: kafka.truststore.jks
        - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
          value: \"1\"
        - name: KAFKA_TRANSACTION_STATE_LOG_MIN_ISR
          value: \"1\"
        - name: KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
          value: \"1\"
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
    - port: 9092
      protocol: TCP
      targetPort: 9092
---
apiVersion: v1
kind: Service
metadata:
  name: zookeeper
  namespace: $KUBENAMESPACE
spec:
  selector:
    app: kafka
  ports:
    - port: 2181
      protocol: TCP
      targetPort: 2181""" > ssl-kafka-zookeeper.yaml
    cd ..
}


keygen || rm -rf output && yamlobject && \
kubectl apply -f output/ssl-kafka-zookeeper.yaml && \
echo $PASSWD > output/cert-password.txt && \
echo;echo 'All set! Certs + Password are located in the output folder';echo
 
