#!/bin/bash
set -e

# Check if environment is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <environment>"
    echo "Available environments: e360, yh"
    exit 1
fi

ENV=$1

# Validate environment
if [ "$ENV" != "e360" ] && [ "$ENV" != "yh" ]; then
    echo "Invalid environment. Must be either 'e360' or 'yh'"
    exit 1
fi

# Map environment to project ID
if [ "$ENV" == "e360" ]; then
    PROJECT_ID="e360-lab"
else
    PROJECT_ID="yh-intelapi-1339190"
fi

# Update terraform.tfvars with the selected environment
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/target_env = .*/target_env = \"$ENV\"/" terraform.tfvars
else
    # Linux
    sed -i "s/target_env = .*/target_env = \"$ENV\"/" terraform.tfvars
fi

# Initialize Terraform
echo "Initializing Terraform..."
terraform init

# Apply Terraform configuration
echo "Applying Terraform configuration for environment: $ENV (project: $PROJECT_ID)"
terraform apply -auto-approve

# Get the instance IP
INSTANCE_IP=$(terraform output -raw instance_ip)

echo "Deployment complete!"
echo "Instance IP: $INSTANCE_IP"
echo "You can SSH into the instance using:"
echo "gcloud compute ssh video-processing-controller --project $PROJECT_ID --zone us-central1-a"
echo "View logs using:"
echo "gcloud compute ssh video-processing-controller --project $PROJECT_ID --zone us-central1-a --command 'sudo journalctl -u video-processing -f'" 