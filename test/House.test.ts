import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import chai, { expect } from 'chai'
import { solidity } from 'ethereum-waffle'
chai.use(solidity)
import { BigNumber, BigNumberish, Contract } from 'ethers'
import { parseEther, formatEther } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { deploy } from '../scripts/deploy'
import { deployTokens, deployWeth, batchApproval, tokenFromAddress } from './lib/erc20'
import { deployMultiToken } from './lib/MultiToken'
import {} from './lib/protocol'
import { log } from './lib/utils'
import generateReport from './lib/table/generateReport'
const { AddressZero } = ethers.constants

describe("House integration tests", function () {

  let signers: SignerWithAddress[]
  let weth: Contract
  let house: Contract
  let signer: SignerWithAddress
  let Alice: string
  let tokens: Contract[], comp: Contract, dai: Contract, MultiToken: Contract
  let venue: Contract
  let manager: Contract
  let core: Contract
  let baseToken, quoteToken, strikePrice, expiry, isCall
  let oid: string
  let false_oid: string
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

  const setTest = (venue: Contract, signer: string) => {
    let quantity: BigNumber = parseEther('1')
    let params: any = venue.interface.encodeFunctionData('setTest', [quantity])
    return house.execute(0, venue.address, params)
  }

  const venueDeposit = (venue: Contract, receiver: string, oid: string) => {
    let amount: BigNumber = parseEther('1')
    let params: any = venue.interface.encodeFunctionData('deposit', [oid, amount, receiver])
    return house.execute(0, venue.address, params)
  }

  const venueMintWrap = (venue: Contract, receiver: string, oid: string) => {
    let amount: BigNumber = parseEther('1')
    let params: any = venue.interface.encodeFunctionData('mintOptionsThenWrap', [oid, amount, receiver])
    return house.execute(0, venue.address, params)
  }
// todo, util function to simply mint options for user on demand
  const venueSplitDeposit = (venue: Contract, receiver: string, oid: string) => {
    let amount: BigNumber = parseEther('1')
    let params: any = venue.interface.encodeFunctionData('splitOptionsAndDeposit', [oid, amount, [receiver, receiver]])
    return house.execute(1, venue.address, params)
  }

  const quoteTokenDeposit = (venue: Contract, receiver: string, quoteToken: Contract) => {
    let amount: BigNumber = parseEther('2')
    // deposit quote tokens to balance
    let depositParams: any = venue.interface.encodeFunctionData('depositToken', [
      quoteToken.address,
      amount.mul(strikePrice).div(parseEther('1')),
      receiver,
    ])
    return house.execute(1, venue.address, depositParams)
  }

  const venueExercise = (venue: Contract, receiver: string, oid: string, quoteToken: Contract) => {
    let amount: BigNumber = parseEther('2')

    let params: any = venue.interface.encodeFunctionData('exerciseFromBalance', [oid, amount, receiver])
    return house.execute(1, venue.address, params)
  }

  beforeEach(async function() {
    // 1. get signers
    signers = await ethers.getSigners()
    signer = signers[0]
    Alice = signer.address

    // 2. get weth, erc-20 tokens, and wrapped tokens
    weth = await deployWeth(signer)
    tokens = await deployTokens(signer, 2, ['comp', 'dai'])
    ;[comp, dai] = tokens
    MultiToken = await deployMultiToken(signer)

    // 3. select option params
    baseToken = comp
    quoteToken = dai
    strikePrice = parseEther('1000')
    expiry = 1615190111
    isCall = true

    // 4. deploy house
    house = await deploy('House', { from: signers[0], args: [AddressZero] })

    // 5. deploy venue
    venue = await deploy('BasicVenue', { from: signers[0], args: [weth.address, house.address, MultiToken.address] })

    // 6. deploy core with the house as the manager
    core = await deploy('Core', { from: signers[0], args: [house.address] })

    // 7. create options
    await core.createOption(baseToken.address, quoteToken.address, strikePrice, expiry, isCall)

    // 8. get the oid for the created options
    oid = await core.getOIdFromParameters(baseToken.address, quoteToken.address, strikePrice, expiry, isCall)
    false_oid = await core.getOIdFromParameters(Alice, Alice, strikePrice, expiry, isCall)


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
    //console.log(await shortToken.symbol(), await longToken.symbol(), longToken.address == shortToken.address)
    //await generateReport(contractNames, contracts, tokens, addresses, addressNamesArray)

    // approve base tokens to be pulled from caller
    await baseToken.approve(house.address, ethers.constants.MaxUint256)
    // approve base tokens to be pulled from caller
    await quoteToken.approve(house.address, ethers.constants.MaxUint256)
  })

  afterEach(async function () {
    let contractNames: string[] = ['House', 'Venue']
    let contracts = [house, venue]
    let addresses = [signer.address, MultiToken.address]
    let addressNamesArray: string[] = ['Alice', 'MultiToken']
    await generateReport(contractNames, contracts, tokens, addresses, addressNamesArray)
  })

  it('weth()', async () => {
    expect(await venue.getWeth()).to.eq(weth.address)
  })

  it('house()', async () => {
    expect(await venue.getHouse()).to.eq(house.address)
  })

  describe('Deposit', async () => {

    it('Caller can use the house to deposit an option in a venue', async () => {
      let params: any = venue.interface.encodeFunctionData('deposit', [oid, parseEther('1'), Alice])
      await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
    })

    it('Caller can use the house to deposit an option in a venue on behalf of another contract or account', async () => {
      let params: any = venue.interface.encodeFunctionData('deposit', [oid, parseEther('1'), house.address])
      await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
    })

    it('Caller CANNOT use the house to deposit a non-existent option in a venue', async () => {
      let params: any = venue.interface.encodeFunctionData('deposit', [false_oid, parseEther('1'), Alice])
      await expect(house.execute(0, venue.address, params)).to.be.revertedWith("EXECUTION_FAIL")
    })

    it('Caller CANNOT use the house to deposit an option in a venue if they do not have a sufficient balance', async () => {
      let params: any = venue.interface.encodeFunctionData('deposit', [oid, parseEther('10000000000000000'), Alice])
      await expect(house.execute(0, venue.address, params)).to.be.revertedWith("EXECUTION_FAIL")
    })

  })

  describe('Withdraw', async () => {

    it('Caller can use the house to withdraw an option from a venue', async () => {
      await venueDeposit(venue, Alice, oid)
      let params: any = venue.interface.encodeFunctionData('withdraw', [oid, parseEther('1'), [Alice, Alice]])
      await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
    })

    it('Caller CANNOT use the house to withdraw an option from a venue on behalf of another account', async () => {
      await venueDeposit(venue, Alice, oid)
      let params: any = venue.interface.encodeFunctionData('withdraw', [oid, parseEther('1'), [Alice, Alice]])
      await expect(house.connect(signers[2]).execute(1, venue.address, params)).to.be.revertedWith("House: NOT_DEPOSITOR")
    })

    it('Caller CANNOT use the house to withdraw an option from a venue if they have no options deposited', async () => {
      let params: any = venue.interface.encodeFunctionData('withdraw', [oid, parseEther('1'), [Alice, Alice]])
      await expect(house.execute(0, venue.address, params)).to.be.revertedWith("EXECUTION_FAIL")
    })

  })

  it('Caller can use a valid venue to borrow options without collateral', async () => {
    let params: any = venue.interface.encodeFunctionData('borrowOptionTest', [oid, parseEther('1')])
    await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
  })

  it('Depositor can use venue to mint long and short options, wrap them, and deposit them into the house', async () => {
    let params: any = venue.interface.encodeFunctionData('mintOptionsThenWrap', [oid, parseEther('1'), Alice])
    await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
  })

  it('Depositor can use venue to split wrapped options into long and short tokens and send them (update the balance of) the receivers.', async () => {
    let receivers: string[] = [Alice, Alice]
    await venueDeposit(venue, Alice, oid)
    await venueMintWrap(venue, Alice, oid)
    let params: any = venue.interface.encodeFunctionData('splitOptionsAndDeposit', [oid, parseEther('1'), receivers])
    await expect(house.execute(1, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
  })

  it('Caller can use venue to exercise options (burn long tokens, pay quote tokens, and receive underlying)', async () => {
    await venueDeposit(venue, Alice, oid)
    await venueMintWrap(venue, Alice, oid)
    await venueSplitDeposit(venue, Alice, oid)

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

    let prevBaseBal = await baseToken.balanceOf(Alice)
    let receiver: string = Alice
    let params: any = venue.interface.encodeFunctionData('exerciseFromBalance', [oid, amount, receiver])
    await expect(house.execute(1, venue.address, params)).to.emit(house, 'Executed').withArgs(signer.address, venue.address)
    let postBaseBal = await baseToken.balanceOf(Alice)
    let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
    expect(baseBalDiff).to.eq(amount)
  })

  it('Caller can use venue to redeem option and claim underlying when they hold both long and short tokens', async () => {
    await venueDeposit(venue, Alice, oid)
    await venueMintWrap(venue, Alice, oid)
    await venueSplitDeposit(venue, Alice, oid)
    // approve quote tokens to be pulled from user to the venue.
    await quoteToken.approve(venue.address, ethers.constants.MaxUint256)
    await quoteTokenDeposit(venue, Alice, quoteToken)
    await venueExercise(venue, Alice, oid, quoteToken)
    let amount: BigNumber = parseEther('1')

    let prevBaseBal = await quoteToken.balanceOf(Alice)
    let receiver: string = Alice
    let params: any = venue.interface.encodeFunctionData('redeemFromBalance', [oid, amount, receiver])
    await expect(house.execute(1, venue.address, params)).to.emit(house, 'Executed').withArgs(signer.address, venue.address)
    let postBaseBal = await quoteToken.balanceOf(Alice)
    let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
    expect(baseBalDiff).to.eq(amount.mul(strikePrice).div(parseEther('1')))
  })

  it('Caller can use venue to close options when they hold wrapped option tokens (which contain both long and short tokens)', async () => {
    // mint and wrap 1 option
    let amount: BigNumber = parseEther('2')
    let receiver: string = Alice

    let mintParams2: any = venue.interface.encodeFunctionData('deposit', [oid, amount, receiver])
    await house.execute(0, venue.address, mintParams2)

    let mintParams: any = venue.interface.encodeFunctionData('mintOptionsThenWrap', [oid, amount, receiver])
    await expect(house.execute(0, venue.address, mintParams))
      .to.emit(house, 'Executed')
      .withArgs(signer.address, venue.address)

    // redeem from wrapped balance
    let prevBaseBal = await baseToken.balanceOf(Alice)
    let params: any = venue.interface.encodeFunctionData('closeFromWrappedBalance', [oid, amount, receiver])
    await expect(house.execute(1, venue.address, params)).to.emit(house, 'Executed').withArgs(signer.address, venue.address)
    let postBaseBal = await baseToken.balanceOf(Alice)
    let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
    expect(baseBalDiff).to.eq(amount)
  })

  it('Caller can use venue to close options when they hold both long and short tokens in the venue', async () => {
    // approve tokens
    const max = ethers.constants.MaxUint256
    await longToken.approve(house.address, max)
    await shortToken.approve(house.address, max)
    // mint options and deposit
    let amount: BigNumber = parseEther('1')
    let receiver: string = Alice
    let mintParams: any = venue.interface.encodeFunctionData('deposit', [oid, amount, receiver])
    await expect(house.execute(0, venue.address, mintParams))
      .to.emit(house, 'Executed')
      .withArgs(signer.address, venue.address)

    // close from balance
    let prevBaseBal = await baseToken.balanceOf(Alice)
    let params: any = venue.interface.encodeFunctionData('closeFromBalance', [oid, amount, receiver])
    await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(signer.address, venue.address)
    let postBaseBal = await baseToken.balanceOf(Alice)
    let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
    expect(baseBalDiff).to.eq(amount)
  })

  it('Caller can use venue to close options when they hold both long and short options in their wallet', async () => {
    // approve tokens
    const max = ethers.constants.MaxUint256
    await longToken.approve(house.address, max)
    await shortToken.approve(house.address, max)
    // mint options and deposit
    let amount: BigNumber = parseEther('2')
    let receiver: string = Alice
    await venueDeposit(venue, Alice, oid)
    await venueMintWrap(venue, Alice, oid)
    await venueSplitDeposit(venue, Alice, oid)
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
    let params: any = venue.interface.encodeFunctionData('close', [oid, amount, receiver])
    await expect(house.execute(1, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
    let postBaseBal = await baseToken.balanceOf(Alice)
    let baseBalDiff = ethers.BigNumber.from(postBaseBal).sub(prevBaseBal)
    expect(baseBalDiff).to.eq(amount)
  })
})
