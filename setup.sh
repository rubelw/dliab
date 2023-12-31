#!/usr/bin/env bash


# GLOBAL VARIABLES
CURRENT_DIR="${PWD}"
DOCKER_GROUP="docker"
SLEEP=0
EKS_VERSION="1.28"
CLUSTER_NAME="dliab-eks-cluster"

while getopts ":d" opt; do
  case $opt in
    d)
      delete=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ "$delete" ]; then
  echo "Delete mode is enabled."
  eksctl delete cluster --name "${CLUSTER_NAME}"
  exit 0
fi


print_with_header() {
    local header_length=40
    local header_char="#"

    # Check if the first argument is provided
    if [ -z "$1" ]; then
        echo "Usage: print_with_header <string>"
        return 1
    fi

    # Print header
    printf "\n\n%${header_length}s\n" | tr ' ' "$header_char"

    # Print the provided string
    echo "$1 - ${LINENO}"

    # Print footer
    printf "%${header_length}s\n" | tr ' ' "$header_char"
}


check_directory_in_path() {
    # Check if the first argument is provided
    if [ -z "$1" ]; then
        echo "Usage: check_directory_in_path <directory_path>"
        return 1
    fi

    directory_path="$1"

    # Check if the directory is in the PATH
    if [[ ":$PATH:" == *":$directory_path:"* ]]; then
        echo "Directory '$directory_path' is in the PATH."
        return 0
    else
        echo "Directory '$directory_path' is not in the PATH."
        return 1
    fi
}

get_aws_account_id() {
    # Use the AWS CLI to get account information
    aws sts get-caller-identity --output json
    account_info=$(aws sts get-caller-identity --output json)

    # Extract the account ID using jq (JSON processor)
    account_id=$(echo "$account_info" | jq -r '.Account')

    echo "AWS Account ID: $account_id"
    AWS_ACCOUNT_ID="${account_id}"
}

get_default_ssh_key_path() {
    local default_ssh_key_paths=("~/.ssh/id_rsa" "~/.ssh/id_dsa")

    for key_path in "${default_ssh_key_paths[@]}"; do
        expanded_path=$(eval echo "$key_path")
        if [ -f "$expanded_path" ]; then
            echo "Default SSH key path: $expanded_path"
            export DEFAULT_SSH_KEY_PATH="$expanded_path"
            return 0
        fi
    done

    echo "Default SSH key not found."
    return 1
}

prompt_user() {
    local prompt_message="$1"
    local user_input

    read -p "$prompt_message (yes/no): " user_input

    case "$user_input" in
        [yY]|[yY][eE][sS])
            echo "User entered 'yes'."
            return 0
            ;;
        [nN]|[nN][oO])
            echo "User entered 'no'."
            return 1
            ;;
        *)
            echo "Invalid input. Please enter 'yes' or 'no'."
            return 2
            ;;
    esac
}

print_with_header "Getting default ssh key path for ${USER}"
get_default_ssh_key_path
echo "Default ssh key path is:  ${DEFAULT_SSH_KEY_PATH}"
sleep $SLEEP  # Sleeping so user can see info on screen

prompt_user "Do you have an EC2 keypair with the same name as your default ssh key?"
result=$?

if [ $result -eq 0 ]; then
    keypair=$(basename "${DEFAULT_SSH_KEY_PATH}")
    export KEYPAIR_NAME="${keypair}"
    echo "Keypair name set to ${KEYPAIR_NAME} - Continuing..."
elif [ $result -eq 1 ]; then
    echo "Please create an EC2 keypair with the same name as your defailt ssh key and try running again."
    echo "Exiting."
    exit 1
else
    echo "Invalid input. Exiting."
    exit 1
fi



print_with_header "Killing all port forwarding"
pkill -f "kubectl port-forward"
sleep $SLEEP  # Sleeping so user can see info on screen


print_with_header "Checking if a venv subdirectory exists"
VENV_DIR="./venv"  # Replace with the desired path for the virtual environment

# Check if the virtual environment exists
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."

    # Create the virtual environment using Python 3.9
    python3 -m venv "$VENV_DIR"

    echo "Virtual environment created at '$VENV_DIR'."
    source "$VENV_DIR/bin/activate"

else
    echo "Virtual environment already exists at '$VENV_DIR'."
    source "$VENV_DIR/bin/activate"

fi
sleep $SLEEP  # Sleeping so user can see info on screen



print_with_header "Installing requirements.txt to virtual environment"
pip install -r requirements.txt
print_with_header "Done installing requirements to virtual environment"
sleep $SLEEP  # Sleeping so user can see info on screen


print_with_header "Are we using the python version in the virtual env?"
which python
sleep $SLEEP  # Sleeping so user can see info on screen


print_with_header "Getting and setting AWS creds from ~/.aws default profile"
# Call the Python script and capture its output
python_output=$(python scripts/get_aws_creds.py)

# Execute the exported commands
eval "$python_output"

# Verify that the environmental variables are set
echo "AWS_DEFAULT_REGION: $AWS_DEFAULT_REGION"
sleep $SLEEP  # Sleeping so user can see info on screen



print_with_header "Get AWS account id"
get_aws_account_id
echo "AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
sleep $SLEEP  # Sleeping so user can see info on screen



print_with_header "Checking ${HOME}/bin directory is installed"
BIN_DIR="${HOME}/bin"  # Replace with the desired path for the virtual environment

# Check if the virtual environment exists
if [ ! -d "$BIN_DIR" ]; then
  mkdir -p $BIN_DIR
fi
sleep $SLEEP  # Sleeping so user can see info on screen


print_with_header "Checking if ${HOME}/bin in PATH"

check_directory_in_path "${HOME}/bin"
if [ $? -eq 0 ]; then
    echo "${HOME}/bin in PATH.- ${LINENO}"
else
    echo "${HOME}/bin not in PATH. - ${LINENO}"
    export PATH=$PATH:$HOME/bin
fi



print_with_header "Checking if kubectl installed in ${HOME}/bin directory"
if [ -f "${HOME}/bin/kubectl" ]; then
    echo "kubectl exists in directory"
else
    kubectl_version="1.28.3"
    cd "${HOME}/bin"
    curl -O "https://s3.us-west-2.amazonaws.com/amazon-eks/${kubectl_version}/2023-11-14/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
fi
cd "${CURRENT_DIR}"


print_with_header "Checking if helm installed in ${HOME}/bin directory"
if [ -f "${HOME}/bin/helm" ]; then
    echo "helm exists in directory"
else
    cd "${HOME}/bin"
    helm_version="3.13.0"
    curl -LO "https://get.helm.sh/helm-v${helm_version}-linux-amd64.tar.gz"
    tar -zxvf helm-v${helm_version}-linux-amd64.tar.gz
    mv linux-amd64/helm "${HOME}/bin/"
    rm -rf linux-amd64
    rm "helm-v${helm_version}-linux-amd64.tar.gz"
    chmod +x helm
fi
cd "${CURRENT_DIR}"


print_with_header "Checking if aksctl is installed in ${HOME}/bin directory"
if [ -f "${HOME}/bin/eksctl" ]; then
    echo "eksctl exists in directory"
else
    echo "Installing eksctl..."
    cd "${HOME}/bin"
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    # (Optional) Verify checksum
    curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
    tar -xzf eksctl_$PLATFORM.tar.gz -C "${HOME}/bin" && rm eksctl_$PLATFORM.tar.gz

fi
cd "${CURRENT_DIR}"



print_with_header "Checking if git is installed"
if command -v git &> /dev/null ; then
    echo "Git is installed"
else
    echo "Git is not installed"
    sudo yum install git -y
fi


print_with_header "Check if charts directory exists"
if [ ! -d "${CURRENT_DIR}/charts" ]; then
  mkdir -p "${CURRENT_DIR}/charts"
fi
sleep $SLEEP  # Sleeping so user can see info on screen

print_with_header "Check if dockerfiles directory exists"
if [ ! -d "${CURRENT_DIR}/dockerfiles" ]; then
  mkdir -p "${CURRENT_DIR}/dockerfiles"
fi
sleep $SLEEP  # Sleeping so user can see info on screen



print_with_header "Check if docker is installed"
if command -v docker &> /dev/null
then
    echo "Docker is installed.- ${LINENO}"
else
    echo "Docker is not installed.- ${LINENO}"
    # Update the system - 'sudo yum update':
    sudo yum update

    #Install the required dependencies:
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2

    # Add the Docker repository:
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    #Install Docker:
    sudo yum install docker-ce docker-ce-cli containerd.io
fi


print_with_header "Check if ${USER} is a member of the docker group"
groupname="docker"
username="${USER}"
#Check Docker Group Membership:
if id -nG "$username" | grep -qw "$groupname"; then
    echo "User $username is a member of group $groupname."
else
    echo "User $username is not a member of group $groupname."
    echo "Adding ${USER} to docker group"
    sudo usermod -aG docker $USER
fi


print_with_header "Check if docker is active and running"
DOCKER_STATUS=$(systemctl is-active docker)

if [ "$DOCKER_STATUS" = "active" ]; then
    echo "Docker is already running.- ${LINENO}"
else
    echo "Docker is not running. Starting Docker...- ${LINENO}"
    sudo systemctl start docker
    echo "Docker is now running.- ${LINENO}"
fi


##########################################
# Dowload all the needed helm charts
##########################################

print_with_header "Install airflow charts"
directory="airflow"

if [ ! -d "${CURRENT_DIR}/charts/${directory}" ]; then
  mkdir -p "${CURRENT_DIR}/charts/${directory}"
  git clone https://github.com/airflow-helm/charts.git "${CURRENT_DIR}/charts/${directory}"
  cd "${CURRENT_DIR}/charts/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi


print_with_header "Install trino charts"
directory="trino"

if [ ! -d "${CURRENT_DIR}/charts/${directory}" ]; then
  mkdir -p "${CURRENT_DIR}/charts/${directory}"
  git clone https://github.com/trinodb/charts.git "${CURRENT_DIR}/charts/${directory}"
  cd "${CURRENT_DIR}/charts/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi


print_with_header "Install superset charts"
directory="superset"

if [ ! -d "${CURRENT_DIR}/charts/${directory}" ]; then
  mkdir -p "${CURRENT_DIR}/charts/${directory}"
  git clone https://github.com/apache/superset.git "${CURRENT_DIR}/charts/${directory}"
  cd "${CURRENT_DIR}/charts/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi



print_with_header "Install openldap charts"
directory="openldap"

if [ ! -d "${CURRENT_DIR}/charts/${directory}" ]; then
  mkdir -p "${CURRENT_DIR}/charts/${directory}"
  git clone https://github.com/jp-gouin/helm-openldap.git  "${CURRENT_DIR}/charts/${directory}"
  cd "${CURRENT_DIR}/charts/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi


print_with_header "Install bitnami charts"
directory="bitnami-charts"

if [ ! -d "${CURRENT_DIR}/charts/${directory}" ]; then
  print_with_header "This will take a few minutes"
  mkdir -p "${CURRENT_DIR}/charts/${directory}"
  git clone https://github.com/bitnami/charts.git "${CURRENT_DIR}/charts/${directory}"
  cd "${CURRENT_DIR}/charts/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi


print_with_header "Installing openmetadata charts"
directory="openmetadata"

if [ ! -d "${CURRENT_DIR}/charts/${directory}" ]; then
  mkdir -p "${CURRENT_DIR}/charts/${directory}"
  git clone https://github.com/open-metadata/openmetadata-helm-charts.git "${CURRENT_DIR}/charts/${directory}"
  cd "${CURRENT_DIR}/charts/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi


# Specify the folder containing the .tgz files
folder="${CURRENT_DIR}/charts/${directory}/charts/deps/charts"
echo "folder for dep charts: ${folder} - ${LINENO}"

# Check if the folder exists
if [ ! -d "${CURRENT_DIR}/charts/${directory}/charts/deps/charts/airflow" ]; then

  echo "Adding opensearch directory- ${LINENO}"
  helm repo add opensearch https://opensearch-project.github.io/helm-charts/
  helm dependency build "charts/${directory}/charts/deps/"

  # Change to the specified folder
  cd "$folder" || exit

  # Loop through all .tgz files and unzip them
  for file in *.tgz; do
      echo "Extracting $file..."
      tar -xzf "$file"
      rm $file
  done

  echo "Unzipping complete. - ${LINENO}"

  file="${CURRENT_DIR}/charts/${directory}/charts/deps/Chart.yaml"
  search_string="Add Dependencies of other charts"

  # Check if the file exists
  if [ -f "$file" ]; then
      # Use grep to find the line containing the search string
      line=$(grep -n "$search_string" "$file")

      if [ -n "$line" ]; then
          echo "Line containing '$search_string':- ${LINENO}"
          echo "$line"
          # Split the string into an array
          # Save the current IFS value
          IFS_OLD=$IFS

          # Set IFS to colon
          IFS=":"
          read -ra parts <<< "$line"
          line_number="${parts[0]}"
          echo "line_number ${line_number} - ${LINENO}"

          # Check if the file exists
          # Use sed to delete everything after the specified line
          #sed -i "${line_number},$ d" "$file"  # Delete lines
          sed -i "${line_number},$ s/^/#/" "$file"  # Comment out lines

          echo "Content after line $line_number deleted."
          rm "${CURRENT_DIR}/charts/${directory}/charts/deps/Chart.lock"
          # Restore IFS to its original value
          IFS=$IFS_OLD
      else
          echo "Search string '$search_string' not found in file.- ${LINENO}"
      fi
  else
      echo "Error: File '$file' not found.- ${LINENO}"
  fi

else
    echo "Folder '$folder' already exists.- ${LINENO}"
fi


####################################
# Download all the dockerfiles
####################################
print_with_header "Clone binami containers"
directory="bitnami"

if [ ! -d "${CURRENT_DIR}/dockerfiles/${directory}" ]; then
  echo "${directory} does not exist"
  mkdir -p "${CURRENT_DIR}/dockerfiles/${directory}"
  git clone https://github.com/bitnami/containers.git "${CURRENT_DIR}/dockerfiles/${directory}"
  cd "dockerfiles/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi


print_with_header "Clone openldap dockerfiles"
directory="openldap"

if [ ! -d "${CURRENT_DIR}/dockerfiles/${directory}" ]; then
  echo "${directory} does not exist"
  mkdir -p "${CURRENT_DIR}/dockerfiles/${directory}"
  git clone https://github.com/samisalkosuo/openldap-docker.git "${CURRENT_DIR}/dockerfiles/${directory}"
  cd "dockerfiles/${directory}"
  rm -rf .git
  cd "${CURRENT_DIR}"
else
  echo "Directory '$directory' already exists. Skipping git clone.- ${LINENO}"
fi



######################################
# Build dockerfiles
#####################################

# Set the name of the ECR repository to check
ecr_repository_name="dliab-opensearch"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '$AWS_DEFAULT_REGION'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '$AWS_DEFAULT_REGION'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "$AWS_DEFAULT_REGION"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '$AWS_DEFAULT_REGION'."
fi
cd "${CURRENT_DIR}"


# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/opensearch"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/opensearch/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM "bitnami/opensearch:latest"

EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    # Build Docker image
    cd "dockerfiles/opensearch" && echo "cd to dockerfiles/opensearch" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"

fi





ecr_repository_name="dliab-openldap"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '$aws_region'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '${AWS_DEFAULT_REGION}'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '${AWS_DEFAULT_REGION}'."
fi
cd "${CURRENT_DIR}"

# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/openldap"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi


    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    echo "Docker image \"${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}\" does not exist locally."
    cd "dockerfiles/openldap" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . --no-cache && cd "${CURRENT_DIR}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"
fi

cd "${CURRENT_DIR}"




# Set the name of the ECR repository to check
ecr_repository_name="dliab-postgres"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '$AWS_DEFAULT_REGION'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '$AWS_DEFAULT_REGION'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "$AWS_DEFAULT_REGION"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '$AWS_DEFAULT_REGION'."
fi
cd "${CURRENT_DIR}"


# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/postgres"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/postgres/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM "bitnami/postgresql:latest"

EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    # Build Docker image
    cd "dockerfiles/postgres" && echo "cd to dockerfiles/postgres" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"

fi





# Set the name of the ECR repository to check
ecr_repository_name="dliab-redis-exporter"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '$AWS_DEFAULT_REGION'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '$AWS_DEFAULT_REGION'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "$AWS_DEFAULT_REGION"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '$AWS_DEFAULT_REGION'."
fi
cd "${CURRENT_DIR}"


# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/redis-exporter"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/redis-exporter/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM "bitnami/redis-exporter:1.55.0-debian-11-r2"

EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    # Build Docker image
    cd "dockerfiles/redis-exporter" && echo "cd to dockerfiles/redis-exporter" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"

fi







# Set the name of the ECR repository to check
ecr_repository_name="dliab-redis-sentinel"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '$AWS_DEFAULT_REGION'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '$AWS_DEFAULT_REGION'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "$AWS_DEFAULT_REGION"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '$AWS_DEFAULT_REGION'."
fi
cd "${CURRENT_DIR}"


# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/redis-sentinel"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/redis-sentinel/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM bitnami/redis-sentinel:7.2.3-debian-11-r1

EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    # Build Docker image
    cd "dockerfiles/redis-sentinel" && echo "cd to dockerfiles/redis-sentinel" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"

fi





# Set the name of the ECR repository to check
ecr_repository_name="dliab-redis"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '$AWS_DEFAULT_REGION'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '$AWS_DEFAULT_REGION'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "$AWS_DEFAULT_REGION"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '$AWS_DEFAULT_REGION'."
fi
cd "${CURRENT_DIR}"


# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/redis"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/redis/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM bitnami/redis:latest

EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    # Build Docker image
    cd "dockerfiles/redis" && echo "cd to dockerfiles/redis" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}"| docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"

fi









# Set the name of the ECR repository to check
ecr_repository_name="dliab-airflow"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "$AWS_DEFAULT_REGION" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '$AWS_DEFAULT_REGION'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '$AWS_DEFAULT_REGION'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "$AWS_DEFAULT_REGION"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '$AWS_DEFAULT_REGION'."
fi
cd "${CURRENT_DIR}"


# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/airflow"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/airflow/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM apache/airflow:2.6.3-python3.9

EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    # Build Docker image
    cd "dockerfiles/airflow" && echo "cd to dockerfiles/airflow" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"

fi




ecr_repository_name="dliab-openssl"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '${AWS_DEFAULT_REGION}."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '${AWS_DEFAULT_REGION}'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '${AWS_DEFAULT_REGION}'."
fi
cd "${CURRENT_DIR}"

# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/openssl"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/openssl/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM alpine/openssl:latest


EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    aws ecr get-login-password --region "${AWS_ACCOUNT_ID}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    echo "Docker image "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" does not exist locally."
    cd "dockerfiles/openssl" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"
fi

cd "${CURRENT_DIR}"




# Set the name of the ECR repository to check

ecr_repository_name="dliab-busybox"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '${AWS_DEFAULT_REGION}'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '${AWS_DEFAULT_REGION}'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '${AWS_DEFAULT_REGION}'."
fi
cd "${CURRENT_DIR}"

# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/busybox"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/busybox/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM busybox:latest


EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    echo "Docker image "409396177599.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" does not exist locally."
    cd "dockerfiles/busybox" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"
fi

cd "${CURRENT_DIR}"






# Set the name of the ECR repository to check

ecr_repository_name="dliab-self-service-password"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '${AWS_DEFAULT_REGION}'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '${AWS_DEFAULT_REGION}'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '${AWS_DEFAULT_REGION}'."
fi
cd "${CURRENT_DIR}"

# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/self-service-password"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/self-service-password/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM tiredofit/self-service-password:5.2.3


EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    echo "Docker image "409396177599.dkr.ecr.us-east-1.amazonaws.com/${ecr_repository_name}" does not exist locally."
    cd "dockerfiles/self-service-password" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"
fi

cd "${CURRENT_DIR}"







# Set the name of the ECR repository to check

ecr_repository_name="dliab-phpldapadmin"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '${AWS_DEFAULT_REGION}'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '${AWS_DEFAULT_REGION}'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '${AWS_DEFAULT_REGION}'."
fi
cd "${CURRENT_DIR}"

# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/phpldapadmin"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/phpldapadmin/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM osixia/phpldapadmin:0.9.0


EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    echo "Docker image "409396177599.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" does not exist locally."
    cd "dockerfiles/phpldapadmin" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"
fi

cd "${CURRENT_DIR}"




ecr_repository_name="dliab-openmetadata-server"

# Check if the ECR repository exists
if aws ecr describe-repositories --repository-names "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}" &> /dev/null; then
    echo "ECR repository '$ecr_repository_name' exists in region '${AWS_DEFAULT_REGION}'."
else
    echo "ECR repository '$ecr_repository_name' does not exist in region '${AWS_DEFAULT_REGION}'."
    # Create the ECR repository
    aws ecr create-repository --repository-name "$ecr_repository_name" --region "${AWS_DEFAULT_REGION}"

    # Output success message
    echo "ECR repository '$ecr_repository_name' created in region '${AWS_DEFAULT_REGION}'."
fi
cd "${CURRENT_DIR}"

# Check if Docker image with the specified tag exists
if docker images "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}" | grep -q "latest"; then
    echo "Docker image "${ecr_repository_name}:latest" exists locally."
else

    directory="${CURRENT_DIR}/dockerfiles/openmetadata-server"

    if [ -d "$directory" ]; then
        echo "Directory exists."
    else
        echo "Directory does not exist."
        mkdir -p $directory
    fi

    filename="${CURRENT_DIR}/dockerfiles/openmetadata-server/Dockerfile"

    if [ ! -e "$filename" ]; then
        # Create the file
        cat > "$filename" <<EOF
FROM openmetadata/server:latest


EOF

        echo "File created: $filename"
    else
        echo "File already exists: $filename"
    fi

    aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}"

    echo "Docker image "409396177599.dkr.ecr.us-east-1.amazonaws.com/${ecr_repository_name}" does not exist locally."
    cd "dockerfiles/openmetadata-server" && docker build -t "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest" . && cd "${CURRENT_DIR}"

    # Push Docker image to ECR
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/${ecr_repository_name}:latest"
fi

cd "${CURRENT_DIR}"


################################################
#  Create EKS Cluster
################################################
print_with_header "# Create AWS EKS cluster"
# Get a list of AWS EKS clusters
clusters=$(aws eks list-clusters --query 'clusters' --output json | jq -r '.| map(.) | .[]')
IFS=$'\n' read -d '' -ra cluster_list <<< "$clusters"


# Target name to check
target_name="${CLUSTER_NAME}"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${cluster_list[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."



  # AWS EKS Cluster Configuration
  region="${AWS_DEFAULT_REGION}"
  node_group_name="eks-node-group"
  node_group_min_size=1
  node_group_max_size=4
  node_group_desired_capacity=4
  node_instance_type="t3.medium"
  key_pair_name="${KEYPAIR_NAME}"  # Replace with your EC2 Key Pair name

  # Create EKS Cluster
  echo "Creating EKS Cluster..."
  eksctl create cluster \
    --name "${CLUSTER_NAME}" \
    --nodegroup-name "$node_group_name" \
    --nodes "$node_group_desired_capacity" \
    --nodes-min "$node_group_min_size" \
    --nodes-max "$node_group_max_size" \
    --node-type "$node_instance_type" \
    --node-volume-size 50 \
    --ssh-access \
    --ssh-public-key "$key_pair_name" \
    --version "${EKS_VERSION}" \
    --managed \
    --asg-access

  aws eks update-kubeconfig --region "${AWS_DEFAULT_REGION}" --name "${CLUSTER_NAME}"




  # approve persistent volumes
  eksctl utils associate-iam-oidc-provider --region="${AWS_DEFAULT_REGION}" --cluster="${CLUSTER_NAME}" --approve


  # Create EBS Driver
  eksctl create iamserviceaccount \
    --region "${AWS_DEFAULT_REGION}" \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster "${CLUSTER_NAME}" \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve \
    --role-only \
    --role-name AmazonEKS_EBS_CSI_DriverRole

  # Create driver role
  eksctl create addon --name aws-ebs-csi-driver --cluster "${CLUSTER_NAME}" --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole --force

  # Add pod addon
  eksctl create addon --cluster "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}" --name eks-pod-identity-agent

  # Add efs addon


  role_name=AmazonEKS_EFS_CSI_DriverRole

  eksctl create iamserviceaccount \
    --name efs-csi-controller-sa \
    --namespace kube-system \
    --cluster "${CLUSTER_NAME}" \
    --role-name $role_name \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy \
    --approve


  TRUST_POLICY=$(aws iam get-role --role-name $role_name --query 'Role.AssumeRolePolicyDocument' | \
    sed -e 's/efs-csi-controller-sa/efs-csi-*/' -e 's/StringEquals/StringLike/')

  aws iam update-assume-role-policy --role-name $role_name --policy-document "$TRUST_POLICY"

  eksctl create addon --cluster "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}" --name aws-efs-csi-driver

  aws iam create-policy --policy-name=eks-admin-policy --policy-document='{"Version": "2012-10-17", "Statement": {"Sid": "AdminPrivs", "Effect": "Allow", "Action": ["eks:*" ], "Resource": "*" }}'

  # Delete cluster
  #eksctl delete cluster --name my-eks-cluster

  echo "#############################"
  echo " Update config map"
  echo "#############################"
  python scripts/modify_configmap.py "${AWS_ACCOUNT_ID}"


fi




print_with_header "# Check if charts installed"

# Run helm list and store the output in an array
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_DEFAULT_REGION}"

read -ra helm_data <<< "$(helm list --output=json --short)"
echo "helm list: ${helm_data}"
helm_data=${helm_data//\[}
helm_data=${helm_data//\]}
helm_data=${helm_data//\"}
helm_data=${helm_data//,/ }


echo "helm_data: ${helm_data}"
# Print the array elements
IFS=' ' read -r -a helm_array <<< "$helm_data"

echo "Helm releases: ${helm_array[@]}"

# Iterate over each item in the array
for item in "${helm_array[@]}"; do
    echo "Processing item: $item"


done

#############################
# Install secrets
##############################


# Target name to check
target_name="dliab-secrets-chart"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."
  helm install dliab-secrets-chart charts/dliab-secrets \
  --values charts/dliab-secrets/values.yaml
fi



###############################
# Install Openldap chart
###############################


# Target name to check
target_name="openldap-chart"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."
  helm install openldap-chart charts/openldap/ \
  --set global.imageRegistry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --set global.adminPassword=password \
  --set global.configPassword=password \
  --set image.repository=dliab-openldap \
  --set image.tag=latest \
  --set phpldapadmin.env.PHPLDAPADMIN_LDAP_CLIENT_TLS_REQCERT=never \
  --set initTLSSecret.image.registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --set initTLSSecret.image.repository=dliab-openssl \
  --set initTLSSecret.image.tag=latest \
  --set ltb-passwd.image.repository=dliab-self-service-password \
  --set ltb-passwd.image.tag=latest \
  --set phpldapadmin.image.repository=dliab-phpldapadmin \
  --set phpldapadmin.image.tag=latest \
  --set persistence.enabled=false \
  --set replication.enabled=false \
  --set env.LDAP_ENABLE_MEMBERS="yes" \
  --values charts/openldap/values.yaml

  #OpenLDAP-Stack-HA has been installed. You can access the server from within the k8s cluster using:
  #  openldap-chart.default.svc.cluster.local:
  #  Or
  #  openldap-chart.default.svc.cluster.local:
  #
  #You can access the LDAP adminPassword and configPassword using:
  #
  #  kubectl get secret --namespace default openldap-chart -o jsonpath="{.data.LDAP_ADMIN_PASSWORD}" | base64 --decode; echo
  #  kubectl get secret --namespace default openldap-chart -o jsonpath="{.data.LDAP_CONFIG_ADMIN_PASSWORD}" | base64 --decode; echo

  #You can access the LDAP service, from within the cluster (or with kubectl port-forward) with a command like (replace password and domain):
  #  ldapsearch -x -H ldap://openldap-chart.default.svc.cluster.local: -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w $LDAP_ADMIN_PASSWORD

  #You can access PHPLdapAdmin, using
  #     - http://phpldapadmin.example

  #You can access Self Service Password, using
  #     - http://ssl-ldap2.example

  #Test server health using Helm test:
  #  helm test openldap-chart
  #
  # port forward phpadmin
  # kubectl port-forward services/openldap-chart-phpldapadmin 8081:80 &

fi


#############################
# Install postgres database
#############################


# Target name to check
target_name="postgres-chart"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."
  helm dependencies build charts/bitnami-charts/bitnami/postgresql/


  helm install postgres-chart \
  --set global.imageRegistry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --set image.registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --set image.repository=dliab-postgres \
  --set image.tag=latest \
  charts/bitnami-charts/bitnami/postgresql/ --values charts/bitnami-charts/bitnami/postgresql/values.yaml

  #PostgreSQL can be accessed via port 5432 on the following DNS names from within your cluster:
  #    postgres-chart-postgresql.default.svc.cluster.local - Read/Write connection
  #
  #To get the password for "postgres" run:
  #
  #    export POSTGRES_ADMIN_PASSWORD=$(kubectl get secret --namespace default postgres-chart-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
  #
  #To get the password for "bn_airflow" run:
  #
  #    export POSTGRES_PASSWORD=$(kubectl get secret --namespace default postgres-chart-postgresql -o jsonpath="{.data.password}" | base64 -d)
  #
  #To connect to your database run the following command:
  #
  #    kubectl run postgres-chart-postgresql-client --rm --tty -i --restart='Never' --namespace default --image docker.io/bitnami/postgresql:16.1.0-debian-11-r16 --env="PGPASSWORD=$POSTGRES_PASSWORD" \
  #      --command -- psql --host postgres-chart-postgresql -U bn_airflow -d bitnami_airflow -p 5432
  #
  #    > NOTE: If you access the container using bash, make sure that you execute "/opt/bitnami/scripts/postgresql/entrypoint.sh /bin/bash" in order to avoid the error "psql: local user with ID 1001} does not exist"
  #
  #To connect to your database from outside the cluster execute the following commands:
  #
  #    kubectl port-forward --namespace default svc/postgres-chart-postgresql 5432:5432 &
  #    PGPASSWORD="$POSTGRES_PASSWORD" psql --host 127.0.0.1 -U bn_airflow -d bitnami_airflow -p 5432

  echo "Sleeping for 120 seconds"
  sleep 120

  # Poll the pod until it becomes ready
  echo "Waiting for the pod to become ready..."

  namespace="default"
  pod_name="postgres-chart-postgresql-0"

  is_pod_ready() {
      kubectl get pod "$pod_name" -n "$namespace" --output=jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q "True"
  }

  while ! is_pod_ready; do
      sleep 5
  done

  echo "Pod is now ready."

  echo "port forwarding"
  kubectl port-forward service/postgres-chart-postgresql 5432:5432 &
  sleep 3
  POSTGRES_ADMIN_PASSWORD=$(kubectl get secret --namespace default postgres-chart-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
  PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" psql --host 127.0.0.1 -U postgres -d postgres -p 5432 -a -f "${CURRENT_DIR}/scripts/postgres_setup.sql
  echo "Done configuring airflow database"


fi


########################
# Install Redis chart
########################



# Target name to check
target_name="redis-chart"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."
  helm dependencies build charts/bitnami-charts/bitnami/redis/

  helm install redis-chart charts/bitnami-charts/bitnami/redis/ \
  --set auth.password=redis \
  --set global.imageRegistry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --set image.registry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --set image.repository=dliab-redis \
  --set image.tag=latest \
  --values charts/bitnami-charts/bitnami/redis/values.yaml

  #** Please be patient while the chart is being deployed **
  #
  #Redis&reg; can be accessed on the following DNS names from within your cluster:
  #
  #    redis-chart-master.default.svc.cluster.local for read/write operations (port 6379)
  #    redis-chart-replicas.default.svc.cluster.local for read-only operations (port 6379)

  #To get your password run:
  #
  #    export REDIS_PASSWORD=$(kubectl get secret --namespace default redis-chart -o jsonpath="{.data.redis-password}" | base64 -d)
  #
  #To connect to your Redis&reg; server:
  #
  #1. Run a Redis&reg; pod that you can use as a client:
  #
  #   kubectl run --namespace default redis-client --restart='Never'  --env REDIS_PASSWORD=$REDIS_PASSWORD  --image docker.io/bitnami/redis:7.2.3-debian-11-r2 --command -- sleep infinity
  #
  #   Use the following command to attach to the pod:
  #
  #   kubectl exec --tty -i redis-client \
  #   --namespace default -- bash
  #
  #2. Connect using the Redis&reg; CLI:
  #   REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h redis-chart-master
  #   REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h redis-chart-replicas
  #
  #To connect to your database from outside the cluster execute the following commands:
  #
  #    kubectl port-forward --namespace default svc/redis-chart-master 6379:6379 &
  #    REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli -h 127.0.0.1 -p 6379


fi


################################
# Install airflow chart
################################


# Target name to check
target_name="airflow-chart"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else


  # create database airflow_db;
  # create user airflow_user with password 'airflow_pass';
  # grant all privileges on database airflow_db to airflow_user;
  # grant all on schema public to airflow_user;
  # ALTER DATABASE airflow_db OWNER TO airflow_user;


  echo "$target_name is not in the array."
  helm dependencies build charts/airflow/charts/airflow

  # We need to create an extra-values.yaml file because we can't get the parameters passed-through with --set command
  cat<<EOF > "${CURRENT_DIR}/charts/airflow/charts/airflow/extra-values.yaml"
web:
  ########################################
  ## FILE | webserver_config.py
  ########################################
  ##
  webserverConfig:
    ## if the `webserver_config.py` file is mounted
    ## - set to false if you wish to mount your own `webserver_config.py` file
    ##
    enabled: true

    ## the full content of the `webserver_config.py` file (as a string)
    ## - docs for Flask-AppBuilder security configs:
    ##   https://flask-appbuilder.readthedocs.io/en/latest/security.html
    ##
    ## ____ EXAMPLE _______________
    ##   stringOverride: |
    ##     from airflow import configuration as conf
    ##     from flask_appbuilder.security.manager import AUTH_DB
    ##
    ##     # the SQLAlchemy connection string
    ##     SQLALCHEMY_DATABASE_URI = conf.get('core', 'SQL_ALCHEMY_CONN')
    ##
    ##     # use embedded DB for auth
    ##     AUTH_TYPE = AUTH_DB
    ##
    stringOverride: |
      from flask_appbuilder.security.manager import AUTH_LDAP

      # only needed for airflow 1.10
      #from airflow import configuration as conf
      #SQLALCHEMY_DATABASE_URI = conf.get("core", "SQL_ALCHEMY_CONN")

      AUTH_TYPE = AUTH_LDAP
      AUTH_LDAP_SERVER = "ldap://openldap-chart.default.svc.cluster.local"
      AUTH_LDAP_USE_TLS = False

      # registration configs
      AUTH_USER_REGISTRATION = True  # allow users who are not already in the FAB DB
      AUTH_USER_REGISTRATION_ROLE = "Public"  # this role will be given in addition to any AUTH_ROLES_MAPPING
      AUTH_LDAP_FIRSTNAME_FIELD = "givenName"
      AUTH_LDAP_LASTNAME_FIELD = "sn"
      AUTH_LDAP_EMAIL_FIELD = "mail"  # if null in LDAP, email is set to: "{username}@email.notfound"

      # search configs
      AUTH_LDAP_SEARCH = "ou=users,dc=sirius,dc=com"  # the LDAP search base
      AUTH_LDAP_UID_FIELD = "uid"  # the username field
      AUTH_LDAP_BIND_USER = "cn=admin,dc=sirius,dc=com"  # the special bind username for search
      AUTH_LDAP_BIND_PASSWORD = "passw0rd"  # the special bind password for search

      # a mapping from LDAP DN to a list of FAB roles
      AUTH_ROLES_MAPPING = {
          "cn=operations,ou=groups,dc=sirius,dc=com": ["User"],
          "cn=admin,ou=groups,dc=sirius,dc=com": ["Admin"],
      }



      # the LDAP user attribute which has their role DNs
      AUTH_LDAP_GROUP_FIELD = "memberOf"

      # if we should replace ALL the user's roles each login, or only on registration
      AUTH_ROLES_SYNC_AT_LOGIN = True

      # force users to re-auth after 30min of inactivity (to keep roles in sync)
      PERMANENT_SESSION_LIFETIME = 1800
EOF

  helm install airflow-chart charts/airflow/charts/airflow \
  --set redis.enabled='false' \
  --set externalRedis.host='redis-chart-master.default.svc.cluster.local' \
  --set externalRedis.user=default \
  --set externalRedis.password=redis \
  --set postgresql.enabled=false \
  --set externalDatabase.type=postgres \
  --set externalDatabase.host=postgres-chart-postgresql.default.svc.cluster.local \
  --set externalDatabase.port=5432 \
  --set externalDatabase.user=airflow_user \
  --set externalDatabase.database=airflow_db \
  --set externalDatabase.password=airflow_pass \
  --set airflow.image.repository="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"/dliab-airflow \
  --set airflow.image.tag=latest \
  --values charts/airflow/charts/airflow/values.yaml \
  --values charts/airflow/charts/airflow/extra-values.yaml


fi

#############################
# Install OpenSearch
#############################


# Target name to check
target_name="opensearch-chart"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."
  helm install opensearch-chart charts/openmetadata/charts/deps/charts/opensearch \
  --set global.dockerRegistry="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com" \
  --set image.repository=dliab-opensearch \
  --set image.tag=latest \
  --set majorVersion=latest \
  --set persistence.image=dliab-busybox \
  --set sysctlInit.image=dliab-busybox \
  --values charts/openmetadata/charts/deps/charts/opensearch/values.yaml \
  --values charts/openmetadata/charts/deps/values.yaml


fi


###################################
# Install OpenMetadata
###################################



# Target name to check
target_name="openmetadata"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."
  helm dependencies build charts/openmetadata/charts/openmetadata


  # We need to create an extra-values.yaml file because we can't get the parameters passed-through with --set command
  cat<<EOF > "${CURRENT_DIR}/charts/openmetadata/charts/openmetadata/extra-values.yaml"
openmetadata:
  config:
    authorizer:
      principalDomain: "sirius.com"
    authentication:
      enableSelfSignup: false
      provider: "ldap"
      ldapConfiguration:
        dnAdminPrincipal: "cn=admin,dc=sirius,dc=com"
        userBaseDN: "ou=users,dc=sirius,dc=com"
        mailAttributeName: "mail"
        host: openldap-chart.default.svc.cluster.local
        port: 389
EOF

  helm install openmetadata charts/openmetadata/charts/openmetadata \
  --set image.repository="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/dliab-openmetadata-server" \
  --set image.tag="latest" \
  --set openmetadata.config.database.enabled=true \
  --set openmetadata.config.database.host="postgres-chart-postgresql.default.svc.cluster.local" \
  --set openmetadata.config.database.dbScheme="postgresql" \
  --set openmetadata.config.database.port=5432 \
  --set openmetadata.config.database.driverClass="org.postgresql.Driver" \
  --set openmetadata.config.database.auth.username="openmetadata_user" \
  --set openmetadata.config.database.auth.password.secretRef="postgres-secrets" \
  --set openmetadata.config.database.auth.password.secretKey="password" \
  --set openmetadata.config.pipelineServiceClientConfig.apiEndpoint="http://airflow-chart-web.default.cluster.local:8080" \
  --set openmetadata.config.pipelineServiceClientConfig.auth.password.secretRef="airflow-secrets" \
  --set openmetadata.config.pipelineServiceClientConfig.auth.password.secretKey="openmetadata-airflow-password" \
  --set openmetadata.config.elasticsearch.enabled=false \
  --set openmetadata.config.elasticsearch.host="opensearch-cluster-master.default.svc.cluster.local" \
  --set openmetadata.config.upgradeMigrationConfigs.force=true \
  --values charts/openmetadata/charts/openmetadata/values.yaml \
  --values charts/openmetadata/charts/openmetadata/extra-values.yaml

  #--set-string openmetadata.config.authentication.ldapConfiguration.dnAdminPrincipal=cn=admin,dc=sirius,dc=com \
  #--set openmetadata.config.authentication.ldapConfiguration.userBaseDN="ou=users,dc=sirius,dc=com" \
  #--set openmetadata.config.authentication.ldapConfiguration.mailAttributeName="mail" \
  #--set openmetadata.config.authorizer.principalDomain="sirius.com" \
  #--set openmetadata.config.authentication.enableSelfSignup=false \
  #--set openmetadata.config.authentication.provider="ldap" \
  #--set openmetadata.config.authentication.ldapConfiguration.host=openldap-chart.default.svc.cluster.local \
  #--set openmetadata.config.authentication.ldapConfiguration.port=389 \






fi

################################
# Install Trino
################################

# Target name to check
target_name="trino"

# Flag to indicate if the name is found
name_found=false

# Iterate through the array
for name in "${helm_array[@]}"; do
    if [ "$name" == "$target_name" ]; then
        name_found=true
        break
    fi
done

# Check the result
if [ "$name_found" == true ]; then
  echo "$target_name is in the array."
else
  echo "$target_name is not in the array."
  helm dependencies build charts/trino/charts/trino
  helm install trino charts/trino/charts/trino \
  --set image.repository="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com/openlake-trino" \
  --set image.tag=latest \
  --values charts/trino/charts/trino/values.yaml



fi

########################
# Forwarding all ports
########################

kubectl port-forward services/openldap-chart 3389:389 &
kubectl port-forward --namespace default svc/openmetadata 8585:8585 &
kubectl port-forward --namespace default svc/airflow-chart-web 8080:8080 &
kubectl port-forward services/openldap-chart-phpldapadmin 8081:80 &
kubectl port-forward service/postgres-chart-postgresql 5432:5432 &
kubectl port-forward service/trino 8082:8080 &

