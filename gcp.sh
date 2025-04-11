#!/bin/bash

# Configuration Variables
PROJECT_ID="gopale-lab"  # Updated to your project ID
REGION="us-central1"
SECONDARY_REGION="us-east1"
VPC_NAME="gopale-vpc"
PRIVATE_SUBNET_1="gopale-private-subnet-1"
PRIVATE_SUBNET_2="gopale-private-subnet-2"
PUBLIC_SUBNET="gopale-public-subnet"
CONNECTOR_NAME="gopale-connector"
SERVICE_NAME="gopale-service"
NEG_NAME="gopale-neg"
LB_IP_NAME="gopale-lb-ip"
BACKEND_SERVICE="gopale-backend"
URL_MAP="gopale-url-map"
HTTP_PROXY="gopale-http-proxy"
FORWARDING_RULE="gopale-lb-rule"
IMAGE_URL="public.ecr.aws/515880899753/gopale-ecr:latest"

# Step 1: Set the Project
echo "Setting the project to $PROJECT_ID..."
gcloud config set project $PROJECT_ID

# Step 2: Enable Required APIs
echo "Enabling required APIs..."
gcloud services enable \
  compute.googleapis.com \
  run.googleapis.com \
  vpcaccess.googleapis.com \
  cloudbuild.googleapis.com

# Step 3: Create VPC and Subnets
echo "Creating VPC: $VPC_NAME..."
gcloud compute networks create $VPC_NAME \
  --subnet-mode=custom \
  --bgp-routing-mode=regional

echo "Creating private subnet 1: $PRIVATE_SUBNET_1 in $REGION..."
gcloud compute networks subnets create $PRIVATE_SUBNET_1 \
  --network=$VPC_NAME \
  --region=$REGION \
  --range=10.0.1.0/24

echo "Creating private subnet 2: $PRIVATE_SUBNET_2 in $SECONDARY_REGION..."
gcloud compute networks subnets create $PRIVATE_SUBNET_2 \
  --network=$VPC_NAME \
  --region=$SECONDARY_REGION \
  --range=10.0.2.0/24

echo "Creating public subnet: $PUBLIC_SUBNET in $REGION..."
gcloud compute networks subnets create $PUBLIC_SUBNET \
  --network=$VPC_NAME \
  --region=$REGION \
  --range=10.0.3.0/24

# Step 4: Create Serverless VPC Access Connector
echo "Creating Serverless VPC Access connector: $CONNECTOR_NAME..."
gcloud compute networks vpc-access connectors create $CONNECTOR_NAME \
  --region=$REGION \
  --network=$VPC_NAME \
  --range=10.0.4.0/28 \
  --min-instances=2 \
  --max-instances=10

# Step 5: Configure Firewall Rules
echo "Creating firewall rule to allow internal traffic..."
gcloud compute firewall-rules create gopale-allow-internal \
  --network=$VPC_NAME \
  --allow=tcp:0-65535,udp:0-65535,icmp \
  --source-ranges=10.0.0.0/16 \
  --direction=INGRESS

echo "Creating firewall rule to allow Load Balancer and health checks..."
gcloud compute firewall-rules create gopale-allow-lb \
  --network=$VPC_NAME \
  --allow=tcp:5000 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --direction=INGRESS

# Step 6: Deploy to Cloud Run
echo "Deploying to Cloud Run: $SERVICE_NAME..."
gcloud run deploy $SERVICE_NAME \
  --image=$IMAGE_URL \
  --region=$REGION \
  --platform=managed \
  --vpc-connector=$CONNECTOR_NAME \
  --allow-unauthenticated \
  --port=5000 \
  --min-instances=1 \
  --max-instances=10 \
  --cpu=1 \
  --memory=512Mi \
  --no-allow-unauthenticated # Temporarily allow public access; we'll secure with LB

# Step 7: Set Up Load Balancer
echo "Creating Serverless Network Endpoint Group (NEG): $NEG_NAME..."
gcloud compute network-endpoint-groups create $NEG_NAME \
  --region=$REGION \
  --network-endpoint-type=serverless \
  --cloud-run-service=$SERVICE_NAME

echo "Reserving a static IP for the Load Balancer: $LB_IP_NAME..."
gcloud compute addresses create $LB_IP_NAME \
  --global \
  --ip-version=IPV4

echo "Creating backend service: $BACKEND_SERVICE..."
gcloud compute backend-services create $BACKEND_SERVICE \
  --global \
  --load-balancing-scheme=EXTERNAL_MANAGED

echo "Adding NEG to backend service..."
gcloud compute backend-services add-backend $BACKEND_SERVICE \
  --global \
  --network-endpoint-group=$NEG_NAME \
  --network-endpoint-group-region=$REGION

echo "Creating URL map: $URL_MAP..."
gcloud compute url-maps create $URL_MAP \
  --default-service=$BACKEND_SERVICE

echo "Creating target HTTP proxy: $HTTP_PROXY..."
gcloud compute target-http-proxies create $HTTP_PROXY \
  --url-map=$URL_MAP

echo "Creating forwarding rule: $FORWARDING_RULE..."
gcloud compute forwarding-rules create $FORWARDING_RULE \
  --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --address=$LB_IP_NAME \
  --ports=80 \
  --target-http-proxy=$HTTP_PROXY

# Step 8: Get the Load Balancer IP and Test
echo "Retrieving the Load Balancer IP..."
LB_IP=$(gcloud compute addresses describe $LB_IP_NAME --global --format="get(address)")
echo "Load Balancer IP: $LB_IP"

echo "Testing the application via Load Balancer..."
curl http://$LB_IP

echo "Setup complete! Access your application at http://$LB_IP"