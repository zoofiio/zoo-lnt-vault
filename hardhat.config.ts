import dotenv from "dotenv";
import "@typechain/hardhat";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";

import { HardhatUserConfig } from "hardhat/config";
import { NetworkUserConfig } from "hardhat/types";

dotenv.config();

const chainIds = {
  hardhat: 31337,
  ganache: 1337,
  mainnet: 1,
  sepolia: 11155111,
  'bera-bartio': 80084,
};

// Ensure that we have all the environment variables we need.
const deployerKey: string = process.env.DEPLOYER_KEY || "";
const infuraKey: string = process.env.INFURA_KEY || "";

function createTestnetConfig(network: keyof typeof chainIds): NetworkUserConfig {
  // if (!infuraKey) {
  //   throw new Error("Missing INFURA_KEY");
  // }

  let nodeUrl;
  switch (network) {
    case "mainnet":
      nodeUrl = `https://mainnet.infura.io/v3/${infuraKey}`;
      break;
    case "sepolia":
      // nodeUrl = `https://sepolia.infura.io/v3/${infuraKey}`;
      nodeUrl = 'https://eth-sepolia.public.blastapi.io';
      break;
    case 'bera-bartio':
      nodeUrl = 'https://bartio.rpc.berachain.com';
      break;
  }

  return {
    chainId: chainIds[network],
    url: nodeUrl,
    accounts: [`${deployerKey}`],
  };
}

const config: HardhatUserConfig = {
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./test",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          metadata: {
            bytecodeHash: "ipfs",
          },
          // You should disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          optimizer: {
            enabled: true,
            runs: 100,
            // https://hardhat.org/hardhat-runner/docs/reference/solidity-support#support-for-ir-based-codegen
            // details: {
            //   yulDetails: {
            //     optimizerSteps: "u",
            //   },
            // },
          },
          viaIR: true
        },
      },
    ],
  },
  abiExporter: {
    flat: true,
  },
  gasReporter: {
    enabled: false
  },
  mocha: {
    parallel: false,
    timeout: 100000000
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v6",
  },
  sourcify: {
    enabled: false
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_KEY || "",
      sepolia: process.env.ETHERSCAN_KEY || "",
      'bera-bartio': process.env.BERA_EXPLORER_KEY  || ""
    },
    customChains: [
      {
        network: "bera-bartio",
        chainId: 80084,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/80084/etherscan/api",
          browserURL: "https://bartio.beratrail.io"
        }
      },

    ]
  },
};

if (deployerKey) {
  config.networks = {
    mainnet: createTestnetConfig("mainnet"),
    sepolia: createTestnetConfig("sepolia"),
    'bera-bartio': createTestnetConfig('bera-bartio'),
  };
}

config.networks = {
  ...config.networks,
  hardhat: {
    chainId: 1337,
    gas: "auto",
    gasPrice: "auto",
    allowUnlimitedContractSize: false,
  },
};

export default config;
