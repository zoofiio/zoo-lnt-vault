// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

interface IYTSwap  {

    event Initialized();

    event Swap(address indexed user, uint256 ytSwapPaymentAmount, uint256 fees, uint256 yTokenAmount);

    function initialize(
        address _yt, address _ytSwapPaymentToken, uint256 _ytSwapPrice,
        uint256 _epochStartTime, uint256 _epochDuration, uint256 _ytInitAmount
    ) external;
    
}
