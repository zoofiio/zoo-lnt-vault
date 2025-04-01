#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Updating Solidity imports to named import style ===${NC}"

# Count of files processed and updated
FILES_PROCESSED=0
FILES_UPDATED=0

# Process all Solidity files in src directory
find src -name "*.sol" | while read file; do
  FILES_PROCESSED=$((FILES_PROCESSED+1))
  echo -e "${YELLOW}Processing: ${file}${NC}"
  
  # Create a temporary file for the changes
  tmp_file="${file}.tmp"
  
  # Extract all import statements and check if they need to be updated
  UPDATED=false
  
  # Read line by line and apply transformations
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^import[[:space:]]+(\"|\')([^\"\']+)(\"|\')[[:space:]]*\;[[:space:]]* ]]; then
      # This is an import statement without named imports
      import_path="${BASH_REMATCH[2]}"
      
      # Extract the last part of the path to get the potential file name
      file_name=$(basename "$import_path" .sol)
      
      # Replace any slashes with dots for nested paths
      contract_name=${file_name//\//.}
      
      # Special case for OpenZeppelin contracts
      if [[ "$import_path" == *"/contracts/"* ]]; then
        # Extract last part after the last slash
        contract_name=$(echo "$import_path" | rev | cut -d'/' -f1 | rev | cut -d'.' -f1)
      fi
      
      # Create the named import
      echo "import {$contract_name} from \"$import_path\";" >> "$tmp_file"
      UPDATED=true
    else
      # Pass through unchanged
      echo "$line" >> "$tmp_file"
    fi
  done < "$file"
  
  if [ "$UPDATED" = true ]; then
    # Replace the original file with the updated one
    mv "$tmp_file" "$file"
    FILES_UPDATED=$((FILES_UPDATED+1))
    echo -e "${GREEN}Updated: ${file}${NC}"
  else
    # Remove the temporary file if no changes were made
    rm "$tmp_file"
    echo -e "No changes needed for: ${file}"
  fi
done

echo -e "${BLUE}=== Import Update Complete ===${NC}"
echo -e "${GREEN}Files processed: $FILES_PROCESSED${NC}"
echo -e "${GREEN}Files updated: $FILES_UPDATED${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${YELLOW}Note: This script provides a basic transformation of imports.${NC}"
echo -e "${YELLOW}Some files may need manual adjustments if they have special import requirements.${NC}"
echo -e "${BLUE}===============================================${NC}"