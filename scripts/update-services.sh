#!/bin/bash

# Update ECS Services Script
# This script forces ECS services to update with the latest Docker images
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
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-ecs-trial}"
CLUSTER_NAME="${ENVIRONMENT_NAME}-cluster"
WAIT_FOR_STABLE="${WAIT_FOR_STABLE:-true}"

# Services to update (can be overridden by passing service name as argument)
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
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Verify cluster exists
    if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
        log_error "ECS cluster '$CLUSTER_NAME' not found in region $AWS_REGION"
        exit 1
    fi
    
    log_info "Prerequisites check passed ✓"
}

# Update a single service
update_service() {
    local service=$1
    local service_name="${ENVIRONMENT_NAME}-${service}-service"
    
    log_step "Updating ${service} service..."
    
    # Check if service exists
    local service_status=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$AWS_REGION" \
        --query 'services[0].status' \
        --output text 2>/dev/null)
    
    if [ "$service_status" != "ACTIVE" ]; then
        log_error "Service '$service_name' not found or not active"
        return 1
    fi
    
    # Force new deployment
    log_info "Forcing new deployment for ${service} service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$service_name" \
        --force-new-deployment \
        --region "$AWS_REGION" \
        --query 'service.serviceName' \
        --output text > /dev/null
    
    if [ $? -eq 0 ]; then
        log_info "Deployment initiated for ${service} service ✓"
        return 0
    else
        log_error "Failed to update ${service} service"
        return 1
    fi
}

# Wait for service to stabilize
wait_for_service() {
    local service=$1
    local service_name="${ENVIRONMENT_NAME}-${service}-service"
    
    log_step "Waiting for ${service} service to stabilize..."
    log_info "This may take 5-10 minutes..."
    
    # Use AWS CLI wait command
    aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$AWS_REGION"
    
    if [ $? -eq 0 ]; then
        log_info "${service} service is now stable ✓"
        return 0
    else
        log_error "${service} service failed to stabilize"
        log_error "Check CloudWatch Logs for details: aws logs tail /ecs/${ENVIRONMENT_NAME} --follow --filter-pattern \"${service}\""
        return 1
    fi
}

# Get deployment status
get_deployment_status() {
    local service=$1
    local service_name="${ENVIRONMENT_NAME}-${service}-service"
    
    log_step "Getting deployment status for ${service}..."
    
    aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$AWS_REGION" \
        --query 'services[0].deployments[*].[id,status,runningCount,desiredCount,rolloutState]' \
        --output table
}

# Check service health
check_service_health() {
    local service=$1
    local service_name="${ENVIRONMENT_NAME}-${service}-service"
    
    log_step "Checking ${service} service health..."
    
    local running_count=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$AWS_REGION" \
        --query 'services[0].runningCount' \
        --output text)
    
    local desired_count=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --region "$AWS_REGION" \
        --query 'services[0].desiredCount' \
        --output text)
    
    log_info "Running tasks: ${running_count}/${desired_count}"
    
    if [ "$running_count" -eq "$desired_count" ]; then
        log_info "${service} service is healthy ✓"
        return 0
    else
        log_warning "${service} service is not at desired capacity"
        return 1
    fi
}

# Main execution
main() {
    echo ""
    log_info "=========================================="
    log_info "  ECS Service Update"
    log_info "=========================================="
    log_info "Environment: ${ENVIRONMENT_NAME}"
    log_info "Cluster: ${CLUSTER_NAME}"
    log_info "Region: ${AWS_REGION}"
    log_info "Services: ${SERVICES[*]}"
    log_info "Wait for stable: ${WAIT_FOR_STABLE}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Update all services
    local failed_services=()
    local updated_services=()
    
    # First, trigger updates for all services
    for service in "${SERVICES[@]}"; do
        echo ""
        log_info "------------------------------------------"
        log_info "Updating ${service} service"
        log_info "------------------------------------------"
        
        if update_service "$service"; then
            updated_services+=("$service")
        else
            failed_services+=("$service")
        fi
    done
    
    # If any service failed to update, exit
    if [ ${#failed_services[@]} -gt 0 ]; then
        log_error "Failed to update services: ${failed_services[*]}"
        exit 1
    fi
    
    # Wait for services to stabilize if requested
    if [ "$WAIT_FOR_STABLE" = "true" ]; then
        echo ""
        log_info "=========================================="
        log_info "  Waiting for Deployments to Complete"
        log_info "=========================================="
        
        for service in "${updated_services[@]}"; do
            echo ""
            if ! wait_for_service "$service"; then
                failed_services+=("$service")
            fi
        done
    fi
    
    # Final health check
    echo ""
    log_info "=========================================="
    log_info "  Final Health Check"
    log_info "=========================================="
    
    for service in "${updated_services[@]}"; do
        echo ""
        check_service_health "$service"
        get_deployment_status "$service"
    done
    
    # Summary
    echo ""
    log_info "=========================================="
    log_info "  Update Summary"
    log_info "=========================================="
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_info "All services updated successfully! ✓"
        echo ""
        log_info "Updated services:"
        for service in "${updated_services[@]}"; do
            echo "  • ${service}-service"
        done
        echo ""
        log_info "Monitor your deployment:"
        echo "  aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${ENVIRONMENT_NAME}-auth-service --region ${AWS_REGION}"
        echo "  aws logs tail /ecs/${ENVIRONMENT_NAME} --follow"
        exit 0
    else
        log_error "The following services failed: ${failed_services[*]}"
        log_error "Check logs with: aws logs tail /ecs/${ENVIRONMENT_NAME} --follow"
        exit 1
    fi
}

# Run main function
main