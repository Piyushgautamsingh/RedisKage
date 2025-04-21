import boto3
import os
import logging
import hashlib
import sys

BACKUP_DIR = os.getenv('BACKUP_DIR')
S3_ENDPOINT_URL = os.getenv('S3_ENDPOINT_URL')
S3_BUCKET_NAME = os.getenv('S3_BUCKET_NAME')
S3_ACCESS_KEY_ID = os.getenv('S3_ACCESS_KEY_ID')
S3_SECRET_ACCESS_KEY = os.getenv('S3_SECRET_ACCESS_KEY')

# Logging Configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger()

def calculate_file_hash(file_path):
    """Calculate the MD5 hash of a file."""
    md5 = hashlib.md5()
    with open(file_path, 'rb') as f:
        while chunk := f.read(8192):
            md5.update(chunk)
    return md5.hexdigest()

def upload_to_s3(backup_dir):
    try:
        s3 = boto3.client('s3',
                          endpoint_url=S3_ENDPOINT_URL,
                          aws_access_key_id=S3_ACCESS_KEY_ID,
                          aws_secret_access_key=S3_SECRET_ACCESS_KEY)
        for filename in os.listdir(backup_dir):
            file_path = os.path.join(backup_dir, filename)
            if os.path.isfile(file_path):
                try:
                    # Check if the file already exists in S3
                    response = s3.head_object(Bucket=S3_BUCKET_NAME, Key=filename)
                    s3_etag = response['ETag'].strip('"')
                    local_file_hash = calculate_file_hash(file_path)
                    # Upload only if the file has changed
                    if s3_etag != local_file_hash:
                        s3.upload_file(file_path, S3_BUCKET_NAME, filename)
                        logger.info(f"Updated file '{file_path}' in '{S3_BUCKET_NAME}/{filename}'")
                    else:
                        logger.info("No changes detected. File not uploaded.")
                except s3.exceptions.ClientError as e:
                    if e.response['Error']['Code'] == '404':
                        s3.upload_file(file_path, S3_BUCKET_NAME, filename)
                        logger.info(f"Uploaded new file '{file_path}' to '{S3_BUCKET_NAME}/{filename}'")
                    else:
                        logger.error(f"Error checking S3 for file '{file_path}': {e}")
    except Exception as e:
        logger.error(f"Error uploading files from '{backup_dir}' to '{S3_BUCKET_NAME}': {e}")