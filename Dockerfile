FROM --platform=linux/amd64 google/cloud-sdk:slim

WORKDIR /app

# Install Python and dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    unzip \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN curl -fsSL https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip -o terraform.zip \
    && unzip terraform.zip \
    && mv terraform /usr/local/bin/ \
    && rm terraform.zip \
    && terraform version

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip3 install --break-system-packages --no-cache-dir -r requirements.txt

# Copy all files
COPY cost_manager.py main.tf variables.tf outputs.tf entrypoint.sh ./
RUN chmod 755 /app/entrypoint.sh

# Debug: Show what files are in the container
RUN echo "=== Container contents ===" && \
    ls -la && \
    echo "=== Looking for tfvars files ===" && \
    find / -name "*.tfvars*" || true

# Set the entrypoint
ENTRYPOINT ["/bin/bash", "/app/entrypoint.sh"]