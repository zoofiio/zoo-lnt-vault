import { TransactionResponse } from "@ethersproject/providers";
import { FactoryOptions } from "@nomicfoundation/hardhat-ethers/types";
import { closeSync, existsSync, openSync, readFileSync, writeFileSync } from "fs";
import { ethers, network, run } from "hardhat";

const path = "./json/" + network.name + ".json";

if (!existsSync(path)) {
  const num = openSync(path, "w");
  closeSync(num);
}

export type DeployedVerifyJson = { [k: string]: any };
export function getJson(): DeployedVerifyJson {
  const json = readFileSync(path, "utf-8");
  const dto = JSON.parse(json || "{}") as any;
  return dto;
}

export function writeJson(dto: DeployedVerifyJson) {
  writeFileSync(path, JSON.stringify(dto, undefined, 2));
}

export function saveAny(dto: DeployedVerifyJson) {
  const old = getJson() || {};
  const nDto = { ...old, ...dto };
  writeJson(nDto);
}

export async function deployContract(name: string, args: any[], saveName?: string, factoryOptions?: FactoryOptions) {
  const showName = saveName || name;
  const old = getJson()[showName];
  const Factory = await ethers.getContractFactory(name, factoryOptions);
  if (!old?.address) {
    // console.log(`${showName} code size: ${Factory.bytecode.length / 2} bytes`);
    const Contract = await Factory.deploy(...args);
    await Contract.waitForDeployment();

    saveAny({ [showName]: { address: await Contract.getAddress(), args } });
    console.info("deployed:", showName, await Contract.getAddress());
    return await Contract.getAddress();
  } else {
    console.info("already deployed:", showName, old.address);
    return old.address as string;
  }
}

export async function deployUseCreate2(name: string, salt: string, typeargs: any[] = [], saveName?: string, factoryOptions?: FactoryOptions) {
  const showName = saveName || name;
  const AddCreate2 = "0x0000000000FFe8B47B3e2130213B802212439497";
  const immutableCreate2 = await ethers.getContractAt("ImmutableCreate2FactoryInterface", AddCreate2);
  let initCode = "";
  const factory = await ethers.getContractFactory(name, factoryOptions);
  if (typeargs.length) {
    const encodeArgs = ethers.AbiCoder.defaultAbiCoder().encode(typeargs.slice(0, typeargs.length / 2), typeargs.slice(typeargs.length / 2));
    initCode = ethers.solidityPacked(["bytes", "bytes"], [factory.bytecode, encodeArgs]);
  } else {
    initCode = factory.bytecode;
  }
  if (!initCode) throw "Error";
  const address = ethers.getCreate2Address(AddCreate2, salt, ethers.keccak256(ethers.toBeHex(initCode)));
  const deployed = await immutableCreate2.hasBeenDeployed(address);
  if (deployed) {
    console.info("already-deployd:", showName, address);
  } else {
    const tx = await immutableCreate2.safeCreate2(salt, initCode);
    await tx.wait(1);
    console.info("deplyed:", showName, address);
  }
  saveAny({ [showName]: { address, salt, typeargs } });
  return address;
}

export async function verfiy(key: string) {
  const json = getJson() || {};
  const item = json[key];
  if (!item.address) {
    return;
  }
  let taskArguments = {
    address: item.address,
  };

  if (item.contract) {
    taskArguments = {
      ...taskArguments,
      contract: item.contract,
    };
  }

  if (item.args) {
    taskArguments = {
      ...taskArguments,
      constructorArguments: item.args,
    };
  } else if (item.typeargs) {
    taskArguments = {
      ...taskArguments,
      constructorArguments: item.typeargs.slice(item.typeargs.length / 2),
    };
  }

  await run("verify:verify", {
    ...taskArguments,
  }).catch((error) => {
    console.error(error);
  });
}

export async function verifyAll() {
  const json = getJson() || {};
  for (const key in json) {
    console.info("start do verify:", key);
    await verfiy(key);
  }
}

export function wait1Tx<T extends { wait: (num: number) => Promise<any> }>(tx: T) {
  return tx.wait(1);
}

export function runAsync<T>(fn: () => Promise<T>, name: string = "Main") {
  fn()
    .catch(console.error)
    .then(() => console.info(name + " Finall"));
}
