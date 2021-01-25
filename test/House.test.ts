import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { deploy } from '../scripts/deploy'
import { deployTokens, deployWeth, batchApproval, deployVirtualTokens } from './lib/erc20'
import { deployUniRouter, deployUniswap, deployPrimitiveOption } from './lib/protocol'
import { log } from './lib/utils'
const { AddressZero } = ethers.constants

describe('House', function () {
  let signers: SignerWithAddress[]
  let weth: Contract
  let house: Contract
  let signer: SignerWithAddress
  let tokens: Contract[], comp: Contract, dai: Contract, wbtc: Contract, vcomp: Contract, vdai: Contract
  let option: Contract, redeem: Contract, virtualTokens: Contract[], virtualOption: Contract, virtualRedeem: Contract
  let underlying: Contract, strike: Contract, base: BigNumber, quote: BigNumber, expiry: string // primitive
  let router: Contract, factory: Contract // uniswap
  let sushiswapVenue: Contract

  const deadline = Math.floor(Date.now() / 1000) + 60 * 20

  const getTokenAddresses = () => {
    const array = tokens.map((token) => {
      return token.address
    })
    return array
  }

  const getVirtualAddresses = () => {
    const array = virtualTokens.map((token) => {
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
    signers = await ethers.getSigners()
    signer = signers[0]

    // tokens
    weth = await deployWeth(signer)
    tokens = await deployTokens(signer, 2)
    ;[comp, dai] = tokens

    // option params
    underlying = comp
    strike = dai
    base = parseEther('1')
    quote = parseEther('100')
    expiry = '1690868800'

    // primitive
    house = await deploy('House', { from: signers[0], args: [weth.address, AddressZero, AddressZero] })
    ;[option, redeem] = await deployPrimitiveOption(signer, underlying.address, strike.address, base, quote, expiry)
    sushiswapVenue = await deploy('SushiSwapVenue', { args: [weth.address, house.address, AddressZero] })

    // uniswap
    ;[factory, router] = await deployUniswap(signer, weth.address)

    // virtual tokens
    log('deploying virtuals')
    virtualTokens = await deployVirtualTokens(signer, getTokenAddresses(), house.address)
    ;[vcomp, vdai] = virtualTokens
    log('issuing virtuals')
    virtualTokens.map(async (token, i) => {
      const virtualAsset = token.address
      const asset = tokens[i].address
      await house.issueVirtual(asset, virtualAsset)
    })
    let vunderlying = vcomp
    let vstrike = vdai
    log('deploying voptions')
    ;[virtualOption, virtualRedeem] = await deployPrimitiveOption(
      signer,
      vunderlying.address,
      vstrike.address,
      base,
      quote,
      expiry
    )

    await house.issueVirtualOption(option.address, virtualOption.address)

    // end state is virtual assets for each asset, underlying & strike, virtual option + virtual redeem

    // approve all tokens and contract
    await batchApproval([house.address, router.address], [underlying, strike, option, redeem], [signer])
    await factory.createPair(underlying.address, redeem.address)
  })

  describe('House.constructor', function () {
    beforeEach(async function () {})

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

  describe('Venue.constructor', function () {
    beforeEach(async function () {
      sushiswapVenue = await deploy('SushiSwapVenueTest', {
        args: [weth.address, house.address, AddressZero, router.address, factory.address],
      })
    })

    it('weth()', async () => {
      expect(await sushiswapVenue.weth()).to.eq(weth.address)
    })
    it('house()', async () => {
      expect(await sushiswapVenue.house()).to.eq(house.address)
    })
    it('capitol()', async () => {
      expect(await sushiswapVenue.capitol()).to.eq(AddressZero)
    })
  })

  describe('House.addTokens', function () {
    beforeEach(async function () {})

    it('adds tokens successfully', async () => {
      let depositor: string = signer.address
      await house.addTokens(depositor, getTokenAddresses(), getAmounts())
      tokens.map(async (token, i) => {
        expect(await house.credit(token.address, signer.address)).to.eq(getAmounts()[i])
      })
    })
  })

  describe('House.execute', function () {
    beforeEach(async function () {
      house = await deploy('House', { from: signers[0], args: [weth.address, AddressZero, AddressZero] })
      await batchApproval([house.address], tokens, [signer])
      await batchApproval([house.address], [option, redeem], [signer])
    })

    it('setTest', async () => {
      let depositor: string = signer.address
      let venue: string = sushiswapVenue.address
      let quantity: BigNumber = parseEther('1')
      let params: any = sushiswapVenue.interface.encodeFunctionData('setTest', [quantity])
      await expect(house.execute(venue, params)).to.emit(house, 'Executed').withArgs(signer.address, venue)
    })

    it('addShortLiquidityWithUnderlying', async () => {
      let depositor: string = signer.address
      let venue: string = sushiswapVenue.address
      let quantity: BigNumber = parseEther('1')
      let params: any = sushiswapVenue.interface.encodeFunctionData('addShortLiquidityWithUnderlying', [
        option.address,
        quantity,
        quantity,
        '0',
        signer.address,
        deadline,
      ])
      await expect(house.execute(venue, params)).to.emit(house, 'Executed').withArgs(signer.address, venue)
    })
  })
})
