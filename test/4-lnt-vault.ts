import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { 
  deployContractsFixture, ONE_DAY_IN_SECS, expectNumberEquals, expectBigNumberEquals, makeToken,
  calcClaimedVt, calcBurnedVt, expectedY, expectedInitSwapParams, expectedCalcSwap, SETTINGS_DECIMALS
} from './utils';
import { 
  NftStakingPool__factory,
  VToken__factory,
  YtRewardsPoolOpt1__factory,
  YtRewardsPoolOpt2__factory
} from "../typechain";
import { encodeBytes32String, formatUnits, parseUnits } from 'ethers';

const { provider } = ethers;

const BigNumber = require('bignumber.js');

describe('LNT Vault', () => {

  beforeEach(async () => {
    const { nftToken, Alice, Bob, Caro } = await loadFixture(deployContractsFixture);

    nftToken.connect(Alice).safeMint(Alice.address, 1);
    nftToken.connect(Alice).safeMint(Alice.address, 2);
    nftToken.connect(Alice).safeMint(Alice.address, 3);
    nftToken.connect(Alice).safeMint(Bob.address, 4);
    nftToken.connect(Alice).safeMint(Bob.address, 5);
    nftToken.connect(Alice).safeMint(Bob.address, 6);
    nftToken.connect(Alice).safeMint(Caro.address, 7);
    nftToken.connect(Alice).safeMint(Caro.address, 8);
    nftToken.connect(Alice).safeMint(Caro.address, 9);
  });

  it('LNT Vault basic E2E works', async () => {
    const { protocol, settings, vault, nftStakingPoolFactory, ytRewardsPoolFactory, nftToken, nftVestingToken, Alice, Bob, Caro } = await loadFixture(deployContractsFixture);
    const vToken = VToken__factory.connect(await vault.vToken(), ethers.provider);

    await settings.connect(Alice).updateVaultParamValue(await vault.getAddress(), ethers.encodeBytes32String("f1"), 10 ** 9); // 10%
    await settings.connect(Alice).updateVaultParamValue(await vault.getAddress(), ethers.encodeBytes32String("f2"), 10 ** 9); // 10%

    const genesisTime = await time.latest();
    let currentEpochId = 0;

    /**
     * Day 0:
     *  Alice deposits NFT 1 & 2
     *  Bob deposits NFT 4
     */
    await expect(vault.connect(Alice).depositNft(4)).to.be.revertedWith(/Not owner of NFT/);
    await expect(nftToken.connect(Alice).approve(await vault.getAddress(), 1)).not.to.be.reverted;
    let trans = await vault.connect(Alice).depositNft(1);
    await expect(trans)
      .to.emit(vault, 'NftDeposit').withArgs(currentEpochId, Alice.address, 1);
    await expect(trans).to.changeTokenBalances(
      nftToken,
      [Alice.address, await vault.getAddress()],
      [-1, 1]
    );
    // cann't deposit same nft again
    await expect(vault.connect(Alice).depositNft(1)).to.be.revertedWith(/Not owner of NFT/);
    // deposit another nft
    await expect(nftToken.connect(Alice).approve(await vault.getAddress(), 2)).not.to.be.reverted;
    await expect(vault.connect(Alice).depositNft(2)).not.to.be.reverted;
    // Bob deposits NFT 4
    await expect(nftToken.connect(Bob).setApprovalForAll(await vault.getAddress(), true)).not.to.be.reverted;
    await expect(vault.connect(Bob).depositNft(4)).not.to.be.reverted;

    /**
     * Day 1: Alice initialize the vault
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS);
    const EpochDuration = 10 * ONE_DAY_IN_SECS;
    const NftVtAmount = ethers.parseUnits("10000", await nftVestingToken.decimals());  // 10000 $VT per NFT
    const NftVestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 4, Day 104]
    const NftVestingEndTime = genesisTime + ONE_DAY_IN_SECS * 4 + NftVestingDuration;
    const YtSwapPaymentToken = await makeToken(await protocol.getAddress(), "Mock USDT", "USDT", 6);
    const YtSwapPrice = 10 ** 9;  // (10 ** 9) / (10 ** 10) = 0.1; meaning 1 $YT = 0.1 $USDT
    trans = await vault.connect(Alice).initialize(EpochDuration, NftVtAmount, NftVestingEndTime, NftVestingDuration, await YtSwapPaymentToken.getAddress(), YtSwapPrice);
    await expect(trans)
      .to.emit(vault, 'Initialized');
    await expect(vault.connect(Alice).initialize(EpochDuration, NftVtAmount, NftVestingEndTime, NftVestingDuration, await YtSwapPaymentToken.getAddress(), YtSwapPrice)).to.be.revertedWith(/Already initialized/);

    /**
     * Day 2: Could not claim deposit before Leading Time
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 2);
    await expect(vault.connect(Alice).claimDepositNft(1)).to.be.revertedWith(/Not claimable yet/);
    await expect(vault.connect(Bob).claimDepositNft(1)).to.be.revertedWith(/Not owner of NFT/);
    // Could not redeem unclaimed deposit
    await expect(vault.connect(Alice).redeemNft(1)).to.be.revertedWith(/Not claimed deposit yet/);

    /**
     * Day 3 + 10 seconds: Alice claims deposit 1
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 3 + 10);
    trans = await vault.connect(Alice).claimDepositNft(1);
    let transTime = BigInt((await trans.getBlock())!.timestamp);
    let result = await calcClaimedVt(vault, 1n);
    console.log(`Alice claim deposit nft 1, $VT: ${ethers.formatUnits(result.netVtAmount, await vToken.decimals())}, fees: ${ethers.formatUnits(result.fees, await vToken.decimals())}`);
    await expect(trans)
      .to.emit(vault, 'VTokenMinted').withArgs(Alice.address, 1, result.netVtAmount, result.fees)
      .to.emit(vault, 'NftDepositClaimed').withArgs(currentEpochId, Alice.address, 1);
    await expect(trans).to.changeTokenBalances(
      vToken,
      [Alice.address, await settings.treasury()],
      [result.netVtAmount, result.fees]
    );
    // Check nft staking pool
    let nftStakingPool = NftStakingPool__factory.connect(await vault.nftStakingPool(), provider);
    expect(await nftStakingPool.balanceOf(Alice.address)).to.equal(1);

    /**
     * Day 5: Alice start epoch 1
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 5);
    trans = await vault.connect(Alice).startEpoch1();
    transTime = BigInt((await trans.getBlock())!.timestamp);
    currentEpochId = 1;
    await expect(trans)
      .to.emit(vault, 'EpochStarted').withArgs(currentEpochId, transTime, EpochDuration);
    
    // Should have 1 $YT
    expect(await vault.yTokenTotalSupply(currentEpochId)).to.equal(ethers.parseUnits("1", await vault.ytDecimals()));

    /**
     *  Alice claim deposits NFT 2
     *  Bob claim deposits NFT 4
     */
    await expect(vault.connect(Alice).claimDepositNft(1)).to.be.revertedWith(/Already claimed/);
    await expect(vault.connect(Alice).claimDepositNft(2)).not.to.be.reverted;
    await expect(vault.connect(Bob).claimDepositNft(4)).not.to.be.reverted;
    expect(await nftStakingPool.balanceOf(Alice.address)).to.equal(2);
    expect(await nftStakingPool.balanceOf(Bob.address)).to.equal(1);
    expect(await nftStakingPool.totalSupply()).to.equal(3);

    /**
     * Day 16:
     *  Alice redeems NFT 2, and automatically start a new epoch
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 16);
    trans = await vault.connect(Alice).redeemNft(2);
    transTime = BigInt((await trans.getBlock())!.timestamp);
    currentEpochId = 2;
    const vtBurnAmount = await calcBurnedVt(vault, 2n);
    console.log(`Alice redeem nft 2, need burn $VT: ${ethers.formatUnits(vtBurnAmount, await vToken.decimals())}`);
    await expect(trans)
      .to.emit(vault, 'NftRedeem').withArgs(currentEpochId, Alice.address, 2)
      .to.emit(vault, 'VTokenBurned').withArgs(Alice.address, 2, vtBurnAmount);
    await expect(trans).to.changeTokenBalances(
      vToken,
      [Alice.address],
      [-vtBurnAmount]
    );
    expect(await nftStakingPool.balanceOf(Alice.address)).to.equal(1);
    expect(await nftStakingPool.totalSupply()).to.equal(2);

    // 7 days later, could not claim redeem yet. Need wait to next epoch
    await time.increase(7 * ONE_DAY_IN_SECS + 100);
    await expect(vault.connect(Alice).claimRedeemNft(2)).to.be.revertedWith(/Not claimable yet/);

    /**
     * Day 27:
     *  Epoch 2 ends. Alice claims redeem NFT 2, and auto start epoch 3
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 27);
    trans = await vault.connect(Alice).claimRedeemNft(2);
    transTime = BigInt((await trans.getBlock())!.timestamp);
    currentEpochId = 3;
    await expect(trans)
      .to.emit(vault, 'NftRedeemClaimed').withArgs(currentEpochId, Alice.address, 2);
    await expect(trans).to.changeTokenBalances(
      nftToken,
      [Alice.address, await vault.getAddress()],
      [1, -1]
    );
    // Should have 2 $YT
    expect(await vault.yTokenTotalSupply(currentEpochId)).to.equal(ethers.parseUnits("2", await vault.ytDecimals()));

    // Now Alice could deposit NFT 2 again
    await expect(nftToken.connect(Alice).setApprovalForAll(await vault.getAddress(), true)).not.to.be.reverted;
    await expect(vault.connect(Alice).depositNft(2)).not.to.be.reverted;

    /**
     * Test nft vesting token
     */
    const aliceVtBalance = await vToken.balanceOf(Alice.address);
    const bobVtBalance = await vToken.balanceOf(Bob.address);
    console.log(`Alice $VT balance: ${ethers.formatUnits(aliceVtBalance, await vToken.decimals())}, Bob $VT balance: ${ethers.formatUnits(bobVtBalance, await vToken.decimals())}`);

    const totalNftVestingTokenAmount = ethers.parseUnits("1000000", await nftVestingToken.decimals());
    await expect(nftVestingToken.connect(Alice).mint(await vault.getAddress(), totalNftVestingTokenAmount)).not.to.be.reverted;

    // Admin could withdraw NFT vesting token from Vault
    await expect(vault.connect(Bob).withdrawNftVestingToken(totalNftVestingTokenAmount)).to.be.revertedWith(/Ownable: caller is not the owner/);
    await expect(vault.connect(Alice).withdrawNftVestingToken(totalNftVestingTokenAmount)).not.to.be.reverted;

    const nftVestingTokenClaimAmount = ethers.parseUnits("1000", await nftVestingToken.decimals());
    await expect(vault.connect(Alice).claimNftVestingToken(nftVestingTokenClaimAmount)).to.be.revertedWith(/Insufficient token balance/);

    await expect(nftVestingToken.connect(Alice).approve(await vault.getAddress(), nftVestingTokenClaimAmount)).not.to.be.reverted;
    trans = await vault.connect(Alice).depositNftVestingToken(nftVestingTokenClaimAmount);
    await expect(trans)
      .to.emit(vault, 'NftVestingTokenDeposite').withArgs(Alice.address, nftVestingTokenClaimAmount);
    await expect(trans).to.changeTokenBalances(
      nftVestingToken,
      [Alice.address, await vault.getAddress()],
      [-nftVestingTokenClaimAmount, nftVestingTokenClaimAmount]
    );

    trans = await vault.connect(Bob).claimNftVestingToken(nftVestingTokenClaimAmount);
    await expect(trans)
      .to.emit(vault, 'NftVestingTokenClaimed').withArgs(Bob.address, nftVestingTokenClaimAmount);
    await expect(trans).to.changeTokenBalances(
      nftVestingToken,
      [Bob.address, await vault.getAddress()],
      [nftVestingTokenClaimAmount, -nftVestingTokenClaimAmount]
    );
    await expect(trans).to.changeTokenBalances(
      vToken,
      [Bob.address],
      [-nftVestingTokenClaimAmount]
    );
  });

  it('Swap works', async () => {
    const { protocol, settings, vault, nftToken, nftVestingToken, Alice, Bob, Caro } = await loadFixture(deployContractsFixture);
    const vToken = VToken__factory.connect(await vault.vToken(), ethers.provider);
    const nftStakingPool = NftStakingPool__factory.connect(await vault.nftStakingPool(), provider);

    await settings.connect(Alice).updateVaultParamValue(await vault.getAddress(), ethers.encodeBytes32String("f1"), 10 ** 9); // 10%
    await settings.connect(Alice).updateVaultParamValue(await vault.getAddress(), ethers.encodeBytes32String("f2"), 10 ** 9); // 10%

    const genesisTime = await time.latest();
    let currentEpochId = 0;

    /**
     * Day 0:
     *  Alice deposits NFT 1 & 2
     *  Bob deposits NFT 4
     */
    await expect(nftToken.connect(Alice).setApprovalForAll(await vault.getAddress(), true)).not.to.be.reverted;
    await expect(nftToken.connect(Bob).setApprovalForAll(await vault.getAddress(), true)).not.to.be.reverted;

    await expect(vault.connect(Alice).depositNft(1)).not.to.be.reverted;
    await expect(vault.connect(Alice).depositNft(2)).not.to.be.reverted;
    await expect(vault.connect(Bob).depositNft(4)).not.to.be.reverted;

    /**
     * Day 1: Alice initialize the vault
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS);
    const EpochDuration = 10 * ONE_DAY_IN_SECS;
    const NftVtAmount = ethers.parseUnits("10000", await nftVestingToken.decimals());  // 10000 $VT per NFT
    const NftVestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 4, Day 104]
    const NftVestingEndTime = genesisTime + ONE_DAY_IN_SECS * 4 + NftVestingDuration;
    let YtSwapPaymentToken = await makeToken(await protocol.getAddress(), "Mock USDT", "USDT", 6);
    let YtSwapPrice = 10 ** 9;  // (10 ** 9) / (10 ** 10) = 0.1; meaning 1 $YT = 0.1 $USDT
    await expect(vault.connect(Bob).initialize(EpochDuration, NftVtAmount, NftVestingEndTime, NftVestingDuration, await YtSwapPaymentToken.getAddress(), YtSwapPrice)).to.be.revertedWith(/Ownable: caller is not the owner/);
    await expect(vault.connect(Alice).initialize(EpochDuration, NftVtAmount, NftVestingEndTime, NftVestingDuration, await YtSwapPaymentToken.getAddress(), YtSwapPrice)).not.to.be.reverted;

    /**
     * Day 3 + 10 seconds: Alice & Bob claim their deposits
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 3 + 10);
    await expect(vault.connect(Alice).claimDepositNft(1)).not.to.be.reverted;
    await expect(vault.connect(Alice).claimDepositNft(2)).not.to.be.reverted;
    await expect(vault.connect(Bob).claimDepositNft(4)).not.to.be.reverted;

    /**
     * Day 5: Alice start epoch 1. Should have 3 $YT
     */
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 5);
    await expect(vault.connect(Alice).startEpoch1()).not.to.be.reverted;
    currentEpochId = 1;
    let epochInfo = await vault.epochInfoById(currentEpochId);
    expect(await vault.yTokenTotalSupply(currentEpochId)).to.equal(ethers.parseUnits("3", await vault.ytDecimals()));

    const ytDecimals = await vault.ytDecimals();
    const ytPriceDecimals = SETTINGS_DECIMALS;
    const YtSwapPaymentTokenDecimals = await YtSwapPaymentToken.decimals();

    let result = await expectedInitSwapParams(vault, 3, (Number)(ethers.formatUnits(epochInfo.ytSwapPrice, ytPriceDecimals)));
    let actualX = await vault.epochNextSwapX(currentEpochId);
    let actualK0 = await vault.epochNextSwapK0(currentEpochId);
    expectBigNumberEquals(parseUnits(result.X + "", ytDecimals), actualX);
    expectBigNumberEquals(parseUnits(result.k0 + "", ytDecimals + YtSwapPaymentTokenDecimals + ytPriceDecimals), actualK0);

    // check Y
    let actualY = await vault.Y();
    let expectedYValue = await expectedY(vault);
    expectBigNumberEquals(ethers.parseUnits(expectedYValue + "", YtSwapPaymentTokenDecimals), actualY);

    /**
     * $YT: 3; Price: 0.1 $USDT per $YT
     * Bob swaps 0.05 $USDT for $YT
     */
    let swapAssetAmount = ethers.parseUnits("0.05", await YtSwapPaymentToken.decimals());
    let swapResult = await expectedCalcSwap(vault, 0.05);  // X_updated: 2.5714285714285716, m: 0.4285714285714284
    let actualResult = await vault.calcSwap(swapAssetAmount);
    expectBigNumberEquals(parseUnits(swapResult.X_updated + "", await vault.ytDecimals()), actualResult[0]);
    expectBigNumberEquals(parseUnits(swapResult.m + "", await vault.ytDecimals()), actualResult[1]);
    
    let f2 = await vault.paramValue(encodeBytes32String("f2"));
    let fees = swapAssetAmount * f2 / (10n ** SETTINGS_DECIMALS);

    await expect(YtSwapPaymentToken.connect(Alice).mint(Bob.address, swapAssetAmount)).not.to.be.reverted;
    await expect(YtSwapPaymentToken.connect(Bob).approve(await vault.getAddress(), swapAssetAmount)).not.to.be.reverted;
    actualResult = await vault.calcSwap(swapAssetAmount - fees);
    let trans = await vault.connect(Bob).swap(swapAssetAmount);
    const ytBobAmount = actualResult[1];
    expectBigNumberEquals(ytBobAmount, await vault.yTokenUserBalance(currentEpochId, Bob.address));
    await expect(trans).to.changeTokenBalances(
      YtSwapPaymentToken,
      [Bob.address, await vault.nftStakingPool(), await settings.treasury()],
      [-swapAssetAmount, swapAssetAmount - fees, fees]
    );
    await expect(trans)
      .to.emit(vault, "Swap").withArgs(currentEpochId, Bob.address, swapAssetAmount, fees, anyValue)
      .to.emit(nftStakingPool, "RewardsTokenAdded").withArgs(await YtSwapPaymentToken.getAddress())
      .to.emit(nftStakingPool, "RewardsAdded").withArgs(await YtSwapPaymentToken.getAddress(), swapAssetAmount - fees);
    // Alice should get 2/3 of the rewards, and Bob get 1/3
    let ytTotalRewards = swapAssetAmount - fees;
    expect(await nftStakingPool.earned(Alice.address, await YtSwapPaymentToken.getAddress())).to.equal(ytTotalRewards * 2n / 3n);
    expect(await nftStakingPool.earned(Bob.address, await YtSwapPaymentToken.getAddress())).to.equal(ytTotalRewards * 1n / 3n);
    await expect(nftStakingPool.connect(Alice).getRewards()).not.to.be.reverted;
    await expect(nftStakingPool.connect(Bob).getRewards()).not.to.be.reverted;
    // Check yt balance in yt rewards pool
    await time.increase(60);
    let ytRewardsPoolOpt1 = YtRewardsPoolOpt1__factory.connect(epochInfo.ytRewardsPoolOpt1, provider);
    let ytRewardsPoolOpt2 = YtRewardsPoolOpt2__factory.connect(epochInfo.ytRewardsPoolOpt2, provider);
    expect(await ytRewardsPoolOpt1.balanceOf(Bob.address)).to.equal(await vault.yTokenUserBalance(currentEpochId, Bob.address));
    expect((await ytRewardsPoolOpt2.collectableYt(Bob.address))[1]).to.be.gt(0);

    // k0 not changed.
    let yTokenBalance = await vault.yTokenUserBalance(currentEpochId, await vault.getAddress());
    console.log(`yToken balance: ${formatUnits(yTokenBalance, await vault.ytDecimals())}`);
    console.log(`k0 after swap: ${formatUnits(await vault.epochNextSwapK0(currentEpochId), ytDecimals + YtSwapPaymentTokenDecimals + ytPriceDecimals)}`);

    // X is changed
    console.log(`X after swap: ${formatUnits(await vault.epochNextSwapX(currentEpochId), ytDecimals)}`);

    /**
     * How about we use 10 $USDT to swap $YT?
     */
    swapAssetAmount = ethers.parseUnits("10", await YtSwapPaymentToken.decimals());
    swapResult = await expectedCalcSwap(vault, 10);
    actualResult = await vault.calcSwap(swapAssetAmount);
    expectBigNumberEquals(parseUnits(swapResult.X_updated + "", await vault.ytDecimals()), actualResult[0]);
    expectBigNumberEquals(parseUnits(swapResult.m + "", await vault.ytDecimals()), actualResult[1]);

    /**
     * Reinitialize with different swap payment token and price
     */
    console.log('Update YT swap payment token and price');
    YtSwapPaymentToken = await makeToken(await protocol.getAddress(), "Mock WETH", "WETH", 18);
    YtSwapPrice = 10 ** 8;  // (10 ** 8) / (10 ** 10) = 0.01; meaning 1 $YT = 0.01 $WETH
    await expect(vault.connect(Alice).initialize(EpochDuration, NftVtAmount, NftVestingEndTime, NftVestingDuration, await YtSwapPaymentToken.getAddress(), YtSwapPrice)).to.be.revertedWith(/Already initialized/);
    await expect(vault.connect(Alice).reInitialize(EpochDuration, NftVtAmount, NftVestingEndTime, NftVestingDuration, await YtSwapPaymentToken.getAddress(), YtSwapPrice))
      .to.emit(vault, "ReInitialized").withArgs(EpochDuration, NftVtAmount, NftVestingEndTime, NftVestingDuration, await YtSwapPaymentToken.getAddress(), YtSwapPrice);

    // Swap price of current epoch is not affected
    swapResult = await expectedCalcSwap(vault, 10);
    actualResult = await vault.calcSwap(swapAssetAmount);
    expectBigNumberEquals(parseUnits(swapResult.X_updated + "", await vault.ytDecimals()), actualResult[0]);
    expectBigNumberEquals(parseUnits(swapResult.m + "", await vault.ytDecimals()), actualResult[1]);

    /**
     * Day 17: Epoch 1 ends. Now YT swap price should be in $WETH
     */
    console.log(`Day 17: Epoch 2 starts`);
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 17);
    swapAssetAmount = ethers.parseUnits("0.5", await YtSwapPaymentToken.decimals());
    fees = swapAssetAmount * f2 / (10n ** SETTINGS_DECIMALS);
    swapResult = await expectedCalcSwap(vault, 0.5); 
    actualResult = await vault.calcSwap(swapAssetAmount);
    expectBigNumberEquals(parseUnits(swapResult.X_updated.toFixed(Number(await vault.ytDecimals())) + "", await vault.ytDecimals()), actualResult[0]);
    expectBigNumberEquals(parseUnits(swapResult.m.toFixed(Number(await vault.ytDecimals())) + "", await vault.ytDecimals()), actualResult[1]);

    // Caro swaps $WETH for $YT
    await expect(YtSwapPaymentToken.connect(Alice).mint(Caro.address, swapAssetAmount)).not.to.be.reverted;
    await expect(YtSwapPaymentToken.connect(Caro).approve(await vault.getAddress(), swapAssetAmount)).not.to.be.reverted;
    actualResult = await vault.calcSwap(swapAssetAmount - fees);
    trans = await vault.connect(Caro).swap(swapAssetAmount);
    currentEpochId = 2;
    const ytCaroAmount = actualResult[1];
    expectBigNumberEquals(ytCaroAmount, await vault.yTokenUserBalance(currentEpochId, Caro.address));
    await expect(trans).to.changeTokenBalances(
      YtSwapPaymentToken,
      [Caro.address, await vault.nftStakingPool(), await settings.treasury()],
      [-swapAssetAmount, swapAssetAmount - fees, fees]
    );
    await expect(trans)
      .to.emit(vault, "Swap").withArgs(currentEpochId, Caro.address, swapAssetAmount, fees, anyValue)
      .to.emit(nftStakingPool, "RewardsTokenAdded").withArgs(await YtSwapPaymentToken.getAddress())
      .to.emit(nftStakingPool, "RewardsAdded").withArgs(await YtSwapPaymentToken.getAddress(), swapAssetAmount - fees);
    // Alice should get 2/3 of the rewards, and Bob get 1/3
    ytTotalRewards = swapAssetAmount - fees;
    expect(await nftStakingPool.earned(Alice.address, await YtSwapPaymentToken.getAddress())).to.equal(ytTotalRewards * 2n / 3n);
    expect(await nftStakingPool.earned(Bob.address, await YtSwapPaymentToken.getAddress())).to.equal(ytTotalRewards * 1n / 3n);

    // Check yt balance in yt rewards pool
    await time.increase(60);
    epochInfo = await vault.epochInfoById(currentEpochId);
    ytRewardsPoolOpt1 = YtRewardsPoolOpt1__factory.connect(epochInfo.ytRewardsPoolOpt1, provider);
    ytRewardsPoolOpt2 = YtRewardsPoolOpt2__factory.connect(epochInfo.ytRewardsPoolOpt2, provider);
    expect(await ytRewardsPoolOpt1.balanceOf(Caro.address)).to.equal(await vault.yTokenUserBalance(currentEpochId, Caro.address));
    expect((await ytRewardsPoolOpt2.collectableYt(Caro.address))[1]).to.be.gt(0);

    /**
     * Check yt rewards
     */
    await expect(ytRewardsPoolOpt2.connect(Bob).collectYt()).not.to.be.reverted;
    await expect(ytRewardsPoolOpt2.connect(Caro).collectYt()).not.to.be.reverted;

    const ytRewardsToken1 = await makeToken(await protocol.getAddress(), "Mock Reward 1", "RWD1", 18);
    const ytRewardsToken2 = await makeToken(await protocol.getAddress(), "Mock Reward 2", "RWD2", 8);
    const ytRewards1 = ethers.parseUnits("10000", await ytRewardsToken1.decimals());
    const ytRewards2 = ethers.parseUnits("10000", await ytRewardsToken2.decimals());
    await expect(ytRewardsToken1.connect(Alice).mint(Alice.address, ytRewards1)).not.to.be.reverted;
    await expect(ytRewardsToken2.connect(Alice).mint(Alice.address, ytRewards2)).not.to.be.reverted;
    await expect(ytRewardsToken1.connect(Alice).approve(await vault.getAddress(), ytRewards1)).not.to.be.reverted;
    await expect(ytRewardsToken2.connect(Alice).approve(await vault.getAddress(), ytRewards2)).not.to.be.reverted;

    // Add $RWD1 and $RWD2 to yt rewards pool opt1
    trans = await vault.connect(Alice).addYtRewards(await ytRewardsToken1.getAddress(), ytRewards1 / 2n, 0);
    await expect(trans)
      .to.emit(ytRewardsPoolOpt1, "RewardsTokenAdded").withArgs(await ytRewardsToken1.getAddress())
      .to.emit(ytRewardsPoolOpt1, "RewardsAdded").withArgs(await ytRewardsToken1.getAddress(), ytRewards1 / 2n);
    await expect(trans).to.changeTokenBalances(
      ytRewardsToken1,
      [Alice.address, await ytRewardsPoolOpt1.getAddress()],
      [-ytRewards1 / 2n, ytRewards1 / 2n]
    );

    trans = await vault.connect(Alice).addYtRewards(await ytRewardsToken2.getAddress(), ytRewards2 / 4n, 0);
    await expect(trans)
      .to.emit(ytRewardsPoolOpt1, "RewardsTokenAdded").withArgs(await ytRewardsToken2.getAddress())
      .to.emit(ytRewardsPoolOpt1, "RewardsAdded").withArgs(await ytRewardsToken2.getAddress(), ytRewards2 / 4n);
    await expect(trans).to.changeTokenBalances(
      ytRewardsToken2,
      [Alice.address, await ytRewardsPoolOpt1.getAddress()],
      [-ytRewards2 / 4n, ytRewards2 / 4n]
    );

    trans = await vault.connect(Alice).addYtRewards(await ytRewardsToken1.getAddress(), ytRewards1 / 2n, 1);
    await expect(trans)
      .to.emit(ytRewardsPoolOpt2, "RewardsTokenAdded").withArgs(await ytRewardsToken1.getAddress())
      .to.emit(ytRewardsPoolOpt2, "RewardsAdded").withArgs(await ytRewardsToken1.getAddress(), ytRewards1 / 2n);
    await expect(trans).to.changeTokenBalances(
      ytRewardsToken1,
      [Alice.address, await ytRewardsPoolOpt2.getAddress()],
      [-ytRewards1 / 2n, ytRewards1 / 2n]
    );

    await expect(vault.connect(Alice).addYtRewards(await ytRewardsToken1.getAddress(), ytRewards1 / 3n, 3)).to.be.reverted;

  });

});
