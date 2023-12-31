#!/usr/bin/env python3

import yaml
import json
import sys
import subprocess
import tempfile
import os

def create_named_temporary_directory():
    # Create a named temporary directory
    temp_dir = tempfile.mkdtemp(prefix="my_temp_dir_")

    return temp_dir

def update_configmap(namespace, configmap_name, file_path):
    try:
        # Run kubectl apply command to update the ConfigMap with the contents of the local file
        result = subprocess.run(
            ["kubectl", "apply", "-n", namespace, "-f", str(file_path)+'/config.yaml'],
            check=True,
            capture_output=True,
            text=True,
        )

        # Check if the command was successful
        if result.returncode == 0:
            return True
        else:
            print(f"Error: {result.stderr}")
            return False

    except subprocess.CalledProcessError as e:
        print(f"Error: {e}")
        return False


def get_configmap(namespace, configmap_name,account_id,temp_directory ):
    try:

        # Run kubectl get configmap command
        result = subprocess.run(
            ["kubectl", "get", "configmap", configmap_name, "-n", namespace, "-o", "yaml"],
            check=True,
            capture_output=True,
            text=True,
        )

        # Check if the command was successful
        if result.returncode == 0:
            data = yaml.safe_load(result.stdout)
            print('data: ' + str(data))

            map_user_exists = -1
            for item in data['data']:
                if str(item) == 'mapUsers':
                    map_user_exists = 1

            if map_user_exists < 0:
                data['data']['mapUsers'] = '- userarn: arn:aws:iam::' + str(
                    account_id) + ':root\n  groups:\n  - system:masters\n'

                print('data is now: '+str(data))
                print('temp dir: '+str(temp_directory))
                with open(str(temp_directory)+'/config.yaml','w') as file:
                    yaml.dump(data,file)

                update_configmap(namespace, configmap_name, temp_directory)
            else:
                print('not updating')

        else:
            print(f"Error: {result.stderr}")
            return None

    except subprocess.CalledProcessError as e:
        print(f"Error: {e}")
        return None


def main():
    account_id = sys.argv[1]
    namespace = "kube-system"
    configmap_name = "aws-auth"

    temp_directory = create_named_temporary_directory()

    get_configmap(namespace, configmap_name, account_id, temp_directory)





if __name__ == "__main__":
    # This block will only be executed if the script is run directly, not if it's imported as a module
    main()

