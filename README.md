# RedisKage

**RedisKage** is a reliable backup and restore application designed for Redis clusters. It efficiently manages Redis keys and configuration files, ensuring data integrity and availability. RedisKage backs up Redis keys based on a specified pattern and the critical `nodes.conf` file, which contains Redis cluster node configurations. These backups are stored locally and automatically uploaded to an S3 bucket. Additionally, RedisKage supports restoring missing keys from S3, making it an essential tool for cluster management.

---

## Features

- **Pattern-Based Key Backup**: Back up Redis keys that match a specified pattern.
- **Node Configuration Backup**: Save the `nodes.conf` file with Redis cluster node details.
- **S3 Integration**: Automatically upload backups to an S3 bucket and retrieve them for restores.
- **Automated Scheduling**: Configure periodic backup and restore processes using the `SCHEDULE_TIME` environment variable (in seconds).
- **Redis Cluster Healer**: A sidecar component that monitors and ensures the health of the Redis cluster, providing stability and fault tolerance.

---

## Components

RedisKage includes several Python scripts and a shell script for managing backups, restores, and cluster health:

### 1. **`get_keys.py`**
   - Backups Redis keys that match a specific pattern.
   - Stores the backups locally in `/rediskage/backup`.

### 2. **`get_nodeconf.py`**
   - Retrieves the `nodes.conf` file from Redis pods using the Kubernetes client.
   - Saves the configuration locally in `/rediskage/backup`.

### 3. **`upload_file.py`**
   - Uploads local backup files from `/rediskage/backup` to a specified S3 bucket.

### 4. **`put_keys.py`**
   - Downloads backups from the S3 bucket.
   - Restores missing Redis keys using the downloaded files.

### 5. **`redis-cluster-healer.sh`**
   - Operates as a sidecar to monitor the Redis cluster.
   - Detects and resolves node failures, manages new pods, and ensures cluster stability.
   - Works in parallel with RedisKage’s backup and restore processes.

---

## Configuration

RedisKage is configured via the following environment variables:

| Variable                  | Description                                                | Default Value                  |
|---------------------------|------------------------------------------------------------|--------------------------------|
| `SCHEDULE_TIME`           | Interval (in seconds) for backups and restores             | `60`                           |
| `PATTERN`                 | Pattern to match Redis keys for backup                     | `"tyk-admin-api*"`             |
| `BACKUP_DIR`              | Directory to store local backups                           | `/rediskage/backup`            |
| `S3_ENDPOINT_URL`         | URL for S3-compatible storage                              | `""`                           |
| `S3_BUCKET_NAME`          | Name of the S3 bucket for backups                          | `""`                           |
| `REDIS_NODE`              | Address of the Redis node                                  | `""`                           |
| `NODECONF_FILE_PATH`      | Path to the `nodes.conf` file on the Redis pod             | `/bitnami/redis/data/nodes.conf` |
| `CACERT`                  | Path to the CA certificate for Redis SSL/TLS               | `/var/lib/rediskage/config/certs/ca.crt` |
| `TLS_CRT`                 | Path to the TLS certificate for Redis SSL/TLS              | `/var/lib/rediskage/config/certs/tls.crt` |
| `TLS_KEY`                 | Path to the TLS key for Redis SSL/TLS                      | `/var/lib/rediskage/config/certs/tls.key` |
| `KUBECONFIG`              | Path to the Kubernetes configuration file                 | `/var/lib/rediskage/config/kubeconfig`     |

---

## Usage

### 1. **Automated Backups**
   - RedisKage periodically runs `get_keys.py` and `get_nodeconf.py` to back up Redis keys matching the specified pattern and the `nodes.conf` file.
   - Backups are stored locally in `/rediskage/backup`.

### 2. **S3 Backup Upload**
   - Once a backup is created, `upload_file.py` automatically uploads files from `/rediskage/backup` to the configured S3 bucket.

### 3. **Automated Restores**
   - Using the same `SCHEDULE_TIME`, `put_keys.py` periodically restores missing Redis keys from the backups stored in the S3 bucket.

### 4. **Redis Cluster Healer**
   - The Redis Cluster Healer continuously monitors the cluster for issues, such as node failures.
   - It resolves problems by adding new pods, managing replicas, and ensuring overall stability.

---

## Deployment

### Prerequisites

- **Kubernetes**: RedisKage requires a Kubernetes environment with access to Redis pods and permissions to interact with the Kubernetes API.
- **S3 Storage**: An S3 bucket or compatible storage service must be set up for backups.

### Example Deployment Configuration

Set environment variables in your Kubernetes manifest:

```yaml
spec:
  containers:
  - env:
    - name: SCHEDULE_TIME
      value: '60'
```

### Logs

RedisKage provides real-time logs for all operations, including backups, uploads, and restores, enabling easy monitoring and troubleshooting.

### Sidecar Deployment

The Redis Cluster Healer is deployed as a sidecar container alongside RedisKage. While RedisKage handles backups and restores, the healer continuously ensures the health and stability of the Redis cluster.

