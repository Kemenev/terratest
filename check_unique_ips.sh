#!/bin/sh

# Проверка дубликатов IP в vms.yaml
IP_CONFLICTS=$(yq '.[] | .netbox_ip_address.address' vms.yaml | sort | uniq -d)
if [ ! -z "$IP_CONFLICTS" ]; then
  echo "Duplicate IP addresses found:"
  echo "$IP_CONFLICTS"
  exit 1
fi
