// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

library Constants {
  /**
   * @notice The address interpreted as native token of the chain.
   */
  address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  uint256 public constant PROTOCOL_DECIMALS = 10;

  enum YtRewardsPoolOption {
    Opt1,
    Opt2
  }

  struct NftDeposit {
    address owner;
    uint256 nftTokenId;
    uint256 depositTime;
    uint256 depositAtEpoch;
    uint256 claimableTime;  // unused for nft deposits on epoch 0
    bool claimed;
    uint256 f1OnClaim;  // f1 value when claimed
  }

  struct NftRedeem {
    address owner;
    uint256 nftTokenId;
    uint256 redeemTime;
    uint256 redeemAtEpoch;
    uint256 claimableTime;
    bool claimed;
  }

  struct Epoch {
    uint256 epochId;
    uint256 startTime;
    uint256 duration;
    address ytSwapPaymentToken;
    uint256 ytSwapPrice;
    address ytRewardsPoolOpt1;
    address ytRewardsPoolOpt2;
  }

  struct Terms {
    uint256 T1;
    uint256 T2;
    uint256 T3;
    uint256 T4;
    uint256 T5;
    uint256 T6;
    uint256 T7;
    uint256 T8;
  }

}