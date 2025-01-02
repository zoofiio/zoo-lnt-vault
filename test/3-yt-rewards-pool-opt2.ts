import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time, loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ONE_DAY_IN_SECS, deployContractsFixture, expectBigNumberEquals, makeToken } from './utils';
import { 
  MockVault, YtRewardsPoolOpt2, MockERC20,
  MockVault__factory, YtRewardsPoolOpt2__factory,
  MockERC20__factory
} from "../typechain";

describe('YtRewardsPoolOpt2', () => {

  let mockVault: MockVault;
  let ytRewardsPool: YtRewardsPoolOpt2;
  let rewardsToken: MockERC20;
  let rewardsToken2: MockERC20;

  beforeEach(async () => {
    const { protocol, settings, nftStakingPoolFactory, ytRewardsPoolFactory, nftToken, nftVestingToken, Alice } = await loadFixture(deployContractsFixture);

    const MockVaultFactory = await ethers.getContractFactory("MockVault");
    const MockVault = await MockVaultFactory.deploy(
      await protocol.getAddress(), await settings.getAddress(), await nftStakingPoolFactory.getAddress(), await ytRewardsPoolFactory.getAddress(),
      await nftToken.getAddress(), await nftVestingToken.getAddress(), "Zoo VToken", "VT"
    );
    mockVault = MockVault__factory.connect(await MockVault.getAddress(), ethers.provider);

    let trans = await protocol.connect(Alice).addVault(await mockVault.getAddress());
    await trans.wait();
    await settings.connect(Alice).updateVaultParamValue(await mockVault.getAddress(), ethers.encodeBytes32String("f1"), 0);
    await settings.connect(Alice).updateVaultParamValue(await mockVault.getAddress(), ethers.encodeBytes32String("f2"), 0);

    const YtRewardsPoolOpt2Factory = await ethers.getContractFactory("YtRewardsPoolOpt2");
    const YtRewardsPoolOpt2 = await YtRewardsPoolOpt2Factory.deploy(await mockVault.getAddress(), await time.latest() + 62);
    ytRewardsPool = YtRewardsPoolOpt2__factory.connect(await YtRewardsPoolOpt2.getAddress(), ethers.provider);

    rewardsToken = await makeToken(await protocol.getAddress(), "ERC20 Mock", "MockERC20", 18);
    rewardsToken2 = await makeToken(await protocol.getAddress(), "ERC20 Mock", "MockERC20", 8);

    await expect(rewardsToken.connect(Alice).mint(Alice.address, ethers.parseUnits("1000000000000000000", await rewardsToken.decimals()))).not.to.be.reverted;
    await expect(rewardsToken2.connect(Alice).mint(Alice.address, ethers.parseUnits("1000000000000000000", await rewardsToken2.decimals()))).not.to.be.reverted;
  });

  /**
   * second 0: Bob swaps for 10 YT
   * second +11 (+10s): Bob swaps for 20 YT
   * second +6 (+5s): Bob swaps for 30 YT
   * second +11 (+10s): Bob collects YT
   * second +9 (+5s): Caro swaps for 10 YT
   * second +13 (+10s): Caro collects YT
   * - second +5: Epoch ends
   * second +10? (+10s): Caro collects YT
   */
  it('YtRewardsPoolOpt2 Time Weighted YT Works', async () => {
    const [Alice, Bob, Caro] = await ethers.getSigners();

    // const rewardsToken = MockERC20__factory.connect(await mockVault.assetToken(), ethers.provider);

    // Cannot add rewards if no YT is staked
    await expect(rewardsToken.connect(Alice).approve(await mockVault.getAddress(), ethers.parseUnits("1", await rewardsToken.decimals()))).not.to.be.reverted;
    await expect(mockVault.connect(Alice).mockAddRewards(
      ytRewardsPool,
      await rewardsToken.getAddress(),
      ethers.parseUnits("1", await rewardsToken.decimals()))
    ).to.be.revertedWith('Cannot add rewards without YT staked');

    // Bob swaps for 10 YT
    let bobYTAmount = ethers.parseUnits('10');
    let trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Bob.address, bobYTAmount);
    await expect(trans).to.emit(ytRewardsPool, "YtSwapped").withArgs(Bob.address, bobYTAmount);
    let lastTimestamp1 = BigInt((await trans.getBlock())!.timestamp);
    
    expect(await ytRewardsPool.ytSum(Bob.address)).to.equal(bobYTAmount);
    expect(await ytRewardsPool.ytLastCollectTime(Bob.address)).to.equal(lastTimestamp1);
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(0);
    expect(await ytRewardsPool.totalSupply()).to.equal(0);

    // 10 seconds later, Bob swaps for 20 YT
    await time.increase(10);
    bobYTAmount = ethers.parseUnits('20');
    trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Bob.address, bobYTAmount);
    let lastTimestamp2 = BigInt((await trans.getBlock())!.timestamp);
    let ytSumBob = ethers.parseUnits('30');
    let ytTimeWeightedBob = (lastTimestamp2 - lastTimestamp1) * ethers.parseUnits('10');
    console.log(`ytTimeWeightedBob: ${lastTimestamp2 - lastTimestamp1} seconds passed, ${ethers.formatUnits(ytTimeWeightedBob, await rewardsToken.decimals())}`);

    expect(await ytRewardsPool.ytSum(Bob.address)).to.equal(ytSumBob);
    expect(await ytRewardsPool.ytLastCollectTime(Bob.address)).to.equal(lastTimestamp2);
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(ytTimeWeightedBob);
    expect(await ytRewardsPool.totalSupply()).to.equal(ytTimeWeightedBob);

    // 5 seconds later, Bob swaps for 30 YT
    await time.increase(5);
    bobYTAmount = ethers.parseUnits('30');
    trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Bob.address, bobYTAmount);
    lastTimestamp1 = BigInt((await trans.getBlock())!.timestamp);
    ytSumBob = ethers.parseUnits('60');
    ytTimeWeightedBob = ytTimeWeightedBob + (lastTimestamp1 - lastTimestamp2) * ethers.parseUnits('30');
    console.log(`ytTimeWeightedBob: ${lastTimestamp1 - lastTimestamp2} seconds passed, ${ethers.formatUnits(ytTimeWeightedBob, await rewardsToken.decimals())}`);
    await expect(trans).to.emit(ytRewardsPool, "TimeWeightedYtAdded").withArgs(Bob.address, (lastTimestamp1 - lastTimestamp2) * ethers.parseUnits('30'));

    expect(await ytRewardsPool.ytSum(Bob.address)).to.equal(ytSumBob);
    expect(await ytRewardsPool.ytLastCollectTime(Bob.address)).to.equal(lastTimestamp1);
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(ytTimeWeightedBob);
    expect(await ytRewardsPool.totalSupply()).to.equal(ytTimeWeightedBob);

    // 10 seconds laster, Bob collects rewards
    await time.increase(10);
    let ytCollectable = await ytRewardsPool.collectableYt(Bob.address);
    console.log(`ytTimeWeightedBob: ${ethers.formatUnits(ytCollectable[1], await rewardsToken.decimals())}`);
    trans = await ytRewardsPool.connect(Bob).collectYt();
    lastTimestamp2 = BigInt((await trans.getBlock())!.timestamp);
    ytTimeWeightedBob = ytTimeWeightedBob + (lastTimestamp2 - lastTimestamp1) * ethers.parseUnits('60');
    console.log(`ytTimeWeightedBob: ${lastTimestamp2 - lastTimestamp1} seconds passed, ${ethers.formatUnits(ytTimeWeightedBob, await rewardsToken.decimals())}`);
    await expect(trans).to.emit(ytRewardsPool, "TimeWeightedYtAdded").withArgs(Bob.address, (lastTimestamp2 - lastTimestamp1) * ethers.parseUnits('60'));

    expect(await ytRewardsPool.ytSum(Bob.address)).to.equal(ytSumBob);  // 60
    expect(await ytRewardsPool.ytLastCollectTime(Bob.address)).to.equal(lastTimestamp2);  // 11 + 6 + 11 = 28
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(ytTimeWeightedBob);  // 950
    expect(await ytRewardsPool.totalSupply()).to.equal(ytTimeWeightedBob);

    console.log(`Epoch end in seconds: ${await ytRewardsPool.epochEndTimestamp() - lastTimestamp2}`);  // 27

    // Deposit 10000 $rewardsToken as rewards
    let totalRewards = ethers.parseUnits('10000', await rewardsToken.decimals());
    await expect(ytRewardsPool.connect(Alice).addRewards(await rewardsToken.getAddress(), totalRewards)).to.be.revertedWith("Caller is not Vault");
    await expect(rewardsToken.connect(Alice).approve(await mockVault.getAddress(), totalRewards)).not.to.be.reverted;
    trans = await mockVault.connect(Alice).mockAddRewards(ytRewardsPool, await rewardsToken.getAddress(), totalRewards);
    await expect(trans)
      .to.emit(ytRewardsPool, 'RewardsTokenAdded').withArgs(await rewardsToken.getAddress())
      .to.emit(ytRewardsPool, 'RewardsAdded').withArgs(await rewardsToken.getAddress(), totalRewards);
    await expect(trans).to.changeTokenBalances(
      rewardsToken,
      [Alice.address, await ytRewardsPool.getAddress()],
      [-totalRewards, totalRewards]
    );

    // Bob get all the rewards
    expectBigNumberEquals(totalRewards, await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress()));

    // Caro could collect YT, but nothing collected
    ytCollectable = await ytRewardsPool.collectableYt(Caro.address);
    expect(ytCollectable[1]).to.equal(0);
    await expect(ytRewardsPool.connect(Caro).collectYt()).not.to.be.reverted;

    // 5 seconds later, Caro swaps for 10 YT
    await time.increase(5);
    let caroYTAmount = ethers.parseUnits('10');
    let ytSumCaro = ethers.parseUnits('10');
    trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Caro.address, caroYTAmount);
    await expect(trans).to.emit(ytRewardsPool, "YtSwapped").withArgs(Caro.address, caroYTAmount);
    let lastTimestamp3 = BigInt((await trans.getBlock())!.timestamp);
    console.log(`${lastTimestamp3 - lastTimestamp2} seconds passed, Caro swapped for 10 YT`);  // 9 seconds
    console.log(`Epoch end in seconds: ${await ytRewardsPool.epochEndTimestamp() - lastTimestamp3}`);  // 18 seconds
    
    expect(await ytRewardsPool.ytSum(Caro.address)).to.equal(caroYTAmount);
    expect(await ytRewardsPool.ytLastCollectTime(Caro.address)).to.equal(lastTimestamp3);
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(0);

    expect((await ytRewardsPool.collectableYt(Bob.address))[1]).to.equal(ethers.parseUnits((60 * 9) + "", await rewardsToken.decimals()));
    expect((await ytRewardsPool.collectableYt(Caro.address))[1]).to.equal(0);

    // Alice add rewardsToken2 rewards, and Bob still get all the rewards
    let token2Rewards = ethers.parseUnits('3000', await rewardsToken2.decimals());
    await expect(rewardsToken2.connect(Alice).approve(await mockVault.getAddress(), token2Rewards)).not.to.be.reverted;
    trans = await mockVault.connect(Alice).mockAddRewards(ytRewardsPool, await rewardsToken2.getAddress(), token2Rewards);
    await expect(trans)
      .to.emit(ytRewardsPool, 'RewardsTokenAdded').withArgs(await rewardsToken2.getAddress())
      .to.emit(ytRewardsPool, 'RewardsAdded').withArgs(await rewardsToken2.getAddress(), token2Rewards);
    await expect(trans).to.changeTokenBalances(
      rewardsToken2,
      [Alice.address, await ytRewardsPool.getAddress()],
      [-token2Rewards, token2Rewards]
    );
    expectBigNumberEquals(token2Rewards, await ytRewardsPool.earned(Bob.address, await rewardsToken2.getAddress()));
    expect(await ytRewardsPool.earned(Caro.address, await rewardsToken2.getAddress())).to.equal(0);

    // 10 seconds later, Caro collect YT
    await time.increase(10);
    trans = await ytRewardsPool.connect(Caro).collectYt();
    let lastTimestamp4 = BigInt((await trans.getBlock())!.timestamp);  // 13 seconds
    let ytTimeWeightedCaro =  (lastTimestamp4 - lastTimestamp3) * ethers.parseUnits('10');
    console.log(`ytTimeWeightedCaro: ${lastTimestamp4 - lastTimestamp3} seconds passed, ${ethers.formatUnits(ytTimeWeightedCaro, await rewardsToken.decimals())}`);
    await expect(trans).to.emit(ytRewardsPool, "TimeWeightedYtAdded").withArgs(Caro.address, (lastTimestamp4 - lastTimestamp3) * ethers.parseUnits('10'));
    console.log(`Epoch end in seconds: ${await ytRewardsPool.epochEndTimestamp() - lastTimestamp4}`);  // 5 seconds

    expect(await ytRewardsPool.ytSum(Bob.address)).to.equal(ytSumBob);  // 60
    expect(await ytRewardsPool.ytSum(Caro.address)).to.equal(ytSumCaro);  // 10
    expect(await ytRewardsPool.ytLastCollectTime(Bob.address)).to.equal(lastTimestamp2);  // 11 + 6 + 11 = 28
    expect(await ytRewardsPool.ytLastCollectTime(Caro.address)).to.equal(lastTimestamp4);  // 11 + 6 + 11 + 13
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(ytTimeWeightedBob);  // 950
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(ytTimeWeightedCaro);  // 130
    expect(await ytRewardsPool.totalSupply()).to.equal(ytTimeWeightedBob + ytTimeWeightedCaro);

    // 10 seconds later, Caro collect YT. It's truncated to epoch ends (+5s)
    let epochEndTimestamp = await ytRewardsPool.epochEndTimestamp();
    await time.increase(10);
    let ytCollectableCaro = await ytRewardsPool.collectableYt(Caro.address);
    expect(ytCollectableCaro[0]).to.equal(epochEndTimestamp);
    expect(ytCollectableCaro[1]).to.equal(ethers.parseUnits((10 * 5) + "", await rewardsToken.decimals()));  // 50

    let ytCollectableBob = await ytRewardsPool.collectableYt(Bob.address);
    expect(ytCollectableBob[0]).to.equal(epochEndTimestamp);
    expect(ytCollectableBob[1]).to.equal(ethers.parseUnits((60 * (9 + 13 + 5)) + "", await rewardsToken.decimals()));  // 1620

    trans = await ytRewardsPool.connect(Caro).collectYt();
    lastTimestamp2 = BigInt((await trans.getBlock())!.timestamp);
    ytTimeWeightedCaro = ytTimeWeightedCaro + (epochEndTimestamp - lastTimestamp4) * ethers.parseUnits('10');
    console.log(`ytTimeWeightedCaro: ${epochEndTimestamp - lastTimestamp4} seconds passed, ${ethers.formatUnits(ytTimeWeightedCaro, await rewardsToken.decimals())}`);
    await expect(trans).to.emit(ytRewardsPool, "TimeWeightedYtAdded").withArgs(Caro.address, ethers.parseUnits('50'));

    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(ytTimeWeightedBob);  // 950
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(ytTimeWeightedCaro);  // 180

    // Bob claimed all rewards
    expect(await ytRewardsPool.earned(Caro.address, await rewardsToken.getAddress())).to.equal(0);
    expect(await ytRewardsPool.earned(Caro.address, await rewardsToken2.getAddress())).to.equal(0);
    trans = await ytRewardsPool.connect(Bob).getRewards();
    expect(await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress())).to.equal(0);
    expect(await ytRewardsPool.earned(Bob.address, await rewardsToken2.getAddress())).to.equal(0);

    // Epoch ends. 10 seconds later, Bob swaps for 100 YT. But only cause previous YT collected (60 YT and 9 + 13 +5 = 27 seconds)
    await time.increase(10);
    bobYTAmount = ethers.parseUnits('100');
    trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Bob.address, bobYTAmount);
    ytSumBob = ethers.parseUnits((60 + 100) + "");
    ytTimeWeightedBob = ytTimeWeightedBob + (9n + 13n + 5n) * ethers.parseUnits('60');
    console.log(`ytTimeWeightedBob: ${9n + 13n + 5n} seconds passed, ${ethers.formatUnits(ytTimeWeightedBob, await rewardsToken.decimals())}`);
    await expect(trans).to.emit(ytRewardsPool, "TimeWeightedYtAdded").withArgs(Bob.address, (9n + 13n + 5n) * ethers.parseUnits('60'));

    expect(await ytRewardsPool.ytSum(Bob.address)).to.equal(ytSumBob);
    expect(await ytRewardsPool.ytLastCollectTime(Bob.address)).to.equal(epochEndTimestamp);
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(ytTimeWeightedBob);  // 950 + 1620 = 2570
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(ytTimeWeightedCaro);  // 180

    // 10 seconds later, Bob and Caro swaps for more YT, but no YT is collectable
    await time.increase(10);
    await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Bob.address, ethers.parseUnits('100'));
    await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Caro.address, ethers.parseUnits('100'));
    expect(await ytRewardsPool.collectableYt(Bob.address)).to.deep.equal([epochEndTimestamp, 0]);
    expect(await ytRewardsPool.collectableYt(Caro.address)).to.deep.equal([epochEndTimestamp, 0]);

    // New rewards added. Bob and Caro should get rewards proportionally
    const newBribes = ethers.parseUnits('30000');
    await expect(rewardsToken.connect(Alice).approve(await mockVault.getAddress(), newBribes)).not.to.be.reverted;
    await mockVault.connect(Alice).mockAddRewards(ytRewardsPool, await rewardsToken.getAddress(), newBribes);
    let iBGTBobBribes = newBribes * ytTimeWeightedBob / (ytTimeWeightedBob + ytTimeWeightedCaro);
    let iBGTCaroBribes = newBribes * ytTimeWeightedCaro / (ytTimeWeightedBob + ytTimeWeightedCaro);
    expectBigNumberEquals(iBGTBobBribes, await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress()));
    expectBigNumberEquals(iBGTCaroBribes, await ytRewardsPool.earned(Caro.address, await rewardsToken.getAddress()));
  });

});
