import { ethers, waffle } from 'hardhat'
import { Signer } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { TransactionRequest } from '@ethersproject/providers'
import UniswapV2FactoryABI from '@uniswap/v2-core/build/UniswapV2Factory.json'
const { deployContract } = waffle

const DEFAULT_DEPLOY: TransactionRequest = {
  gasLimit: 9500000,
}

export const deployFactory = async (signer: Signer, ...args: any) => {
  const contract = await deployContract(signer, UniswapV2FactoryABI, [...args], DEFAULT_DEPLOY)
  return contract
}
