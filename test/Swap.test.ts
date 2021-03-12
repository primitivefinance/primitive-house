import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import chai, { expect } from 'chai'
import { solidity, deployContract } from 'ethereum-waffle'
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

import UniswapV2Factory from '@uniswap/v2-core/build/UniswapV2Factory.json'
import UniswapV2Router02 from '@uniswap/v2-periphery/build/UniswapV2Router02.json'

describe("SwapVenue testing", function () {

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
  let uniswapFactory: Contract, uniswapRouter: Contract

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

    uniswapFactory = await deployContract(signer, UniswapV2Factory, [signer.address], {gasLimit: 9500000})
    uniswapRouter = await deployContract(signer, UniswapV2Router02, [uniswapFactory.address, weth.address], {gasLimit: 9500000})

    // 5. deploy venue
    venue = await deploy('SwapVenue', { from: signers[0], args: [weth.address, house.address, MultiToken.address, uniswapFactory.address, uniswapRouter.address] })

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

  it('Swap venue can be used to create a new redeem/underlying pool and add liquidity', async () => {
    let params: any = venue.interface.encodeFunctionData('addShortLiquidityWithUnderlying', [oid, parseEther('1'), deadline])
    await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)

    // check that house has the correct long token balance
    let longBalance = await longToken.balanceOf(house.address)
    expect(longBalance.eq(parseEther('1')))
    // get the swap pair
    let pair = await uniswapFactory.getPair(shortToken.address, baseToken.address)
    // check that the pool received the correct short token balance
    let shortBalance = await shortToken.balanceOf(pair)
    expect(shortBalance.eq(parseEther('1')))
    // check that the house received the right LP token balance
    let pairToken = tokenFromAddress(pair, signers[0])
    let pairSupply = await pairToken.totalSupply()
    let lpBalance = await pairToken.balanceOf(house.address)
    // This is the creation of the pool so all the lp shares should be owned by house
    expect(lpBalance.eq(pairSupply))
    // check that the no underlying remains in the venue
    let baseTokenBalance = await baseToken.balanceOf(venue.address)
    expect(baseTokenBalance.eq(0))
  })

  it('Swap venue can be used to add liquidity to an existing redeem/underlying pool', async () => {
    let params: any = venue.interface.encodeFunctionData('addShortLiquidityWithUnderlying', [oid, parseEther('1'), deadline])
    // add initial liquidity
    await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)
    // add liquidity a second time
    await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)

    // check that house has the correct long token balance
    let longBalance = await longToken.balanceOf(house.address)
    expect(longBalance.eq(parseEther('2')))
    // get the swap pair
    let pair = await uniswapFactory.getPair(shortToken.address, baseToken.address)
    // check that the pool received the correct short token balance
    let shortBalance = await shortToken.balanceOf(pair)
    expect(shortBalance.eq(parseEther('2')))
    // check that the house received the right LP token balance
    let pairToken = tokenFromAddress(pair, signers[0])
    let pairSupply = await pairToken.totalSupply()
    let lpBalance = await pairToken.balanceOf(house.address)
    // This is the creation of the pool so all the lp shares should be owned by house
    expect(lpBalance.eq(pairSupply))
    // check that the no underlying remains in the venue
    let baseTokenBalance = await baseToken.balanceOf(venue.address)
    expect(baseTokenBalance.eq(0))
  })

  it('Swap venue can be used to create a new long/underlying pool and add liquidity', async () => {
    let params: any = venue.interface.encodeFunctionData('addLongLiquidityWithUnderlying', [oid, parseEther('1'), deadline])
    await expect(house.execute(0, venue.address, params)).to.emit(house, 'Executed').withArgs(Alice, venue.address)

    // check that house has the correct long token balance
    let shortBalance = await shortToken.balanceOf(house.address)
    expect(shortBalance.eq(parseEther('1')))
    // get the swap pair
    let pair = await uniswapFactory.getPair(longToken.address, baseToken.address)
    // check that the pool received the correct short token balance
    let longBalance = await longToken.balanceOf(pair)
    expect(longBalance.eq(parseEther('1')))
    // check that the house received the right LP token balance
    let pairToken = tokenFromAddress(pair, signers[0])
    let pairSupply = await pairToken.totalSupply()
    let lpBalance = await pairToken.balanceOf(house.address)
    // This is the creation of the pool so all the lp shares should be owned by house
    expect(lpBalance.eq(pairSupply))
    // check that the no underlying remains in the venue
    let baseTokenBalance = await baseToken.balanceOf(venue.address)
    expect(baseTokenBalance.eq(0))
  })
})
