##################################################
# List all EBS volumes - status available
##################################################

#!/bin/bash

# Function - get current date and time
get_date_time() {
    date +%Y-%m-%d" "%H:%M
}

# Global variables
current_date=$(date +%Y-%m-%d)
full_log="full_log_${current_date}.txt"
output_file="ebs_unnatached.csv"


>full_log_${current_date}.txt
>accounts.txt
>ebs_unnatached.csv

# Write the header to the output file
echo "Account,Region,Volume ID,Volume Size,Volume Type" > "${output_file}"


# Get all active accounts in the organization
for account in $(aws organizations list-accounts --query 'Accounts[?Status==`ACTIVE`].Id' --profile master --output text); do

    echo "$(get_date_time)" | tee -a ${full_log}
    echo "+------------------------------+" | tee -a ${full_log}
    echo "Processing account: $account"     | tee -a ${full_log}
    echo "+------------------------------+" | tee -a ${full_log}    
       
    # Assume role Terraform
    rolearn="arn:aws:iam::${account}:role/Terraform"
    assumed_role=$(aws sts assume-role \
                    --role-arn ${rolearn} \
                    --role-session-name AssumeRoleSession \
                    --profile master \
                    --query 'Credentials.{AccessKeyId:AccessKeyId,SecretAccessKey:SecretAccessKey,SessionToken:SessionToken}')
    # Set up the credentials
    export AWS_ACCESS_KEY_ID=$(echo ${assumed_role} | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo ${assumed_role} | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo ${assumed_role} | jq -r '.SessionToken')

	# Check if account role can be assumed
    if [ -z "${assumed_role}" ]; then
        echo "${account} NOK" >> accounts.txt
    else
        echo "${account} OK" >> accounts.txt
	fi
	
	# Get AWS regions
	aws_regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
		
	# Loop to work on all regions
	for region in ${aws_regions}; do		
		
		# Get all volumes - state available
		volume_ids=$(aws ec2 describe-volumes \
			--region $region \
			--filters Name=status,Values=available \
			--query 'Volumes[].[VolumeId,Size,VolumeType]' \
			--output text)

		# Check if there is any output
    	if [ -z "${volume_ids}" ]; then
        	echo "Region ${region} has no data" | tee -a ${full_log}
    	else			
        	# Print region
			echo "Region: $region" | tee -a ${full_log}

			# Using while with IFS=$'\t' to read each line of volume_ids, splitting the fields by tabs
			while IFS=$'\t' read -r volume_id size volume_type; do
    			echo "$account,$region,$volume_id,$size,$volume_type" >> "${output_file}"
			done <<< "${volume_ids}"

			echo "${volume_ids}" | tee -a ${full_log}

		fi
	echo "---" | tee -a ${full_log}
	done
	echo "" | tee -a ${full_log}

	# Unset assumed role credentials
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
done
