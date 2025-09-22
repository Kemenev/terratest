IP_LIST=$(yq eval '.[] | .netbox_ip_address.address' vms.yaml)
DUPLICATES=$(echo "$IP_LIST" | sort | uniq -d)
if [ ! -z "$DUPLICATES" ]; then
  echo "Duplicate IP addresses found:"
  echo "$DUPLICATES"
  exit 1
fi
