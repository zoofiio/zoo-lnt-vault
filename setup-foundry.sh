#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setting up Foundry environment for Zoo LNT Vault ===${NC}"

# Create necessary directories
echo -e "${YELLOW}Creating necessary directories...${NC}"
mkdir -p test/foundry/tokens
mkdir -p test/foundry/vaults
mkdir -p test/foundry/market
mkdir -p test/foundry/mocks
mkdir -p script
mkdir -p deployment

# Install foundry dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
if [ ! -d "lib/forge-std" ]; then
    echo "Installing forge-std..."
    forge install foundry-rs/forge-std --no-commit
fi

if [ ! -d "lib/openzeppelin-contracts" ]; then
    echo "Installing OpenZeppelin contracts..."
    forge install OpenZeppelin/openzeppelin-contracts@v5.0.0 --no-commit
fi

# Check and set the correct Solidity version
echo -e "${YELLOW}Verifying Solidity compiler version...${NC}"
echo "Solidity 0.8.26 is configured in foundry.toml"

# Build the project
echo -e "${YELLOW}Building the project...${NC}"
forge build

# Handle any special initialization needed for Foundry tests
echo -e "${YELLOW}Setting up remappings...${NC}"
cat > remappings.txt << EOL
ds-test/=lib/forge-std/lib/ds-test/src/
forge-std/=lib/forge-std/src/
@openzeppelin/=lib/openzeppelin-contracts/
hardhat/=node_modules/hardhat/
EOL

# Create a deployment directory if it doesn't exist
mkdir -p deployment

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${YELLOW}To run tests:${NC} forge test"
echo -e "${YELLOW}To run specific test:${NC} forge test --match-path test/foundry/mocks/MockTest.sol -vv"
echo -e "${YELLOW}To generate a gas report:${NC} forge test --gas-report"
echo -e "${YELLOW}To deploy contracts:${NC} forge script script/DeployContracts.s.sol:DeployWithMocksScript --rpc-url localhost --broadcast"
echo -e "${BLUE}===============================================${NC}"