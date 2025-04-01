import _ from 'lodash';
import { expect } from "chai";
import { encodeBytes32String, formatUnits } from "ethers";
import { ethers } from "hardhat";
import { Signer } from 'ethers';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import {
  MockERC20__factory,
  MockERC721__factory,
  ERC20__factory,
  LntContractFactory,
  WETH__factory,
  LntMarketFactory__factory,
  LntMarketRouter__factory,
  LntContractFactory__factory,
  LntVaultBase
} from "../typechain";

const { provider } = ethers;

export const ONE_DAY_IN_SECS = 24 * 60 * 60;

export const SETTINGS_DECIMALS = 10n;

export const nativeTokenAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

export const maxContractSize = 24576;

export async function deployContractsFixture() {
  const [Alice, Bob, Caro, Dave, Ivy] = await ethers.getSigners();

  const WETHFactory = await ethers.getContractFactory("WETH");
  const WETH = await WETHFactory.deploy();
  const weth = WETH__factory.connect(await WETH.getAddress(), provider);

  const LntMarketFactoryFactory = await ethers.getContractFactory("LntMarketFactory");
  const LntMarketFactory = await LntMarketFactoryFactory.deploy();
  const lntMarketFactory = LntMarketFactory__factory.connect(await LntMarketFactory.getAddress(), provider);

  const LntMarketRouterFactory = await ethers.getContractFactory("LntMarketRouter");
  const LntMarketRouter = await LntMarketRouterFactory.deploy(await lntMarketFactory.getAddress(), await weth.getAddress());
  const lntMarketRouter = LntMarketRouter__factory.connect(await LntMarketRouter.getAddress(), provider);

  const LntContractFactoryFactory = await ethers.getContractFactory("LntContractFactory");
  const LntContractFactory = await LntContractFactoryFactory.deploy(Ivy.address);
  const lntContractFactory = LntContractFactory__factory.connect(await LntContractFactory.getAddress(), provider);

  return { 
    Alice, Bob, Caro, Dave, weth, lntContractFactory, lntMarketFactory, lntMarketRouter
  };
}

export async function deployContract(
  lntContractFactory: LntContractFactory, deployer: Signer,
  bytecode: string, constructorArgs: string
) {
  const tx = await lntContractFactory.connect(deployer).deployContract(bytecode, constructorArgs);
  const receipt = await tx.wait();
  const deployedEvent = receipt!.logs
    .map(log => lntContractFactory.interface.parseLog(log))
    .find(event => event && event.name === 'ContractDeployed');

  const contractAddress = deployedEvent!.args.contractAddress;
  // console.log(`Contract deployed at: ${contractAddress}`);

  // const event = receipt!.logs.find(receipt!.logs => _.get(log, 'fragment.name') === 'ContractDeployed');
  // const contractAddress = event!.args[1];

  return contractAddress;
}

export function expandTo18Decimals(n: number) {
  return BigInt(n) * (10n ** 18n);
}

// ensure result is within .01%
export function expectNumberEquals(expected: number, actual: number) {
  const equals = absNum(expected - actual) <= absNum(expected) / 10000;
  if (!equals) {
    console.log(`Number does not equal. expected: ${expected.toString()}, actual: ${actual.toString()}`);
  }
  expect(equals).to.be.true;
}

// ensure result is within .01%
export function expectBigNumberEquals(expected: bigint, actual: bigint) {
  const equals = abs(expected - actual) <= abs(expected) / 10000n;
  if (!equals) {
    console.log(`BigNumber does not equal. expected: ${expected.toString()}, actual: ${actual.toString()}`);
  }
  expect(equals).to.be.true;
}

export function numberToPercent(num: number) {
  return new Intl.NumberFormat("default", {
    style: "percent",
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  }).format(num);
}

export function power(pow: number | bigint) {
  return 10n ** BigInt(pow);
}

export function abs(n: bigint) {
  return n < 0n ? -n : n;
}

export function absNum(n: number) {
  return n < 0 ? -n : n;
}

export const addr0000 = "0x0000000000000000000000000000000000000000";
export const addr1111 = "0x1111111111111111111111111111111111111111";
export const getSimpleAddress = (i: number) =>
  `0x${Array.from({ length: 40 })
    .map(() => `${i}`)
    .join("")}`;

export const getBytes32String = (i: number) =>
  `0x${Array.from({ length: 64 })
    .map(() => `${i}`)
    .join("")}`;

export const increaseTime = async (time: number) => {
  await ethers.provider.send("evm_increaseTime", [time]);
  await ethers.provider.send("evm_mine"); // this one will have 02:00 PM as its timestamp
};

export const getTime = async () => {
  const block = await ethers.provider.getBlock("latest");
  return block!.timestamp;
};

export const makeToken = async (name: string, symbol: string, decimals: number = 18) => {
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const ERC20 = await MockERC20Factory.deploy(name, symbol, decimals);
  const erc20 = MockERC20__factory.connect(await ERC20.getAddress(), provider);

  return erc20
};

export async function calcMintedVt(vault: LntVaultBase, tokenId: bigint, value: bigint) {
  const vestingSchedules = await vault.vestingSchedules();
  const vestingSchedule = await vault.NFTType() == 1n ? vestingSchedules[0] : _.find(vestingSchedules, { tokenId: tokenId });
  const nftVtAmountPerNft = vestingSchedule!.vestingTokenAmountPerNft;
  const nftVestingStartTime = vestingSchedule!.vestingStartTime;
  const nftVestingDuration = vestingSchedule!.vestingDuration;
  const f1 = await vault.paramValue(encodeBytes32String("f1"));

  let remainingTime = 0n;
  const currentTime = await time.latest();
  if (currentTime < nftVestingStartTime + nftVestingDuration) {
    remainingTime = nftVestingStartTime + nftVestingDuration - BigInt(currentTime);
  }
  remainingTime = (_.min([remainingTime, nftVestingDuration]))!;

  const vtAmount = (nftVtAmountPerNft * value) * remainingTime / nftVestingDuration;
  const fees = vtAmount * f1 / (10n ** SETTINGS_DECIMALS);
  const netVtAmount = vtAmount - fees;

  return { netVtAmount, fees };
}

export async function calcBurnedVt(vault: LntVaultBase, depositId: bigint, tokenId: bigint, value: bigint) {
  const vestingSchedules = await vault.vestingSchedules();
  const vestingSchedule = await vault.NFTType() == 1n ? vestingSchedules[0] : _.find(vestingSchedules, { tokenId: tokenId });
  const nftVtAmountPerNft = vestingSchedule!.vestingTokenAmountPerNft;
  const nftVestingStartTime = vestingSchedule!.vestingStartTime;
  const nftVestingDuration = vestingSchedule!.vestingDuration;

  const nftDepositInfo = await vault.depositInfo(depositId);
  const f1 = nftDepositInfo.f1OnDeposit;

  let remainingTime = 0n;
  const currentTime = await time.latest();
  if (currentTime < nftVestingStartTime + nftVestingDuration) {
    remainingTime = nftVestingStartTime + nftVestingDuration - BigInt(currentTime);
  }
  remainingTime = (_.min([remainingTime, nftVestingDuration]))!;

  const vtAmount = (nftVtAmountPerNft * value) * remainingTime / nftVestingDuration;
  const fees = vtAmount * f1 / (10n ** SETTINGS_DECIMALS);
  const netVtAmount = vtAmount - fees;

  return netVtAmount;
}