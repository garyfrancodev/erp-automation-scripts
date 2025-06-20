#!/bin/bash

ERP_DOMAINS_API=$(op read "op://ERP/ERP_DOMAINS/credential")
DOMAIN_NAME="mandox.com.bo"
SUBDOMAIN="$1"
IP="172.235.128.227"

# Obtener ID del dominio
DOMAIN_ID=$(curl -s -H "Authorization: Bearer $ERP_DOMAINS_API" https://api.linode.com/v4/domains \
  | jq ".data[] | select(.domain==\"$DOMAIN_NAME\") | .id")

# Crear subdominio
curl -s -X POST https://api.linode.com/v4/domains/$DOMAIN_ID/records \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"A\",
    \"name\": \"$SUBDOMAIN\",
    \"target\": \"$IP\",
    \"ttl_sec\": 300
  }" | jq
