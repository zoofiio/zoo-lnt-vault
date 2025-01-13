import dotenv from "dotenv";
import { ethers } from "hardhat";
import { MockERC721__factory } from "../typechain";
import { getJson, wait1Tx } from "./hutils";

dotenv.config();

async function main() {
  const [root] = await ethers.getSigners();
  const data = getJson();
  const mk721 = MockERC721__factory.connect(data["MockERC721"].address, root);
  const to = root.address;

  // for (let tokenId = 2000; tokenId < 2010; tokenId++) {
  //   await mk721.safeMint(to, tokenId).then(wait1Tx);
  //   console.info("minted:", tokenId);
  // }
  const tokenids = [1000001, 1000002, 2000, 2001];
  for (const tokenid of tokenids) {
    console.info("owner:", tokenid, await mk721.ownerOf(tokenid));
  }
}

main().catch(console.error);
