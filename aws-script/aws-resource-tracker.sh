#!/bin/bash

#################################
# AUTHOR: GAYATHRI
# 
#
# THIS SCRIPT WILL REPORT THE AWS RESOURCE USAGE
#
#################################

# AWS S3
# AWS EC2
# AWS Lambde
# AWS IAM Users

#########################

#To execute in debug mode (show commands)
set -x

# list s3 buckets
echo "Print list of S3 buckets"
aws s3 ls >> ResourceTracker

# List EC2 instances using jq
echo "Print list of Instances"
aws ec2 describe-instances | jq '.Reservations[].Instances[].InstanceId' >> ResourceTracker

# List Lambda 
echo "Print list of Lambda functions"
aws lambda list-functions >> ResourceTracker

# List IAM users
echo "Print list of IAM users"
aws iam list-users >> ResourceTracker

