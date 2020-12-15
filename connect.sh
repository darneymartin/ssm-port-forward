#!/bin/bash

# Set Default Variable Values
LOCAL_PORT="80"
REMOTE_PORT="80"
REMOTE_HOST="localhost"
INSTANCE_ID=""

SSM_USER="ssm-user"

HelpFunction()
{
   echo ""
   echo "Usage: $0 -h REMOTE_HOST -p REMOTE_PORT -l LOCAL_PORT -i INSTANCE_ID"
   echo -e "\t-h The remote host you want to connect to"
   echo -e "\t-p The remote port of the host you want to connect to"
   echo -e "\t-l the local port you want the connection forwarded to"
   echo -e "\t-l The Jump Box instance ID"
   exit 1 # Exit script after printing help
}

while getopts "a:b:c:" opt
do
   case "$opt" in
      h ) REMOTE_HOST="$OPTARG" ;;
      p ) REMOTE_PORT="$OPTARG" ;;
      l ) LOCAL_PORT="$OPTARG" ;;
      i ) INSTANCE_ID="$OPTARG" ;;
      ? ) HelpFunction ;; # Print HelpFunction in case parameter is non-existent
   esac
done

# Print HelpFunction in case parameters are empty
if [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_PORT" ] || [ -z "$LOCAL_PORT" ] || [ -z "$INSTANCE_ID" ]
then
   echo "Some or all of the parameters are empty";
   HelpFunction
fi


function checkDependencies {
    errorMessages=()

    echo -ne "Checking dependencies..................\r"

    # Check AWS CLI
    aws=$(aws --version 2>&1)
    if [[ $? != 0 ]]; then
        errorMessages+=('AWS CLI not found. Please install the latest version of AWS CLI.')
    fi

    # Check Session Manager Plugin
    ssm=$(session-manager-plugin --version 2>&1)
    if [[ $? != 0 ]]; then
        errorMessages+=('AWS Session Manager Plugin not found. Please install the latest version of AWS Session Manager Plugin.')
    fi

    # If there are any error messages, print them and exit.
    if [[ $errorMessages ]]; then
        echo -ne "Checking dependencies..................Error"
        echo -ne "\n"
        for errorMessage in "${errorMessages[@]}"
        do
            echo "Failed dependency check"
            echo "======================="
            echo " - ${errorMessage}"
        done
        exit
    fi

    echo -ne "Checking dependencies..................Done"
    echo -ne "\n"
}

function GetInstanceAZ {
    # Get random running instance with Name:${InstanceID}p tag
    echo -ne "Getting available jump instance........\r"
    result=$(aws ec2 describe-instances --region ${AWS_DEFAULT_REGION} --filter "Name=tag:Name,Values=${ENVIRONMENT}" --query "Reservations[].Instances[?State.Name == 'running'].{Id:InstanceId, Az:Placement.AvailabilityZone}[]" --output text)

    if [[ $result ]]; then
        azs=($(echo "$result" | cut -d $'\t' -f 1))
        instances=($(echo "$result" | cut -d $'\t' -f 2))
        
        instancesLength="${#instances[@]}"
        randomInstance=$(( $RANDOM % $instancesLength ))

        instanceId="${instances[$randomInstance]}"
        az="${azs[$randomInstance]}"
        echo -ne "Getting available jump instance........Done"
        echo -ne "\n"
    else
        echo "Could not find a running jump server. Please try again."
        exit
    fi

    
}

function LoadSSHKey {
    # Generate SSH key
    echo -ne "Generating SSH key pair................\r"
    echo -e 'y\n' | ssh-keygen -t rsa -f temp -N '' > /dev/null 2>&1
    echo -ne "Generating SSH key pair................Done"
    echo -ne "\n"

    # Push SSH key to instance
    echo -ne "Pushing public key to instance.........\r"
    aws ec2-instance-connect send-ssh-public-key --region $AWS_DEFAULT_REGION --instance-id $instanceId --availability-zone $az --instance-os-user $SSM_USER --ssh-public-key file://temp.pub > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -ne "Pushing public key to instance.........Error"
        echo -ne "\n"
        exit
    fi
    echo -ne "Pushing public key to instance.........Done"
    echo -ne "\n"
}

function Connect {
    # Connect to instance
    echo -ne "Connecting to instance.................\r"
    ssh -i temp -N -f -M -S temp-ssh.sock -L $LOCAL_PORT:$REMOTE_HOST:$REMOTE_PORT $SSM_USER@$instanceId -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -o ProxyCommand="aws ssm start-session --target %h --document-name 'AWS-StartSSHSession' --parameters portNumber=%p --region $AWS_DEFAULT_REGION" > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -ne "Connecting to instance.................Error"
        echo -ne "\n"
        exit
    fi
    echo -ne "Connecting to instance.................Done\r"
    echo -ne "\n"

    read -rsn1 -p "Press any key to close session."; echo
    ssh -O exit -S temp-ssh.sock *
}
# BEGIN

# Check for dependencies
CheckDependencies

# Get Jump Instance information
GetJumpInstance

# Load SSH key pair to Jump Host
LoadSSHKey

# Connect to instance
Connect

#END