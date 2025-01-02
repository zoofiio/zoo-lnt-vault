

```mermaid
classDiagram
note for ZooProtocol "Entry point of protocol"
class ZooProtocol {
  +address owner
  +ProtocolSettings settings
  +Vault[] vaults
  +addVault(vault)
}
class ProtocolSettings {
  +address treasury
  +Params[] params
  +Params[] vaultParams
  +setTreasury(treasury)
  +upsertParamConfig(default, min, max)
  +updateVaultParamValue(vault, param, value)
}
namespace LNT-Vault {
  class Vault {
    +address nftToken
    +address nftStakingPool
    +address vTokens
    +address[] epochYtRewardsPoolOpt1
    +address[] epochYtRewardsPoolOpt2
    +initialize(...)
    +startEpoch1()
    +depositNft(nftTokenId)
    +claimDepositNft(nftTokenId)
    +redeemNft(nftTokenId)
    +claimRedeemNft(nftTokenId)
    +swap(amount)
    +addYtRewards(token, amount, opt)
  }
  class VToken {
    +mint(amount)
    +burn(amount)
    +...()
  }
  class NftStakingPool {
    +balanceOf(address)
    +totalSupply()
    +earned(user, rewardsToken)
    +notifyNftDepositForUser(user, nftTokenId)
    +notifyNftRedeemForUser(user, nftTokenId)
    +getRewards()
    +addRewards(rewardsToken, rewardsAmount)
    +...()
  }
  class YtRewardsPoolOpt1 {
    +balanceOf(address)
    +totalSupply()
    +earned(user, rewardsToken)
    +getRewards()
    +notifyYtSwappedForUser(user, amount)
    +addRewards(rewardsToken, amount)
    +...()
  }
  class YtRewardsPoolOpt2 {
    +balanceOf(address)
    +totalSupply()
    +earned(user, rewardsToken)
    +collectableYt()
    +collectYt()
    +getRewards()
    +notifyYtSwappedForUser(user, amount)
    +addRewards(rewardsToken, amount)
    +...()
  }
}


ZooProtocol --> ProtocolSettings
ZooProtocol "1" --> "*" Vault
Vault --> VToken
Vault --> NftStakingPool
Vault --> YtRewardsPoolOpt1 : Each Epoch
Vault --> YtRewardsPoolOpt2 : Each Epoch
``````