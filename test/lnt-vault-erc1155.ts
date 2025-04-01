import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Signer, ZeroAddress } from 'ethers';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { 
  deployContractsFixture, deployContract, ONE_DAY_IN_SECS,
  calcMintedVt, calcBurnedVt,
  nativeTokenAddress
} from './utils';
import { 
  MockERC1155, MockERC1155__factory, LntVaultERC1155, LntVaultERC1155__factory,
  VestingToken, VestingToken__factory,
  LntMarketRouter, MockERC20, MockERC20__factory,
  LntContractFactory,
  LntMarketFactory,
} from "../typechain";
import { encodeBytes32String, formatUnits } from 'ethers';

const { provider } = ethers;

describe('LNTVaultERC1155', () => {

  let nft: MockERC1155;
  let lntVault: LntVaultERC1155;
  let vt: VestingToken;
  let lntMarketRouter: LntMarketRouter;
  let lntContractFactory: LntContractFactory;
  let lntMarketFactory: LntMarketFactory;
  
  // Token IDs for testing
  const tokenId1 = 1n;
  const tokenId2 = 2n;
  const tokenId3 = 3n;
  const tokenId4 = 4n;

  beforeEach(async () => {
    const { Alice, Bob, Caro, lntContractFactory: contractFactory, lntMarketFactory: marketFactory, lntMarketRouter: router } = await loadFixture(deployContractsFixture);
    lntMarketRouter = router;
    lntContractFactory = contractFactory;
    lntMarketFactory = marketFactory;

    const MockERC1155Factory = await ethers.getContractFactory("MockERC1155");
    const MockERC1155 = await MockERC1155Factory.connect(Bob).deploy();
    nft = MockERC1155__factory.connect(await MockERC1155.getAddress(), provider);

    const LntVaultERC1155Factory = await ethers.getContractFactory("LntVaultERC1155");
    let bytecode = LntVaultERC1155Factory.bytecode;
    let constructorArgs = (new ethers.AbiCoder()).encode(['address'], [Bob.address]);
    let vaultAddress = await deployContract(lntContractFactory, Bob, bytecode, constructorArgs);
    lntVault = LntVaultERC1155__factory.connect(vaultAddress, provider);

    const VestingTokenFactory = await ethers.getContractFactory("VestingToken");
    bytecode = VestingTokenFactory.bytecode;
    constructorArgs = (new ethers.AbiCoder()).encode(['address', 'string', 'string'], [vaultAddress, "LNT VT", "LNTVT"]);
    let vtAddress = await deployContract(lntContractFactory, Bob, bytecode, constructorArgs);
    vt = VestingToken__factory.connect(vtAddress, provider);

    // Mint tokens to users
    await nft.connect(Bob).mint(Alice.address, tokenId1, 10, "0x");
    await nft.connect(Bob).mint(Alice.address, tokenId2, 20, "0x");
    await nft.connect(Bob).mint(Alice.address, tokenId3, 30, "0x");
    await nft.connect(Bob).mint(Bob.address, tokenId1, 15, "0x");
    await nft.connect(Bob).mint(Bob.address, tokenId2, 25, "0x");
    await nft.connect(Bob).mint(Bob.address, tokenId3, 35, "0x");
    await nft.connect(Bob).mint(Caro.address, tokenId1, 5, "0x");
    await nft.connect(Bob).mint(Caro.address, tokenId2, 10, "0x");
    await nft.connect(Bob).mint(Caro.address, tokenId3, 15, "0x");
  });

  it('LNTVaultERC1155 deposit and redeem works', async () => {
    const [Alice, Bob, Caro] = await ethers.getSigners();

    // Check initial state
    expect(await lntVault.initialized()).to.equal(false);
    expect(await lntVault.owner()).to.equal(Bob.address);

    // Update settings
    await expect(lntVault.connect(Alice).updateParamValue(ethers.encodeBytes32String("f1"), 10 ** 9))
      .to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);
    await expect(lntVault.connect(Bob).updateParamValue(ethers.encodeBytes32String("f1"), 10 ** 9))
      .to.emit(lntVault, "UpdateParamValue")
      .withArgs(encodeBytes32String("f1"), 10 ** 9);

    // Cannot deposit before initialization
    await expect(lntVault.connect(Alice).deposit(tokenId1, 5)).to.be.revertedWith("Not initialized");

    const genesisTime = await time.latest();
    
    // Create vesting schedules for different token IDs
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    // Create vesting schedules for the tokens we'll use in tests
    const vestingSchedules = [
      {
        tokenId: tokenId1,
        weight: 1,  // Weight for this token ID (can be used for relative importance)
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId1
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId2,
        weight: 2,  // Higher weight for tokenId2
        vestingTokenAmountPerNft: ethers.parseUnits("1500", await vt.decimals()),  // 1500 $VT per NFT unit for tokenId2
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId3,
        weight: 3,  // Higher weight for tokenId3
        vestingTokenAmountPerNft: ethers.parseUnits("2000", await vt.decimals()),  // 2000 $VT per NFT unit for tokenId3
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      }
    ];
    
    // Only owner could initialize
    await expect(lntVault.connect(Alice).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).to.emit(lntVault, "Initialized");

    // Could not initialize again
    expect(await lntVault.initialized()).to.equal(true);
    expect(await lntVault.NFT()).to.equal(await nft.getAddress());
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).to.be.revertedWith("Already initialized");

    /**
     * Day 0:
     *  Alice deposits NFT token1 (5 units) & token2 (10 units)
     *  Bob deposits NFT token1 (3 units)
     */
    let currentDepositId = 1;
    await expect(lntVault.connect(Alice).deposit(tokenId1, 50)).to.be.revertedWith(/Insufficient balance/);
    await expect(nft.connect(Alice).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    
    let result = await calcMintedVt(lntVault, tokenId1, 5n);
    let trans = await lntVault.connect(Alice).deposit(tokenId1, 5);
    await expect(trans)
      .to.emit(lntVault, 'Deposit').withArgs(currentDepositId, Alice.address, await nft.getAddress(), tokenId1, 5)
      .to.emit(lntVault, 'VTMinted').withArgs(Alice.address, result.fees, result.netVtAmount);
    await expect(trans).to.changeTokenBalances(
      vt,
      [Alice.address, await lntContractFactory.treasury()],
      [result.netVtAmount, result.fees]
    );
    
    // Deposit another token
    await expect(lntVault.connect(Alice).deposit(tokenId2, 10)).not.to.be.reverted;
    
    // Bob deposits NFT token1
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(tokenId1, 3)).not.to.be.reverted;

    // Day 2: Alice redeems NFT token2
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 2);
    let depositId = 2n;
    expect((await lntVault.depositInfo(depositId)).tokenId).to.equal(tokenId2);
    expect((await lntVault.depositInfo(depositId)).value).to.equal(10);
    await expect(lntVault.connect(Bob).redeem(depositId, tokenId2, 10)).to.be.revertedWith(/Not user of deposit/);
    await expect(lntVault.connect(Alice).redeem(depositId, tokenId2, 20)).to.be.revertedWith(/Invalid value/);

    // Using correct token ID's VestingTokenAmountPerNft for calculation
    const expectedBurnedVtAmount = await calcBurnedVt(lntVault, depositId, tokenId2, 10n);
    trans = await lntVault.connect(Alice).redeem(depositId, tokenId2, 10n);
    await expect(trans)
      .to.emit(lntVault, 'Redeem').withArgs(depositId, Alice.address, await nft.getAddress(), tokenId2, 10n)
      .to.emit(lntVault, 'VTBurned').withArgs(Alice.address, anyValue);

    expect((await lntVault.depositInfo(depositId)).redeemed).to.equal(true);
    
    // Cannot redeem again
    await expect(lntVault.connect(Alice).redeem(depositId, tokenId2, 10)).to.be.revertedWith(/Already redeemed/);
  });

  it('LNTVaultERC1155 redeem ETH works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    const genesisTime = await time.latest();
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    // Create vesting schedules for the tokens we'll use
    const vestingSchedules = [
      {
        tokenId: tokenId1,
        weight: 1,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId1
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId2,
        weight: 1,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId2
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      }
    ];
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).not.to.be.reverted;

    /**
     * Day 0:
     *  Alice deposits NFT token1 (5 units)
     *  Bob deposits NFT token2 (5 units)
     */
    await expect(nft.connect(Alice).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(tokenId1, 5)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(tokenId2, 5)).not.to.be.reverted;

    // Cannot redeem with ETH before initialization T
    await expect(lntVault.connect(Alice).redeemT(1)).to.be.revertedWith("Not initialized T");

    // Only owner could initialize
    await expect(lntVault.connect(Alice).initializeT(
      nativeTokenAddress
    )).to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    await expect(lntVault.connect(Bob).initializeT(
      nativeTokenAddress
    )).to.emit(lntVault, "InitializedT");

    // Could not initialize again
    expect(await lntVault.initializedT()).to.equal(true);
    expect(await lntVault.T()).to.equal(nativeTokenAddress);
    await expect(lntVault.connect(Bob).initializeT(
      nativeTokenAddress
    )).to.be.revertedWith("Already initialized");

    // Could not redeem T before vesting ends
    await expect(lntVault.connect(Alice).redeemT(1)).to.be.revertedWith("Vesting not ended");

    // Day 102: Alice redeems T
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 102);

    const redeemAmount = ethers.parseUnits("2500", 18); // 5 units * 1000 $VT per unit * half = 2500
    await expect(lntVault.connect(Alice).redeemT(
      redeemAmount
    )).to.be.revertedWith("Insufficient token balance");

    // Bob transfers ETH to lntVault to simulate the vesting
    await expect(Bob.sendTransaction({ to: await lntVault.getAddress(), value: ethers.parseUnits("5000", 18) })).not.to.be.reverted;

    let tx = await lntVault.connect(Alice).redeemT(redeemAmount);
    await expect(tx)
      .to.emit(lntVault, 'RedeemT').withArgs(Alice.address, redeemAmount);
    await expect(tx).to.changeEtherBalances(
      [Alice, lntVault],
      [redeemAmount, -redeemAmount]
    );
    await expect(tx).to.changeTokenBalances(
      vt,
      [Alice],
      [-redeemAmount]
    );
  });

  it('LNTVaultERC1155 redeem ERC20 works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    // Create a MockERC20 token for testing
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const MockERC20 = await MockERC20Factory.connect(Bob).deploy("Mock Token", "MT", 18);
    const mockToken = MockERC20__factory.connect(await MockERC20.getAddress(), provider);
    
    // Mint tokens to Bob for later transfer to vault
    await mockToken.connect(Bob).mint(Bob.address, ethers.parseUnits("10000", 18));

    const genesisTime = await time.latest();
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    // Create vesting schedules for the tokens we'll use
    const vestingSchedules = [
      {
        tokenId: tokenId1,
        weight: 1,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId1
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId2,
        weight: 2,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId2
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      }
    ];
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).not.to.be.reverted;

    /**
     * Day 0:
     *  Alice deposits NFT token1 (5 units)
     *  Bob deposits NFT token2 (5 units)
     */
    await expect(nft.connect(Alice).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(tokenId1, 5)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(tokenId2, 5)).not.to.be.reverted;

    // Cannot redeem with ERC20 before initialization T
    await expect(lntVault.connect(Alice).redeemT(1)).to.be.revertedWith("Not initialized T");

    // Only owner could initialize
    await expect(lntVault.connect(Alice).initializeT(
      await mockToken.getAddress()
    )).to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    await expect(lntVault.connect(Bob).initializeT(
      await mockToken.getAddress()
    )).to.emit(lntVault, "InitializedT");

    // Could not initialize again
    expect(await lntVault.initializedT()).to.equal(true);
    expect(await lntVault.T()).to.equal(await mockToken.getAddress());
    await expect(lntVault.connect(Bob).initializeT(
      await mockToken.getAddress()
    )).to.be.revertedWith("Already initialized");

    // Could not redeem T before vesting ends
    await expect(lntVault.connect(Alice).redeemT(1)).to.be.revertedWith("Vesting not ended");

    // Day 102: Alice redeems T
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 102);

    const redeemAmount = ethers.parseUnits("2500", 18); // 5 units * 1000 $VT per unit * half = 2500
    await expect(lntVault.connect(Alice).redeemT(
      redeemAmount
    )).to.be.revertedWith("Insufficient token balance");

    // Bob transfers tokens to lntVault to simulate the vesting
    await expect(mockToken.connect(Bob).transfer(await lntVault.getAddress(), ethers.parseUnits("5000", 18))).not.to.be.reverted;

    // Verify the vault has received the tokens
    expect(await mockToken.balanceOf(await lntVault.getAddress())).to.equal(ethers.parseUnits("5000", 18));

    let tx = await lntVault.connect(Alice).redeemT(redeemAmount);
    await expect(tx)
      .to.emit(lntVault, 'RedeemT').withArgs(Alice.address, redeemAmount);
    await expect(tx).to.changeTokenBalances(
      mockToken,
      [Alice, lntVault],
      [redeemAmount, -redeemAmount]
    );
    await expect(tx).to.changeTokenBalances(
      vt,
      [Alice],
      [-redeemAmount]
    );
  });

  it('LNTVaultERC1155 buyback with ETH works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    const genesisTime = await time.latest();
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    // Create vesting schedules for the tokens we'll use
    const vestingSchedules = [
      {
        tokenId: tokenId1,
        weight: 1,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId1
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId2,
        weight: 2,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId2
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      }
    ];
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).not.to.be.reverted;

    // Setup NFT deposits
    await expect(nft.connect(Alice).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(tokenId1, 5)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(tokenId2, 5)).not.to.be.reverted;

    await expect(lntVault.connect(Bob).initializeT(nativeTokenAddress)).to.emit(lntVault, "InitializedT");

    // Day 102: Ready for buyback
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 102);

    const totalT = ethers.parseUnits("1000", 18);
    // Bob transfers ETH to lntVault to simulate the vesting
    await expect(Bob.sendTransaction({ to: await lntVault.getAddress(), value: totalT })).not.to.be.reverted;

    let buybackAmount = ethers.parseUnits("2000", 18);
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.revertedWith("Insufficient token balance");

    buybackAmount = ethers.parseUnits("500", 18);
    await expect(lntVault.connect(Alice).buyback(buybackAmount, 0n))
      .to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    // Fails if there are no VT/T trading pair
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.reverted;

    // Add VT/T liquidity
    const liquidityVTAmount = ethers.parseUnits("1000", await vt.decimals());
    await expect(vt.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityVTAmount)).not.to.be.reverted;
    await expect(lntMarketRouter.connect(Alice).addLiquidityETH(
      await vt.getAddress(), liquidityVTAmount, 0, 0, Alice.address, (await time.latest()) + 60, { value: ethers.parseEther("800") }
    )).not.to.be.reverted;

    // Buyback is protected by slippage
    await expect(lntVault.connect(Bob).buyback(buybackAmount, ethers.parseEther("1000"))).to.be.revertedWith(/LntMarketRouter: INSUFFICIENT_OUTPUT_AMOUNT/);

    const pairAddress = await lntMarketFactory.getPair(await vt.getAddress(), await lntMarketRouter.WETH());

    console.log(`Before buyback, Vault's $ETH balance: ${formatUnits(await provider.getBalance(await lntVault.getAddress()), 18)}, Pool $VT balance: ${formatUnits(await vt.balanceOf(pairAddress), await vt.decimals())}`);
    let tx = await lntVault.connect(Bob).buyback(buybackAmount, ethers.parseEther("250"));
    await expect(tx)
      .to.emit(lntVault, 'Buyback').withArgs(Bob.address, buybackAmount, anyValue)
      .to.emit(vt, 'Transfer').withArgs(await lntVault.getAddress(), ZeroAddress, anyValue);
    await expect(tx).to.changeEtherBalances(
      [lntVault],
      [-buybackAmount]
    );
    console.log(`After buyback, Vault's $ETH balance: ${formatUnits(await provider.getBalance(await lntVault.getAddress()), 18)}, Pool $VT balance: ${formatUnits(await vt.balanceOf(pairAddress), await vt.decimals())}`);
  });

  it('LNTVaultERC1155 buyback with ERC20 works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    // Create a MockERC20 token for testing
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const MockERC20 = await MockERC20Factory.connect(Bob).deploy("Mock Token", "MT", 18);
    const mockToken = MockERC20__factory.connect(await MockERC20.getAddress(), provider);
    
    // Mint tokens to Alice & Bob for later transfer to vault
    await mockToken.connect(Bob).mint(Alice.address, ethers.parseUnits("10000", 18));
    await mockToken.connect(Bob).mint(Bob.address, ethers.parseUnits("10000", 18));

    const genesisTime = await time.latest();
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    // Create vesting schedules for the tokens we'll use
    const vestingSchedules = [
      {
        tokenId: tokenId1,
        weight: 1,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId1
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId2,
        weight: 2,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId2
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      }
    ];
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).not.to.be.reverted;

    // Setup NFT deposits
    await expect(nft.connect(Alice).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(tokenId1, 5)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(tokenId2, 5)).not.to.be.reverted;

    await expect(lntVault.connect(Bob).initializeT(mockToken)).to.emit(lntVault, "InitializedT");

    // Day 102: Ready for buyback
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 102);

    const totalT = ethers.parseUnits("1000", 18);
    // Bob transfers tokens to lntVault to simulate the vesting
    await expect(mockToken.connect(Bob).transfer(await lntVault.getAddress(), totalT)).not.to.be.reverted;

    // Verify the vault has received the tokens
    expect(await mockToken.balanceOf(await lntVault.getAddress())).to.equal(totalT);

    let buybackAmount = ethers.parseUnits("2000", 18);
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.revertedWith("Insufficient token balance");

    buybackAmount = ethers.parseUnits("500", 18);
    await expect(lntVault.connect(Alice).buyback(buybackAmount, 0n))
      .to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    // Fails if there are no VT/T trading pair
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.reverted;

    // Add VT/T liquidity
    const liquidityVTAmount = ethers.parseUnits("3000", await vt.decimals());
    const liquidityTokenAmount = ethers.parseUnits("2000", await mockToken.decimals());
    await expect(vt.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityVTAmount)).not.to.be.reverted;
    await expect(mockToken.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityTokenAmount)).not.to.be.reverted;
    await expect(lntMarketRouter.connect(Alice).addLiquidity(
      await vt.getAddress(), await mockToken.getAddress(), liquidityVTAmount, liquidityTokenAmount, 0, 0, Alice.address, (await time.latest()) + 60
    )).not.to.be.reverted;

    // Buyback is protected by slippage
    await expect(lntVault.connect(Bob).buyback(buybackAmount, ethers.parseUnits("1000", await mockToken.decimals()))).to.be.revertedWith(/LntMarketRouter: INSUFFICIENT_OUTPUT_AMOUNT/);

    const pairAddress = await lntMarketFactory.getPair(await vt.getAddress(), await mockToken.getAddress());

    console.log(`Before buyback, Vault's $MT balance: ${formatUnits(await mockToken.balanceOf(await lntVault.getAddress()), await mockToken.decimals())}, Pool $VT balance: ${formatUnits(await vt.balanceOf(pairAddress), await vt.decimals())}`);
    let tx = await lntVault.connect(Bob).buyback(buybackAmount, ethers.parseUnits("250", await mockToken.decimals()));
    await expect(tx)
      .to.emit(lntVault, 'Buyback').withArgs(Bob.address, buybackAmount, anyValue)
      .to.emit(vt, 'Transfer').withArgs(await lntVault.getAddress(), ZeroAddress, anyValue);
    await expect(tx).to.changeTokenBalances(
      mockToken,
      [lntVault],
      [-buybackAmount]
    );
    console.log(`After buyback, Vault's $MT balance: ${formatUnits(await mockToken.balanceOf(await lntVault.getAddress()), await mockToken.decimals())}, Pool $VT balance: ${formatUnits(await vt.balanceOf(pairAddress), await vt.decimals())}`);
  });

  it('LNTVaultERC1155 should handle multiple users, tokens and amounts correctly', async () => {
    const [Alice, Bob, Caro] = await ethers.getSigners();

    const genesisTime = await time.latest();
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    // Create vesting schedules for the tokens we'll use
    const vestingSchedules = [
      {
        tokenId: tokenId1,
        weight: 1,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId1
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId2,
        weight: 2,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId2
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      },
      {
        tokenId: tokenId3,
        weight: 3,
        vestingTokenAmountPerNft: ethers.parseUnits("1000", await vt.decimals()),  // 1000 $VT per NFT unit for tokenId3
        vestingStartTime: VestingStartTime,
        vestingDuration: VestingDuration
      }
    ];
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), vestingSchedules
    )).not.to.be.reverted;

    // All users approve the vault to move their tokens
    await expect(nft.connect(Alice).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(nft.connect(Caro).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;

    // Each user deposits different token IDs with different amounts
    const aliceDeposit1 = await lntVault.connect(Alice).deposit(tokenId1, 5);
    const aliceDeposit2 = await lntVault.connect(Alice).deposit(tokenId2, 10);
    const bobDeposit1 = await lntVault.connect(Bob).deposit(tokenId1, 8);
    const bobDeposit2 = await lntVault.connect(Bob).deposit(tokenId3, 15);
    const caroDeposit1 = await lntVault.connect(Caro).deposit(tokenId1, 3);
    const caroDeposit2 = await lntVault.connect(Caro).deposit(tokenId3, 7);

    // Check balances after all deposits
    expect(await nft.balanceOf(Alice.address, tokenId1)).to.equal(10 - 5);  // Starting 10 - 5 deposited
    expect(await nft.balanceOf(Alice.address, tokenId2)).to.equal(20 - 10); // Starting 20 - 10 deposited
    expect(await nft.balanceOf(Bob.address, tokenId1)).to.equal(15 - 8);    // Starting 15 - 8 deposited
    expect(await nft.balanceOf(Bob.address, tokenId3)).to.equal(35 - 15);   // Starting 35 - 15 deposited
    expect(await nft.balanceOf(Caro.address, tokenId1)).to.equal(5 - 3);    // Starting 5 - 3 deposited
    expect(await nft.balanceOf(Caro.address, tokenId3)).to.equal(15 - 7);   // Starting 15 - 7 deposited

    // Check vault balances
    expect(await nft.balanceOf(await lntVault.getAddress(), tokenId1)).to.equal(5 + 8 + 3); // All user deposits combined
    expect(await nft.balanceOf(await lntVault.getAddress(), tokenId2)).to.equal(10);
    expect(await nft.balanceOf(await lntVault.getAddress(), tokenId3)).to.equal(15 + 7);

    // Fast forward to allow redemptions
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 10);

    // Multiple users redeem parts of their deposits
    await expect(lntVault.connect(Alice).redeem(1, tokenId1, 5)).not.to.be.reverted; 
    await expect(lntVault.connect(Bob).redeem(3, tokenId1, 8)).not.to.be.reverted;
    await expect(lntVault.connect(Caro).redeem(5, tokenId1, 3)).not.to.be.reverted; 

    // Check balances after partial redemptions
    expect(await nft.balanceOf(Alice.address, tokenId1)).to.equal(5 + 5); 
    expect(await nft.balanceOf(Bob.address, tokenId1)).to.equal(7 + 8);  
    expect(await nft.balanceOf(Caro.address, tokenId1)).to.equal(2 + 3);

    // Check vault balances
    expect(await nft.balanceOf(await lntVault.getAddress(), tokenId1)).to.equal((5 - 5) + (8 - 8) + (3 - 3)); // Remaining after redemptions

    // Verify redemption state
    expect((await lntVault.depositInfo(1)).redeemed).to.equal(true);
    expect((await lntVault.depositInfo(3)).redeemed).to.equal(true);
    expect((await lntVault.depositInfo(5)).redeemed).to.equal(true);

    // Verify all tokenId1 redemptions are now complete
    expect((await lntVault.depositInfo(1)).redeemed).to.equal(true);
    expect((await lntVault.depositInfo(5)).redeemed).to.equal(true);
    
    // Vault should have no tokenId1 left
    expect(await nft.balanceOf(await lntVault.getAddress(), tokenId1)).to.equal(0);

    // Users still have other tokens deposited
    expect(await nft.balanceOf(await lntVault.getAddress(), tokenId2)).to.equal(10);
    expect(await nft.balanceOf(await lntVault.getAddress(), tokenId3)).to.equal(15 + 7);
  });
});
