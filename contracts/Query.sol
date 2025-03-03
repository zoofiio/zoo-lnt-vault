// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;
import "./interfaces/IVault.sol";
import "./libs/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface MIVault is IVault {
    function initialized() external view returns (bool);

    function epochIdCount() external view returns (uint256);

    function Y() external view returns (uint256);

    function nftVtAmount() external view returns (uint256);

    function nftVestingEndTime() external view returns (uint256);

    function nftVestingDuration() external view returns (uint256);

    function nftDepositIds() external view returns (uint256[] memory);
}

interface ERC20 is IERC20 {
    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

interface BribesPool {
    function bribeTokens() external view returns (address[] memory);

    function earned(
        address user,
        address bribeToken
    ) external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    // only adhocBribesPool
    function collectableYT(
        address user
    ) external view returns (uint256, uint256);
}

interface IYtRewardsPool {
    function rewardsTokens() external view returns (address[] memory);

    function earned(
        address user,
        address rewardsToken
    ) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address user) external view returns (uint256);

    // for opt2
    function ytCollectTimestampApplicable() external view returns (uint256);

    function collectableYt(
        address user
    ) external view returns (uint256, uint256);
}

contract Query is Ownable {
    struct VaultEpoch {
        uint256 epochId;
        uint256 startTime;
        uint256 duration;
        address ytSwapPaymentToken;
        uint256 ytSwapPrice;
        address ytRewardsPoolOpt1;
        address ytRewardsPoolOpt2;
        uint256 yTokenTotalSupply;
        uint256 vaultYTokenBalance;
    }
    struct Vault {
        uint256 epochCount;
        uint256 nftVtAmount;
        uint256 nftVestingEndTime;
        uint256 nftVestingDuration;
        bool initialized;
        uint256 yTokenTotalSupply; // YT TotalSupply
        uint256 f2;
        uint256 Y;
        uint256 NftDepositLeadingTime;
        uint256 NftRedeemWaitingPeriod;
        VaultEpoch current;
    }
    struct RewardInfo {
        uint256 epochId;
        address token;
        string symbol;
        uint8 decimals;
        uint256 earned;
        uint256 total;
    }
    struct VaultEpochUser {
        uint256 epochId;
        RewardInfo[] opt1;
        RewardInfo[] opt2;
        uint256 userBalanceYToken;
        // for opt2
        uint256 userYTPoints;
        uint256 userClaimableYTPoints;
    }

    constructor() Ownable(_msgSender()) {}

    function queryVault(address vault) external view returns (Vault memory) {
        return _queryVault(vault);
    }

    function queryVaultEpoch(
        address vault,
        uint256 epochId
    ) external view returns (VaultEpoch memory) {
        return _queryVaultEpoch(vault, epochId);
    }

    function queryVaultEpochUser(
        address vault,
        uint256 epochId,
        address user
    ) external view returns (VaultEpochUser memory veu) {
        return _queryVaultEpochUser(vault, epochId, user);
    }

    // ====================internal====================

    function _queryVault(address vault) internal view returns (Vault memory v) {
        MIVault iv = MIVault(vault);
        (bool successEpochId, bytes memory _epochId) = vault.staticcall(
            abi.encodeWithSignature("currentEpochId()")
        );
        if (successEpochId) {
            v.epochCount = abi.decode(_epochId, (uint256));
        }
        v.initialized = iv.initialized();
        v.f2 = iv.paramValue("f2");
        v.nftVtAmount = iv.nftVtAmount();
        v.nftVestingDuration = iv.nftVestingDuration();
        v.nftVestingEndTime = iv.nftVestingEndTime();
        v.NftDepositLeadingTime = iv.paramValue('NftDepositLeadingTime');
        v.NftRedeemWaitingPeriod = iv.paramValue('NftRedeemWaitingPeriod');
        (bool successY, bytes memory data) = vault.staticcall(
            abi.encodeWithSignature("Y()")
        );
        if (successY) {
            v.Y = abi.decode(data, (uint256));
        }

        if (v.epochCount > 0) {
            v.current = _queryVaultEpoch(vault, v.epochCount);
        }
    }

    function _queryVaultEpoch(
        address vault,
        uint256 epochId
    ) internal view returns (VaultEpoch memory ve) {
        MIVault iv = MIVault(vault);
        Constants.Epoch memory epoch = iv.epochInfoById(epochId);
        ve.epochId = epoch.epochId;
        ve.startTime = epoch.startTime;
        ve.duration = epoch.duration;
        ve.ytRewardsPoolOpt1 = epoch.ytRewardsPoolOpt1;
        ve.ytRewardsPoolOpt2 = epoch.ytRewardsPoolOpt2;
        ve.ytSwapPaymentToken = epoch.ytSwapPaymentToken;
        ve.ytSwapPrice = epoch.ytSwapPrice;
        ve.yTokenTotalSupply = iv.yTokenTotalSupply(epochId);
        ve.vaultYTokenBalance = iv.yTokenUserBalance(epochId, vault);
    }

    function _queryVaultEpochUser(
        address vault,
        uint256 epochId,
        address user
    ) internal view returns (VaultEpochUser memory veu) {
        MIVault iv = MIVault(vault);
        veu.epochId = epochId;
        Constants.Epoch memory epoch = iv.epochInfoById(epochId);
        IYtRewardsPool iytPool1 = IYtRewardsPool(epoch.ytRewardsPoolOpt1);
        IYtRewardsPool iytPool2 = IYtRewardsPool(epoch.ytRewardsPoolOpt2);
        address[] memory pool1tokens = iytPool1.rewardsTokens();
        address[] memory pool2tokens = iytPool2.rewardsTokens();
        veu.opt1 = new RewardInfo[](pool1tokens.length);
        veu.opt2 = new RewardInfo[](pool2tokens.length);
        unchecked {
            for (uint i = 0; i < pool1tokens.length; i++) {
                address token = pool1tokens[i];
                veu.opt1[i].epochId = epochId;
                veu.opt1[i].token = token;
                veu.opt1[i].earned = iytPool1.earned(user, token);
                ERC20 erc20Token = ERC20(token);
                veu.opt1[i].symbol = erc20Token.symbol();
                veu.opt1[i].decimals = erc20Token.decimals();
                veu.opt1[i].total = erc20Token.balanceOf(
                    epoch.ytRewardsPoolOpt1
                );
            }
            for (uint i = 0; i < pool2tokens.length; i++) {
                address token = pool2tokens[i];
                veu.opt2[i].epochId = epochId;
                veu.opt2[i].token = token;
                veu.opt2[i].earned = iytPool2.earned(user, token);
                ERC20 erc20Token = ERC20(token);
                veu.opt2[i].symbol = erc20Token.symbol();
                veu.opt2[i].decimals = erc20Token.decimals();
                veu.opt2[i].total = erc20Token.balanceOf(
                    epoch.ytRewardsPoolOpt2
                );
            }
        }
        veu.userBalanceYToken = iv.yTokenUserBalance(epochId, user);
        veu.userYTPoints = iytPool2.balanceOf(user);
        (, veu.userClaimableYTPoints) = iytPool2.collectableYt(user);
    }
}
