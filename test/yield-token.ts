import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { formatEther, Signer } from 'ethers';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { 
  deployContractsFixture, ONE_DAY_IN_SECS,
  nativeTokenAddress,
  expectBigNumberEquals
} from './utils';
import { 
  YieldToken, YieldToken__factory,
  MockVault, MockVault__factory,
  MockERC20, MockERC20__factory
} from "../typechain";
import { formatUnits, parseUnits } from 'ethers';

const { provider } = ethers;

describe('YieldToken', () => {
  // Signers
  let Alice: Signer;
  let Bob: Signer;
  let Caro: Signer;
  let Dave: Signer;
  
  // Contract instances
  let yieldToken: YieldToken;
  let mockVault: MockVault;
  let rewardToken1: MockERC20;
  let rewardToken2: MockERC20;
  
  // Addresses for easier access
  let aliceAddress: string;
  let bobAddress: string;
  let caroAddress: string;
  let daveAddress: string;

  async function deployYieldTokenFixture() {
    [Alice, Bob, Caro, Dave] = await ethers.getSigners();
    aliceAddress = await Alice.getAddress();
    bobAddress = await Bob.getAddress();
    caroAddress = await Caro.getAddress();
    daveAddress = await Dave.getAddress();

    // Deploy YieldToken first
    const YieldTokenFactory = await ethers.getContractFactory("YieldToken");
    
    // Deploy MockVault without YieldToken
    const MockVaultFactory = await ethers.getContractFactory("MockVault");
    const MockVaultContract = await MockVaultFactory.connect(Alice).deploy();
    const vaultAddress = await MockVaultContract.getAddress();
    mockVault = MockVault__factory.connect(vaultAddress, provider);
    
    // Now deploy YieldToken with the vault address
    const YieldTokenContract = await YieldTokenFactory.connect(Alice).deploy(
      vaultAddress,
      "Yield Token",
      "YT"
    );
    const ytAddress = await YieldTokenContract.getAddress();
    yieldToken = YieldToken__factory.connect(ytAddress, provider);
    
    // Initialize MockVault with YieldToken's address
    await mockVault.connect(Alice).initialize(ytAddress);
    
    // Deploy reward tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const RewardToken1 = await MockERC20Factory.connect(Alice).deploy("Reward Token 1", "RT1", 18);
    rewardToken1 = MockERC20__factory.connect(await RewardToken1.getAddress(), provider);
    
    const RewardToken2 = await MockERC20Factory.connect(Alice).deploy("Reward Token 2", "RT2", 28); // Changed to 28 decimals
    rewardToken2 = MockERC20__factory.connect(await RewardToken2.getAddress(), provider);

    // Mint initial supply of reward tokens - use correct decimals for each token
    const initialSupply1 = parseUnits("10000", await rewardToken1.decimals());
    const initialSupply2 = parseUnits("10000", await rewardToken2.decimals());
    
    await rewardToken1.connect(Alice).mint(aliceAddress, initialSupply1);
    await rewardToken1.connect(Alice).mint(bobAddress, initialSupply1);
    await rewardToken2.connect(Alice).mint(aliceAddress, initialSupply2);
    await rewardToken2.connect(Alice).mint(bobAddress, initialSupply2);
    
    return { 
      Alice, Bob, Caro, Dave, 
      aliceAddress, bobAddress, caroAddress, daveAddress,
      yieldToken, mockVault, rewardToken1, rewardToken2 
    };
  }

  beforeEach(async () => {
    const fixture = await loadFixture(deployYieldTokenFixture);
    
    // Destructure all fixture variables into the test scope
    Alice = fixture.Alice;
    Bob = fixture.Bob;
    Caro = fixture.Caro;
    Dave = fixture.Dave;
    aliceAddress = fixture.aliceAddress;
    bobAddress = fixture.bobAddress;
    caroAddress = fixture.caroAddress;
    daveAddress = fixture.daveAddress;
    yieldToken = fixture.yieldToken;
    mockVault = fixture.mockVault;
    rewardToken1 = fixture.rewardToken1;
    rewardToken2 = fixture.rewardToken2;
  });

  it('should initialize with correct name, symbol and vault address', async () => {
    expect(await yieldToken.name()).to.equal("Yield Token");
    expect(await yieldToken.symbol()).to.equal("YT");
    expect(await yieldToken.vault()).to.equal(await mockVault.getAddress());
    expect(await yieldToken.decimals()).to.equal(18);
  });

  it('should allow only vault to mint tokens', async () => {
    // Vault can mint
    await expect(mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18)))
      .to.emit(yieldToken, "Transfer")
      .withArgs(ethers.ZeroAddress, aliceAddress, parseUnits("100", 18));
    
    // Others cannot mint directly
    await expect(yieldToken.connect(Bob).mint(bobAddress, parseUnits("100", 18)))
      .to.be.revertedWith("Caller is not the vault");
  });

  it('should initialize with correct epoch end timestamp', async () => {
    // Default is max uint256
    expect(await yieldToken.epochEndTimestamp()).to.equal(ethers.MaxUint256);
    
    // Only vault can update
    const newTimestamp = await time.latest() + ONE_DAY_IN_SECS * 30; // 30 days in future
    await expect(mockVault.connect(Alice).setEpochEndTimestamp(newTimestamp))
      .to.emit(yieldToken, "EpochEndTimestampUpdated")
      .withArgs(newTimestamp);
    
    expect(await yieldToken.epochEndTimestamp()).to.equal(newTimestamp);
  });

  it('should transfer tokens correctly and auto-claim rewards', async () => {
    // Mint tokens to Alice and Bob
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    await mockVault.connect(Alice).mintYieldToken(bobAddress, parseUnits("100", 18));
    
    // Check balances
    expect(await yieldToken.balanceOf(aliceAddress)).to.equal(parseUnits("100", 18));
    expect(await yieldToken.balanceOf(bobAddress)).to.equal(parseUnits("100", 18));
    
    // Transfer tokens
    await expect(yieldToken.connect(Alice).transfer(caroAddress, parseUnits("50", 18)))
      .to.emit(yieldToken, "Transfer")
      .withArgs(aliceAddress, caroAddress, parseUnits("50", 18));
    
    // Check updated balances
    expect(await yieldToken.balanceOf(aliceAddress)).to.equal(parseUnits("50", 18));
    expect(await yieldToken.balanceOf(bobAddress)).to.equal(parseUnits("100", 18));
    expect(await yieldToken.balanceOf(caroAddress)).to.equal(parseUnits("50", 18));
  });

  it('should add and distribute standard rewards correctly', async () => {
    // Mint tokens to users
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    await mockVault.connect(Alice).mintYieldToken(bobAddress, parseUnits("50", 18));
    await mockVault.connect(Alice).mintYieldToken(caroAddress, parseUnits("50", 18));
    
    // Add rewards via vault
    const rewardAmount = parseUnits("200", 18);
    await rewardToken1.connect(Alice).approve(await mockVault.getAddress(), rewardAmount);
    
    await expect(mockVault.connect(Alice).addRewards(await rewardToken1.getAddress(), rewardAmount))
      .to.emit(yieldToken, "RewardsAdded")
      .withArgs(await rewardToken1.getAddress(), rewardAmount, false);
    
    // Check earned rewards - using BigInt operations instead of .mul() and .div()
    const totalSupply = BigInt(200);
    const aliceExpectedReward = (rewardAmount * 100n) / totalSupply; // 100/200 of total supply
    const bobExpectedReward = (rewardAmount * 50n) / totalSupply;    // 50/200 of total supply
    const caroExpectedReward = (rewardAmount * 50n) / totalSupply;   // 50/200 of total supply
    
    expect(await yieldToken.earned(aliceAddress, await rewardToken1.getAddress())).to.be.closeTo(
      aliceExpectedReward, parseUnits("0.1", 18)
    );
    
    expect(await yieldToken.earned(bobAddress, await rewardToken1.getAddress())).to.be.closeTo(
      bobExpectedReward, parseUnits("0.1", 18)
    );
    
    expect(await yieldToken.earned(caroAddress, await rewardToken1.getAddress())).to.be.closeTo(
      caroExpectedReward, parseUnits("0.1", 18)
    );
  });

  it('should add and distribute time-weighted rewards correctly', async () => {
    // Mint tokens to users
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    await mockVault.connect(Alice).mintYieldToken(bobAddress, parseUnits("50", 18));
    
    // Advance time to create time-weighted balances
    await time.increase(ONE_DAY_IN_SECS); // 1 day
    
    // Collect time-weighted balances
    await yieldToken.connect(Alice).collectTimeWeightedBalance();
    await yieldToken.connect(Bob).collectTimeWeightedBalance();
    
    // Check time-weighted balances
    const aliceTimeWeightedBalance = await yieldToken.timeWeightedBalanceOf(aliceAddress);
    const bobTimeWeightedBalance = await yieldToken.timeWeightedBalanceOf(bobAddress);
    
    // Time-weighted balance should be approximately balance * time
    expectBigNumberEquals(parseUnits("100", 18) * BigInt(ONE_DAY_IN_SECS), aliceTimeWeightedBalance);
    expectBigNumberEquals(parseUnits("50", 18) * BigInt(ONE_DAY_IN_SECS), bobTimeWeightedBalance);
    
    // Add time-weighted rewards via vault - use correct decimals
    const timeWeightedRewardAmount = parseUnits("100", await rewardToken2.decimals());
    await rewardToken2.connect(Alice).approve(await mockVault.getAddress(), timeWeightedRewardAmount);
    
    await expect(mockVault.connect(Alice).addTimeWeightedRewards(await rewardToken2.getAddress(), timeWeightedRewardAmount))
      .to.emit(yieldToken, "RewardsAdded")
      .withArgs(await rewardToken2.getAddress(), timeWeightedRewardAmount, true);
    
    // Check time-weighted rewards
    const totalTimeWeightedBalance = await yieldToken.totalTimeWeightedBalance();
    const aliceShare = (aliceTimeWeightedBalance * parseUnits("1", 18)) / totalTimeWeightedBalance;
    const bobShare = (bobTimeWeightedBalance * parseUnits("1", 18)) / totalTimeWeightedBalance;
    
    const aliceExpectedTimeWeightedReward = (timeWeightedRewardAmount * aliceShare) / parseUnits("1", 18);
    const bobExpectedTimeWeightedReward = (timeWeightedRewardAmount * bobShare) / parseUnits("1", 18);
    
    expect(await yieldToken.timeWeightedEarned(aliceAddress, await rewardToken2.getAddress())).to.be.closeTo(
      aliceExpectedTimeWeightedReward, parseUnits("0.1", 18)
    );
    expect(await yieldToken.timeWeightedEarned(bobAddress, await rewardToken2.getAddress())).to.be.closeTo(
      bobExpectedTimeWeightedReward, parseUnits("0.1", 18)
    );
  });

  it('should allow the same token for both standard and time-weighted rewards', async () => {
    // Mint tokens to users
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    await mockVault.connect(Alice).mintYieldToken(bobAddress, parseUnits("50", 18));
    
    // Advance time and collect time-weighted balances
    await time.increase(ONE_DAY_IN_SECS);
    await yieldToken.connect(Alice).collectTimeWeightedBalance();
    await yieldToken.connect(Bob).collectTimeWeightedBalance();
    
    // Use the same token (rewardToken1) for both standard and time-weighted rewards
    const standardRewardAmount = parseUnits("100", await rewardToken1.decimals());
    const timeWeightedRewardAmount = parseUnits("200", await rewardToken1.decimals());
    
    // Add standard rewards
    await rewardToken1.connect(Alice).approve(await mockVault.getAddress(), standardRewardAmount);
    await mockVault.connect(Alice).addRewards(await rewardToken1.getAddress(), standardRewardAmount);
    
    // Add time-weighted rewards with the same token
    await rewardToken1.connect(Alice).approve(await mockVault.getAddress(), timeWeightedRewardAmount);
    await mockVault.connect(Alice).addTimeWeightedRewards(await rewardToken1.getAddress(), timeWeightedRewardAmount);
    
    // Check rewards tokens lists
    const rewardsTokens = await yieldToken.getRewardsTokens();
    const timeWeightedRewardsTokens = await yieldToken.getTimeWeightedRewardsTokens();
    
    expect(rewardsTokens).to.include(await rewardToken1.getAddress());
    expect(timeWeightedRewardsTokens).to.include(await rewardToken1.getAddress());
    
    // Verify both types of rewards are calculated correctly
    expect(await yieldToken.earned(aliceAddress, await rewardToken1.getAddress())).to.be.gt(0);
    expect(await yieldToken.timeWeightedEarned(aliceAddress, await rewardToken1.getAddress())).to.be.gt(0);
  });

  it('should exclude vault and YieldToken addresses from rewards', async () => {
    // Mint tokens to users and to vault
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    await mockVault.connect(Alice).mintYieldToken(bobAddress, parseUnits("50", 18));
    await mockVault.connect(Alice).mintYieldToken(await mockVault.getAddress(), parseUnits("50", 18)); // Mint to vault itself
    await mockVault.connect(Alice).mintYieldToken(await yieldToken.getAddress(), parseUnits("30", 18)); // Mint to token contract itself
    
    // Verify balances
    expect(await yieldToken.balanceOf(await mockVault.getAddress())).to.equal(parseUnits("50", 18));
    expect(await yieldToken.balanceOf(await yieldToken.getAddress())).to.equal(parseUnits("30", 18));
    
    // Check circulating supply (should exclude vault and token contract balances)
    const expectedCirculatingSupply = parseUnits("150", 18); // 100 + 50
    expect(await yieldToken.circulatingSupply()).to.equal(expectedCirculatingSupply);
    
    // Add rewards
    const rewardAmount = parseUnits("150", 18);
    await rewardToken1.connect(Alice).approve(await mockVault.getAddress(), rewardAmount);
    await mockVault.connect(Alice).addRewards(await rewardToken1.getAddress(), rewardAmount);
    
    // Verify rewards calculations - vault and token contract should be excluded
    expect(await yieldToken.earned(await mockVault.getAddress(), await rewardToken1.getAddress())).to.equal(0);
    expect(await yieldToken.earned(await yieldToken.getAddress(), await rewardToken1.getAddress())).to.equal(0);
    
    // Check if Alice and Bob get all rewards
    const aliceExpectedReward = rewardAmount * 100n / 150n; // 100/150 of circulating supply
    const bobExpectedReward = rewardAmount * 50n / 150n;    // 50/150 of circulating supply
    
    expect(await yieldToken.earned(aliceAddress, await rewardToken1.getAddress())).to.be.closeTo(
      aliceExpectedReward, parseUnits("0.1", 18)
    );
    expect(await yieldToken.earned(bobAddress, await rewardToken1.getAddress())).to.be.closeTo(
      bobExpectedReward, parseUnits("0.1", 18)
    );
    
    // Add time-weighted rewards
    await time.increase(ONE_DAY_IN_SECS);
    await yieldToken.connect(Alice).collectTimeWeightedBalance();
    await yieldToken.connect(Bob).collectTimeWeightedBalance();
    
    // Verify vault and token contract don't have time-weighted balance
    expect(await yieldToken.timeWeightedBalanceOf(await mockVault.getAddress())).to.equal(0);
    expect(await yieldToken.timeWeightedBalanceOf(await yieldToken.getAddress())).to.equal(0);
  });

  it('should claim rewards correctly', async () => {
    // Mint tokens to users
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    await mockVault.connect(Alice).mintYieldToken(bobAddress, parseUnits("50", 18));
    
    // Add standard rewards with correct decimals
    const standardRewardAmount = parseUnits("300", await rewardToken1.decimals());
    await rewardToken1.connect(Alice).approve(await mockVault.getAddress(), standardRewardAmount);
    await mockVault.connect(Alice).addRewards(await rewardToken1.getAddress(), standardRewardAmount);
    
    // Add time-weighted rewards
    await time.increase(ONE_DAY_IN_SECS);
    await yieldToken.connect(Alice).collectTimeWeightedBalance();
    await yieldToken.connect(Bob).collectTimeWeightedBalance();
    
    // Add time-weighted rewards with correct decimals
    const timeWeightedRewardAmount = parseUnits("200", await rewardToken2.decimals());
    await rewardToken2.connect(Alice).approve(await mockVault.getAddress(), timeWeightedRewardAmount);
    await mockVault.connect(Alice).addTimeWeightedRewards(await rewardToken2.getAddress(), timeWeightedRewardAmount);
    
    // Check rewards before claiming
    const aliceStandardRewardBefore = await yieldToken.earned(aliceAddress, await rewardToken1.getAddress());
    const aliceTimeWeightedRewardBefore = await yieldToken.timeWeightedEarned(aliceAddress, await rewardToken2.getAddress());
    
    expect(aliceStandardRewardBefore).to.be.gt(0);
    expect(aliceTimeWeightedRewardBefore).to.be.gt(0);
    
    // Initial token balances
    const aliceToken1BalanceBefore = await rewardToken1.balanceOf(aliceAddress);
    const aliceToken2BalanceBefore = await rewardToken2.balanceOf(aliceAddress);
    
    // Claim rewards
    await expect(yieldToken.connect(Alice).claimRewards())
      .to.emit(yieldToken, "RewardsPaid")
      .withArgs(aliceAddress, await rewardToken1.getAddress(), aliceStandardRewardBefore, false)
      .to.emit(yieldToken, "RewardsPaid")
      .withArgs(aliceAddress, await rewardToken2.getAddress(), anyValue, true);
    
    // Check token balances after claiming
    const aliceToken1BalanceAfter = await rewardToken1.balanceOf(aliceAddress);
    const aliceToken2BalanceAfter = await rewardToken2.balanceOf(aliceAddress);
    
    // When checking closeness, use the appropriate decimals
    expect(aliceToken1BalanceAfter).to.be.closeTo(
      aliceToken1BalanceBefore + (aliceStandardRewardBefore),
      parseUnits("0.1", await rewardToken1.decimals())
    );
    expect(aliceToken2BalanceAfter).to.be.closeTo(
      aliceToken2BalanceBefore + (aliceTimeWeightedRewardBefore),
      parseUnits("0.1", await rewardToken2.decimals())
    );
    
    // Rewards should be reset after claiming
    expect(await yieldToken.earned(aliceAddress, await rewardToken1.getAddress())).to.equal(0);
    expect(await yieldToken.timeWeightedEarned(aliceAddress, await rewardToken2.getAddress())).to.equal(0);
  });

  it('should auto-claim rewards on token transfers', async () => {
    // Mint tokens to users
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    
    // Add standard rewards with correct decimals
    const standardRewardAmount = parseUnits("200", await rewardToken1.decimals());
    await rewardToken1.connect(Alice).approve(await mockVault.getAddress(), standardRewardAmount);
    await mockVault.connect(Alice).addRewards(await rewardToken1.getAddress(), standardRewardAmount);
    
    // Add time-weighted rewards
    await time.increase(ONE_DAY_IN_SECS);
    await yieldToken.connect(Alice).collectTimeWeightedBalance();
    
    // Add time-weighted rewards with correct decimals
    const timeWeightedRewardAmount = parseUnits("150", await rewardToken2.decimals());
    await rewardToken2.connect(Alice).approve(await mockVault.getAddress(), timeWeightedRewardAmount);
    await mockVault.connect(Alice).addTimeWeightedRewards(await rewardToken2.getAddress(), timeWeightedRewardAmount);
    
    // Check rewards before transfer
    const aliceStandardRewardBefore = await yieldToken.earned(aliceAddress, await rewardToken1.getAddress());
    const aliceTimeWeightedRewardBefore = await yieldToken.timeWeightedEarned(aliceAddress, await rewardToken2.getAddress());
    
    expect(aliceStandardRewardBefore).to.be.gt(0);
    expect(aliceTimeWeightedRewardBefore).to.be.gt(0);
    
    // Initial token balances
    const aliceToken1BalanceBefore = await rewardToken1.balanceOf(aliceAddress);
    const aliceToken2BalanceBefore = await rewardToken2.balanceOf(aliceAddress);
    
    // Transfer tokens - should auto-claim rewards
    await yieldToken.connect(Alice).transfer(bobAddress, parseUnits("50", 18));
    
    // Check token balances after transfer
    const aliceToken1BalanceAfter = await rewardToken1.balanceOf(aliceAddress);
    const aliceToken2BalanceAfter = await rewardToken2.balanceOf(aliceAddress);
    
    expect(aliceToken1BalanceAfter).to.be.closeTo(
      aliceToken1BalanceBefore + aliceStandardRewardBefore,
      parseUnits("0.1", await rewardToken1.decimals())
    );
    expect(aliceToken2BalanceAfter).to.be.closeTo(
      aliceToken2BalanceBefore + aliceTimeWeightedRewardBefore,
      parseUnits("0.1", await rewardToken2.decimals())
    );
    
    // Rewards should be reset after auto-claiming
    expect(await yieldToken.earned(aliceAddress, await rewardToken1.getAddress())).to.equal(0);
    expect(await yieldToken.timeWeightedEarned(aliceAddress, await rewardToken2.getAddress())).to.equal(0);
  });

  it('should handle ETH as reward token', async () => {
    // Mint tokens to users
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    await mockVault.connect(Alice).mintYieldToken(bobAddress, parseUnits("50", 18));
    
    const ethRewardAmount = parseUnits("10", 18);
    
    // Add ETH as standard rewards
    await expect(mockVault.connect(Alice).addRewards(nativeTokenAddress, ethRewardAmount, { value: ethRewardAmount }))
      .to.emit(yieldToken, "RewardsAdded")
      .withArgs(nativeTokenAddress, ethRewardAmount, false);
    
    // Check ETH rewards - using BigInt operations
    const totalSupply = BigInt(150);
    const aliceExpectedEthReward = (ethRewardAmount * 100n) / totalSupply; // 100/150 of total supply
    
    expect(await yieldToken.earned(aliceAddress, nativeTokenAddress)).to.be.closeTo(
      aliceExpectedEthReward, parseUnits("0.1", 18)
    );
    
    // Add ETH as time-weighted rewards
    await time.increase(ONE_DAY_IN_SECS);
    await yieldToken.connect(Alice).collectTimeWeightedBalance();
    await yieldToken.connect(Bob).collectTimeWeightedBalance();
    
    await expect(mockVault.connect(Alice).addTimeWeightedRewards(nativeTokenAddress, ethRewardAmount, { value: ethRewardAmount }))
      .to.emit(yieldToken, "RewardsAdded")
      .withArgs(nativeTokenAddress, ethRewardAmount, true);
    
    // Check time-weighted ETH rewards
    expect(await yieldToken.timeWeightedEarned(aliceAddress, nativeTokenAddress)).to.be.gt(0);
    
    // Check initial ETH balance
    const aliceEthBalanceBefore = await provider.getBalance(aliceAddress);

    const totalExpectedEthReward = await yieldToken.earned(aliceAddress, nativeTokenAddress) 
      + await yieldToken.timeWeightedEarned(aliceAddress, nativeTokenAddress);
    
    // Claim rewards
    const tx = await yieldToken.connect(Alice).claimRewards();
    const receipt = await tx.wait();
    
    // Calculate gas cost
    const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
    
    // Check ETH balance after claiming
    const aliceEthBalanceAfter = await provider.getBalance(aliceAddress);
    
    // Account for gas cost in ETH balance change verification
    const ethBalanceChange = aliceEthBalanceAfter + gasUsed - aliceEthBalanceBefore;

    expect(ethBalanceChange).to.be.closeTo(totalExpectedEthReward, parseUnits("0.1", 18));
    expectBigNumberEquals(ethBalanceChange, totalExpectedEthReward);
  });

  it('should respect epoch end timestamp for time-weighted balance collection', async () => {
    // Mint tokens to users
    await mockVault.connect(Alice).mintYieldToken(aliceAddress, parseUnits("100", 18));
    
    // Set epoch end timestamp to 5 days in the future
    const currentTime = await time.latest();
    const epochEndTimestamp = currentTime + ONE_DAY_IN_SECS * 5;
    await mockVault.connect(Alice).setEpochEndTimestamp(epochEndTimestamp);
    
    // Advance time beyond epoch end
    await time.increaseTo(epochEndTimestamp + ONE_DAY_IN_SECS);
    
    // Collect time-weighted balance
    await yieldToken.connect(Alice).collectTimeWeightedBalance();
    
    // Time-weighted balance should be capped at epoch end
    const expectedTimeWeightedBalance = parseUnits("100", 18) * BigInt((epochEndTimestamp - currentTime));
    expect(await yieldToken.timeWeightedBalanceOf(aliceAddress)).to.be.closeTo(
      expectedTimeWeightedBalance,
      parseUnits("100", 18) // Allow some margin for block timestamp variations
    );
  });
});
