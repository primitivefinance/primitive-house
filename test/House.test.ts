import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { deploy } from '../scripts/deploy'
import { deployTokens, deployWeth, batchApproval, deployVirtualTokens } from './lib/erc20'
import { deployUniRouter, deployUniswap, deployPrimitiveOption } from './lib/protocol'
import { log } from './lib/utils'
import generateReport from './lib/table/generateReport'
const { AddressZero } = ethers.constants

describe('House', function () {
  let signers: SignerWithAddress[]
  let weth: Contract
  let house: Contract
  let capitol: Contract
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
    // 1. get signers
    signers = await ethers.getSigners()
    signer = signers[0]

    // 2. get weth, erc-20 tokens
    weth = await deployWeth(signer)
    tokens = await deployTokens(signer, 2)
    ;[comp, dai] = tokens

    // 3. select option params
    underlying = comp
    strike = dai
    base = parseEther('1')
    quote = parseEther('100')
    expiry = '1690868800'

    // 4. deploy capitol, house, primitive option + redeem
    capitol = await deploy('Capitol', { from: signer, args: [] })
    house = await deploy('House', { from: signers[0], args: [weth.address, AddressZero, capitol.address] })
    ;[option, redeem] = await deployPrimitiveOption(signer, underlying.address, strike.address, base, quote, expiry)
    // 5. deploy external contracts for venue (sushiswap)
    ;[factory, router] = await deployUniswap(signer, weth.address)
    // 6. deploy venue and add it to capitol
    sushiswapVenue = await deploy('SushiSwapVenueTest', {
      args: [weth.address, house.address, capitol.address, router.address, factory.address],
    })
    await capitol.addVenue(sushiswapVenue.address, 'SushiSwap', '0.0.1', true)

    // 7. deploy virtual versions of the erc-20 tokens
    log('deploying virtuals')
    virtualTokens = await deployVirtualTokens(signer, getTokenAddresses(), house.address)
    ;[vcomp, vdai] = virtualTokens
    // 8. issue the virtual tokens to the house
    log('issuing virtuals')
    virtualTokens.map(async (token, i) => {
      const virtualAsset = token.address
      const asset = tokens[i].address
      await house.issueVirtual(asset, virtualAsset)
    })
    let vunderlying = vcomp
    let vstrike = vdai
    log('deploying voptions')
    // 9. deploy the virtual option + redeem tokens
    ;[virtualOption, virtualRedeem] = await deployPrimitiveOption(
      signer,
      vunderlying.address,
      vstrike.address,
      base,
      quote,
      expiry
    )
    // 10. issue the virtual option to the house
    await house.issueVirtualOption(option.address, virtualOption.address)

    // end state is virtual assets for each asset, underlying & strike, virtual option + virtual redeem

    // 11. approve all tokens and contract
    await batchApproval([house.address, router.address], [underlying, strike, option, redeem], [signer])

    // 12. create the pair for the real underlying token, and the virtual redeem token.
    await factory.createPair(underlying.address, virtualRedeem.address)

    let contractNames: string[] = ['House']
    let contracts = [house]
    let addresses = [signer.address]
    await generateReport(contractNames, contracts, tokens, addresses)
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
      expect(await house.capitol()).to.eq(capitol.address)
    })
  })

  describe('Venue.constructor', function () {
    beforeEach(async function () {})

    it('weth()', async () => {
      expect(await sushiswapVenue.weth()).to.eq(weth.address)
    })
    it('house()', async () => {
      expect(await sushiswapVenue.house()).to.eq(house.address)
    })
    it('capitol()', async () => {
      expect(await sushiswapVenue.capitol()).to.eq(capitol.address)
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
      //house = await deploy('House', { from: signers[0], args: [weth.address, AddressZero, AddressZero] })
      //await batchApproval([house.address], tokens, [signer])
      //await batchApproval([house.address], [option, redeem], [signer])
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
