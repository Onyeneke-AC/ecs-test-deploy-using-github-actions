#!/bin/bash

# Build and Push Script for ECR
# This script builds Docker images and pushes them to Amazon ECR
# Can be run manually or by GitHub Actions

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-eu-west-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-ecs-trial}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Services to build (can be overridden by passing service name as argument)
if [ -z "$1" ]; then
    SERVICES=("auth" "users" "tasks" "frontend")
else
    SERVICES=("$1")
fi

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_warning "AWS_ACCOUNT_ID not set. Attempting to retrieve..."
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        if [ -z "$AWS_ACCOUNT_ID" ]; then
            log_error "Could not determine AWS Account ID. Please set AWS_ACCOUNT_ID environment variable."
            exit 1
        fi
        log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    fi
    
    log_info "Prerequisites check passed ✓"
}

# Login to ECR
login_to_ecr() {
    log_step "Logging in to Amazon ECR..."
    
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin \
        "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    if [ $? -eq 0 ]; then
        log_info "Successfully logged in to ECR ✓"
    else
        log_error "Failed to login to ECR"
        exit 1
    fi
}

# Build Docker image
build_image() {
    local service=$1
    local service_dir="${service}-service"
    
    log_step "Building Docker image for ${service} service..."
    
    # Check if service directory exists
    if [ ! -d "$service_dir" ]; then
        log_error "Service directory '$service_dir' not found"
        return 1
    fi
    
    # Check if Dockerfile exists
    if [ ! -f "$service_dir/Dockerfile" ]; then
        log_error "Dockerfile not found in '$service_dir'"
        return 1
    fi
    
    local image_name="${ENVIRONMENT_NAME}-${service}"
    
    # Build the image
    docker build \
        -t "$image_name:$IMAGE_TAG" \
        -t "$image_name:latest" \
        "$service_dir"
    
    if [ $? -eq 0 ]; then
        log_info "Successfully built ${service} image ✓"
        return 0
    else
        log_error "Failed to build ${service} image"
        return 1
    fi
}

# Push Docker image to ECR
push_image() {
    local service=$1
    local ecr_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    local repository="${ENVIRONMENT_NAME}-${service}"
    local image_name="${ENVIRONMENT_NAME}-${service}"
    
    log_step "Pushing ${service} image to ECR..."
    
    # Tag for ECR
    docker tag "${image_name}:${IMAGE_TAG}" "${ecr_uri}/${repository}:${IMAGE_TAG}"
    docker tag "${image_name}:latest" "${ecr_uri}/${repository}:latest"
    
    # Push with specific tag
    docker push "${ecr_uri}/${repository}:${IMAGE_TAG}"
    if [ $? -ne 0 ]; then
        log_error "Failed to push ${service} image with tag ${IMAGE_TAG}"
        return 1
    fi
    
    # Push latest tag
    docker push "${ecr_uri}/${repository}:latest"
    if [ $? -ne 0 ]; then
        log_error "Failed to push ${service} image with tag latest"
        return 1
    fi
    
    log_info "Successfully pushed ${service} image to ECR ✓"
    log_info "Image URI: ${ecr_uri}/${repository}:${IMAGE_TAG}"
    
    return 0
}

# Main execution
main() {
    echo ""
    log_info "=========================================="
    log_info "  Docker Build and Push to ECR"
    log_info "=========================================="
    log_info "Environment: ${ENVIRONMENT_NAME}"
    log_info "Region: ${AWS_REGION}"
    log_info "Image Tag: ${IMAGE_TAG}"
    log_info "Services: ${SERVICES[*]}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Login to ECR
    login_to_ecr
    
    # Build and push each service
    local failed_services=()
    
    for service in "${SERVICES[@]}"; do
        echo ""
        log_info "------------------------------------------"
        log_info "Processing ${service} service"
        log_info "------------------------------------------"
        
        # Build
        if ! build_image "$service"; then
            failed_services+=("$service")
            log_warning "Skipping push for ${service} due to build failure"
            continue
        fi
        
        # Push
        if ! push_image "$service"; then
            failed_services+=("$service")
            continue
        fi
        
        log_info "${service} service completed successfully ✓"
    done
    
    # Summary
    echo ""
    log_info "=========================================="
    log_info "  Build and Push Summary"
    log_info "=========================================="
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_info "All services built and pushed successfully! ✓"
        echo ""
        log_info "Images pushed:"
        for service in "${SERVICES[@]}"; do
            echo "  • ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT_NAME}-${service}:${IMAGE_TAG}"
        done
        exit 0
    else
        log_error "The following services failed: ${failed_services[*]}"
        exit 1
    fi
}

# Run main function
main