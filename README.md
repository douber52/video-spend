# GCP Credit Spender

An automated tool to help spend GCP credits efficiently by managing compute resources and monitoring costs in real-time.

## Overview

This application automates the process of spending GCP credits by:
1. Creating and managing compute instances using Terraform
2. Monitoring real-time costs using Cloud Monitoring
3. Providing a dashboard for cost and resource tracking
4. Automatically cleaning up resources when target spend is reached

## Prerequisites

- Python 3.9+
- Terraform
- Google Cloud SDK
- Service Account with the following permissions:
  - Compute Instance Admin
  - Monitoring Metric Writer
  - Service Account User
  - IAM Service Account User
  - Project IAM Admin
  - Billing Account Viewer

## Setup

1. Clone the repository:
```bash
git clone <repository-url>
cd spender
```

2. Create a virtual environment:
```bash
python3 -m venv venv
source venv/bin/activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Configure environment variables in `.env`:
```env
# GCP Configuration
GCP_PROJECT_ID=your-project-id
GCP_ZONE=us-central1-a
GCP_REGION=us-central1

# Budget Configuration
TARGET_SPEND=100
INSTANCE_COUNT=4
MACHINE_TYPE=n2-standard-32

# Safety Configuration
CHECK_INTERVAL_MINUTES=0.25
DESTROY_ON_EXIT=true
```

5. Authenticate with GCP:
```bash
gcloud auth application-default login
gcloud services enable monitoring.googleapis.com compute.googleapis.com
```

## Running the Application

1. Start the application:
```bash
python cost_manager.py
```

## Monitoring Dashboard

The application includes a Cloud Monitoring dashboard that shows:
- Total cost by run
- Active runs
- Instance CPU usage
- Instance count
- Disk usage

To update the dashboard:
```bash
# Get dashboard ID and update configuration
DASHBOARD_INFO=$(gcloud monitoring dashboards describe $(gcloud monitoring dashboards list --filter="displayName:Spender" --format="get(name)" | cut -d'/' -f4) --format=json) && \
ETAG=$(echo $DASHBOARD_INFO | jq -r '.etag') && \
jq --arg etag "$ETAG" '. + {etag: $etag}' dashboard.json > dashboard_with_etag.json && \
gcloud monitoring dashboards update $(gcloud monitoring dashboards list --filter="displayName:Spender" --format="get(name)" | cut -d'/' -f4) --config-from-file=dashboard_with_etag.json
```

## Architecture

### Components

1. **Cost Manager (`cost_manager.py`)**
   - Manages compute resources via Terraform
   - Tracks costs in real-time
   - Reports metrics to Cloud Monitoring
   - Handles graceful shutdown

2. **Terraform Configuration**
   - `main.tf`: Main infrastructure configuration
   - `variables.tf`: Variable definitions
   - `terraform.tfvars`: Environment-specific values

3. **Monitoring**
   - Custom metrics for cost tracking
   - Real-time dashboard
   - Instance and disk metrics

### Metrics

The application tracks:
- Total cost per run
- Run status
- Instance CPU usage
- Disk usage
- Instance count

## Safety Features

1. **Cost Control**
   - Target spend limit
   - Real-time cost tracking
   - Automatic resource cleanup

2. **Graceful Shutdown**
   - Signal handling (SIGTERM, SIGINT)
   - Resource cleanup on exit
   - Final metric reporting

3. **Error Handling**
   - Metric writing verification
   - Infrastructure state validation
   - Cleanup confirmation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.