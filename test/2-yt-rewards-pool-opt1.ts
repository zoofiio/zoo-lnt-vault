import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { time, loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ONE_DAY_IN_SECS, deployContractsFixture, expectBigNumberEquals, makeToken } from './utils';
import { 
  MockVault, MockERC20,
  MockVault__factory,
  MockERC20__factory,
  YtRewardsPoolOpt1,
  YtRewardsPoolOpt1__factory
} from "../typechain";

describe('YtRewardsPoolOpt1', () => {

  let mockVault: MockVault;
  let ytRewardsPool: YtRewardsPoolOpt1;
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

    const YtRewardsPoolOpt1Factory = await ethers.getContractFactory("YtRewardsPoolOpt1");
    const YtRewardsPoolOpt1 = await YtRewardsPoolOpt1Factory.deploy(await mockVault.getAddress());
    ytRewardsPool = YtRewardsPoolOpt1__factory.connect(await YtRewardsPoolOpt1.getAddress(), ethers.provider);

    rewardsToken = await makeToken(await protocol.getAddress(), "ERC20 Mock", "MockERC20", 18);
    rewardsToken2 = await makeToken(await protocol.getAddress(), "ERC20 Mock", "MockERC20", 8);

    await expect(rewardsToken.connect(Alice).mint(Alice.address, ethers.parseUnits("1000000000000000000", await rewardsToken.decimals()))).not.to.be.reverted;
    await expect(rewardsToken2.connect(Alice).mint(Alice.address, ethers.parseUnits("1000000000000000000", await rewardsToken2.decimals()))).not.to.be.reverted;
  });

  it('YtRewardsPoolOpt1 works', async () => {
    const [Alice, Bob, Caro] = await ethers.getSigners();

    const genesisTime = (await time.latest()) + ONE_DAY_IN_SECS;

    // Cannot add rewards if no YT is staked
    await expect(rewardsToken.connect(Alice).approve(await mockVault.getAddress(), ethers.parseUnits("1", await rewardsToken.decimals()))).not.to.be.reverted;
    await expect(mockVault.connect(Alice).mockAddRewards(
      ytRewardsPool,
      await rewardsToken.getAddress(),
      ethers.parseUnits("1", await rewardsToken.decimals()))
    ).to.be.revertedWith('Cannot add rewards without YT staked');

    // Bob swaps for 800 YT, and Caro swaps for 200 YT
    let bobYTAmount = ethers.parseUnits('800');
    let caroYTAmount = ethers.parseUnits('200');
    await expect(ytRewardsPool.connect(Alice).notifyYtSwappedForUser(Bob.address, bobYTAmount)).to.be.revertedWith("Caller is not Vault");
    let trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Bob.address, bobYTAmount);
    await expect(trans).to.emit(ytRewardsPool, "YtSwapped").withArgs(Bob.address, bobYTAmount);
    trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Caro.address, caroYTAmount);
    await expect(trans).to.emit(ytRewardsPool, "YtSwapped").withArgs(Caro.address, caroYTAmount);
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(bobYTAmount);
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(caroYTAmount);
    expect(await ytRewardsPool.totalSupply()).to.equal(bobYTAmount + caroYTAmount);

    // Deposit 10000 $rewardsToken as rewards
    await time.increaseTo(genesisTime);
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

    // Bob should immediately get 4/5 rewards, and Caro should get 1/5 rewards
    expectBigNumberEquals(totalRewards * 4n / 5n, await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress()));
    expectBigNumberEquals(totalRewards * 1n / 5n, await ytRewardsPool.earned(Caro.address, await rewardsToken.getAddress()));

    // Bob claim rewards
    let bobRewards = totalRewards * 4n / 5n;
    let caroRewards = totalRewards * 1n / 5n;
    trans = await ytRewardsPool.connect(Bob).getRewards();
    await expect(trans)
      .to.emit(ytRewardsPool, 'RewardsPaid').withArgs(Bob.address, await rewardsToken.getAddress(), bobRewards);
    await expect(trans).to.changeTokenBalances(
      rewardsToken,
      [Bob.address, await ytRewardsPool.getAddress()],
      [bobRewards, -bobRewards]
    );
    expectBigNumberEquals(0n, await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress()));

    // Caro swaps for another 200 YT
    let caroYTAmount2 = ethers.parseUnits('200');
    caroYTAmount = caroYTAmount + caroYTAmount2;  // 400
    trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Caro.address, caroYTAmount2);
    await expect(trans).to.emit(ytRewardsPool, "YtSwapped").withArgs(Caro.address, caroYTAmount2);
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(bobYTAmount);
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(caroYTAmount);
    expect(await ytRewardsPool.totalSupply()).to.equal(bobYTAmount + caroYTAmount);
    
    // Add another round of rewards
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 5);
    const round2Rewards = ethers.parseUnits('30000');
    await expect(rewardsToken.connect(Alice).approve(await mockVault.getAddress(), round2Rewards)).not.to.be.reverted;
    trans = await mockVault.connect(Alice).mockAddRewards(ytRewardsPool, await rewardsToken.getAddress(), round2Rewards);
    await expect(trans)
      .to.emit(ytRewardsPool, 'RewardsAdded').withArgs(await rewardsToken.getAddress(), round2Rewards);
    await expect(trans).to.changeTokenBalances(
      rewardsToken,
      [Alice.address, await ytRewardsPool.getAddress()],
      [-round2Rewards, round2Rewards]
    );

    // Bob should get 2/3 rewards, and Caro should get 1/3 rewards
    let token1BobRewards = round2Rewards * 2n / 3n;  // 20000
    let token1CaroRewards = caroRewards + round2Rewards * 1n / 3n;  // 8000 + 10000
    expectBigNumberEquals(token1BobRewards, await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress()));
    expectBigNumberEquals(token1CaroRewards, await ytRewardsPool.earned(Caro.address, await rewardsToken.getAddress()));

    // Fast-forward to Day 9. Add new rewardsToken2 rewards
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 9);
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

    let token2BobRewards = token2Rewards * 2n / 3n;
    let token2CaroRewards = token2Rewards * 1n / 3n;
    expectBigNumberEquals(token2BobRewards, await ytRewardsPool.earned(Bob.address, await rewardsToken2.getAddress()));
    expectBigNumberEquals(token2CaroRewards, await ytRewardsPool.earned(Caro.address, await rewardsToken2.getAddress()));

    expect(await ytRewardsPool.rewardsTokens()).to.deep.equal([await rewardsToken.getAddress(), await rewardsToken2.getAddress()]);

    // Caro claims all rewards
    trans = await ytRewardsPool.connect(Caro).getRewards();
    await expect(trans)
      .to.emit(ytRewardsPool, 'RewardsPaid').withArgs(Caro.address, await rewardsToken.getAddress(), token1CaroRewards)
      .to.emit(ytRewardsPool, 'RewardsPaid').withArgs(Caro.address, await rewardsToken2.getAddress(), token2CaroRewards);
    await expect(trans).to.changeTokenBalances(
      rewardsToken,
      [Caro.address, await ytRewardsPool.getAddress()],
      [token1CaroRewards, -token1CaroRewards]
    );
    await expect(trans).to.changeTokenBalances(
      rewardsToken2,
      [Caro.address, await ytRewardsPool.getAddress()],
      [token2CaroRewards, -token2CaroRewards]
    );
    expectBigNumberEquals(0n, await ytRewardsPool.earned(Caro.address, await rewardsToken.getAddress()));
    expectBigNumberEquals(0n, await ytRewardsPool.earned(Caro.address, await rewardsToken2.getAddress()));

    bobYTAmount = ethers.parseUnits('800');
    caroYTAmount = ethers.parseUnits('400');
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(bobYTAmount);
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(caroYTAmount);

    // Bob swaps for another 400 YT
    let bobYTAmount2 = ethers.parseUnits('400');
    bobYTAmount = ethers.parseUnits('1200');
    trans = await mockVault.connect(Alice).mockNotifyYtSwappedForUser(await ytRewardsPool.getAddress(), Bob.address, bobYTAmount2);
    await expect(trans).to.emit(ytRewardsPool, "YtSwapped").withArgs(Bob.address, bobYTAmount2);
    expect(await ytRewardsPool.balanceOf(Bob.address)).to.equal(bobYTAmount); // 1200
    expect(await ytRewardsPool.balanceOf(Caro.address)).to.equal(caroYTAmount);  // 400
    expect(await ytRewardsPool.totalSupply()).to.equal(bobYTAmount + caroYTAmount);  // 1600

    token1BobRewards = ethers.parseUnits('20000', await rewardsToken.decimals());
    token2BobRewards = ethers.parseUnits('2000', await rewardsToken2.decimals());
    expectBigNumberEquals(token1BobRewards, await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress()));
    expectBigNumberEquals(token2BobRewards, await ytRewardsPool.earned(Bob.address, await rewardsToken2.getAddress()));

    // Fast-forward to Day 10. Add new rewardsToken rewards
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 10);
    let token1Rewards = ethers.parseUnits('1600', await rewardsToken.decimals());
    await expect(rewardsToken.connect(Alice).approve(await mockVault.getAddress(), token1Rewards)).not.to.be.reverted;
    trans = await mockVault.connect(Alice).mockAddRewards(ytRewardsPool, await rewardsToken.getAddress(), token1Rewards);
    await expect(trans)
      .to.emit(ytRewardsPool, 'RewardsAdded').withArgs(await rewardsToken.getAddress(), token1Rewards);
    await expect(trans).to.changeTokenBalances(
      rewardsToken,
      [Alice.address, await ytRewardsPool.getAddress()],
      [-token1Rewards, token1Rewards]
    );

    token1BobRewards = ethers.parseUnits('21200', await rewardsToken.decimals());
    token2BobRewards = ethers.parseUnits('2000', await rewardsToken2.decimals());
    expectBigNumberEquals(token1BobRewards, await ytRewardsPool.earned(Bob.address, await rewardsToken.getAddress()));
    expectBigNumberEquals(token2BobRewards, await ytRewardsPool.earned(Bob.address, await rewardsToken2.getAddress()));

    token1CaroRewards = ethers.parseUnits('400', await rewardsToken.decimals());
    token2CaroRewards = 0n;
    expectBigNumberEquals(token1CaroRewards, await ytRewardsPool.earned(Caro.address, await rewardsToken.getAddress()));
    expectBigNumberEquals(token2CaroRewards, await ytRewardsPool.earned(Caro.address, await rewardsToken2.getAddress()));

  });

});
