import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import dotenv from "dotenv";
import { ethers } from "hardhat";
import {
  MockERC20__factory,
  MockERC721__factory,
  NftStakingPoolFactory__factory,
  ProtocolSettings__factory,
  Vault__factory,
  YtRewardsPoolFactory__factory,
  ZooProtocol__factory,
} from "../typechain";
import { deployContract, wait1Tx } from "./hutils";

dotenv.config();

const treasuryAddress = "0xC73ce0c5e473E68058298D9163296BebAC2b729C";

let deployer: SignerWithAddress;

const testers: any[] = ["0x956Cd653e87269b5984B8e1D2884E1C0b1b94442", "0xc97B447186c59A5Bb905cb193f15fC802eF3D543", "0x1851CbB368C7c49B997064086dA94dBAD90eB9b5"];

async function main() {
  const signers = await ethers.getSigners();
  deployer = signers[0];
  const nonce = await deployer.getNonce();
  console.log("deployer:", deployer.address);
  console.log("nonce:", nonce);

  const protocolAddress = await deployContract("ZooProtocol", []);
  const protocol = ZooProtocol__factory.connect(await protocolAddress, deployer);

  const protocolSettingsAddress = await deployContract("ProtocolSettings", [protocolAddress, treasuryAddress]);
  const settings = ProtocolSettings__factory.connect(await protocolSettingsAddress, deployer);

  const nftStakingPoolFactoryAddress = await deployContract("NftStakingPoolFactory", [await protocol.getAddress()]);
  const nftStakingPoolFactory = NftStakingPoolFactory__factory.connect(nftStakingPoolFactoryAddress, deployer);

  const ytRewardsPoolFactoryAddress = await deployContract("YtRewardsPoolFactory", [await protocol.getAddress()]);
  const ytRewardsPoolFactory = YtRewardsPoolFactory__factory.connect(ytRewardsPoolFactoryAddress, deployer);

  const vaultCalculatorAddress = await deployContract("VaultCalculator", []);

  const nftTokenAddress = await deployContract("MockERC721", [await protocol.getAddress(), "Mock ERC721", "MK721"]);
  const nftToken = MockERC721__factory.connect(nftTokenAddress, deployer);

  const nftVestingTokenAddress = await deployContract("MockERC20", [await protocol.getAddress(), "Mock ERC20", "MK20", 18]);
  const nftVestingToken = MockERC20__factory.connect(await nftVestingTokenAddress, deployer);

  const needTests = (
    await Promise.all(
      testers.map((item) =>
        nftToken
          .connect(deployer)
          .isTester(item)
          .then((isTester) => ({ tester: item, isTester }))
      )
    )
  )
    .filter((item) => !item.isTester)
    .map((item) => item.tester);
  if (needTests.length) {
    await nftToken.connect(deployer).batchSetTesters(needTests, true).then(wait1Tx);
    console.log(`${await nftToken.symbol()}: ${needTests} are now testers`);
  }
  const needTests2 = (
    await Promise.all(
      testers.map((item) =>
        nftVestingToken
          .connect(deployer)
          .isTester(item)
          .then((isTester) => ({ tester: item, isTester }))
      )
    )
  )
    .filter((item) => !item.isTester)
    .map((item) => item.tester);
  if (needTests2) {
    await nftVestingToken.connect(deployer).batchSetTesters(needTests2, true).then(wait1Tx);
    console.log(`${await nftVestingToken.symbol()}: ${needTests2} are now testers`);
  }

  const vaultAddress = await deployContract(
    "Vault",
    [
      await protocol.getAddress(),
      await settings.getAddress(),
      await nftStakingPoolFactory.getAddress(),
      await ytRewardsPoolFactory.getAddress(),
      await nftToken.getAddress(),
      await nftVestingToken.getAddress(),
      "Zoo vToken",
      "VT",
    ],
    `${await nftToken.symbol()}_Vault`,
    {
      libraries: {
        VaultCalculator: vaultCalculatorAddress,
      },
    }
  );
  console.info("VToken:", await Vault__factory.connect(vaultAddress, deployer).vToken());
  if (!(await protocol.connect(deployer).isVault(vaultAddress))) {
    await protocol.connect(deployer).addVault(vaultAddress).then(wait1Tx);
    console.log(`Added vault to protocol`);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
