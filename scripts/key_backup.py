import logging
import os,sys
import json
import schedule
import time
from rediscluster import RedisCluster
from retry import retry
from redis.exceptions import ResponseError
import pyfiglet
import key_upload
import key_restore
import pyfiglet
from termcolor import colored


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
PATTERN_LIST = os.getenv('PATTERN', '').split(',')
BACKUP_DIR = os.getenv('BACKUP_DIR')

# Logging Configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger()

@retry(tries=3, delay=2, backoff=2)
def connect_to_redis():
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
    return rc

def display_header():
    ascii_art = pyfiglet.figlet_format("REDISKAGE", font="big", width=100)
    colored_art = colored(ascii_art, "cyan")
    border = "#" * 100
    bordered_art = f"{border}\n{colored_art}{border}"
    
    print(bordered_art)
    print("\n\t\t\t\tRepository: \033]8;;https://github.com/piyushgautamsingh/rediskage\ahttps://github.com/piyushgautamsingh/rediskage\033]8;;\a\n")

def backup_keys(source_cluster, pattern, backup_dir):
    cursor = "0"
    while cursor != 0:
        try:
            scan_result = source_cluster.scan(cursor=cursor, count=100, match=pattern)
            for node, (next_cursor, keys) in scan_result.items():
                cursor = next_cursor
                for key in keys:
                    try:
                        key_type = source_cluster.type(key)
                        if key_type != 'string':
                            logger.warning(f"Ignoring key '{key}' as its type is '{key_type}'")
                            continue
                        ttl = source_cluster.ttl(key)
                        logger.info(f"TTL: {ttl}, Key: {key}")
                        value = source_cluster.get(key)
                        if value is not None:
                            backup_file = os.path.join(backup_dir, f"{key}.json")
                            backup_data = {
                                "key": key,
                                "value": value
                            }
                            if os.path.exists(backup_file):
                                with open(backup_file, "r") as f:
                                    existing_data = json.load(f)
                                    if existing_data["value"] != value:
                                        with open(backup_file, "w") as new_f:
                                            json.dump(backup_data, new_f)
                                            logger.info(f"Key '{key}' content changed. Updated '{backup_file}'")
                                    else:
                                        logger.info(f"Key '{key}' content is unchanged. Skipping update.")
                            else:
                                with open(backup_file, "w") as f:
                                    json.dump(backup_data, f)
                                    logger.info(f"Key '{key}' backup file created with current content.")
                        else:
                            logger.warning(f"Key '{key}' has no value.")
                    except ResponseError as e:
                        logger.error(f"Error processing key {key}: {e}")
                    except Exception as e:
                        logger.error(f"Error processing key {key}: {e}")
        except Exception as e:
            logger.error(f"Error scanning keys: {e}")
            break

def get_keys_with_pattern():
    try:
        redis_cluster = connect_to_redis()
        for pattern in PATTERN_LIST:
            backup_keys(redis_cluster, pattern, BACKUP_DIR)
        key_upload.upload_to_s3(BACKUP_DIR)
        key_restore.put_keys_to_redis()
    except Exception as e:
        logger.error(f"Error: {e}")
        raise
    finally:
        if 'redis_cluster' in locals():
            redis_cluster.close()

if __name__ == "__main__":
    display_header()
    logging.info(colored("Rediskage possessing cluster... Shadow possession Jutsu!", 'yellow'))
    logging.info(colored("✓ Redis cluster possessed", 'green'))
    schedule.every(int(SCHEDULE_TIME)).seconds.do(get_keys_with_pattern)
    while True:
        schedule.run_pending()
        time.sleep(1)