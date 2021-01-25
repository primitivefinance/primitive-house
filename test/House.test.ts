import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { deploy } from '../scripts/deploy'
import { deployTokens, deployWeth, batchApproval } from './lib/erc20'
const { AddressZero } = ethers.constants

describe('House', function () {
  let signers: SignerWithAddress[]
  let weth: Contract
  let house: Contract
  let signer: SignerWithAddress
  let tokens: Contract[], comp: Contract, dai: Contract, wbtc: Contract

  before(async function () {
    signers = await ethers.getSigners()
    signer = signers[0]
    tokens = await deployTokens(signer, 2)
    ;[comp, dai] = tokens
  })

  describe('House.constructor', function () {
    beforeEach(async function () {
      weth = await deployWeth(signer)
      house = await deploy('House', { from: signers[0], args: [weth.address, AddressZero, AddressZero] })
    })

    it('weth()', async () => {
      expect(await house.weth()).to.eq(weth.address)
    })
    it('registry()', async () => {
      expect(await house.registry()).to.eq(AddressZero)
    })
    it('capitol()', async () => {
      expect(await house.capitol()).to.eq(AddressZero)
    })
  })

  const getTokenAddresses = () => {
    const array = tokens.map((token) => {
      return token.address
    })
    return array
  }

  const getAmounts = () => {
    let ONE: BigNumber = parseEther('1')
    const array = tokens.map(() => {
      return ONE
    })
    return array
  }

  describe('House.addTokens', function () {
    beforeEach(async function () {
      weth = await deployWeth(signer)
      house = await deploy('House', { from: signers[0], args: [weth.address, AddressZero, AddressZero] })
      await batchApproval([house.address], tokens, [signer])
    })

    it('adds tokens successfully', async () => {
      let depositor: string = signer.address
      await house.addTokens(depositor, getTokenAddresses(), getAmounts())
      tokens.map(async (token, i) => {
        expect(await house.credit(token.address, signer.address)).to.eq(getAmounts()[i])
      })
    })
  })
})
