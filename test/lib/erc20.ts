import { ethers, waffle } from 'hardhat'
import { deploy } from '../../scripts/deploy'
import { Contract, BigNumber, Signer } from 'ethers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import WethArtifact from '@primitivefi/contracts/artifacts/WETH9.json'
const { MaxUint256 } = ethers.constants
const { deployContract } = waffle

export const deployWeth = async (signer: Signer) => {
  const weth: Contract = await deployContract(signer, WethArtifact, [], {
    gasLimit: 9500000,
  })
  return weth
}

export const deployTokens = async (signer: Signer, quantity: number, totalSupply?: BigNumber) => {
  const amount = ethers.utils.parseEther('1000000000')
  let tokens: Contract[] = []

  for (let i = 0; i < quantity; i++) {
    let token = await deploy('TestERC20', { from: signer, args: [totalSupply ? totalSupply : amount] })
    tokens.push(token)
  }

  return tokens
}

export const deployVirtualTokens = async (signer: Signer, tokens: string[], house: string, totalSupply?: BigNumber) => {
  const amount = ethers.utils.parseEther('1000000000')
  let virtualTokens: Contract[] = []

  for (let i = 0; i < tokens.length; i++) {
    let token = await deploy('VERC20', { from: signer, args: [tokens[i], house] })
    virtualTokens.push(token)
  }

  return virtualTokens
}

export const batchApproval = async (
  arrayOfAddresses: string[],
  arrayOfTokens: Contract[],
  arrayOfSigners: SignerWithAddress[]
) => {
  // for each contract
  for (let c = 0; c < arrayOfAddresses.length; c++) {
    let address = arrayOfAddresses[c]
    // for each token
    for (let t = 0; t < arrayOfTokens.length; t++) {
      let token = arrayOfTokens[t]
      // for each owner
      for (let u = 0; u < arrayOfSigners.length; u++) {
        let signer = arrayOfSigners[u]
        let allowance = await token.connect(signer).allowance(signer.address, address)
        if (allowance < MaxUint256) {
          await token.connect(signer).approve(address, MaxUint256)
        }
      }
    }
  }
}
