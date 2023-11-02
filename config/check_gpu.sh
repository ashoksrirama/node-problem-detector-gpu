#!/bin/bash

readonly OK=0
readonly NONOK=1
readonly UNKNOWN=2

readonly SERVICE='gpu.service'

# Check systemd cmd present
if ! command -v nvidia-smi >/dev/null; then
  echo "Could not find 'nvidia-smi' - require nvidia-smi"
  exit $UNKNOWN
fi

# Check the instance type to find # of GPUs
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
INSTANCE_TYPE=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type`
ROLE_NAME=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/`
AWS_CREDS=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME`
export AWS_DEFAULT_REGION=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region`
export AWS_ACCESS_KEY_ID=`echo $AWS_CREDS | jq -r .AccessKeyId`
export AWS_SECRET_ACCESS_KEY=`echo $AWS_CREDS | jq -r .SecretAccessKey`
export AWS_SESSION_TOKEN=`echo $AWS_CREDS | jq -r .Token`

GPU_COUNT=`aws-curl --request POST --header "Content-Type: application/x-www-form-urlencoded" --data "Action=DescribeInstanceTypes" --data "InstanceType.1=${INSTANCE_TYPE}" --data "Version=2016-11-15"  "https://ec2.us-west-2.amazonaws.com" | xmllint --format --xpath "//*[local-name()='gpuInfo']/*[local-name()='gpus']/*[local-name()='item']/*[local-name()='count']/text()" -`

AWS_CMD_STATUS=$?

# Unable to fetch the GPU count, either its credential issue or its not a GPU instance
if [ $AWS_CMD_STATUS -ne 0 ]
then
    echo "Unable to get GPU Count from DescribeInstanceTypes API, failed with status code: ${AWS_CMD_STATUS}"
    exit $UNKNOWN
fi

# Its a GPU instance, lets verify the nvidia-smi status and match the # of available GPUs
nvidia-smi
NVDIA_SMI_STATUS=$?

if [ ${NVDIA_SMI_STATUS} -gt 0 ]
then
    echo "nvidia-smi failed with error code - $NVDIA_SMI_STATUS"
    exit $NONOK
fi

#GPU_COUNT=`aws ec2 describe-instance-types --instance-types g5.xlarge --query 'InstanceTypes[0].GpuInfo.Gpus[*].Count' --output text`
NGPU_COUNT=`nvidia-smi --list-gpus | wc -l`

if [ $GPU_COUNT -eq $NGPU_COUNT ]
then
    echo "GPU Count match"
    exit $OK
else
    echo "Count didn't match $GPU_COUNT != $NGPU_COUNT"
    exit $NONOK
fi
