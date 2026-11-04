#!/bin/bash

#Github API URL
API_URL="https://api.github.com"

#Github username and personal access token
USERNAME=$username
TOKEN=$token

#User and Repository information
REPO_OWNER=$1
REPO_NAME=$2

# Function to make a GET request to the Github API


# Function to List users with reaf access to the repository

function list_users_with_read_access (
     local endpoint="repos/${REPO_OWNER}/${REPO_NAME}/collaborators"


