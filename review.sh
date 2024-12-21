#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print section headers
print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

# Function to print status with color
print_status() {
    local status=$1
    case $status in
        "RUNNING")
            echo -e "${GREEN}$status${NC}"
            ;;
        "TERMINATED"|"STOPPED")
            echo -e "${RED}$status${NC}"
            ;;
        *)
            echo -e "${YELLOW}$status${NC}"
            ;;
    esac
}

print_header "Video Processor Status Review"

# Get the controller instance
CONTROLLER=$(gcloud compute instances list --filter="name~'video-processor-controller'" --format="get(name,zone,status)")
if [ -n "$CONTROLLER" ]; then
    echo -e "${CYAN}Controller Instance:${NC}"
    echo "$CONTROLLER"
    
    # Get instance details
    INSTANCE_NAME=$(echo "$CONTROLLER" | awk '{print $1}')
    ZONE=$(echo "$CONTROLLER" | awk '{print $2}')
    STATUS=$(echo "$CONTROLLER" | awk '{print $3}')
    
    echo -e "\n${CYAN}Instance Details:${NC}"
    gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" \
        --format="table(
            name,
            status,
            creationTimestamp.date('%Y-%m-%d %H:%M:%S'),
            networkInterfaces[0].networkIP,
            machineType.basename()
        )"

    # Get instance metrics for the last 5 minutes
    echo -e "\n${CYAN}Instance Metrics (Last 5 minutes):${NC}"
    END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    START_TIME=$(date -u -v-5M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "5 minutes ago" +"%Y-%m-%dT%H:%M:%SZ")
    
    gcloud logging read "resource.type=\"gce_instance\" AND 
        resource.labels.instance_id=\"$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(id)')\" AND 
        timestamp >= \"$START_TIME\"" \
        --format="table(timestamp.date('%Y-%m-%d %H:%M:%S'):label=TIMESTAMP,severity,jsonPayload.message:label=MESSAGE)" \
        --order=asc \
        --limit=20 | \
        while IFS= read -r line; do
            if [[ $line == *"ERROR"* ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ $line == *"WARN"* ]]; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "$line"
            fi
        done
else
    echo -e "${RED}No controller instance found${NC}"
fi

print_header "Worker Instances"
echo -e "${CYAN}Active Workers:${NC}"
gcloud compute instances list \
    --filter="name~'video-processor-' AND -name~'controller'" \
    --format="table(
        name,
        zone,
        status.color(red=TERMINATED,green=RUNNING,yellow=STAGING),
        creationTimestamp.date('%Y-%m-%d %H:%M:%S'),
        machineType.basename()
    )"

print_header "Cost Metrics"
echo -e "${CYAN}Current Run Cost:${NC}"
# Get cost metrics for the last hour
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date -u -v-1H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")

gcloud logging read "resource.type=\"gce_instance\" AND 
    resource.labels.instance_id=\"$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(id)')\" AND 
    jsonPayload.message=~\".*Total cost.*\" AND 
    timestamp >= \"$START_TIME\"" \
    --format="table(timestamp.date('%Y-%m-%d %H:%M:%S'):label=TIMESTAMP,jsonPayload.message:label=COST)" \
    --order=desc \
    --limit=1

print_header "Resource Summary"
echo -e "${CYAN}Total Resources:${NC}"
gcloud compute instances list \
    --filter="name~'video-processor-'" \
    --format="table(
        machineType.basename():label=MACHINE_TYPE,
        status,
        zone
    )"

print_header "Application Status"
echo -e "${CYAN}Recent Events:${NC}"
gcloud logging read "resource.type=\"gce_instance\" AND 
    resource.labels.instance_id=\"$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(id)')\" AND 
    (jsonPayload.SYSLOG_IDENTIFIER=\"video-processor.service\" OR 
     jsonPayload.MESSAGE=~\".*video-processor.service.*\" OR
     jsonPayload.message=~\".*Initializing GCP Cost Manager.*\")" \
    --format="table(timestamp.date('%Y-%m-%d %H:%M:%S'):label=TIMESTAMP,jsonPayload.message:label=MESSAGE)" \
    --order=desc \
    --limit=20 | \
    while IFS= read -r line; do
        if [[ $line == *"ERROR"* ]]; then
            echo -e "${RED}$line${NC}"
        elif [[ $line == *"WARN"* ]]; then
            echo -e "${YELLOW}$line${NC}"
        else
            echo "$line"
        fi
    done