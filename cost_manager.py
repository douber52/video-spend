import os
import time
import logging
import uuid
from google.cloud import monitoring_v3
from google.cloud import compute_v1
from google.cloud import resourcemanager_v3
from datetime import datetime, timedelta
import subprocess
from dotenv import load_dotenv
import json
import sys
import requests
from urllib.parse import quote

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

class GCPCostManager:
    def __init__(self, project_id, target_spend, region=None, zone=None):
        # Force reload of environment variables first
        load_dotenv(override=True)
        
        self.project_id = project_id
        self.target_spend = float(target_spend)
        self.region = region
        self.zone = zone
        self.run_id = str(uuid.uuid4())[:8]
        self.accumulated_cost = 0.0
        self.last_update_time = time.time()
        self.compute_client = compute_v1.InstancesClient()
        self.machine_types_client = compute_v1.MachineTypesClient()
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        
        # Get machine type and instance count from environment
        self.machine_type = os.getenv('MACHINE_TYPE')
        self.instance_count = int(os.getenv('INSTANCE_COUNT'))
        
        # Get the cost per hour for this machine type
        self.cost_per_hour = self.get_instance_cost_per_hour()
        
        logging.info(f"Initializing GCP Cost Manager with:")
        logging.info(f"  Project ID: {project_id}")
        logging.info(f"  Target Spend: ${target_spend}")
        logging.info(f"  Machine Type: {self.machine_type}")
        logging.info(f"  Instance Count: {self.instance_count}")
        logging.info(f"  Run ID: {self.run_id}")
        
        # Initialize Terraform
        self.init_terraform()

    def init_terraform(self):
        """Initialize and apply Terraform configuration"""
        try:
            # Force reload of environment variables
            load_dotenv(override=True)
            
            # Update instance properties from environment
            self.machine_type = os.getenv('MACHINE_TYPE')
            self.instance_count = int(os.getenv('INSTANCE_COUNT'))
            
            logging.info(f"Environment variables loaded:")
            logging.info(f"  MACHINE_TYPE: {os.getenv('MACHINE_TYPE')}")
            logging.info(f"  INSTANCE_COUNT: {os.getenv('INSTANCE_COUNT')}")
            logging.info(f"  TARGET_SPEND: {os.getenv('TARGET_SPEND')}")
            
            logging.info(f"Using configuration from environment:")
            logging.info(f"  Machine Type: {self.machine_type}")
            logging.info(f"  Instance Count: {self.instance_count}")
            
            # Debug: Show current directory contents
            ls_result = subprocess.run(
                ['ls', '-la'],
                check=True,
                capture_output=True,
                text=True
            )
            logging.info(f"Directory contents before terraform init:\n{ls_result.stdout}")

            # Remove any existing tfvars files
            for f in ['terraform.tfvars', 'terraform.tfvars.tpl', 'terraform.tfvars.bak']:
                if os.path.exists(f):
                    os.remove(f)
                    logging.info(f"Removed {f}")

            # Create terraform.tfvars with proper content using updated properties
            tfvars_content = {
                'environments': {
                    'e360': {
                        'project_id': self.project_id,
                        'region': self.region,
                        'zone': self.zone,
                        'instance_count': self.instance_count,
                        'machine_type': self.machine_type,
                        'target_spend': float(self.target_spend)
                    }
                },
                'target_env': 'e360',
                'instance_count': self.instance_count,
                'machine_type': self.machine_type
            }

            # Write the tfvars file in HCL format
            with open('terraform.tfvars', 'w') as f:
                f.write('environments = {\n')
                f.write('  e360 = {\n')
                f.write(f'    project_id         = "{tfvars_content["environments"]["e360"]["project_id"]}"\n')
                f.write(f'    region            = "{tfvars_content["environments"]["e360"]["region"]}"\n')
                f.write(f'    zone              = "{tfvars_content["environments"]["e360"]["zone"]}"\n')
                f.write(f'    instance_count    = {tfvars_content["environments"]["e360"]["instance_count"]}\n')
                f.write(f'    machine_type      = "{tfvars_content["environments"]["e360"]["machine_type"]}"\n')
                f.write(f'    target_spend      = {tfvars_content["environments"]["e360"]["target_spend"]}\n')
                f.write('  }\n')
                f.write('}\n\n')
                f.write(f'target_env = "{tfvars_content["target_env"]}"\n')
                f.write(f'instance_count = {tfvars_content["instance_count"]}\n')
                f.write(f'machine_type = "{tfvars_content["machine_type"]}"\n')
                f.write('create_service_account = false\n')
                f.write('create_artifact_registry = false\n')

            logging.info("Created terraform.tfvars with content:")
            with open('terraform.tfvars', 'r') as f:
                logging.info(f.read())

            # Initialize Terraform
            init_result = subprocess.run(
                ['terraform', 'init'],
                capture_output=True,
                text=True,
                check=True
            )
            logging.info("Terraform initialized successfully")

            # Apply Terraform configuration
            apply_result = subprocess.run(
                ['terraform', 'apply', '-auto-approve'],
                capture_output=True,
                text=True,
            )
            
            if apply_result.returncode != 0:
                raise Exception(f"Terraform apply failed: {apply_result.stderr}")
            
            logging.info("Terraform applied successfully")
            
        except subprocess.CalledProcessError as e:
            logging.error(f"Error running Terraform command: {e.stderr}")
            raise
        except Exception as e:
            logging.error(f"Error initializing Terraform: {str(e)}")
            raise

    def get_instance_cost_per_hour(self):
        """Get the actual cost per hour for the instance type using Cloud Compute API"""
        try:
            logging.info(f"Getting cost for machine type: {self.machine_type}")

            # Get machine type details from Compute API
            request = compute_v1.GetMachineTypeRequest(
                project=self.project_id,
                zone=self.zone,
                machine_type=self.machine_type
            )
            
            machine_type_info = self.machine_types_client.get(request=request)
            
            # Calculate based on specs
            vcpus = machine_type_info.guest_cpus
            memory_gb = machine_type_info.memory_mb / 1024.0
            
            # Base N2 prices
            cpu_price = 0.031611  # N2 price per vCPU
            memory_price = 0.004237  # N2 price per GB
            
            hourly_cost = (vcpus * cpu_price + memory_gb * memory_price)
            total_hourly_cost = hourly_cost * self.instance_count
            per_15s_cost = total_hourly_cost * (15.0/3600.0)
            
            logging.info(f"Instance Cost Summary:")
            logging.info(f"  Machine Type: {self.machine_type}")
            logging.info(f"  Region: {self.region}")
            logging.info(f"  vCPUs: {vcpus}")
            logging.info(f"  Memory: {memory_gb:.1f} GB")
            logging.info(f"  CPU Price: ${cpu_price}/hour/vCPU")
            logging.info(f"  Memory Price: ${memory_price}/hour/GB")
            logging.info(f"  Target Instances: {self.instance_count}")
            logging.info(f"  Cost Per Instance: ${hourly_cost:.4f}/hour")
            logging.info(f"  Total Hourly Cost: ${total_hourly_cost:.2f}/hour")
            logging.info(f"  Total 15-Second Cost: ${per_15s_cost:.4f}/15s")
            return hourly_cost
            
        except Exception as e:
            logging.error(f"Error getting instance cost from Cloud Compute API: {str(e)}")
            logging.warning("Using default rate of $1.50/hour")
            return 1.50  # Default fallback rate

    def _get_access_token(self):
        """Get the current access token for API calls"""
        try:
            cmd = ['gcloud', 'auth', 'print-access-token']
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            logging.error(f"Failed to get access token: {e}")
            raise

    def get_instance_count(self):
        """Get the current number of running instances"""
        try:
            instance_filter = 'name eq video-processor-.*'
            request = compute_v1.ListInstancesRequest(
                project=self.project_id,
                zone=self.zone,
                filter=instance_filter
            )
            instances = list(self.compute_client.list(request=request))
            running_count = sum(1 for instance in instances if instance.status == "RUNNING")
            return running_count
        except Exception as e:
            logging.error(f"Error getting instance count: {str(e)}")
            # Fallback to environment variable
            return int(os.getenv('INSTANCE_COUNT', '8'))

    def get_current_cost(self):
        """Get the current cost for the project"""
        now = datetime.utcnow()
        # Look back 15 seconds
        start_time = now - timedelta(seconds=15)
        
        project_name = f"projects/{self.project_id}"
        interval = monitoring_v3.TimeInterval({
            'start_time': {'seconds': int(start_time.timestamp())},
            'end_time': {'seconds': int(now.timestamp())}
        })
        
        try:
            # First, list actual running instances
            instance_filter = 'name eq video-processor-.*'
            request = compute_v1.ListInstancesRequest(
                project=self.project_id,
                zone=self.zone,
                filter=instance_filter
            )
            instances = list(self.compute_client.list(request=request))
            instance_count = len(instances)
            logging.info(f"Found {instance_count} instances via Compute API")
            
            period_cost = 0.0
            
            for instance in instances:
                if instance.status == "RUNNING":
                    instance_name = instance.name
                    instance_id = instance.id
                    
                    logging.info(f"Found running instance: {instance_name}")
                    logging.info(f"Instance ID: {instance_id}")
                    
                    # Calculate cost for 15 seconds of runtime
                    hours_fraction = 15.0 / 3600.0  # 15 seconds as fraction of hour
                    instance_cost = self.cost_per_hour * hours_fraction
                    period_cost += instance_cost
                    logging.info(f"Added cost ${instance_cost:.2f} for instance {instance_name}")
            
            # Update accumulated cost
            current_time = time.time()
            if period_cost > 0:
                self.accumulated_cost += period_cost
                self.last_update_time = current_time
                logging.info(f"Period cost: ${period_cost:.2f}, Total accumulated cost: ${self.accumulated_cost:.2f}")
            
            # Write the cost metric
            self.write_cost_metric(self.accumulated_cost)
            
            return self.accumulated_cost
        except Exception as e:
            logging.error(f"Error getting current cost: {str(e)}")
            return self.accumulated_cost  # Return last known cost instead of 0

    def write_cost_metric(self, cost):
        """Write the current cost to Cloud Monitoring"""
        try:
            series = monitoring_v3.TimeSeries()
            series.metric.type = "custom.googleapis.com/spender/total_cost"
            series.resource.type = "generic_node"
            
            # Set labels matching dashboard
            series.metric.labels["run_id"] = self.run_id
            series.metric.labels["environment"] = "e360"
            series.metric.labels["component"] = "worker"
            
            series.resource.labels["project_id"] = self.project_id
            series.resource.labels["location"] = self.zone
            series.resource.labels["namespace"] = "spender"
            series.resource.labels["node_id"] = self.run_id
            
            # For GAUGE metrics, start_time must equal end_time
            now = time.time()
            now_seconds = int(now)
            now_nanos = int((now - now_seconds) * 10**9)
            
            # Create the point with equal start and end times
            point = monitoring_v3.Point({
                "interval": {
                    "end_time": {"seconds": now_seconds, "nanos": now_nanos},
                    "start_time": {"seconds": now_seconds, "nanos": now_nanos}
                },
                "value": {"double_value": cost}
            })
            series.points = [point]
            
            logging.info(f"Writing metric with labels: {series.metric.labels}")
            self.monitoring_client.create_time_series(
                request={
                    "name": f"projects/{self.project_id}",
                    "time_series": [series]
                }
            )
            logging.info(f"Successfully wrote cost metric: ${cost:.2f}")
        except Exception as e:
            logging.error(f"Error writing cost metric: {str(e)}")

    def write_instance_count_metric(self, count):
        """Write the current instance count to Cloud Monitoring"""
        try:
            series = monitoring_v3.TimeSeries()
            series.metric.type = "custom.googleapis.com/spender/instance_count"
            series.resource.type = "generic_node"
            
            # Set labels matching dashboard
            series.metric.labels["run_id"] = self.run_id
            series.metric.labels["environment"] = "e360"
            series.metric.labels["component"] = "worker"
            
            series.resource.labels["project_id"] = self.project_id
            series.resource.labels["location"] = self.zone
            series.resource.labels["namespace"] = "spender"
            series.resource.labels["node_id"] = self.run_id
            
            # For GAUGE metrics, start_time must equal end_time
            now = time.time()
            now_seconds = int(now)
            now_nanos = int((now - now_seconds) * 10**9)
            
            point = monitoring_v3.Point({
                "interval": {
                    "end_time": {"seconds": now_seconds, "nanos": now_nanos},
                    "start_time": {"seconds": now_seconds, "nanos": now_nanos}
                },
                "value": {"int64_value": count}
            })
            series.points = [point]
            
            logging.info(f"Writing instance count metric: {count}")
            self.monitoring_client.create_time_series(
                request={
                    "name": f"projects/{self.project_id}",
                    "time_series": [series]
                }
            )
            logging.info(f"Successfully wrote instance count metric: {count}")
        except Exception as e:
            logging.error(f"Error writing instance count metric: {str(e)}")

    def check_and_manage_resources(self):
        """Check current costs and manage resources accordingly"""
        try:
            current_cost = self.get_current_cost()
            logging.info(f"Current cost: ${current_cost:.2f}")
            
            # Get and write instance count
            instance_count = self.get_instance_count()
            self.write_instance_count_metric(instance_count)
            
            if current_cost >= self.target_spend:
                logging.warning(f"Cost (${current_cost:.2f}) exceeds target (${self.target_spend:.2f})")
                self.cleanup_resources()
            else:
                logging.info(f"Cost is within target. Current: ${current_cost:.2f}, Target: ${self.target_spend:.2f}")
        
        except Exception as e:
            logging.error(f"Error in check_and_manage_resources: {str(e)}")
            raise

    def cleanup_resources(self):
        """Clean up resources using Terraform destroy"""
        try:
            # Run terraform destroy
            destroy_result = subprocess.run(
                ['terraform', 'destroy', '-auto-approve'],
                capture_output=True,
                text=True
            )
            
            if destroy_result.returncode != 0:
                raise Exception(f"Terraform destroy failed: {destroy_result.stderr}")
            
            logging.info("Resources cleaned up successfully")
            sys.exit(0)
            
        except Exception as e:
            logging.error(f"Error during cleanup: {str(e)}")
            sys.exit(1)

    def test_credentials(self):
        """Test if credentials are properly configured"""
        try:
            # Try to list projects as a simple test
            from google.cloud import resourcemanager_v3
            client = resourcemanager_v3.ProjectsClient()
            project_name = f"projects/{self.project_id}"
            project = client.get_project(name=project_name)
            print(f"Successfully authenticated. Project: {project.project_id}")
            return True
        except Exception as e:
            print(f"Authentication failed: {str(e)}")
            return False

def main():
    # Load environment variables
    load_dotenv()
    
    # Get configuration from environment
    project_id = os.getenv('GCP_PROJECT_ID')
    target_spend = os.getenv('TARGET_SPEND')
    region = os.getenv('GCP_REGION')
    zone = os.getenv('GCP_ZONE')
    check_interval = 15.0 / 60.0  # 15 seconds in minutes
    
    logging.info(f"Check Interval: {check_interval * 60} seconds")
    
    cost_manager = None
    try:
        # Initialize cost manager
        cost_manager = GCPCostManager(
            project_id=project_id,
            target_spend=target_spend,
            region=region,
            zone=zone
        )
        
        if not cost_manager.test_credentials():
            print("Failed to authenticate. Exiting.")
            sys.exit(1)
        
        # Main loop
        while True:
            cost_manager.check_and_manage_resources()
            time.sleep(check_interval * 60)  # Convert minutes to seconds
            
    except KeyboardInterrupt:
        logging.info("Shutting down...")
        if cost_manager and os.getenv('DESTROY_ON_EXIT', 'true').lower() == 'true':
            cost_manager.cleanup_resources()
            sys.exit(0)
    except Exception as e:
        logging.error(f"Error in main loop: {str(e)}")
        if cost_manager and os.getenv('DESTROY_ON_EXIT', 'true').lower() == 'true':
            try:
                cost_manager.cleanup_resources()
            except Exception as cleanup_error:
                logging.error(f"Error during cleanup: {str(cleanup_error)}")
        sys.exit(1)

if __name__ == "__main__":
    main() 