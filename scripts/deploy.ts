import { Contract, Signer } from 'ethers'
import { ethers } from 'hardhat'

export const deploy = async (contractName: string, { from, args }: { from?: Signer; args: any }): Promise<Contract> => {
  let factory = await ethers.getContractFactory(contractName)
  if (from) {
    factory.connect(from)
  }
  const contract = await factory.deploy(...args)
  await contract.deployed()
  return contract
}
