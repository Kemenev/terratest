IP_LIST=$(yq eval '.ip' vms.yaml)
DUPLICATES=$(echo "$IP_LIST" | sort | uniq -d)
if [ ! -z "$DUPLICATES" ]; then
  echo "Duplicate IP addresses found:"
  echo "$DUPLICATES"
  exit 1
fi
