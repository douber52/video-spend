#!/bin/bash
set -ex  # Add -x for verbose debugging

# Load environment variables
set -a
source /app/container.env
set +a

echo "==== Debug: All Environment Variables ===="
env | sort

echo "==== Debug: Critical Variables ===="
echo "GCP_PROJECT_ID=${GCP_PROJECT_ID}"
echo "TARGET_SPEND=${TARGET_SPEND}"
echo "INSTANCE_COUNT=${INSTANCE_COUNT}"
echo "MACHINE_TYPE=${MACHINE_TYPE}"
echo "BILLING_ACCOUNT_ID=${BILLING_ACCOUNT_ID}"

echo "==== Generating terraform.tfvars ===="
cat > terraform.tfvars << EOL
environments = {
  e360 = {
    project_id         = "${GCP_PROJECT_ID}"
    region            = "${GCP_REGION}"
    zone              = "${GCP_ZONE}"
    billing_account_id = "${BILLING_ACCOUNT_ID}"
    instance_count    = ${INSTANCE_COUNT}
    machine_type      = "${MACHINE_TYPE}"
    target_spend      = ${TARGET_SPEND}
  }
}

target_env = "e360"
instance_count = ${INSTANCE_COUNT}
machine_type = "${MACHINE_TYPE}"
EOL

echo "==== Contents of generated terraform.tfvars ===="
cat terraform.tfvars

echo "==== Directory contents ===="
ls -la