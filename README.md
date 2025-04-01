# Zoo LNT Vault (Foundry Edition)

This repository contains the smart contracts for the Zoo LNT Vault system, a solution for NFT staking and yield generation.

## Development Environment

This project uses [Foundry](https://book.getfoundry.sh/) for development, testing, and deployment.

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/zoo-lnt-vault
cd zoo-lnt-vault
```

2. Install the dependencies:
```bash
forge install
```

3. Build the project:
```bash
forge build
```

### Testing

Run the tests:

```bash
forge test
```

Run tests with verbosity level for more details:

```bash
forge test -vvv
```

To run a specific test file:

```bash
forge test --match-path test/tokens/YieldTokenTest.sol -vvv
```

To run a specific test function:

```bash
forge test --match-test testAddRewards -vvv
```

### Gas Reporting

To generate a gas report:

```bash
forge test --gas-report
```

### Scripts

#### Calculate LntMarket Init Code Hash

This script calculates the init code hash used for CREATE2 deployment of LntMarket pairs:

```bash
forge script script/GetInitCodeHash.s.sol --rpc-url localhost
```

#### Deploy Contracts

To deploy contracts to a local network:

```bash
forge script script/DeployContracts.s.sol --rpc-url localhost --broadcast
```

To deploy with mock contracts (for testing):

```bash
forge script script/DeployContracts.s.sol:DeployWithMocksScript --rpc-url localhost --broadcast
```

For deployment to a real network, set the environment variables:

```bash
export PRIVATE_KEY=your_private_key
export TREASURY_ADDRESS=0x...
export NFT_CONTRACT_ADDRESS=0x...
export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your_api_key

forge script script/DeployContracts.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

## Contract Architecture

- **LntVaultBase**: Base vault functionality shared across different NFT vault implementations
- **LntVaultERC721**: Vault for ERC721 NFTs
- **LntVaultERC1155**: Vault for ERC1155 NFTs
- **VestingToken (VT)**: Token representing vesting ownership in the vault
- **YieldToken (YT)**: Token representing yield-generating ownership in the vault
- **LntContractFactory**: Factory for deployment of ZooFi contracts
- **LntMarketFactory/Router/Pair**: Decentralized exchange functionality for ZooFi tokens

## License

This project is licensed under the Apache-2.0 license.