import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { encodeBytes32String } from "ethers";
import { ethers } from "hardhat";
import { deployContractsFixture } from "./utils";
import {
  MockERC20__factory,
  MockERC721__factory,
  Vault__factory,
  VToken__factory
} from "../typechain";

const { provider } = ethers;

describe("Ownable", () => {

  it("Protocol ownable work", async () => {
    const {
      Alice, Bob, protocol, settings, vault
    } = await loadFixture(deployContractsFixture);
    const vToken = VToken__factory.connect(await vault.vToken(), provider);

    let protocolOwner = await protocol.owner();
    expect(protocolOwner).to.equal(await protocol.protocolOwner(), "Protocol owner is Alice");
    expect(protocolOwner).to.equal(Alice.address, "Protocol owner is Alice");

    const contracts = [settings, vault, vToken];
    for (const contract of contracts) {
      const owner = await contract.owner();
      expect(owner).to.equal(protocolOwner, "Contract owner is protocol owner Alice");
    }
    
    await expect(protocol.connect(Bob).transferOwnership(Bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(protocol.connect(Alice).transferOwnership(Bob.address))
      .to.emit(protocol, "OwnershipTransferred")
      .withArgs(Alice.address, Bob.address);

    protocolOwner = await protocol.owner();
    expect(protocolOwner).to.equal(await protocol.protocolOwner(), "Protocol owner is Bob");
    expect(protocolOwner).to.equal(Bob.address, "Protocol owner is Bob");

    for (const contract of contracts) {
      const owner = await contract.owner();
      expect(owner).to.equal(Bob.address, "Contract owner is protocol owner Bob");
    }
  });

  it("Privileged operations", async () => {
    const {
      Alice, Bob, protocol, settings, nftStakingPoolFactory, ytRewardsPoolFactory, vault, vaultCalculator
    } = await loadFixture(deployContractsFixture);
    const vToken = VToken__factory.connect(await vault.vToken(), provider);

    let protocolOwner = await protocol.owner();
    expect(protocolOwner).to.equal(await protocol.protocolOwner(), "Protocol owner is Alice");
    expect(protocolOwner).to.equal(Alice.address, "Protocol owner is Alice");

    // Create vault. Any one could deploy a Vault, but only protocol owner could register it to protocol
    const MockERC721Factory = await ethers.getContractFactory("MockERC721");
    const MockERC721 = await MockERC721Factory.deploy(await protocol.getAddress(), "Dummy NFT", "DNFT");
    const dummyNft = MockERC721__factory.connect(await MockERC721.getAddress(), provider);
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const MockERC20 = await MockERC20Factory.deploy(await protocol.getAddress(), "Dummy Token", "DMY", 18);
    const dummyToken = MockERC20__factory.connect(await MockERC20.getAddress(), provider);
    const VaultFactory = await ethers.getContractFactory("Vault", {
      libraries: {
        VaultCalculator: await vaultCalculator.getAddress(),
      }
    });
    const DmyVaultContract = await VaultFactory.deploy(
      await protocol.getAddress(), await settings.getAddress(), await nftStakingPoolFactory.getAddress(), await ytRewardsPoolFactory.getAddress(),
      await dummyNft.getAddress(), await dummyToken.getAddress(), "Zoo vDmy", "vDmy"
    );
    const dummyVault = Vault__factory.connect(await DmyVaultContract.getAddress(), provider);

    await expect(protocol.connect(Bob).addVault(await dummyVault.getAddress())).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(protocol.connect(Alice).transferOwnership(Bob.address)).not.to.be.reverted;
    await expect(protocol.connect(Bob).addVault(await dummyVault.getAddress()))
      .to.emit(protocol, "VaultAdded")
      .withArgs(await dummyNft.getAddress(), await dummyVault.getAddress());
    expect(await protocol.isVault(await dummyVault.getAddress())).to.equal(true, "Vault is added");
    expect(await protocol.isVaultAsset(await dummyNft.getAddress())).to.equal(true, "Vault asset is added");
    expect(await protocol.getVaultAddresses(await dummyNft.getAddress())).to.deep.equal([await dummyVault.getAddress()], "Vault address is added");
    
    // Only admin could update params
    await expect(settings.connect(Alice).setTreasury(Bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(settings.connect(Alice).upsertParamConfig(encodeBytes32String("C"), 5 * 10 ** 8, 1 * 10 ** 8, 10 ** 10)).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(settings.connect(Alice).updateVaultParamValue(await dummyVault.getAddress(), encodeBytes32String("C"), 10 ** 8)).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(protocol.connect(Bob).transferOwnership(Alice.address)).not.to.be.reverted;
    await expect(settings.connect(Alice).setTreasury(Bob.address))
      .to.emit(settings, "UpdateTreasury")
      .withArgs(anyValue, Bob.address);

    await expect(settings.connect(Alice).upsertParamConfig(encodeBytes32String("C"), 5 * 10 ** 8, 1 * 10 ** 8, 10 ** 10))
      .to.emit(settings, "UpsertParamConfig")
      .withArgs(encodeBytes32String("C"), 5 * 10 ** 8, 1 * 10 ** 8, 10 ** 10);
    await expect(settings.connect(Alice).updateVaultParamValue(await dummyVault.getAddress(), encodeBytes32String("C"), 10 ** 7)).to.be.revertedWith("Invalid param or value");
    await expect(settings.connect(Alice).updateVaultParamValue(await dummyVault.getAddress(), encodeBytes32String("C"), 2 * 10 ** 8))
      .to.emit(settings, "UpdateVaultParamValue")
      .withArgs(await dummyVault.getAddress(), encodeBytes32String("C"), 2 * 10 ** 8);
    expect(await settings.treasury()).to.equal(Bob.address, "Treasury is Bob");
    expect(await settings.paramConfig(encodeBytes32String("C"))).to.deep.equal([5n * 10n ** 8n, 1n * 10n ** 8n, 10n ** 10n], "Param C is updated");
    expect(await settings.vaultParamValue(await dummyVault.getAddress(), encodeBytes32String("C"))).to.equal(2 * 10 ** 8, "Vault param C is updated");
   
    // Only admin could update principal token's name and symbol
    await expect(vToken.connect(Bob).setName("Dummy V Token V2")).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(vToken.connect(Bob).setSymbol("DmyVT2")).to.be.revertedWith("Ownable: caller is not the owner");
    await expect(vToken.connect(Alice).setName("Dummy V Token V2")).not.to.be.reverted;
    await expect(vToken.connect(Alice).setSymbol("DmyVT2")).not.to.be.reverted;
    expect(await vToken.name()).to.equal("Dummy V Token V2", "V Token name is updated");
    expect(await vToken.symbol()).to.equal("DmyVT2", "V Token symbol is updated");

  });

});
