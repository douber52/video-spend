import json
import subprocess

# Configuration variables (example values, replace with real data)
PROJECT_ID = "e360-lab"
REGION = "us-central1"
TARGET_SPEND = 20000.00  # USD
INSTANCE_HOURLY_COST = 200.00  # USD/hour for chosen instance type (e.g., a large GPU instance)
HOURS = 24

# This script attempts to:
# 1. Check CPU quota in the given project/region.
# 2. Calculate how many instances are needed to spend TARGET_SPEND in HOURS using INSTANCE_HOURLY_COST.
# 3. Compare required instance count with available quota.

def get_quota():
    # Retrieve quota information as JSON
    # 'compute project-info describe' often doesn't directly provide quota in JSON,
    # so we use 'gcloud compute regions describe' to get regional quotas, or
    # 'gcloud projects describe' for some global quotas.
    # Below we assume a regional check:
    cmd = ["gcloud", "compute", "regions", "describe", REGION, "--project", PROJECT_ID, "--format=json"]
    output = subprocess.check_output(cmd)
    data = json.loads(output)
    return data

def find_cpu_quota(data):
    # Find the CPU quota from the region's quota data
    # The JSON includes a 'quotas' field like:
    # "quotas": [
    #   {
    #     "metric": "CPUS",
    #     "limit": 500,
    #     "usage": 0
    #   },
    #   ...
    # ]
    for quota in data.get("quotas", []):
        if quota["metric"] == "CPUS":
            return quota["limit"] - quota["usage"]
    return 0

def main():
    data = get_quota()
    available_cpus = find_cpu_quota(data)

    # Calculate how many instances needed
    # Spend needed per hour: TARGET_SPEND / HOURS
    needed_per_hour = TARGET_SPEND / HOURS

    # Number of instances = needed_per_hour / INSTANCE_HOURLY_COST
    instances_needed = needed_per_hour / INSTANCE_HOURLY_COST

    # Round up since we need whole instances
    instances_needed = int(instances_needed) if instances_needed == int(instances_needed) else int(instances_needed) + 1

    # Now check if we have enough CPUs for that many instances.
    # Assuming each instance is a certain machine type with known CPU count, e.g., 96 vCPUs per instance.
    # Replace this with the actual vCPU count for your chosen instance type.
    INSTANCE_VCPU = 64
    total_vcpus_needed = instances_needed * INSTANCE_VCPU

    print(f"Available CPUs: {available_cpus}")
    print(f"Instances needed: {instances_needed}")
    print(f"Total vCPUs required: {total_vcpus_needed}")

    if total_vcpus_needed <= available_cpus:
        print("You have sufficient quota to run this many instances.")
    else:
        print("You do NOT have sufficient CPU quota to meet the spending target. Consider fewer, more expensive instances or request a quota increase.")

if __name__ == "__main__":
    main()
