import _ from 'lodash';
import { expect } from "chai";
import { encodeBytes32String, formatUnits } from "ethers";
import { ethers } from "hardhat";
import { time } from '@nomicfoundation/hardhat-network-helpers';
import {
  MockERC20__factory,
  MockERC721__factory,
  ProtocolSettings__factory,
  ZooProtocol__factory,
  Vault__factory,
  VaultCalculator__factory,
  NftStakingPoolFactory__factory,
  YtRewardsPoolFactory__factory,
  Vault,
  ERC20__factory,
} from "../typechain";

const { provider } = ethers;

export const ONE_DAY_IN_SECS = 24 * 60 * 60;

export const SETTINGS_DECIMALS = 10n;

export const nativeTokenAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

export const maxContractSize = 24576;

export async function deployContractsFixture() {
  const [Alice, Bob, Caro, Dave, Ivy] = await ethers.getSigners();

  const ZooProtocolFactory = await ethers.getContractFactory("ZooProtocol");
  expect(ZooProtocolFactory.bytecode.length / 2).lessThan(maxContractSize);
  const ZooProtocol = await ZooProtocolFactory.deploy();
  const protocol = ZooProtocol__factory.connect(await ZooProtocol.getAddress(), provider);

  const ProtocolSettingsFactory = await ethers.getContractFactory("ProtocolSettings");
  expect(ProtocolSettingsFactory.bytecode.length / 2).lessThan(maxContractSize);
  const ProtocolSettings = await ProtocolSettingsFactory.deploy(await protocol.getAddress(), Ivy.address);
  const settings = ProtocolSettings__factory.connect(await ProtocolSettings.getAddress(), provider);

  const NftStakingPoolFactoryFactory = await ethers.getContractFactory("NftStakingPoolFactory");
  const NftStakingPoolFactory = await NftStakingPoolFactoryFactory.deploy(await protocol.getAddress());
  const nftStakingPoolFactory = NftStakingPoolFactory__factory.connect(await NftStakingPoolFactory.getAddress(), provider);

  const YtRewardsPoolFactoryFactory = await ethers.getContractFactory("YtRewardsPoolFactory");
  const YtRewardsPoolFactory = await YtRewardsPoolFactoryFactory.deploy(await protocol.getAddress());
  const ytRewardsPoolFactory = YtRewardsPoolFactory__factory.connect(await YtRewardsPoolFactory.getAddress(), provider);

  const MockERC721Factory = await ethers.getContractFactory("MockERC721");
  const MockERC721 = await MockERC721Factory.deploy(await protocol.getAddress(), "Mock ERC721", "Mock721");
  const nftToken = MockERC721__factory.connect(await MockERC721.getAddress(), provider);
  
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const MockERC20 = await MockERC20Factory.deploy(await protocol.getAddress(), "ERC20 Mock", "MockERC20", 18);
  const nftVestingToken = MockERC20__factory.connect(await MockERC20.getAddress(), provider);

  const VaultCalculatorFactory = await ethers.getContractFactory("VaultCalculator");
  const VaultCalculator = await VaultCalculatorFactory.deploy();
  const vaultCalculator = VaultCalculator__factory.connect(await VaultCalculator.getAddress(), provider);

  const VaultFactory = await ethers.getContractFactory("Vault", {
    libraries: {
      VaultCalculator: await vaultCalculator.getAddress(),
    }
  });
  console.log(`Vault code size: ${VaultFactory.bytecode.length / 2} bytes. (max: ${maxContractSize} bytes)`);

  const VaultContract = await VaultFactory.deploy(
    await protocol.getAddress(), await settings.getAddress(), 
    await nftStakingPoolFactory.getAddress(), await ytRewardsPoolFactory.getAddress(),
    await nftToken.getAddress(), await nftVestingToken.getAddress(), "Zoo vToken", "VT"
  );
  const vault = Vault__factory.connect(await VaultContract.getAddress(), provider);
  let trans = await protocol.connect(Alice).addVault(await vault.getAddress());
  await trans.wait();

  return { 
    Alice, Bob, Caro, Dave,
    protocol, settings, nftStakingPoolFactory, ytRewardsPoolFactory, nftToken, nftVestingToken,
    vaultCalculator, vault
  };
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

export const makeToken = async (protocol: string, name: string, symbol: string, decimals: number = 18) => {
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const ERC20 = await MockERC20Factory.deploy(protocol, name, symbol, decimals);
  const erc20 = MockERC20__factory.connect(await ERC20.getAddress(), provider);

  return erc20
};

export async function calcClaimedVt(vault: Vault, nftTokenId: bigint) {
  const nftVtAmount = await vault.nftVtAmount();
  const nftVestingDuration = await vault.nftVestingDuration();
  const nftVestingEndTime = await vault.nftVestingEndTime();
  const f1 = await vault.paramValue(encodeBytes32String("f1"));

  const nftDepositInfo = await vault.nftDepositInfo(nftTokenId);
  const leadingTimeEnd = nftDepositInfo.claimableTime;

  const remainingTime = _.min([nftVestingEndTime - leadingTimeEnd, nftVestingDuration]);
  const vtAmount = nftVtAmount * remainingTime! / nftVestingDuration;
  const fees = vtAmount * f1 / (10n ** SETTINGS_DECIMALS);
  const netVtAmount = vtAmount - fees;

  return { netVtAmount, fees };
}

export async function calcBurnedVt(vault: Vault, nftTokenId: bigint) {
  const nftVtAmount = await vault.nftVtAmount();
  const nftVestingDuration = await vault.nftVestingDuration();
  const nftVestingEndTime = await vault.nftVestingEndTime();

  const nftDepositInfo = await vault.nftDepositInfo(nftTokenId);
  const f1 = nftDepositInfo.f1OnClaim;

  const nftRedeemInfo = await vault.nftRedeemInfo(nftTokenId);
  const redeemTime = nftRedeemInfo.redeemTime;

  const remainingTime = _.min([nftVestingEndTime - redeemTime, nftVestingDuration]);
  const vtAmount = nftVtAmount * remainingTime! / nftVestingDuration;
  const fees = vtAmount * f1 / (10n ** SETTINGS_DECIMALS);
  const vtBurnAmount = vtAmount - fees;

  return vtBurnAmount;
}

export async function expectedY(vault: Vault) {
  const epochId = await vault.currentEpochId(); 
  const epoch = await vault.epochInfoById(epochId);

  const xDecimals = await vault.ytDecimals();
  const YtSwapPaymentToken = ERC20__factory.connect(epoch.ytSwapPaymentToken, provider);
  const yDecimals = await YtSwapPaymentToken.decimals();
  const k0Decimals = xDecimals + yDecimals + 10n;
  let X = Number(ethers.formatUnits(await vault.epochNextSwapX(epochId), xDecimals));
  let k0 = Number(ethers.formatUnits(await vault.epochNextSwapK0(epochId), k0Decimals));

  let deltaT = 0;
  if (epoch.startTime + epoch.duration >= await time.latest()) {
    // in current epoch
    deltaT = (await time.latest()) - Number(epoch.startTime);
  } 
  else {
    // in a new epoch
    deltaT = 0;
    const yTokenAmount = Number(ethers.formatUnits(await vault.ytNewEpoch(), await vault.ytDecimals()));
    const result = await expectedInitSwapParams(vault, yTokenAmount, Number(ethers.formatUnits(await vault.ytSwapPrice(), SETTINGS_DECIMALS)));
    X = result.X;
    k0 = result.k0;
  }

  // Y = k0 / (X * (1 + ∆t / 86400)2)
  let decayPeriod = Number(await vault.paramValue(encodeBytes32String("D"))) / 30;

  let Y = k0 / (X * (1 + deltaT / decayPeriod) * (1 + deltaT / decayPeriod));

  console.log(`expectedY, X: ${X}, k0: ${k0}, Y: ${Y}`);

  return Y;
}

export async function expectedInitSwapParams(vault: Vault, N: number, ytSwapPrice: number) {
  const X = N;

  // Y(0) = X * P
  const Y0 = X * ytSwapPrice;

  // k0 = X * Y0
  const k0 = X * Y0;

  console.log(`expectedInitSwapParams, ytSwapPrice (P): ${ytSwapPrice}, X: ${X}, Y0: ${Y0}, k0: ${k0}`);

  return { X, k0 };
}

export async function expectedCalcSwap(vault: Vault, n: number) {
  const epochId = await vault.currentEpochId();  // require epochId > 0
  const epoch = await vault.epochInfoById(epochId);

  const xDecimals = await vault.ytDecimals();
  const YtSwapPaymentToken = ERC20__factory.connect(epoch.ytSwapPaymentToken, provider);
  const yDecimals = await YtSwapPaymentToken.decimals();
  const k0Decimals = xDecimals + yDecimals + 10n;

  let X = Number(ethers.formatUnits(await vault.epochNextSwapX(epochId), xDecimals));
  let k0 = Number(ethers.formatUnits(await vault.epochNextSwapK0(epochId), k0Decimals));

  let deltaT = 0;
  if (epoch.startTime + epoch.duration >= await time.latest()) {
    // in current epoch
    deltaT = (await time.latest()) - Number(epoch.startTime);
  } 
  else {
    // in a new epoch
    deltaT = 0;
    const yTokenAmount = Number(ethers.formatUnits(await vault.ytNewEpoch(), await vault.ytDecimals()));
    const result = await expectedInitSwapParams(vault, yTokenAmount, Number(ethers.formatUnits(await vault.ytSwapPrice(), SETTINGS_DECIMALS)));
    X = result.X;
    k0 = result.k0;
  }
  // console.log(`expectedCalcSwap, X: ${X}, k0: ${k0}, deltaT: ${deltaT}`);

  // X' = X * k0 / (k0 + X * n * (1 + ∆t / 86400)2)
  let decayPeriod = Number(await vault.paramValue(encodeBytes32String("D"))) / 30;
  let X_updated = X * k0 / (k0 + X * n * (1 + deltaT / decayPeriod) * (1 + deltaT / decayPeriod));

  // m = X - X'
  let m = X - X_updated;

  console.log(`expectedCalcSwap, X: ${X}, k0: ${k0}, deltaT: ${deltaT}, X_updated: ${X_updated}, m: ${m}`);

  return { X_updated, m };
}