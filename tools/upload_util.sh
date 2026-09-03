#!/bin/bash

if [[ "$#" == '0' ]]; then
    echo -e 'ERROR: No File Specified!' && exit 1
fi

FILE="$1"

# Upload file with progress bar
RESPONSE=$(curl --progress-bar -X POST -F "file=@$FILE" "https://upload.gofile.io/uploadfile")

# Extract download link
LINK=$(echo "$RESPONSE" | jq -r '.data.downloadPage')

# Check if upload succeeded
if [[ "$LINK" == "null" || -z "$LINK" ]]; then
    echo -e "\n Upload failed! Full response:"
    echo "$RESPONSE"
    exit 1
fi

# Print result
echo "$LINK"
echo