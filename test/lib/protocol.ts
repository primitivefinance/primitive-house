import { ethers, waffle } from 'hardhat'
import { Signer } from 'ethers'
import UniswapV2Router02 from '@uniswap/v2-periphery/build/UniswapV2Router02.json'
import UniswapV2Factory from '@uniswap/v2-core/build/UniswapV2Factory.json'
import Option from '@primitivefi/contracts/artifacts/Option.json'
import Redeem from '@primitivefi/contracts/artifacts/Redeem.json'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { TransactionRequest } from '@ethersproject/providers'

const { deployContract } = waffle

const DEFAULT_DEPLOY: TransactionRequest = {
  gasLimit: 9500000,
}

export const deployUniRouter = async (signer: Signer, ...args: any) => {
  console.log(args)
  const contract = await deployContract(signer, UniswapV2Router02, [...args], DEFAULT_DEPLOY)
  return contract
}

export const deployUniswap = async (signer: SignerWithAddress, ...args: any) => {
  const factory = await deployContract(signer, UniswapV2Factory, [signer.address], DEFAULT_DEPLOY)
  const router = await deployContract(signer, UniswapV2Router02, [factory.address, ...args], DEFAULT_DEPLOY)
  return [factory, router]
}

export const deployPrimitiveOption = async (signer: SignerWithAddress, ...args: any) => {
  const option = await deployContract(signer, Option, [], DEFAULT_DEPLOY)
  await option.initialize(...args)
  const redeem = await deployContract(signer, Redeem, [], DEFAULT_DEPLOY)
  await redeem.initialize(signer.address, option.address)
  await option.initRedeemToken(redeem.address)

  return [option, redeem]
}
