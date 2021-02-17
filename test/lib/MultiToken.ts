import { ethers, waffle } from 'hardhat'
import { deploy } from '../../scripts/deploy'
import { Contract, BigNumber, Signer } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import WethArtifact from '@primitivefi/contracts/artifacts/WETH9.json'
import MultiToken from '../../build/contracts/MultiToken.sol/MultiToken.json'
const { MaxUint256 } = ethers.constants
const { deployContract } = waffle

export const deployMultiToken = async (signer: Signer) => {
  let token = await deploy('MultiToken', { from: signer, args: [] })
  return token
}

export const multiTokenFromAddress = async (address: string, signer: Signer) => {
  let token = new ethers.Contract(address, MultiToken.abi, signer)
  return token
}
