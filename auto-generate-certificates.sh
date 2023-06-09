#!/usr/bin/env bash

set -Eeo pipefail

# Your Welcome - SB


EXPIREDAYS=3650
echo -n "Enter the FQDN: "
read FQDN
NAME=$(echo $FQDN | awk -F '.' '{print $1}')
echo -n "Enter a password to use in order to generate them: "
read -s PASSWD


keygen() {
    mkdir -p output
    cd output
    expect <<- DONE
    set timeout -1
    spawn screen keytool -keystore kafka.server.keystore.jks -alias localhost -keyalg RSA -validity ${EXPIREDAYS} -genkey
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "*Unknown*"
    send -- "SRE Team\r"
    expect "*Unknown*"
    send -- "SRE\r"
    expect "*Unknown*"
    send -- "se7enack\r"
    expect "*Unknown*"
    send -- "Boston\r" 
    expect "*Unknown*"
    send -- "MA\r"
    expect "*Unknown*"
    send -- "US\r" 
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
    send -- "US\r" 
    expect "State*"
    send -- "MA\r"
    expect "*city*"
    send -- "Boston\r" 
    expect "*company*"
    send -- "se7enack\r"
    expect "*Unit*"
    send -- "SRE\r"
    expect "*qualified*"
    send -- "${FQDN}\r"
    expect "Email*"
    send -- "noreply@getburke.com\r"
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
    spawn screen keytool -keystore kafka.server.truststore.jks -alias CARoot -importcert -file ca-cert
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
    spawn screen keytool -keystore kafka.server.keystore.jks -alias localhost -certreq -file cert-file
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect eof
DONE
    echo "Success"
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days ${EXPIREDAYS} -CAcreateserial -passin pass:${PASSWD}
    openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days ${EXPIREDAYS} -CAcreateserial -passin pass:${PASSWD}
    expect <<- DONE
    set timeout -1  
    spawn screen keytool -keystore kafka.server.keystore.jks -alias CARoot -importcert -file ca-cert
    expect "*pass*"
    send -- "${PASSWD}\r"
    expect "Trust*"
    send -- "yes\r"
    expect eof
DONE
    echo "Success"
    expect <<- DONE
    set timeout -1  
    spawn screen keytool -keystore kafka.server.keystore.jks -alias localhost -importcert -file cert-signed
    expect "*pass*" 
    send -- "${PASSWD}\r"
    expect eof
DONE
    echo "Finished"
    cd ..
}


keygen || rm -rf output
