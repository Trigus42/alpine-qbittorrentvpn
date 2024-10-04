#!/bin/bash

# Description: This script is used to set the output for the GitHub action. 
# It writes the output to the file specified by the GITHUB_OUTPUT environment variable. 
# The output is formatted as name<<delimiter followed by the value and then the delimiter. 
# This allows for arrays to be passed as output. However they must be joined to a string
# using newline characters before like so: "$(IFS=$'\n'; echo "${ARRAY[*]}")""

# Arguments:
# $1: name of the output
# $2: value of the output

name=$1
value=$2

filePath="${GITHUB_OUTPUT}"
delimiter="ghadelimiter_$(uuidgen)"

# Shouldn't happen, but just in case
if [[ "$name" == *"$delimiter"* ]]; then
    echo "Error: name contains the delimiter $delimiter"
    return 1
fi

# Write to the output file with the formatted message
echo "${name}<<${delimiter}" >> "$filePath"
echo "${value}" >> "$filePath"
echo "${delimiter}" >> "$filePath"
