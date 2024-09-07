#!/bin/bash

set -euo pipefail

token=$(curl -sL \
    'https://www.privateinternetaccess.com/api/client/v2/token' \
    --form "username=$PIA_USER" \
    --form "password=$PIA_PASS" \
    | jq -r '.token')

# Get servers associated with chosen region. Select first wireguard server. The order and selection
# of these appear to change with each call
serverInfo=$(curl -sL \
    'https://serverlist.piaservers.net/vpninfo/servers/v6' \
    | head -1 \
    | jq --arg REGION_ID "$PIA_REGION" '.regions[] | select(.id == $REGION_ID) | .servers.wg[0]')

wgIp=$(echo $serverInfo | jq -r '.ip')
wgHostname=$(echo $serverInfo | jq -r '.cn')

privateKey=$(wg genkey)
publicKey=$(echo "$privateKey" | wg pubkey)

addKeyResponse=$(curl -sLG \
    --connect-to "$wgHostname::$wgIp:" \
    --cacert "ca.rsa.4096.crt" \
    --data-urlencode "pt=$token" \
    --data-urlencode "pubkey=$publicKey" \
    "https://$wgHostname:1337/addKey")

if [[ $(echo "$addKeyResponse" | jq -r '.status') != "OK" ]]; then
    >&2 echo "Failed to add key to server"
    echo "$addKeyResponse"
fi

wgInterfaceAddress=$(echo "$addKeyResponse" | jq -r '.peer_ip')
wgServerPublicKey=$(echo "$addKeyResponse" | jq -r '.server_key')
wgEndpoint="${wgIp}:$(echo "$addKeyResponse" | jq -r '.server_port')"

echo "\
[Interface]
Address = $wgInterfaceAddress
PrivateKey = $privateKey

[Peer]
PersistentKeepalive = 25
PublicKey = $wgServerPublicKey
AllowedIPs = $WG_ALLOWED_IPS
Endpoint = $wgEndpoint
" > "$WG_CONFIG_PATH"

>&2 echo "Config written to ${WG_CONFIG_PATH}"
