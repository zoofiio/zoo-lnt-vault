// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ILntVault} from "./ILntVault.sol";

interface ILntYieldsVault is ILntVault {

    event EpochStarted(uint256 epochId, uint256 startTime, uint256 duration);

    struct Epoch {
        uint256 epochId;
        uint256 startTime;
        uint256 duration;
        address yt;
        address ytSwap;
    }

    function currentEpoch() external view returns (uint256);

    function epochCount() external view returns (uint256);

    function epochInfo(uint256 epochId) external view returns (Epoch memory);

    function totalWeightedDepositValue() external view returns (uint256);

    function addNftStakingRewards(address rewardsToken, uint256 rewardsAmount) external payable;

    function addYTRewards(address rewardsToken, uint256 rewardsAmount) external payable;

    function addYTTimeWeightedRewards(address rewardsToken, uint256 rewardsAmount) external payable;

}
