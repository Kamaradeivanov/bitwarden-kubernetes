#!/usr/bin/env bash

# Initialize environment
SCRIPT_NAME=$0
ACTION=$1
ENV=$2

function readEnvironmentFile() {
  if [ -f "$1.env" ]; then
    source $1.env
  else
    echo -e "No file named $1.env\n"
    listCommands
    exit 1
  fi
}

function applyConfiguration() {
  echo "Copy the SMTP configuration"
  sed -i "s/globalSettings__mail__replyToEmail=.*/globalSettings__mail__replyToEmail=${SMTP_REPLY_MAIL}/g" ./global/secret.env
  sed -i "s/globalSettings__mail__smtp__host=.*/globalSettings__mail__smtp__host=${SMTP_HOST}/g" ./global/secret.env
  sed -i "s/globalSettings__mail__smtp__port=.*/globalSettings__mail__smtp__port=${SMTP_PORT}/g" ./global/secret.env
  sed -i "s/globalSettings__mail__smtp__ssl=.*/globalSettings__mail__smtp__ssl=${SMTP_SSL}/g" ./global/secret.env
  sed -i "s/globalSettings__mail__smtp__username=.*/globalSettings__mail__smtp__username=${SMTP_USERNAME}/g" ./global/secret.env
  sed -i "s#globalSettings__mail__smtp__password=.*#globalSettings__mail__smtp__password=${SMTP_PASSWORD}#g" ./global/secret.env
  sed -i "s/globalSettings__mail__smtp__useDefaultCredentials=.*/globalSettings__mail__smtp__useDefaultCredentials=${SMTP_USE_DEFAULT_CREDS}/g" ./global/secret.env

  echo "Copy the domain name into variables"
  sed -i "s/value: .*/value: ${DOMAIN_HOST}/g" ./ingress_patch.yml
  sed -i "s#globalSettings__baseServiceUri__vault=.*#globalSettings__baseServiceUri__vault=https://${DOMAIN_HOST}#g" ./global/configmap.env
  sed -i "s#globalSettings__baseServiceUri__api=.*#globalSettings__baseServiceUri__api=https://${DOMAIN_HOST}/api#g" ./global/configmap.env
  sed -i "s#globalSettings__baseServiceUri__identity=.*#globalSettings__baseServiceUri__identity=https://${DOMAIN_HOST}/identity#g" ./global/configmap.env
  sed -i "s#globalSettings__baseServiceUri__admin=.*#globalSettings__baseServiceUri__admin=https://${DOMAIN_HOST}/admin#g" ./global/configmap.env
  sed -i "s#globalSettings__baseServiceUri__sso=.*#globalSettings__baseServiceUri__sso=https://${DOMAIN_HOST}/sso#g" ./global/configmap.env
  sed -i "s#globalSettings__baseServiceUri__notifications=.*#globalSettings__baseServiceUri__notifications=https://${DOMAIN_HOST}/notifications#g" ./global/configmap.env
  sed -i "s#globalSettings__attachment__baseUrl=.*#globalSettings__attachment__baseUrl=https://${DOMAIN_HOST}/attachments#g" ./global/configmap.env

  echo "Copy the storage class for kubernetes PVC"
  sed -i "s/storageClassName: .*/storageClassName: ${KUBERNETES_STORAGE_CLASSE}/g" ./mssql/pvc.yml

  echo "Copy the registration configuration"
  sed -i "s/globalSettings__disableUserRegistration=.*/globalSettings__disableUserRegistration=${DISABLE_REGISTRATION}/g" ./global/configmap.env

  echo "Copy the admin email list configuration"
  sed -i "s/adminSettings__admins=.*/adminSettings__admins=${ADMINS_EMAIL_LIST}/g" ./global/configmap.env

  echo "Copy the bitwarden installation id and key"
  sed -i s/globalSettings__installation__id=\.\*/globalSettings__installation__id=$INSTALLATION_ID/g ./global/secret.env
  sed -i s/globalSettings__installation__key=\.\*/globalSettings__installation__key=$INSTALLATION_KEY/g ./global/secret.env

  echo "Copy the duo configuration"
  sed -i s/globalSettings__duo__aKey=\.\*/globalSettings__duo__aKey=$DUO_KEY/g ./global/secret.env

  echo "Copy the yubico configuration"
  sed -i s/globalSettings__yubico__clientId=\.\*/globalSettings__yubico__clientId=$YUBICO_CLIENT_ID/g ./global/secret.env
  sed -i s/globalSettings__yubico__key=\.\*/globalSettings__yubico__key=$YUBICO_KEY/g ./global/secret.env

  echo "Copy the hipb configuration"
  sed -i s/globalSettings__hibpApiKey=\.\*/globalSettings__hibpApiKey=$HIBP_API_KEY/g ./global/secret.env
}

function generateConfiguration() {
  echo "Generate identity.pfx file and password"
  IDENTITY_CERT_PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c70)
  openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout identity.key -out identity.crt -subj "/CN=Bitwarden IdentityServer" -days 10950
  openssl pkcs12 -export -out ./identity/identity.pfx -inkey identity.key -in identity.crt -passout pass:$IDENTITY_CERT_PASSWORD
  rm identity.key identity.crt
  sed -i s/globalSettings__identityServer__certificatePassword=\.\*/globalSettings__identityServer__certificatePassword=$IDENTITY_CERT_PASSWORD/g ./identity/.env

  echo "Generate MSSQL password"
  SA_PASSWORD=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c70)
  sed -i s/SA_PASSWORD=\.\*/SA_PASSWORD=$SA_PASSWORD/g ./mssql/.env
  sed -i s/Password=\.\*\;/Password=$SA_PASSWORD\;/g ./global/secret.env

  echo "Generate identity key"
  IDENTITY_KEY=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c70)
  sed -i s/globalSettings__internalIdentityKey=\.\*/globalSettings__internalIdentityKey=$IDENTITY_KEY/g ./global/secret.env

  echo "Generate identity client key"
  IDENTITY_CLIENT_KEY=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c70)
  sed -i s/globalSettings__oidcIdentityClientKey=\.\*/globalSettings__oidcIdentityClientKey=$IDENTITY_CLIENT_KEY/g ./global/secret.env
}

function listCommands() {
cat << EOT
Available commands:

init environment
install environment
apply environment
delete environment
help

Exemple :
  Create a prod.env file based on .env
    >$ cp .env prod.env

  Initialize the configuration based on your prod.env file
    >$ $SCRIPT_NAME init prod

  Create namespace and install bitwarden
    >$ $SCRIPT_NAME install prod

  Apply any modification from your prod.env file
    >$ $SCRIPT_NAME install prod

  Delete bitwarden and the namespace
    >$ $SCRIPT_NAME delete prod
EOT
}

# Commands

if [ "$ACTION" == "install" ]; then
  readEnvironmentFile $ENV
  kubectl create ns $KUBERNETES_NAMESPACE
  kubectl apply -n $KUBERNETES_NAMESPACE -k .
elif [ "$ACTION" == "apply" ]; then
  readEnvironmentFile $ENV
  applyConfiguration
  kubectl apply -n $KUBERNETES_NAMESPACE -k .
elif [ "$ACTION" == "delete" ]; then
  readEnvironmentFile $ENV
  kubectl delete -n $KUBERNETES_NAMESPACE -k .
  kubectl delete ns $KUBERNETES_NAMESPACE
elif [ "$ACTION" == "init" ]; then
  readEnvironmentFile $ENV
  generateConfiguration
  applyConfiguration
elif [ "$ACTION" == "help" ]; then
    listCommands
else
    echo "No command found."
    echo
    listCommands
fi
