import os
import json
import logging
import boto3
import sys
import schedule
from rediscluster import RedisCluster

# Logging Configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger()

# Get environment variables
SCHEDULE_TIME = os.getenv('SCHEDULE_TIME')
REDIS_NODES = os.getenv('REDIS_NODES')
REDIS_NODE_LIST = [
    {"host": host_port.split(":")[0], "port": int(host_port.split(":")[1])}
    for host_port in REDIS_NODES.split(",")
]
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD')
CA_CERT = os.getenv('CA_CERT')
TLS_CERT = os.getenv('TLS_CERT')
TLS_KEY = os.getenv('TLS_KEY')
PATTERN = os.getenv('PATTERN')
BACKUP_DIR = os.getenv('BACKUP_DIR')
S3_ENDPOINT_URL = os.getenv('S3_ENDPOINT_URL')
S3_BUCKET_NAME = os.getenv('S3_BUCKET_NAME')
S3_ACCESS_KEY_ID = os.getenv('S3_ACCESS_KEY_ID')
S3_SECRET_ACCESS_KEY = os.getenv('S3_SECRET_ACCESS_KEY')


def download_file_from_s3(s3_client, bucket_name, s3_key, local_path):
    try:
        s3_client.download_file(bucket_name, s3_key, local_path)
        logger.info(f"Downloaded file '{s3_key}' from S3 to '{local_path}'")
    except Exception as e:
        logger.error(f"Error downloading file '{s3_key}' from S3: {e}")

def push_keys_to_cluster(target_cluster, input_files):
    for input_file in input_files:
        try:
            with open(input_file, "r") as f:
                data = json.load(f)
                key = data.get("key")
                value = data.get("value")
                if key and value:
                    # Check if key already exists in Redis
                    if not target_cluster.exists(key):
                        target_cluster.set(key, value)
                        logger.info(f"Pushed key '{key}' to Redis cluster")
                    else:
                        logger.info(f"Key '{key}' already exists in Redis. Skipping.")
                else:
                    logger.error(f"Missing key or value in JSON file {input_file}")
        except json.JSONDecodeError as e:
            logger.error(f"Error decoding JSON in file {input_file}: {e}")
        except FileNotFoundError:
            logger.error(f"File not found: {input_file}")
        except Exception as e:
            logger.error(f"Error processing file {input_file}: {e}")

def put_keys_to_redis():
    try:
        logger.info("Attempting to connect to Redis...")
        rc = RedisCluster(
            startup_nodes=REDIS_NODE_LIST,
            username="default",
            password=REDIS_PASSWORD,
            ssl=True,
            ssl_certfile=TLS_CERT,
            ssl_keyfile=TLS_KEY,
            ssl_ca_certs=CA_CERT,
            decode_responses=True,
            skip_full_coverage_check=True,
            socket_keepalive=True
        )
        s3 = boto3.client('s3',
                          endpoint_url=S3_ENDPOINT_URL,
                          aws_access_key_id=S3_ACCESS_KEY_ID,
                          aws_secret_access_key=S3_SECRET_ACCESS_KEY)

        response = s3.list_objects_v2(Bucket=S3_BUCKET_NAME, Prefix='')
        if 'Contents' in response:
            for obj in response['Contents']:
                s3_key = obj['Key']
                local_path = os.path.join(BACKUP_DIR, os.path.basename(s3_key))
                download_file_from_s3(s3, S3_BUCKET_NAME, s3_key, local_path)
                
        input_files = [os.path.join(BACKUP_DIR, file) for file in os.listdir(BACKUP_DIR) if file.endswith('.json')]
        if input_files:
            push_keys_to_cluster(rc, input_files)
        else:
            logger.warning("No .json files found in backup directory.")

    except Exception as e:
        logger.error(f"Error in main execution: {e}")
    finally:
        if 'rc' in locals():
            rc.close()