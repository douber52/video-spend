#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Starting Full Redeployment ===${NC}"

# Function to wait for instance deletion
wait_for_deletion() {
    local instance_name=$1
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! gcloud compute instances list --filter="name:($instance_name)" --format="get(name)" | grep -q .; then
            return 0
        fi
        echo "Waiting for instance deletion... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    return 1
}

# 1. Destroy existing infrastructure
echo -e "\n${YELLOW}=== Destroying Existing Infrastructure ===${NC}"

# Stop the controller instance if it exists
CONTROLLER=$(gcloud compute instances list --filter="name~'video-processor-controller'" --format="get(name,zone)")
if [ -n "$CONTROLLER" ]; then
    INSTANCE_NAME=$(echo "$CONTROLLER" | awk '{print $1}')
    ZONE=$(echo "$CONTROLLER" | awk '{print $2}')
    echo -e "${YELLOW}Stopping controller instance: $INSTANCE_NAME${NC}"
    gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE" --quiet || true
fi

# Destroy Terraform-managed resources
if [ -f "terraform.tfstate" ]; then
    echo -e "${YELLOW}Running terraform destroy...${NC}"
    terraform destroy -auto-approve || true
fi

# Clean up any remaining instances (including workers)
echo -e "${YELLOW}Cleaning up any remaining instances...${NC}"
INSTANCES=$(gcloud compute instances list --filter="name~'video-processor'" --format="get(name,zone)")
if [ -n "$INSTANCES" ]; then
    while IFS= read -r instance; do
        if [ -n "$instance" ]; then
            NAME=$(echo "$instance" | awk '{print $1}')
            ZONE=$(echo "$instance" | awk '{print $2}')
            echo -e "${YELLOW}Deleting instance: $NAME${NC}"
            gcloud compute instances delete "$NAME" --zone="$ZONE" --quiet || true
            wait_for_deletion "$NAME"
        fi
    done <<< "$INSTANCES"
fi

# Clean up service accounts
echo -e "${YELLOW}Cleaning up service accounts...${NC}"
SA_EMAIL="video-processor-controller@e360-lab.iam.gserviceaccount.com"
if gcloud iam service-accounts list --filter="email:$SA_EMAIL" --format="get(email)" | grep -q .; then
    echo -e "${YELLOW}Deleting service account: $SA_EMAIL${NC}"
    gcloud iam service-accounts delete "$SA_EMAIL" --quiet || true
fi

# Clean up firewall rules
echo -e "${YELLOW}Cleaning up firewall rules...${NC}"
FIREWALL_RULE="allow-video-processor-controller"
if gcloud compute firewall-rules list --filter="name:$FIREWALL_RULE" --format="get(name)" | grep -q .; then
    echo -e "${YELLOW}Deleting firewall rule: $FIREWALL_RULE${NC}"
    gcloud compute firewall-rules delete "$FIREWALL_RULE" --quiet || true
fi

# Clean up local Terraform state
echo -e "${YELLOW}Cleaning up local Terraform state...${NC}"
rm -rf .terraform* terraform.tfstate* || true

# 2. Initialize fresh Terraform state
echo -e "\n${YELLOW}=== Initializing Fresh Deployment ===${NC}"
echo -e "${GREEN}Running terraform init...${NC}"
terraform init

# 3. Apply new infrastructure
echo -e "\n${YELLOW}=== Deploying New Infrastructure ===${NC}"
echo -e "${GREEN}Running terraform apply...${NC}"
terraform apply -auto-approve

# 4. Wait for deployment to complete
echo -e "\n${YELLOW}=== Waiting for Deployment to Complete ===${NC}"
sleep 30  # Give time for instance to start up

# 5. Verify deployment
echo -e "\n${YELLOW}=== Verifying Deployment ===${NC}"
./review.sh

echo -e "\n${GREEN}=== Redeployment Complete ===${NC}"
echo -e "Monitor the deployment with: ${YELLOW}./review.sh${NC}"