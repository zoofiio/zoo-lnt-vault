#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Fixing Solidity file indentation to use 4 spaces ===${NC}"

# Count of files processed and updated
FILES_PROCESSED=0
FILES_UPDATED=0

# Create backup directory
mkdir -p backups/sol_indentation_fix

# Create a temporary directory for processing
mkdir -p temp_processing

# Process all Solidity files in src, test, script directories
find src test script -type f -name "*.sol" | while read file; do
    FILES_PROCESSED=$((FILES_PROCESSED+1))
    echo -e "${YELLOW}Processing: ${file}${NC}"
    
    # Create a backup
    cp "$file" "backups/sol_indentation_fix/$(basename "$file").bak"
    
    # First, replace all indentation with 4-space indentation
    # 1. Remove all leading spaces
    # 2. Then add 4 spaces for each indentation level (tab)
    
    # First convert all tabs to spaces if any exist
    expand -t 4 "$file" > "temp_processing/$(basename "$file")"
    
    # Now fix the indentation
    # 1. Remove all leading whitespace first
    # 2. Then convert indentation levels to 4 spaces
    awk '{
        # Count the number of leading spaces
        match($0, /^[ \t]+/);
        indent_len = RLENGTH;
        if (indent_len > 0) {
            indent_text = substr($0, 1, indent_len);
            # Count the number of indentation levels (2 spaces = 1 level)
            levels = indent_len / 2;
            # Create new indentation with 4 spaces per level
            new_indent = "";
            for (i = 0; i < levels; i++) {
                new_indent = new_indent "    ";
            }
            # Replace the indentation
            print new_indent substr($0, indent_len + 1);
        } else {
            print $0;
        }
    }' "temp_processing/$(basename "$file")" > "$file"
    
    FILES_UPDATED=$((FILES_UPDATED+1))
    echo -e "${GREEN}Updated: ${file}${NC}"
done

# Clean up temporary directory
rm -rf temp_processing

echo -e "${BLUE}=== Indentation Fix Complete ===${NC}"
echo -e "${GREEN}Files processed: $FILES_PROCESSED${NC}"
echo -e "${GREEN}Files updated: $FILES_UPDATED${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${YELLOW}Note: Backups of the original files are saved in 'backups/sol_indentation_fix/'${NC}"
echo -e "${BLUE}===============================================${NC}"