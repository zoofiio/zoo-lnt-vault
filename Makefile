.PHONY: all test clean build help

all: clean build test

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@forge clean

# Build the project
build:
	@echo "Building..."
	@forge build

# Run tests
test:
	@echo "Running tests..."
	@forge test

# Run tests with gas report
test-gas:
	@echo "Running tests with gas report..."
	@forge test --gas-report

# Deploy with mock contracts (for testing)
deploy-mocks:
	@echo "Deploying contracts with mocks..."
	@forge script script/DeployContracts.s.sol:DeployWithMocksScript --rpc-url localhost --broadcast

# Deploy on a specific network (requires env vars)
deploy-network:
	@echo "Deploying contracts to network..."
	@forge script script/DeployContracts.s.sol --rpc-url $(RPC_URL) --broadcast

# Format solidity code
format:
	@echo "Formatting code..."
	@forge fmt

# Generate documentation
docs:
	@echo "Generating documentation..."
	@forge doc

# Help command
help:
	@echo "Available commands:"
	@echo "  make all           - Clean, build, and test"
	@echo "  make clean         - Remove build artifacts"
	@echo "  make build         - Compile contracts"
	@echo "  make test          - Run tests"
	@echo "  make test-gas      - Run tests with gas reporting"
	@echo "  make deploy-mocks  - Deploy contracts with mock dependencies"
	@echo "  make deploy-network RPC_URL=<url> - Deploy to a specific network"
	@echo "  make format        - Format Solidity code"
	@echo "  make docs          - Generate documentation"