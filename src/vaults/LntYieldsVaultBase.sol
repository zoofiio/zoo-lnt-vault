// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ILntYieldsVault} from "../interfaces/ILntYieldsVault.sol";
import {INftStakingPool} from "../interfaces/INftStakingPool.sol";
import {IYieldToken} from "../interfaces/IYieldToken.sol";
import {IYTSwap} from "../interfaces/IYTSwap.sol";
import {Constants} from "../libs/Constants.sol";
import {TokensHelper} from "../libs/TokensHelper.sol";
import {LntVaultBase} from "./LntVaultBase.sol";

abstract contract LntYieldsVaultBase is LntVaultBase, ILntYieldsVault {

    uint256 internal _currentEpochId;  // default to 0
    mapping(uint256 => Epoch) internal _epochs;  // epoch id => epoch info

    address public nftStakingPool;

    uint256 public totalWeightedDepositValue;

    mapping(address => uint256) internal _pendingNftStakingRewards;

    constructor(address _owner) LntVaultBase(_owner) {

    }

    /* ================= VIEWS ================ */

    function currentEpoch() public view returns (uint256) {
        require(_currentEpochId > 0, "No epochs yet");
        return _currentEpochId;
    }

    function epochCount() public view returns (uint256) {
        return _currentEpochId;
    }

    function epochInfo(uint256 epochId) public view onlyValidEpochId(epochId) returns (Epoch memory) {
        return _epochs[epochId];
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, LntVaultBase) returns (bool) {
        return interfaceId == type(ILntYieldsVault).interfaceId || super.supportsInterface(interfaceId);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function __LntYieldVaultBase_init(address _NFT, address _lntMarketRouter, address _VT, address _nftStakingPool) internal onlyOwner {
        __LntVaultBase_init(_NFT, _lntMarketRouter, _VT);
        require(_nftStakingPool != address(0), "Zero address detected");
        nftStakingPool = _nftStakingPool;
    }

    function startNewEpoch(
        address yt, address ytSwap, address ytSwapPaymentToken, uint256 ytSwapPrice
    ) external nonReentrant onlyOwner onlyInitialized {
        require(yt != address(0) && ytSwap != address(0) && ytSwapPaymentToken != address(0), "Zero address detected");
        require(ytSwapPrice > 0, "Invalid price");

        if (_currentEpochId > 0) {
            Epoch memory epoch = _epochs[_currentEpochId];
            require(block.timestamp > epoch.startTime + epoch.duration, "Current epoch not ended yet");
        }

        _currentEpochId++;
        _epochs[_currentEpochId].epochId = _currentEpochId;
        _epochs[_currentEpochId].startTime = block.timestamp;
        _epochs[_currentEpochId].duration = paramValue("D");
        _epochs[_currentEpochId].yt = yt;
        _epochs[_currentEpochId].ytSwap = ytSwap;

        emit EpochStarted(_currentEpochId, block.timestamp, paramValue("D"));

        uint256 ytDecimals = IERC20Metadata(yt).decimals();
        uint256 ytInitAmount = totalWeightedDepositValue * (10 ** ytDecimals);
        IYieldToken(yt).mint(address(this), ytInitAmount);
        IYieldToken(yt).approve(ytSwap, ytInitAmount);

        IYieldToken(yt).setEpochEndTimestamp(_epochs[_currentEpochId].startTime + _epochs[_currentEpochId].duration);

        IYTSwap(ytSwap).initialize(
            yt, ytSwapPaymentToken, ytSwapPrice, 
            _epochs[_currentEpochId].startTime, _epochs[_currentEpochId].duration, ytInitAmount
        );
    }

    function addNftStakingRewards(address rewardsToken, uint256 rewardsAmount) external override payable nonReentrant onlyInitialized onlyYTSwap(_currentEpochId) {
        require(rewardsAmount > 0, "Invalid rewards amount");
        require(rewardsToken != address(0), "Zero address detected");

        if (rewardsToken == Constants.NATIVE_TOKEN) {
            require(msg.value == rewardsAmount, "Invalid msg.value");
        }
        else {
            require(msg.value == 0, "Invalid msg.value");
            TokensHelper.transferTokens(rewardsToken, _msgSender(), address(this), rewardsAmount);
        }

        if (INftStakingPool(nftStakingPool).totalSupply() == 0) {
            _pendingNftStakingRewards[rewardsToken] += rewardsAmount;
        }
        else {
            uint256 allStakingRewards = _pendingNftStakingRewards[rewardsToken] + rewardsAmount;
            _pendingNftStakingRewards[rewardsToken] = 0;
            uint256 balance = TokensHelper.balance(address(this), rewardsToken);
            uint256 rewards = Math.min(allStakingRewards, balance);

            if (rewardsToken == Constants.NATIVE_TOKEN) {
                INftStakingPool(nftStakingPool).addRewards{value: rewards}(rewardsToken, rewards);
            }
            else {
                IERC20(rewardsToken).approve(nftStakingPool, rewards);
                INftStakingPool(nftStakingPool).addRewards(rewardsToken, rewards);
            }
        }
    }

    function addYTRewards(address rewardsToken, uint256 rewardsAmount) external override payable nonReentrant onlyOwner onlyInitialized onlyValidEpochId(_currentEpochId) {
        require(rewardsAmount > 0, "Invalid rewards amount");
        require(rewardsToken != address(0), "Zero address detected");

        IYieldToken yt = IYieldToken(_epochs[_currentEpochId].yt);

        if (rewardsToken == Constants.NATIVE_TOKEN) {
            require(msg.value == rewardsAmount, "Invalid msg.value");
            yt.addRewards{value: msg.value}(rewardsToken, rewardsAmount);
        }
        else {
            require(msg.value == 0, "Invalid msg.value");
            TokensHelper.transferTokens(rewardsToken, _msgSender(), address(this), rewardsAmount);
            IERC20(rewardsToken).approve(address(yt), rewardsAmount);
            yt.addRewards(rewardsToken, rewardsAmount);
        }
    }

    function addYTTimeWeightedRewards(address rewardsToken, uint256 rewardsAmount) external override payable nonReentrant onlyOwner onlyInitialized onlyValidEpochId(_currentEpochId) {
        require(rewardsAmount > 0, "Invalid rewards amount");
        require(rewardsToken != address(0), "Zero address detected");

        IYieldToken yt = IYieldToken(_epochs[_currentEpochId].yt);

        if (rewardsToken == Constants.NATIVE_TOKEN) {
            require(msg.value == rewardsAmount, "Invalid msg.value");
            yt.addTimeWeightedRewards{value: msg.value}(rewardsToken, rewardsAmount);
        }
        else {
            require(msg.value == 0, "Invalid msg.value");
            TokensHelper.transferTokens(rewardsToken, _msgSender(), address(this), rewardsAmount);
            IERC20(rewardsToken).approve(address(yt), rewardsAmount);
            yt.addTimeWeightedRewards(rewardsToken, rewardsAmount);
        }
    }


    /* ============== MODIFIERS =============== */

    modifier onlyValidEpochId(uint256 epochId) {
        require(
            epochId > 0 && epochId <= _currentEpochId && _epochs[epochId].startTime > 0,
            "Invalid epoch id"
        );
        _;
    }

    modifier onlyYTSwap(uint256 epochId) {
        require(_msgSender() == _epochs[epochId].ytSwap, "Caller is not YTSwap");
        _;
    }


}
