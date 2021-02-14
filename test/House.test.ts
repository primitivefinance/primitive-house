import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import chai, { expect } from 'chai'
import { solidity } from 'ethereum-waffle'
chai.use(solidity)
import { BigNumber, BigNumberish, Contract } from 'ethers'
import { parseEther, formatEther } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { deploy } from '../scripts/deploy'
import { deployTokens, deployWeth, batchApproval, tokenFromAddress } from './lib/erc20'
import { deployWrappedToken } from './lib/wToken'
import {} from './lib/protocol'
import { log } from './lib/utils'
import generateReport from './lib/table/generateReport'
const { AddressZero } = ethers.constants

describe('House', function () {
  let signers: SignerWithAddress[]
  let weth: Contract
  let house: Contract
  let signer: SignerWithAddress
  let Alice: string
  let tokens: Contract[], comp: Contract, dai: Contract, wToken: Contract
  let venue: Contract
  let manager: Contract
  let core: Contract
  let baseToken, quoteToken, strikePrice, expiry, isCall
  let oid: string
  let longToken: Contract, shortToken: Contract

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
    Alice = signer.address

    // 2. get weth, erc-20 tokens, and wrapped tokens
    weth = await deployWeth(signer)
    tokens = await deployTokens(signer, 2, ['comp', 'dai'])
    ;[comp, dai] = tokens
    wToken = await deployWrappedToken(signer)

    // 3. select option params
    baseToken = comp
    quoteToken = dai
    strikePrice = parseEther('1000')
    expiry = 1615190111
    isCall = true

    // 4. deploy house
    house = await deploy('House', { from: signers[0], args: [AddressZero] })

    // 5. deploy venue
    venue = await deploy('BasicVenue', { from: signers[0], args: [weth.address, house.address, wToken.address] })

    // 6. deploy core with the house as the manager
    core = await deploy('Core', { from: signers[0], args: [house.address] })

    // 7. create options
    await core.createOption(baseToken.address, quoteToken.address, strikePrice, expiry, isCall)

    // 8. get the oid for the created options
    oid = await core.getOIdFromParameters(baseToken.address, quoteToken.address, strikePrice, expiry, isCall)

    // 9. get the tokens for the oid
    let [longAddr, shortAddr] = await core.getTokenData(oid)

    // 10. get erc20 instances for the tokenization so we can query balances
    longToken = tokenFromAddress(longAddr, signers[0])
    shortToken = tokenFromAddress(shortAddr, signers[0])

    // 11. set the core in the house
    await house.setCore(core.address)

    let contractNames: string[] = ['House']
    let contracts: Contract[] = [house]
    let addresses: string[] = [signer.address]
    let addressNamesArray: string[] = ['Alice']
    tokens.push(longToken)
    tokens.push(shortToken)
    console.log(await shortToken.symbol(), await longToken.symbol(), longToken.address == shortToken.address)
    await generateReport(contractNames, contracts, tokens, addresses, addressNamesArray)

    // approve base tokens to be pulled from caller
    await baseToken.approve(house.address, ethers.constants.MaxUint256)
    // approve base tokens to be pulled from caller
    await quoteToken.approve(house.address, ethers.constants.MaxUint256)
  })

  afterEach(async function () {
    let contractNames: string[] = ['House', 'Venue']
    let contracts = [house, venue]
    let addresses = [signer.address, wToken.address]
    let addressNamesArray: string[] = ['Alice', 'wToken']
    await generateReport(contractNames, contracts, tokens, addresses, addressNamesArray)
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

    it('venue.deposit', async () => {
      let depositor: string = signer.address
      let venueAddress: string = venue.address
      let amount: BigNumber = parseEther('1')
      let receiver: string = Alice
      let params: any = venue.interface.encodeFunctionData('deposit', [oid, amount, receiver])
      await expect(house.execute(0, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
    })

    it('venue.mintOptionsThenWrap', async () => {
      let depositor: string = signer.address
      let venueAddress: string = venue.address
      let amount: BigNumber = parseEther('1')
      let receiver: string = Alice
      let params: any = venue.interface.encodeFunctionData('mintOptionsThenWrap', [oid, amount, receiver])
      await expect(house.execute(1, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
    })

    it('venue.splitOptionsAndDeposit', async () => {
      let depositor: string = signer.address
      let venueAddress: string = venue.address
      let amount: BigNumber = parseEther('1')
      let receivers: string[] = [Alice, Alice]
      let params: any = venue.interface.encodeFunctionData('splitOptionsAndDeposit', [oid, amount, receivers])
      await expect(house.execute(1, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
    })

    it('venue.exerciseFromBalance', async () => {
      let amount: BigNumber = parseEther('2')
      // approve quote tokens to be pulled from user to the venue.
      await quoteToken.approve(venue.address, ethers.constants.MaxUint256)
      // deposit quote tokens to balance
      let depositParams: any = venue.interface.encodeFunctionData('depositToken', [
        quoteToken.address,
        amount.mul(strikePrice).div(parseEther('1')),
        Alice,
      ])
      await expect(house.execute(1, venue.address, depositParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      console.log('finished 1st execution to deposit quote tokens')
      let prevBaseBal = await baseToken.balanceOf(Alice)
      let venueAddress: string = venue.address
      let receiver: string = Alice
      let params: any = venue.interface.encodeFunctionData('exerciseFromBalance', [oid, amount, receiver])
      await expect(house.execute(1, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
      let postBaseBal = await baseToken.balanceOf(Alice)
      let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
      expect(baseBalDiff).to.eq(amount)
    })

    it('venue.redeemFromBalance', async () => {
      let amount: BigNumber = parseEther('1')

      let prevBaseBal = await quoteToken.balanceOf(Alice)
      let venueAddress: string = venue.address
      let receiver: string = Alice
      let params: any = venue.interface.encodeFunctionData('redeemFromBalance', [oid, amount, receiver])
      await expect(house.execute(1, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
      let postBaseBal = await quoteToken.balanceOf(Alice)
      let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
      expect(baseBalDiff).to.eq(amount.mul(strikePrice).div(parseEther('1')))
    })

    it('venue.redeemFromWrappedBalance', async () => {
      // mint and wrap 1 option
      let amount: BigNumber = parseEther('2')
      let doubleAmount: BigNumber = parseEther('2')
      let receiver: string = Alice
      let mintParams: any = venue.interface.encodeFunctionData('mintOptionsThenWrap', [oid, doubleAmount, receiver])
      await expect(house.execute(1, venue.address, mintParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      let mintParams2: any = venue.interface.encodeFunctionData('deposit', [oid, parseEther('1'), receiver])
      await expect(house.execute(1, venue.address, mintParams2))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)
      console.log('finished 1st execution')

      // exercise from wrapped balance
      await quoteToken.approve(venue.address, ethers.constants.MaxUint256)
      // deposit quote tokens to balance
      let depositParams: any = venue.interface.encodeFunctionData('depositToken', [
        quoteToken.address,
        amount.mul(strikePrice).div(parseEther('1')),
        Alice,
      ])
      await expect(house.execute(1, venue.address, depositParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      console.log('finished 2nd execution')

      let exerciseParams: any = venue.interface.encodeFunctionData('exerciseFromBalance', [oid, parseEther('1'), receiver])
      await expect(house.execute(1, venue.address, exerciseParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      console.log('finished 3rd execution')

      // redeem from wrapped balance
      let prevBaseBal = await quoteToken.balanceOf(Alice)
      let venueAddress: string = venue.address
      let params: any = venue.interface.encodeFunctionData('redeemFromWrappedBalance', [oid, parseEther('1'), receiver])
      await expect(house.execute(1, venueAddress, params)).to.be.reverted
      let postBaseBal = await quoteToken.balanceOf(Alice)
      let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
      expect(baseBalDiff).to.eq('0')
    })

    it('venue.closeFromWrappedBalance', async () => {
      // mint and wrap 1 option
      let amount: BigNumber = parseEther('2')
      let receiver: string = Alice
      let mintParams: any = venue.interface.encodeFunctionData('mintOptionsThenWrap', [oid, amount, receiver])
      await expect(house.execute(1, venue.address, mintParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      // redeem from wrapped balance
      let prevBaseBal = await baseToken.balanceOf(Alice)
      let venueAddress: string = venue.address
      let params: any = venue.interface.encodeFunctionData('closeFromWrappedBalance', [oid, amount, receiver])
      await expect(house.execute(1, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
      let postBaseBal = await baseToken.balanceOf(Alice)
      let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
      expect(baseBalDiff).to.eq(amount)
    })

    it('venue.closeFromBalance', async () => {
      // approve tokens
      const max = ethers.constants.MaxUint256
      await longToken.approve(house.address, max)
      await shortToken.approve(house.address, max)
      // mint options and deposit
      let amount: BigNumber = parseEther('1')
      let receiver: string = Alice
      let mintParams: any = venue.interface.encodeFunctionData('deposit', [oid, amount, receiver])
      await expect(house.execute(1, venue.address, mintParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      // close from balance
      let prevBaseBal = await baseToken.balanceOf(Alice)
      let venueAddress: string = venue.address
      let params: any = venue.interface.encodeFunctionData('closeFromBalance', [oid, amount, receiver])
      await expect(house.execute(1, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
      let postBaseBal = await baseToken.balanceOf(Alice)
      let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
      expect(baseBalDiff).to.eq(amount)
    })

    it('venue.close', async () => {
      // approve tokens
      const max = ethers.constants.MaxUint256
      await longToken.approve(house.address, max)
      await shortToken.approve(house.address, max)
      // mint options and deposit
      let amount: BigNumber = parseEther('2')
      let receiver: string = Alice
      let mintParams: any = venue.interface.encodeFunctionData('deposit', [oid, amount, receiver])
      await expect(house.execute(1, venue.address, mintParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      // withdraw options
      let withdrawParams: any = venue.interface.encodeFunctionData('withdraw', [oid, amount, [receiver, receiver]])
      await expect(house.execute(1, venue.address, withdrawParams))
        .to.emit(house, 'Executed')
        .withArgs(signer.address, venue.address)

      let longBal = await longToken.balanceOf(Alice)
      let shortBal = await shortToken.balanceOf(Alice)
      expect(longBal).to.eq(shortBal).to.eq(amount)

      // close from wallet
      let prevBaseBal = await baseToken.balanceOf(Alice)
      let venueAddress: string = venue.address
      let params: any = venue.interface.encodeFunctionData('close', [oid, amount, receiver])
      await expect(house.execute(1, venueAddress, params)).to.emit(house, 'Executed').withArgs(signer.address, venueAddress)
      let postBaseBal = await baseToken.balanceOf(Alice)
      let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
      expect(baseBalDiff).to.eq(amount)
    })
  })
})
