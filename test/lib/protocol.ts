import { ethers, waffle } from 'hardhat'
import { Signer } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { TransactionRequest } from '@ethersproject/providers'
const { deployContract } = waffle

const DEFAULT_DEPLOY: TransactionRequest = {
  gasLimit: 9500000,
}

export const deploy = async (signer: Signer, ...args: any) => {
  //const contract = await deployContract(signer, UniswapV2Router02, [...args], DEFAULT_DEPLOY)
  //return contract
}
