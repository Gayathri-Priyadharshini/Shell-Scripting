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

# list s3 buckets
aws s3 ls

# List EC2 instances
aws ec2 describe-instances

# List Lambda 
aws lambda list-functions

# List IAM users
aws iam list-users

