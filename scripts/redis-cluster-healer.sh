#!/bin/bash

# Enviroment Variable
REDIS_PORT_NUMBER=${REDIS_PORT_NUMBER:-6379}
END_POD_NUMBER=${END_POD_NUMBER:-5}
REDIS_CLI_TIMEOUT=${REDIS_CLI_TIMEOUT:-30}
REDIS_CLI_RETRIES=${REDIS_CLI_RETRIES:-3}
REDIS_PASSWORD=${REDIS_PASSWORD:-""}
REDIS_TLS_ENABLED=${REDIS_TLS_ENABLED:-"yes"}
REDIS_CA_CERT=${REDIS_CA_CERT:-""}
REDIS_CLIENT_CERT=${REDIS_CLIENT_CERT:-""}
REDIS_CLIENT_KEY=${REDIS_CLIENT_KEY:-""}
REDIS_RECOVERY_SCRIPT_INTERVEL=${REDIS_RECOVERY_SCRIPT_INTERVEL:-60}
REDIS_HOST_ADDRS=${REDIS_HOST_ADDRS:-"redis-cluster"}
REDIS_HEADLESS_SVC_ADDRS=${REDIS_HEADLESS_SVC_ADDRS:-"redis-cluster-headless"}

# Colors and Symbols
RED='\033[0;31m'
GREEN='\033[0;32m'
#BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
CHECK_MARK="✅"
CROSS_MARK="❌"
INFO="ℹ️"

# Logging functions
log() {
    echo -e "${NC}${INFO} $(date '+%Y-%m-%d %H:%M:%S') - INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}${CHECK_MARK} $(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1${NC}"
}

log_error() {
    echo -e "${RED}${CROSS_MARK} $(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1${NC}" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠️ $(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1${NC}"
}

# Safe Redis CLI function with retries and error handling
redis_cli_safe() {
    local retries=$REDIS_CLI_RETRIES
    local result

    while [ $retries -gt 0 ]; do
        if [ "$REDIS_TLS_ENABLED" = "yes" ]; then
            result=$(timeout $REDIS_CLI_TIMEOUT redis-cli --tls --cacert $REDIS_CA_CERT --cert $REDIS_CLIENT_CERT --key $REDIS_CLIENT_KEY -a $REDIS_PASSWORD "$@")
        else
            result=$(timeout $REDIS_CLI_TIMEOUT redis-cli -a $REDIS_PASSWORD "$@")
        fi

        if [ $? -eq 0 ]; then
            echo "$result"
            return 0
        else
            log_error "Redis command failed: redis-cli $@"
            retries=$((retries - 1))
            log_warning "Retries left: $retries"
            sleep 2
        fi
    done

    log_error "Redis command failed after $REDIS_CLI_RETRIES attempts: redis-cli $@"
    return 1
}

# Remove failed nodes from the cluster
remove_failed_nodes() {
    log "Checking for failed nodes in the cluster..."
    failed_nodes=$(redis_cli_safe -h $REDIS_HOST_ADDRS -p $REDIS_PORT_NUMBER CLUSTER NODES | grep fail | awk '{print $1}' | tr '\n' ' ')

    if [ -z "$failed_nodes" ]; then
        log_success "No failed nodes found in the cluster."
        return 0
    else
        log_warning "Found failed nodes: $failed_nodes"
    fi

    sleep 15  # Wait for cluster state to stabilize

    for failed_node in $failed_nodes; do
        for ((i=0; i<=$END_POD_NUMBER; i++)); do
            log "Attempting to remove failed node $failed_node from redis-cluster-$i..."
            if redis_cli_safe -h $REDIS_HOST_ADDRS-$i.$REDIS_HEADLESS_SVC_ADDRS -p $REDIS_PORT_NUMBER CLUSTER FORGET $failed_node; then
                log_success "Node $failed_node successfully removed from redis-cluster-$i."
            else
                log_error "Failed to remove node $failed_node from redis-cluster-$i."
            fi
        done
    done

    return 0
}

# Find unique IPs of Redis pods
find_unique_ips() {
    unique_ips=$(getent ahosts $REDIS_HEADLESS_SVC_ADDRS | awk '{print $1}' | sort | uniq | tr '\n' ' ')
    log "Unique IPs of all Redis pods: ${unique_ips}"
}

# Find IPs of new Redis pods not in the cluster
find_new_pods_ips() {
    find_unique_ips
    
    ip_addresses=$(redis_cli_safe -h $REDIS_HOST_ADDRS -p $REDIS_PORT_NUMBER CLUSTER NODES | awk '{split($2, a, ":"); print a[1]}' | tr '\n' ' ')      
    log "IP addresses of all nodes in the cluster: ${ip_addresses}"
    
    unique_ips_array=($unique_ips)
    ip_addresses_array=($ip_addresses)
    
    new_pods_ips=()
    
    for ip in "${unique_ips_array[@]}"; do
        found=false
        for cluster_ip in "${ip_addresses_array[@]}"; do
            if [ "$ip" == "$cluster_ip" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            new_pods_ips+=("$ip")
            log "Found new pod IP: $ip"
        fi
    done

    if [ ${#new_pods_ips[@]} -eq 0 ]; then
        log_success "No Redis pods found that are not in the cluster."
        return 1
    else
        log_warning "Found new Redis pods not in the cluster: ${new_pods_ips[*]}"
        return 0
    fi
}

# Add new pods to the cluster
add_new_pods_to_cluster() {
    for new_pod_ip in "${new_pods_ips[@]}"; do
        log "Adding new pod $new_pod_ip to the cluster..."
        if redis_cli_safe -h $REDIS_HOST_ADDRS -p $REDIS_PORT_NUMBER CLUSTER MEET $new_pod_ip $REDIS_PORT_NUMBER; then
            log_success "Node $new_pod_ip successfully added to the cluster."
        else
            log_error "Failed to add node $new_pod_ip to the cluster."
        fi
    done
}

# Get information about masters in the cluster
get_masters_info() {
    local -n masters_with_slots_ref=$1
    local -n masters_without_slots_ref=$2
    local -n masters_without_replicas_ref=$3
    local redis_cluster_info
    
    redis_cluster_info=$(redis_cli_safe -h $REDIS_HOST_ADDRS -p $REDIS_PORT_NUMBER CLUSTER NODES)

    while IFS= read -r node; do
        node_id=$(echo $node | awk '{print $1}')
        ip_port=$(echo $node | awk '{print $2}' | cut -d'@' -f1)
        role=$(echo $node | awk '{print $3}')
        slots=$(echo $node | awk '{print $9}')
        
        if [[ $role == "master" || $role == "myself,master" ]]; then
            if [[ -z $slots ]]; then
                masters_without_slots_ref+=("$node_id")
                log "Added to masters_without_slots: $node_id"
            else
                masters_with_slots_ref+=("$node_id")
                
                replicas=$(redis_cli_safe -h $REDIS_HOST_ADDRS-0.$REDIS_HEADLESS_SVC_ADDRS -p $REDIS_PORT_NUMBER CLUSTER REPLICAS $node_id)
                if [ -z "$replicas" ]; then
                    log_warning "Master $node_id has assigned slots but no replicas."
                    masters_without_replicas_ref+=("$node_id")
                else
                    log_success "Master $node_id has replicas: $replicas"
                fi
            fi
        fi
    done <<< "$redis_cluster_info"
}

# Assign replicas to masters without replicas
assign_replicas() {
    local masters_with_slots=()
    local masters_without_slots=()
    local masters_without_replicas=()

    log "Fetching master information from the cluster..."
    get_masters_info masters_with_slots masters_without_slots masters_without_replicas

    log "Masters with slots: ${masters_with_slots[*]}"
    log "Masters without slots: ${masters_without_slots[*]}"
    log "Masters without replicas: ${masters_without_replicas[*]}"
  
    if [[ ${#masters_without_slots[@]} -eq 0 || ${#masters_without_replicas[@]} -eq 0 ]]; then
        log_success "No available masters without slots or no masters without replicas to assign."
        return 1
    fi

    redis_cluster_info=$(redis_cli_safe -h $REDIS_HOST_ADDRS -p "$REDIS_PORT_NUMBER" CLUSTER NODES)

    for master_id in "${masters_without_replicas[@]}"; do
        for replica_candidate_id in "${masters_without_slots[@]}"; do
            log "Processing replica candidate ID: $replica_candidate_id"

            replica_ip=$(echo "$redis_cluster_info" | awk -v id="$replica_candidate_id" '$1 == id {split($2, a, ":"); print a[1]}')

            if [ -z "$replica_ip" ]; then
                log_error "Failed to obtain IP address for replica candidate $replica_candidate_id."
                continue
            fi

            log "Attempting to set $replica_candidate_id as a replica for master $master_id..."
            if redis_cli_safe -h "$replica_ip" -p "$REDIS_PORT_NUMBER" CLUSTER REPLICATE "$master_id"; then
                log_success "Empty master $replica_candidate_id successfully set as a replica for master $master_id."
                masters_without_slots=($(printf "%s\n" "${masters_without_slots[@]}" | grep -v "^$replica_candidate_id\$"))
                break
            else
                log_error "Failed to set empty master $replica_candidate_id as a replica for master $master_id."
            fi
        done

        if [ ${#masters_without_slots[@]} -eq 0 ]; then
            log_warning "No more empty masters available."
            break
        fi
    done
  
    sleep 15  # Wait for cluster state to stabilize
    log "Redis cluster info after update: \n$(redis_cli_safe -h $REDIS_HOST_ADDRS -p "$REDIS_PORT_NUMBER" CLUSTER NODES)"

    return 0
}

#Main script execution
ascii_art=$(figlet -f big -w 100 "REDISKAGE" | awk '{print "\033[36m" $0 "\033[0m"}')
border=$(printf '%*s\n' 100 | tr ' ' '#')
echo "$border"
echo -e "$ascii_art"
echo "$border"
echo -e "\t\t\t\t\t\t\nRepository: \033]8;;https://github.com/piyushgautamsingh/rediskage\033\\https://github.com/piyushgautamsingh/rediskage\033]8;;\033\\"


while true; do
       log "Starting Redis cluster maintenance..."

       remove_failed_nodes
       clean_status=$?

       find_new_pods_ips
       find_new_pods_ips_status=$?

       if [ $find_new_pods_ips_status -eq 0 ]; then
       add_new_pods_to_cluster
       sleep 15
       fi

       assign_replicas
       log_success "Redis cluster maintenance completed."
       sleep $REDIS_RECOVERY_SCRIPT_INTERVEL;
done