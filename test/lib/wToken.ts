import { ethers, waffle } from 'hardhat'
import { deploy } from '../../scripts/deploy'
import { Contract, BigNumber, Signer } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import WethArtifact from '@primitivefi/contracts/artifacts/WETH9.json'
import wToken from '../../build/contracts/WToken.sol/wToken.json'
const { MaxUint256 } = ethers.constants
const { deployContract } = waffle

export const deployWrappedToken = async (signer: Signer) => {
  let token = await deploy('wToken', { from: signer, args: [] })
  return token
}

export const wrappedTokenFromAddress = async (address: string, signer: Signer) => {
  let token = new ethers.Contract(address, wToken.abi, signer)
  return token
}
