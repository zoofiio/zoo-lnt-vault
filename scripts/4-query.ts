import dotenv from "dotenv";
import { deployContract } from "./hutils";
import { Query__factory } from "../typechain";
import { ethers } from "hardhat";

dotenv.config();

async function main() {
  //   const [root] = await ethers.getSigners();
  const queryAddress = await deployContract("Query", []);
  const [deployer] = await ethers.getSigners();
  const query = Query__factory.connect(queryAddress, deployer);
  const vault = '0x9DaBa44CAe05339B0269c3eCE750313d1C3216c8';
  const current = await query.queryVault(vault);
  console.info("Vault", current);
}

main().catch(console.error);
