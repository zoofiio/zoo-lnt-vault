// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "../interfaces/IProtocolSettings.sol";
import "../interfaces/INftStakingPoolFactory.sol";
import "../interfaces/IYtRewardsPool.sol";
import "../interfaces/IVault.sol";
import "../libs/Constants.sol";
import "../libs/TokensTransfer.sol";
import "../tokens/VToken.sol";

contract MockVault is IVault {
  address public immutable settings;
  address public immutable nftStakingPool;
  address public immutable ytRewardsPoolFactory;

  address public immutable nftToken;
  address public immutable nftVestingToken;
  address public immutable vToken;

  address public ytSwapPaymentToken;
  uint256 public ytSwapPrice;

  uint8 public constant ytDecimals = 18;

  constructor(
    address _protocol,
    address _settings,
    address _nftStakingPoolFactory,
    address _ytRewardsPoolFactory,
    address _nftToken,
    address _nftVestingToken,
    string memory _vTokenName, string memory _vTokenSymbol
  ) {
    settings = _settings;

    nftStakingPool = INftStakingPoolFactory(_nftStakingPoolFactory).createNftStakingPool(address(this));
    ytRewardsPoolFactory = _ytRewardsPoolFactory;

    nftToken = _nftToken;
    nftVestingToken = _nftVestingToken;
    vToken = address(new VToken(_protocol, _settings, _vTokenName, _vTokenSymbol, IERC20Metadata(nftVestingToken).decimals()));
  }

  /* ========== IVault Functions ========== */

  function currentEpochId() public pure returns (uint256) {
    return 0;
  }

  function epochInfoById(uint256) public pure returns (Constants.Epoch memory) {
    return Constants.Epoch(0, 0, 0, address(0), 0, address(0), address(0));
  }

  function paramValue(bytes32) public pure returns (uint256) {
    return 0;
  }

  function ytNewEpoch() public pure returns (uint256) {
    return 0;
  }


  function yTokenTotalSupply(uint256) public pure returns (uint256) {
    return 0;
  }

  function yTokenUserBalance(uint256, address) public pure returns (uint256) {
    return 0;
  }

  function epochNextSwapX(uint256) external pure returns (uint256) {
    return 0;
  }

  function epochNextSwapK0(uint256) external pure returns (uint256) {
    return 0;
  }

  /* ========== Mock Functions ========== */

  function mockNotifyYtSwappedForUser(IYtRewardsPool ytRewardsPool, address user, uint256 yTokenAmount) external {
    ytRewardsPool.notifyYtSwappedForUser(user, yTokenAmount);
  }

  function mockAddRewards(IYtRewardsPool ytRewardsPool, address rewardsToken, uint256 rewardsAmount) external {
    TokensTransfer.transferTokens(rewardsToken, msg.sender, address(this), rewardsAmount);
    IERC20(rewardsToken).approve(address(ytRewardsPool), rewardsAmount);
    ytRewardsPool.addRewards(rewardsToken, rewardsAmount);
  }

}
