#!/bin/bash

# Set variables
LOCAL_PORT="3306"
REMOTE_PORT="3306"
REMOTE_HOST=""

SSM_USER="ssm-user"

#Get Region
read -p "Enter AWS Region: " REGION

#Get Environment
read -p "Enter Environment: " ENVIRONMENT


export AWS_DEFAULT_REGION="${REGION}"

function checkDependencies {
    errorMessages=()

    echo -ne "Checking dependencies..................\r"

    # Check AWS CLI
    aws=$(aws --version 2>&1)
    if [[ $? != 0 ]]; then
        errorMessages+=('AWS CLI not found. Please install the latest version of AWS CLI.')
    else
        minVersion="1.16.213"
        version=$(echo $aws | cut -d' ' -f 1 | cut -d'/' -f 2)

        for i in {1..3}
        do
            x=$(echo "$version" | cut -d '.' -f $i)
            y=$(echo "$minVersion" | cut -d '.' -f $i)
            if [[ $x < $y ]]; then
                errorMessages+=('Installed version of AWS CLI does not meet minimum version. Please install the latest version of AWS CLI.')
                break
            fi
        done
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

function setInstanceIdandAz {
    # Get random running instance with Name:ucom-${ENVIRONMENT}-jump tag
    echo -ne "Getting available jump instance........\r"
    result=$(aws ec2 describe-instances --region ${AWS_DEFAULT_REGION} --filter "Name=tag:Name,Values=ucom-${ENVIRONMENT}-jump" --query "Reservations[].Instances[?State.Name == 'running'].{Id:InstanceId, Az:Placement.AvailabilityZone}[]" --output text)

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

function SSHKey {
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

function tunnelToInstance {
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


# Check for dependencies
#checkDependencies

#setInstanceIdandAz

# Load SSH key pair
#SSHKey

# Connect to instance
#tunnelToInstance
