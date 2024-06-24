##################################################
# List all EBS volumes - status available
##################################################

#!/bin/bash

# Function - get current date and time
get_date_time() {
    date +%Y-%m-%d" "%H:%M
}

# Global variables
dir="$HOME/reports"
current_date=$(date +%Y-%m-%d)
full_log="${dir}/full_log_${current_date}.txt"
output_file="${dir}/ebs_unattached_${current_date}.csv"
account_output="${dir}/accounts.txt"

# Clean up files
> ${full_log}
> ${account_output}
> ${output_file}

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
        echo "${account} NOK" >> ${account_output}
    else
        echo "${account} OK" >> ${account_output}
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

##################################################
# Send an email email
##################################################

# Set variables
source_email="cloudops@centricsoftware.com"
destination_email="fabiano.becatini@centricsoftware.com"
subject="Unattached EBS Volumes List"
attachment_file="ebs_unattached_${current_date}.csv"
raw_message_file="${dir}/raw_message.txt"

cd $dir

# Define the multi-line plain text body
body_text=$(cat <<EOF
Hello,
This is the list of unattached EBS volumes generated on $current_date.
EOF
)
# Define the multi-line HTML text body
body_html="<p>Hello,</p><p>This is the list of unattached EBS volumes generated on $current_date!</p><br><br>"

# Create the raw email
cat << EOF > $raw_message_file
From: $source_email
To: $destination_email
Subject: $subject
MIME-Version: 1.0
Content-Type: multipart/alternative; boundary="----=_Part_0_1718931086_d0671285272b51cb7594b7b4"

------=_Part_0_1718931086_d0671285272b51cb7594b7b4
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: 7bit

$body_text

------=_Part_0_1718931086_d0671285272b51cb7594b7b4
Content-Type: text/html; charset=UTF-8
Content-Transfer-Encoding: 7bit

$body_html

------=_Part_0_1718931086_d0671285272b51cb7594b7b4
Content-Type: text/csv; name="$attachment_file"
Content-Transfer-Encoding: base64
Content-Disposition: attachment; filename="$attachment_file"

$(base64 $attachment_file)
------=_Part_0_1718931086_d0671285272b51cb7594b7b4--
EOF

# Encode the data into base64 format
# '-w 0' option specifies that the output should not be wrapped, meaning the base64 encoded output will be a single continuous line without any line breaks.
message=$(cat $raw_message_file | base64 -w 0)

# Send the raw email using AWS SES
aws ses send-raw-email --raw-message '{"Data":"'${message}'"}' --region us-west-2 --profile master

# Delete temp files
rm -rf aws.txt raw_message.txt