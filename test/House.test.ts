import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, BigNumberish, Contract } from 'ethers'
import { parseEther, formatEther } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { deploy } from '../scripts/deploy'
import { deployTokens, deployWeth, batchApproval } from './lib/erc20'
import {} from './lib/protocol'
import { log } from './lib/utils'
import generateReport from './lib/table/generateReport'
const { AddressZero } = ethers.constants

describe('House', function () {
  let signers: SignerWithAddress[]
  let weth: Contract
  let house: Contract
  let signer: SignerWithAddress
  let tokens: Contract[], comp: Contract, dai: Contract
  let venue: Contract
  const deadline = Math.floor(Date.now() / 1000) + 60 * 20

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

  before(async function () {
    // 1. get signers
    signers = await ethers.getSigners()
    signer = signers[0]

    // 2. get weth, erc-20 tokens
    weth = await deployWeth(signer)
    tokens = await deployTokens(signer, 2)
    ;[comp, dai] = tokens

    // 3. select option params

    // 4. deploy house
    house = await deploy('House', { from: signers[0], args: [AddressZero] })

    // 5. deploy venue
    venue = await deploy('BasicVenue', { from: signers[0], args: [weth.address, house.address] })

    let contractNames: string[] = ['House']
    let contracts = [house]
    let addresses = [signer.address]
    await generateReport(contractNames, contracts, tokens, addresses)
  })

  describe('House.constructor', function () {
    beforeEach(async function () {})
  })

  describe('Venue.constructor', function () {
    beforeEach(async function () {})

    it('weth()', async () => {
      expect(await venue.weth()).to.eq(weth.address)
    })
    it('house()', async () => {
      expect(await venue.house()).to.eq(house.address)
    })
  })

  describe('House.execute', function () {
    beforeEach(async function () {})

    it('setTest', async () => {
      let depositor: string = signer.address
      let venueAddress: string = venue.address
      let quantity: BigNumber = parseEther('1')
      let params: any = venue.interface.encodeFunctionData('setTest', [quantity])
      await expect(house.execute(0, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
    })
  })
})
