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
  MockERC721, MockERC721__factory, LntVaultERC721, LntVaultERC721__factory, 
  VestingToken, VestingToken__factory,
  LntMarketRouter, MockERC20, MockERC20__factory,
  LntContractFactory,
  LntMarketFactory,
} from "../typechain";
import { encodeBytes32String, formatUnits } from 'ethers';

const { provider } = ethers;

describe('LNTVaultERC721', () => {

  let nft: MockERC721;
  let lntVault: LntVaultERC721;
  let vt: VestingToken;
  let lntMarketRouter: LntMarketRouter;
  let lntContractFactory: LntContractFactory;
  let lntMarketFactory: LntMarketFactory;

  beforeEach(async () => {
    const { Alice, Bob, Caro, lntContractFactory: contractFactory, lntMarketFactory: marketFactory, lntMarketRouter: router } = await loadFixture(deployContractsFixture);
    lntMarketRouter = router;
    lntContractFactory = contractFactory;
    lntMarketFactory = marketFactory;

    const MockERC721Factory = await ethers.getContractFactory("MockERC721");
    const MockERC721 = await MockERC721Factory.connect(Bob).deploy("MockERC721", "MK721");
    nft = MockERC721__factory.connect(await MockERC721.getAddress(), provider);

    const LntVaultERC721Factory = await ethers.getContractFactory("LntVaultERC721");
    let bytecode = LntVaultERC721Factory.bytecode;
    let constructorArgs = (new ethers.AbiCoder()).encode(['address'], [Bob.address]);
    let vaultAddress = await deployContract(lntContractFactory, Bob, bytecode, constructorArgs);
    lntVault = LntVaultERC721__factory.connect(vaultAddress, provider);

    const VestingTokenFactory = await ethers.getContractFactory("VestingToken");
    bytecode = VestingTokenFactory.bytecode;
    constructorArgs = (new ethers.AbiCoder()).encode(['address', 'string', 'string'], [vaultAddress, "LNT VT", "LNTVT"]);
    let vtAddress = await deployContract(lntContractFactory, Bob, bytecode, constructorArgs);
    vt = VestingToken__factory.connect(vtAddress, provider);

    await nft.connect(Bob).safeMint(Alice.address, 1);
    await nft.connect(Bob).safeMint(Alice.address, 2);
    await nft.connect(Bob).safeMint(Alice.address, 3);
    await nft.connect(Bob).safeMint(Bob.address, 4);
    await nft.connect(Bob).safeMint(Bob.address, 5);
    await nft.connect(Bob).safeMint(Bob.address, 6);
    await nft.connect(Bob).safeMint(Caro.address, 7);
    await nft.connect(Bob).safeMint(Caro.address, 8);
    await nft.connect(Bob).safeMint(Caro.address, 9);
  });

  it('LNTVaultERC721 deposit and redeem works', async () => {
    const [Alice, Bob, Caro] = await ethers.getSigners();

    // Check initial state
    expect(await lntVault.initialized()).to.equal(false);
    expect(await lntVault.owner()).to.equal(Bob.address);

    // Update settings
    await expect(lntVault.connect(Alice).updateParamValue(ethers.encodeBytes32String("f1"), 10 ** 9)).to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);
    await expect(lntVault.connect(Bob).updateParamValue(ethers.encodeBytes32String("f1"), 10 ** 9))
      .to.emit(lntVault, "UpdateParamValue")
      .withArgs(encodeBytes32String("f1"), 10 ** 9);

    // Cannot deposit before initialization
    await expect(lntVault.connect(Alice).deposit(1, 1)).to.be.revertedWith("Not initialized");

    const genesisTime = await time.latest();
    const VestingTokenAmountPerNft = ethers.parseUnits("10000", await vt.decimals());  // 10000 $VT per NFT
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    // Only owner could initialize
    await expect(lntVault.connect(Alice).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), VestingTokenAmountPerNft, VestingStartTime, VestingDuration
    )).to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), VestingTokenAmountPerNft, VestingStartTime, VestingDuration
    )).to.emit(lntVault, "Initialized");

    // Could not initialize again
    expect(await lntVault.initialized()).to.equal(true);
    expect(await lntVault.NFT()).to.equal(await nft.getAddress());
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), VestingTokenAmountPerNft, VestingStartTime, VestingDuration
    )).to.be.revertedWith("Already initialized");

    /**
     * Day 0:
     *  Alice deposits NFT 1 & 2
     *  Bob deposits NFT 4
     */
    let currentDepositId = 1;
    await expect(lntVault.connect(Alice).deposit(4, 1)).to.be.revertedWith(/Not owner of NFT/);
    await expect(lntVault.connect(Alice).deposit(1, 2)).to.be.revertedWith(/Invalid value/);
    await expect(nft.connect(Alice).approve(await lntVault.getAddress(), 1)).not.to.be.reverted;
    let result = await calcMintedVt(lntVault, 1n, 1n);
    let trans = await lntVault.connect(Alice).deposit(1, 1);
    await expect(trans)
      .to.emit(lntVault, 'Deposit').withArgs(currentDepositId, Alice.address, await nft.getAddress(), 1, 1)
      .to.emit(lntVault, 'VTMinted').withArgs(Alice.address,  result.fees, result.netVtAmount);
    await expect(trans).to.changeTokenBalances(
      nft,
      [Alice.address, await lntVault.getAddress()],
      [-1, 1]
    );
    await expect(trans).to.changeTokenBalances(
      vt,
      [Alice.address, await lntContractFactory.treasury()],
      [result.netVtAmount, result.fees]
    );
    // cann't deposit same nft again
    await expect(lntVault.connect(Alice).deposit(1, 1)).to.be.revertedWith(/Not owner of NFT/);
    // deposit another nft
    await expect(nft.connect(Alice).approve(await lntVault.getAddress(), 2)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(2, 1)).not.to.be.reverted;
    // Bob deposits NFT 4
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(4, 1)).not.to.be.reverted;

    // Day 2: Alice redeems NFT 1
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 2);
    let depositId = 2n;
    let tokenId = 2n;
    expect((await lntVault.depositInfo(depositId)).tokenId).to.equal(tokenId);
    await expect(lntVault.connect(Bob).redeem(depositId, tokenId, 1)).to.be.revertedWith(/Not user of deposit/);
    await expect(lntVault.connect(Alice).redeem(depositId, tokenId, 2)).to.be.revertedWith(/Invalid value/);

    const expectedBurnedVtAmount = await calcBurnedVt(lntVault, depositId, tokenId, 1n);
    trans = await lntVault.connect(Alice).redeem(depositId, tokenId, 1);
    await expect(trans)
      .to.emit(lntVault, 'Redeem').withArgs(depositId, Alice.address, await nft.getAddress(), tokenId, 1)
      .to.emit(lntVault, 'VTBurned').withArgs(Alice.address, anyValue);
    await expect(trans).to.changeTokenBalances(
      nft,
      [Alice.address, await lntVault.getAddress()],
      [1, -1]
    );

    expect((await lntVault.depositInfo(depositId)).redeemed).to.equal(true);
    await expect(lntVault.connect(Alice).redeem(depositId, tokenId, 1n)).to.be.revertedWith(/Already redeemed/);

  });

  it('LNTVaultERC721 redeem ETH works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    const genesisTime = await time.latest();
    const VestingTokenAmountPerNft = ethers.parseUnits("10000", await vt.decimals());  // 10000 $VT per NFT
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), VestingTokenAmountPerNft, VestingStartTime, VestingDuration
    )).not.to.be.reverted;

    /**
     * Day 0:
     *  Alice deposits NFT 1
     *  Bob deposits NFT 4
     */
    await expect(nft.connect(Alice).approve(await lntVault.getAddress(), 1)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(1, 1)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(4, 1)).not.to.be.reverted;

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

    const redeemAmount = ethers.parseUnits("100", 18);
    await expect(lntVault.connect(Alice).redeemT(
      redeemAmount
    )).to.be.revertedWith("Insufficient token balance");

    // Bob transfers 100 ETH to lntVault to simulate the vesting
    await expect(Bob.sendTransaction({ to: await lntVault.getAddress(), value: redeemAmount })).not.to.be.reverted;

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

  it('LNTVaultERC721 redeem ERC20 works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    // Create a MockERC20 token for testing
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const MockERC20 = await MockERC20Factory.connect(Bob).deploy("Mock Token", "MT", 18);
    const mockToken = MockERC20__factory.connect(await MockERC20.getAddress(), provider);
    
    // Mint tokens to Bob for later transfer to vault
    await mockToken.connect(Bob).mint(Bob.address, ethers.parseUnits("1000", 18));

    const genesisTime = await time.latest();
    const VestingTokenAmountPerNft = ethers.parseUnits("10000", await vt.decimals());  // 10000 $VT per NFT
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), VestingTokenAmountPerNft, VestingStartTime, VestingDuration
    )).not.to.be.reverted;

    /**
     * Day 0:
     *  Alice deposits NFT 1
     *  Bob deposits NFT 4
     */
    await expect(nft.connect(Alice).approve(await lntVault.getAddress(), 1)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(1, 1)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(4, 1)).not.to.be.reverted;

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

    const redeemAmount = ethers.parseUnits("100", 18);
    await expect(lntVault.connect(Alice).redeemT(
      redeemAmount
    )).to.be.revertedWith("Insufficient token balance");

    // Bob transfers 100 tokens to lntVault to simulate the vesting
    await expect(mockToken.connect(Bob).transfer(await lntVault.getAddress(), redeemAmount)).not.to.be.reverted;

    // Verify the vault has received the tokens
    expect(await mockToken.balanceOf(await lntVault.getAddress())).to.equal(redeemAmount);

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

  it('LNTVaultERC721 buyback with ETH works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    const genesisTime = await time.latest();
    const VestingTokenAmountPerNft = ethers.parseUnits("10000", await vt.decimals());  // 10000 $VT per NFT
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), VestingTokenAmountPerNft, VestingStartTime, VestingDuration
    )).not.to.be.reverted;

    await expect(nft.connect(Alice).approve(await lntVault.getAddress(), 1)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(1, 1)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(4, 1)).not.to.be.reverted;

    await expect(lntVault.connect(Bob).initializeT(nativeTokenAddress)).to.emit(lntVault, "InitializedT");

    // Day 102: Alice redeems T
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 102);

    const totalT = ethers.parseUnits("100", 18);
    // Bob transfers 100 ETH to lntVault to simulate the vesting
    await expect(Bob.sendTransaction({ to: await lntVault.getAddress(), value: totalT })).not.to.be.reverted;

    let buybackAmount = ethers.parseUnits("200", 18);
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.revertedWith("Insufficient token balance");

    buybackAmount = ethers.parseUnits("10", 18);
    await expect(lntVault.connect(Alice).buyback(buybackAmount, 0n))
      .to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    // Fails if there are no VT/T trading pair
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.reverted;

    // Add VT/T liquidity
    const liquidityVTAmount = ethers.parseUnits("100", await vt.decimals());
    await expect(vt.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityVTAmount)).not.to.be.reverted;
    await expect(lntMarketRouter.connect(Alice).addLiquidityETH(
      await vt.getAddress(), liquidityVTAmount, 0, 0, Alice.address, (await time.latest()) + 60, { value: ethers.parseEther("80") }
    )).not.to.be.reverted;

    // Buyback is protected by slippage
    await expect(lntVault.connect(Bob).buyback(buybackAmount, ethers.parseEther("100"))).to.be.revertedWith(/LntMarketRouter: INSUFFICIENT_OUTPUT_AMOUNT/);

    const pairAddress = await lntMarketFactory.getPair(await vt.getAddress(), await lntMarketRouter.WETH());

    console.log(`Before buyback, Vault's $ETH balance: ${formatUnits(await provider.getBalance(await lntVault.getAddress()), 18)}, Pool $VT balance: ${formatUnits(await vt.balanceOf(pairAddress), await vt.decimals())}`);
    let tx = await lntVault.connect(Bob).buyback(buybackAmount, ethers.parseEther("5"));
    await expect(tx)
      .to.emit(lntVault, 'Buyback').withArgs(Bob.address, buybackAmount, anyValue)
      .to.emit(vt, 'Transfer').withArgs(await lntVault.getAddress(), ZeroAddress, anyValue);
    await expect(tx).to.changeEtherBalances(
      [lntVault],
      [-buybackAmount]
    );
    console.log(`After buyback, Vault's $ETH balance: ${formatUnits(await provider.getBalance(await lntVault.getAddress()), 18)}, Pool $VT balance: ${formatUnits(await vt.balanceOf(pairAddress), await vt.decimals())}`);

  });

  it('LNTVaultERC721 buyback with ERC20 works', async () => {
    const [Alice, Bob] = await ethers.getSigners();

    // Create a MockERC20 token for testing
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const MockERC20 = await MockERC20Factory.connect(Bob).deploy("Mock Token", "MT", 18);
    const mockToken = MockERC20__factory.connect(await MockERC20.getAddress(), provider);
    
    // Mint tokens to Alice & Bob for later transfer to vault
    await mockToken.connect(Bob).mint(Alice.address, ethers.parseUnits("1000", 18));
    await mockToken.connect(Bob).mint(Bob.address, ethers.parseUnits("1000", 18));

    const genesisTime = await time.latest();
    const VestingTokenAmountPerNft = ethers.parseUnits("10000", await vt.decimals());  // 10000 $VT per NFT
    const VestingStartTime = genesisTime + ONE_DAY_IN_SECS;
    const VestingDuration = 100 * ONE_DAY_IN_SECS;   // [Day 1, Day 101]
    
    await expect(lntVault.connect(Bob).initialize(
      await nft.getAddress(), await lntMarketRouter.getAddress(), await vt.getAddress(), VestingTokenAmountPerNft, VestingStartTime, VestingDuration
    )).not.to.be.reverted;

    await expect(nft.connect(Alice).approve(await lntVault.getAddress(), 1)).not.to.be.reverted;
    await expect(lntVault.connect(Alice).deposit(1, 1)).not.to.be.reverted;
    await expect(nft.connect(Bob).setApprovalForAll(await lntVault.getAddress(), true)).not.to.be.reverted;
    await expect(lntVault.connect(Bob).deposit(4, 1)).not.to.be.reverted;

    await expect(lntVault.connect(Bob).initializeT(mockToken)).to.emit(lntVault, "InitializedT");

    // Day 102: Alice redeems T
    await time.increaseTo(genesisTime + ONE_DAY_IN_SECS * 102);

    const totalT = ethers.parseUnits("100", 18);
    // Bob transfers 100 tokens to lntVault to simulate the vesting
    await expect(mockToken.connect(Bob).transfer(await lntVault.getAddress(), totalT)).not.to.be.reverted;

    // Verify the vault has received the tokens
    expect(await mockToken.balanceOf(await lntVault.getAddress())).to.equal(totalT);

    let buybackAmount = ethers.parseUnits("200", 18);
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.revertedWith("Insufficient token balance");

    buybackAmount = ethers.parseUnits("10", 18);
    await expect(lntVault.connect(Alice).buyback(buybackAmount, 0n))
      .to.be.revertedWithCustomError(lntVault, "OwnableUnauthorizedAccount").withArgs(Alice.address);

    // Fails if there are no VT/T trading pair
    await expect(lntVault.connect(Bob).buyback(buybackAmount, 0n)).to.be.reverted;

    // Add VT/T liquidity
    const liquidityVTAmount = ethers.parseUnits("100", await vt.decimals());
    const liquidityTokenAmount = ethers.parseUnits("80", await mockToken.decimals());
    await expect(vt.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityVTAmount)).not.to.be.reverted;
    await expect(mockToken.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityTokenAmount)).not.to.be.reverted;
    await expect(lntMarketRouter.connect(Alice).addLiquidity(
      await vt.getAddress(), await mockToken.getAddress(), liquidityVTAmount, liquidityTokenAmount, 0, 0, Alice.address, (await time.latest()) + 60
    )).not.to.be.reverted;

    // Buyback is protected by slippage
    await expect(lntVault.connect(Bob).buyback(buybackAmount, ethers.parseUnits("100", await mockToken.decimals()))).to.be.revertedWith(/LntMarketRouter: INSUFFICIENT_OUTPUT_AMOUNT/);

    const pairAddress = await lntMarketFactory.getPair(await vt.getAddress(), await mockToken.getAddress());

    console.log(`Before buyback, Vault's $MT balance: ${formatUnits(await mockToken.balanceOf(await lntVault.getAddress()), await mockToken.decimals())}, Pool $VT balance: ${formatUnits(await vt.balanceOf(pairAddress), await vt.decimals())}`);
    let tx = await lntVault.connect(Bob).buyback(buybackAmount, ethers.parseEther("5"));
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
});
