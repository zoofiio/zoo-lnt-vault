import { ethers } from "hardhat";

async function main() {
  const LntMarket = await ethers.getContractFactory('LntMarket');
  console.log(ethers.keccak256(LntMarket.bytecode));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});