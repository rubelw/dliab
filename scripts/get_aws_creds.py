#!/usr/bin/env python3

import inspect
import os
import sys
import subprocess
import boto3
import inquirer
import requests
import time

from configparser import ConfigParser


def check_aws_credentials():
    aws_access_key_id = os.getenv("AWS_ACCESS_KEY_ID")
    aws_secret_access_key = os.getenv("AWS_SECRET_ACCESS_KEY")

    if aws_access_key_id and aws_secret_access_key:
        return True
    else:
        return False

def set_aws_environment_variables():
    # Path to the AWS credentials file
    credentials_file_path = os.path.expanduser("~/.aws/credentials")

    # Read the credentials file
    config = ConfigParser()
    config.read(credentials_file_path)

    # Get the access key ID and secret access key for the default profile
    aws_access_key_id = config.get("default", "aws_access_key_id", fallback=None)
    aws_secret_access_key = config.get("default", "aws_secret_access_key", fallback=None)

    if aws_access_key_id and aws_secret_access_key:
        os.environ["AWS_ACCESS_KEY_ID"] = aws_access_key_id
        os.environ["AWS_SECRET_ACCESS_KEY"] = aws_secret_access_key

def get_aws_region():
    # Path to the AWS configuration file
    config_file_path = os.path.expanduser("~/.aws/config")

    # Read the configuration file
    config = ConfigParser()
    config.read(config_file_path)

    # Get the region for the default profile
    aws_region = config.get("default", "region", fallback=None)

    if aws_region:
        return aws_region



def main():

    # Example usage
    region = get_aws_region()
    set_aws_environment_variables()
    check_aws_credentials()
    aws_access_key_id = os.getenv("AWS_ACCESS_KEY_ID")
    aws_secret_access_key = os.getenv("AWS_SECRET_ACCESS_KEY")

    print("export AWS_ACCESS_KEY_ID="+str(aws_access_key_id))
    print("export AWS_SECRET_ACCESS_KEY="+str(aws_secret_access_key))
    print("export AWS_DEFAULT_REGION="+str(region))


if __name__ == "__main__":
    # This block will only be executed if the script is run directly, not if it's imported as a module
    main()
