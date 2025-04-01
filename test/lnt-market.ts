import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Signer } from 'ethers';
import { loadFixture, time } from '@nomicfoundation/hardhat-network-helpers';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { 
  deployContractsFixture, ONE_DAY_IN_SECS,
} from './utils';
import { 
  MockERC20, MockERC20__factory, 
  LntMarket, LntMarket__factory,
  LntMarketFactory, LntMarketFactory__factory,
  LntMarketRouter, LntMarketRouter__factory,
  WETH, WETH__factory
} from "../typechain";
import { formatUnits, parseUnits } from 'ethers';

const { provider } = ethers;

describe('LNT Market', () => {
  let tokenA: MockERC20;
  let tokenB: MockERC20;
  let weth: WETH;
  let lntMarketFactory: LntMarketFactory;
  let lntMarketRouter: LntMarketRouter;

  beforeEach(async () => {
    const { Alice, Bob, lntMarketFactory: factory, lntMarketRouter: router, weth: _weth } = await loadFixture(deployContractsFixture);
    
    // Keep references to existing contracts
    lntMarketFactory = factory;
    lntMarketRouter = router;
    weth = _weth;
    
    // Create new tokens for each test
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    
    // Deploy TokenA
    const TokenA = await MockERC20Factory.connect(Alice).deploy("Token A", "TKA", 18);
    tokenA = MockERC20__factory.connect(await TokenA.getAddress(), provider);
    
    // Deploy TokenB
    const TokenB = await MockERC20Factory.connect(Alice).deploy("Token B", "TKB", 18);
    tokenB = MockERC20__factory.connect(await TokenB.getAddress(), provider);
    
    // Mint initial tokens
    const initialAmount = parseUnits("10000", 18);
    await tokenA.connect(Alice).mint(Alice.address, initialAmount);
    await tokenA.connect(Alice).mint(Bob.address, initialAmount);
    await tokenB.connect(Alice).mint(Alice.address, initialAmount);
    await tokenB.connect(Alice).mint(Bob.address, initialAmount);
  });

  it('LntMarketFactory creates pairs correctly', async () => {
    const [Alice] = await ethers.getSigners();
    
    // Create a new pair
    const tx = await lntMarketFactory.connect(Alice).createPair(await tokenA.getAddress(), await tokenB.getAddress());
    await tx.wait();
    
    // Check if pair was created correctly
    const pairAddress = await lntMarketFactory.getPair(await tokenA.getAddress(), await tokenB.getAddress());
    expect(pairAddress).to.not.equal(ethers.ZeroAddress);
    
    // Pair should be retrievable regardless of token order
    const pairAddressReversed = await lntMarketFactory.getPair(await tokenB.getAddress(), await tokenA.getAddress());
    expect(pairAddress).to.equal(pairAddressReversed);
    
    // Check all pairs length
    expect(await lntMarketFactory.allPairsLength()).to.equal(1);
    
    // Verify the pair at index 0
    const pairAtIndex = await lntMarketFactory.allPairs(0);
    expect(pairAtIndex).to.equal(pairAddress);
  });

  it('LntMarketRouter adds ERC20-ERC20 liquidity correctly', async () => {
    const [Alice] = await ethers.getSigners();
    
    // Approve router to spend tokens
    const amountA = parseUnits("100", 18);
    const amountB = parseUnits("200", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), amountA);
    await tokenB.connect(Alice).approve(await lntMarketRouter.getAddress(), amountB);
    
    // Deadline
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    // Add liquidity
    const tx = await lntMarketRouter.connect(Alice).addLiquidity(
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      amountA,
      amountB,
      amountA, // Min amount A
      amountB, // Min amount B
      Alice.address,
      deadline
    );
    await tx.wait();
    
    // Get pair address and contract
    const pairAddress = await lntMarketFactory.getPair(await tokenA.getAddress(), await tokenB.getAddress());
    const pair = LntMarket__factory.connect(pairAddress, provider);
    
    // Check liquidity tokens were minted to Alice
    const liquidityBalance = await pair.balanceOf(Alice.address);
    expect(liquidityBalance).to.be.gt(0);
    
    // Check reserves
    const reserves = await pair.getReserves();
    const token0 = await pair.token0();
    
    if (token0 === await tokenA.getAddress()) {
      expect(reserves[0]).to.equal(amountA);
      expect(reserves[1]).to.equal(amountB);
    } else {
      expect(reserves[0]).to.equal(amountB);
      expect(reserves[1]).to.equal(amountA);
    }
  });

  it('LntMarketRouter adds ETH-ERC20 liquidity correctly', async () => {
    const [Alice] = await ethers.getSigners();
    
    // Approve router to spend token
    const tokenAmount = parseUnits("100", 18);
    const ethAmount = parseUnits("1", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), tokenAmount);
    
    // Deadline
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    // Add liquidity with ETH
    const tx = await lntMarketRouter.connect(Alice).addLiquidityETH(
      await tokenA.getAddress(),
      tokenAmount,
      tokenAmount, // Min token amount
      ethAmount,   // Min ETH amount
      Alice.address,
      deadline,
      { value: ethAmount }
    );
    await tx.wait();
    
    // Get pair address and contract
    const pairAddress = await lntMarketFactory.getPair(await tokenA.getAddress(), await weth.getAddress());
    const pair = LntMarket__factory.connect(pairAddress, provider);
    
    // Check liquidity tokens were minted to Alice
    const liquidityBalance = await pair.balanceOf(Alice.address);
    expect(liquidityBalance).to.be.gt(0);
    
    // Check reserves
    const reserves = await pair.getReserves();
    const token0 = await pair.token0();
    
    if (token0 === await tokenA.getAddress()) {
      expect(reserves[0]).to.equal(tokenAmount);
      expect(reserves[1]).to.equal(ethAmount);
    } else {
      expect(reserves[0]).to.equal(ethAmount);
      expect(reserves[1]).to.equal(tokenAmount);
    }
  });

  it('LntMarketRouter swaps ERC20-ERC20 tokens correctly', async () => {
    const [Alice, Bob] = await ethers.getSigners();
    
    // First add liquidity
    const amountA = parseUnits("1000", 18);
    const amountB = parseUnits("1000", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), amountA);
    await tokenB.connect(Alice).approve(await lntMarketRouter.getAddress(), amountB);
    
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    await lntMarketRouter.connect(Alice).addLiquidity(
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      amountA,
      amountB,
      0, // Min amount A
      0, // Min amount B
      Alice.address,
      deadline
    );
    
    // Bob swaps tokens
    const swapAmount = parseUnits("10", 18);
    const minOutputAmount = parseUnits("9", 18); // Allow for some slippage
    
    // Approve router
    await tokenA.connect(Bob).approve(await lntMarketRouter.getAddress(), swapAmount);
    
    // Check balances before swap
    const bobTokenABefore = await tokenA.balanceOf(Bob.address);
    const bobTokenBBefore = await tokenB.balanceOf(Bob.address);
    
    // Perform the swap (exact tokens for tokens)
    const swapTx = await lntMarketRouter.connect(Bob).swapExactTokensForTokens(
      swapAmount,
      minOutputAmount,
      [await tokenA.getAddress(), await tokenB.getAddress()],
      Bob.address,
      deadline
    );
    await swapTx.wait();
    
    // Check balances after swap
    const bobTokenAAfter = await tokenA.balanceOf(Bob.address);
    const bobTokenBAfter = await tokenB.balanceOf(Bob.address);
    
    // Verify Bob spent tokenA
    expect(bobTokenABefore - bobTokenAAfter).to.equal(swapAmount);
    
    // Verify Bob received tokenB
    expect(bobTokenBAfter - bobTokenBBefore).to.be.gte(minOutputAmount);
  });

  it('LntMarketRouter swaps ETH for tokens correctly', async () => {
    const [Alice, Bob] = await ethers.getSigners();
    
    // First add liquidity
    const tokenAmount = parseUnits("1000", 18);
    const ethAmount = parseUnits("10", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), tokenAmount);
    
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    await lntMarketRouter.connect(Alice).addLiquidityETH(
      await tokenA.getAddress(),
      tokenAmount,
      tokenAmount, // Min token amount
      ethAmount,   // Min ETH amount
      Alice.address,
      deadline,
      { value: ethAmount }
    );
    
    // Bob swaps ETH for tokens
    const swapEthAmount = parseUnits("1", 18);
    const minOutputAmount = parseUnits("90", 18); // Expected tokens based on pool ratio
    
    // Check balances before swap
    const bobTokenABefore = await tokenA.balanceOf(Bob.address);
    const bobEthBefore = await provider.getBalance(Bob.address);
    
    // Perform the swap (ETH for exact tokens)
    const swapTx = await lntMarketRouter.connect(Bob).swapExactETHForTokens(
      minOutputAmount,
      [await weth.getAddress(), await tokenA.getAddress()],
      Bob.address,
      deadline,
      { value: swapEthAmount }
    );
    const receipt = await swapTx.wait();
    
    // Check balances after swap
    const bobTokenAAfter = await tokenA.balanceOf(Bob.address);
    const bobEthAfter = await provider.getBalance(Bob.address);
    
    // Calculate gas cost
    const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
    
    // Verify Bob spent ETH (accounting for gas costs)
    expect(bobEthBefore - bobEthAfter - gasUsed).to.equal(swapEthAmount);
    
    // Verify Bob received tokenA
    expect(bobTokenAAfter - bobTokenABefore).to.be.gte(minOutputAmount);
  });

  it('LntMarketRouter swaps tokens for ETH correctly', async () => {
    const [Alice, Bob] = await ethers.getSigners();
    
    // First add liquidity
    const tokenAmount = parseUnits("1000", 18);
    const ethAmount = parseUnits("10", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), tokenAmount);
    
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    await lntMarketRouter.connect(Alice).addLiquidityETH(
      await tokenA.getAddress(),
      tokenAmount,
      tokenAmount, // Min token amount
      ethAmount,   // Min ETH amount
      Alice.address,
      deadline,
      { value: ethAmount }
    );
    
    // Bob swaps tokens for ETH
    const swapTokenAmount = parseUnits("100", 18);
    const minEthOutput = parseUnits("0.9", 18); // Expected ETH based on pool ratio
    
    // Approve router
    await tokenA.connect(Bob).approve(await lntMarketRouter.getAddress(), swapTokenAmount);
    
    // Check balances before swap
    const bobTokenABefore = await tokenA.balanceOf(Bob.address);
    const bobEthBefore = await provider.getBalance(Bob.address);
    
    // Perform the swap (tokens for exact ETH)
    const swapTx = await lntMarketRouter.connect(Bob).swapExactTokensForETH(
      swapTokenAmount,
      minEthOutput,
      [await tokenA.getAddress(), await weth.getAddress()],
      Bob.address,
      deadline
    );
    const receipt = await swapTx.wait();
    
    // Check balances after swap
    const bobTokenAAfter = await tokenA.balanceOf(Bob.address);
    const bobEthAfter = await provider.getBalance(Bob.address);
    
    // Calculate gas cost
    const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
    
    // Verify Bob spent tokenA
    expect(bobTokenABefore - bobTokenAAfter).to.equal(swapTokenAmount);
    
    // Verify Bob received ETH (accounting for gas costs)
    const ethDiff = bobEthAfter - bobEthBefore + gasUsed;
    expect(ethDiff).to.be.gte(minEthOutput);
  });

  it('LntMarketRouter removes ERC20-ERC20 liquidity correctly', async () => {
    const [Alice] = await ethers.getSigners();
    
    // First add liquidity
    const amountA = parseUnits("100", 18);
    const amountB = parseUnits("200", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), amountA);
    await tokenB.connect(Alice).approve(await lntMarketRouter.getAddress(), amountB);
    
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    await lntMarketRouter.connect(Alice).addLiquidity(
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      amountA,
      amountB,
      amountA, // Min amount A
      amountB, // Min amount B
      Alice.address,
      deadline
    );
    
    // Get pair address and liquidity token balance
    const pairAddress = await lntMarketFactory.getPair(await tokenA.getAddress(), await tokenB.getAddress());
    const pair = LntMarket__factory.connect(pairAddress, provider);
    const liquidityBalance = await pair.balanceOf(Alice.address);
    
    // Approve router to spend LP tokens
    await pair.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityBalance);
    
    // Check token balances before removing liquidity
    const aliceTokenABefore = await tokenA.balanceOf(Alice.address);
    const aliceTokenBBefore = await tokenB.balanceOf(Alice.address);
    
    // Remove all liquidity
    await lntMarketRouter.connect(Alice).removeLiquidity(
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      liquidityBalance,
      0, // Min amount A
      0, // Min amount B
      Alice.address,
      deadline
    );
    
    // Check token balances after removing liquidity
    const aliceTokenAAfter = await tokenA.balanceOf(Alice.address);
    const aliceTokenBAfter = await tokenB.balanceOf(Alice.address);
    
    // Verify that Alice received tokens back
    expect(aliceTokenAAfter - aliceTokenABefore).to.be.approximately(amountA, parseUnits("0.01", 18));
    expect(aliceTokenBAfter - aliceTokenBBefore).to.be.approximately(amountB, parseUnits("0.01", 18));
    
    // Verify LP balance is zero
    expect(await pair.balanceOf(Alice.address)).to.equal(0);
  });

  it('LntMarketRouter removes ETH-ERC20 liquidity correctly', async () => {
    const [Alice] = await ethers.getSigners();
    
    // First add liquidity
    const tokenAmount = parseUnits("100", 18);
    const ethAmount = parseUnits("1", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), tokenAmount);
    
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    await lntMarketRouter.connect(Alice).addLiquidityETH(
      await tokenA.getAddress(),
      tokenAmount,
      tokenAmount, // Min token amount
      ethAmount,   // Min ETH amount
      Alice.address,
      deadline,
      { value: ethAmount }
    );
    
    // Get pair address and liquidity token balance
    const pairAddress = await lntMarketFactory.getPair(await tokenA.getAddress(), await weth.getAddress());
    const pair = LntMarket__factory.connect(pairAddress, provider);
    const liquidityBalance = await pair.balanceOf(Alice.address);
    
    // Approve router to spend LP tokens
    await pair.connect(Alice).approve(await lntMarketRouter.getAddress(), liquidityBalance);
    
    // Check balances before removing liquidity
    const aliceTokenABefore = await tokenA.balanceOf(Alice.address);
    const aliceEthBefore = await provider.getBalance(Alice.address);
    
    // Remove all liquidity
    const removeTx = await lntMarketRouter.connect(Alice).removeLiquidityETH(
      await tokenA.getAddress(),
      liquidityBalance,
      0, // Min token amount
      0, // Min ETH amount
      Alice.address,
      deadline
    );
    const receipt = await removeTx.wait();
    
    // Calculate gas cost
    const gasUsed = receipt!.gasUsed * receipt!.gasPrice;
    
    // Check balances after removing liquidity
    const aliceTokenAAfter = await tokenA.balanceOf(Alice.address);
    const aliceEthAfter = await provider.getBalance(Alice.address);
    
    // Verify that Alice received tokens back
    expect(aliceTokenAAfter - aliceTokenABefore).to.be.approximately(tokenAmount, parseUnits("0.01", 18));
    
    // Verify that Alice received ETH back (accounting for gas costs)
    const ethDiff = aliceEthAfter - aliceEthBefore + gasUsed;
    expect(ethDiff).to.be.approximately(ethAmount, parseUnits("0.01", 18));
    
    // Verify LP balance is zero
    expect(await pair.balanceOf(Alice.address)).to.equal(0);
  });

  it('LntMarketRouter handles exact output swaps correctly', async () => {
    const [Alice, Bob] = await ethers.getSigners();
    
    // First add liquidity
    const amountA = parseUnits("1000", 18);
    const amountB = parseUnits("1000", 18);
    await tokenA.connect(Alice).approve(await lntMarketRouter.getAddress(), amountA);
    await tokenB.connect(Alice).approve(await lntMarketRouter.getAddress(), amountB);
    
    const deadline = BigInt(await time.latest()) + BigInt(ONE_DAY_IN_SECS);
    
    await lntMarketRouter.connect(Alice).addLiquidity(
      await tokenA.getAddress(),
      await tokenB.getAddress(),
      amountA,
      amountB,
      0, // Min amount A
      0, // Min amount B
      Alice.address,
      deadline
    );
    
    // Bob wants exactly 20 tokenB
    const exactOutputAmount = parseUnits("20", 18);
    const maxInputAmount = parseUnits("25", 18); // Willing to spend up to 25 tokenA
    
    // Approve router
    await tokenA.connect(Bob).approve(await lntMarketRouter.getAddress(), maxInputAmount);
    
    // Check balances before swap
    const bobTokenABefore = await tokenA.balanceOf(Bob.address);
    const bobTokenBBefore = await tokenB.balanceOf(Bob.address);
    
    // Perform the swap (tokens for exact tokens)
    const swapTx = await lntMarketRouter.connect(Bob).swapTokensForExactTokens(
      exactOutputAmount,
      maxInputAmount,
      [await tokenA.getAddress(), await tokenB.getAddress()],
      Bob.address,
      deadline
    );
    await swapTx.wait();
    
    // Check balances after swap
    const bobTokenAAfter = await tokenA.balanceOf(Bob.address);
    const bobTokenBAfter = await tokenB.balanceOf(Bob.address);
    
    // Verify Bob received exactly the requested amount of tokenB
    expect(bobTokenBAfter - bobTokenBBefore).to.equal(exactOutputAmount);
    
    // Verify Bob spent less than or equal to the max amount of tokenA
    const tokenASpent = bobTokenABefore - bobTokenAAfter;
    expect(tokenASpent).to.be.lte(maxInputAmount);
  });
});
