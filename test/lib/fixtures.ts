import { ethers, waffle } from 'hardhat'
import { Wallet, Contract, BigNumber } from 'ethers'
import { deployContract, link } from 'ethereum-waffle'
import { formatEther, parseEther } from 'ethers/lib/utils'
import constants from './constants'
import MultiToken from '../../build/contracts/MultiToken.sol/MultiToken.json'
import BasicVenue from '../../build/contracts/venues/BasicVenue.sol/BasicVenue.json'


//import batchApproval from './batchApproval'
const { OPTION_TEMPLATE_LIB, REDEEM_TEMPLATE_LIB } = constants.LIBRARIES
import { deployTokens, deployWeth, batchApproval, tokenFromAddress } from './erc20'

// TODO get rid of the old primitive imports we won't be using
import Weth from '@primitivefi/contracts/artifacts/WETH9.json'
import Flash from '@primitivefi/contracts/artifacts/Flash.json'
import Trader from '@primitivefi/contracts/artifacts/Trader.json'
import Option from '@primitivefi/contracts/artifacts/Option.json'
import Redeem from '@primitivefi/contracts/artifacts/Redeem.json'
import Registry from '@primitivefi/contracts/artifacts/Registry.json'
import OptionTest from '@primitivefi/contracts/artifacts/OptionTest.json'
import OptionFactory from '@primitivefi/contracts/artifacts/OptionFactory.json'
import RedeemFactory from '@primitivefi/contracts/artifacts/RedeemFactory.json'
import OptionTemplateLib from '@primitivefi/contracts/artifacts/OptionTemplateLib.json'
import RedeemTemplateLib from '@primitivefi/contracts/artifacts/RedeemTemplateLib.json'

import House from '../../build/contracts/House.sol/House.json'
import Core from '../../build/contracts/Core.sol/Core.json'

import UniswapV2Factory from '@uniswap/v2-core/build/UniswapV2Factory.json'
import UniswapV2Router02 from '@uniswap/v2-periphery/build/UniswapV2Router02.json'
import { connect } from 'http2'

const overrides = { gasLimit: 9500000 }

interface WethFixture {
  weth: Contract
}

export async function wethFixture([wallet]: Wallet[], provider): Promise<WethFixture> {
  const weth = await deployContract(wallet, Weth, [], overrides)
  return { weth }
}

export interface HouseFixture {
  house: Contract
  core: Contract
}

export async function houseFixture([wallet]: Wallet[], provider): Promise<HouseFixture> {
  // Deploy the house contract, with core = 0 uninitialized
  const house = await deployContract(wallet, House, [constants.ADDRESSES.ZERO_ADDRESS], overrides)
  // Deploy the option core with house as manager
  const core = await deployContract(wallet, Core, [house.address], overrides)
  // Set the core address in house
  await house.setCore(core.address)
  return {
    house,
    core
  }
}

export interface UniswapFixture {
  uniswapRouter: Contract
  uniswapFactory: Contract
  weth: Contract
}

export async function uniswapFixture([wallet]: Wallet[], provider): Promise<UniswapFixture> {
  const { weth } = await wethFixture([wallet], provider)
  const uniswapFactory = await deployContract(wallet, UniswapV2Factory, [wallet.address], overrides)
  const uniswapRouter = await deployContract(wallet, UniswapV2Router02, [uniswapFactory.address, weth.address], overrides)
  return { uniswapRouter, uniswapFactory, weth }
}

export interface HouseTestFixture {
  house: HouseFixture
  uniswap: UniswapFixture
  tokens: Contract[]
  multiToken: Contract
  venue: Contract
  parameters: OptionParameters
}

export interface OptionParameters {
  underlying: Contract
  quoteToken: Contract
  strike: BigNumber
  expiry: Number
  isCall: Boolean
}

export async function houseTestFixture([wallet]: Wallet[], provider): Promise<HouseTestFixture> {
  let uniswap = await uniswapFixture([wallet], provider)
  let house = await houseFixture([wallet], provider)
  let tokens: Contract[] = await deployTokens(wallet, 2, ['tokenA', 'tokenB'])
  let multiToken: Contract = await deployContract(wallet, MultiToken, [], overrides)
  let venue = await deployContract(wallet, BasicVenue, [uniswap.weth.address, house.house.address, multiToken.address], overrides)
  let underlying = tokens[0]
  let quoteToken = tokens[1]
  let strike = parseEther('1000')
  let expiry = 1615190111
  let isCall = true

  let parameters: OptionParameters = {
    underlying, quoteToken, strike, expiry, isCall
  }

  await house.core.createOption(underlying.address, quoteToken.address, parameters.strike, parameters.expiry, parameters.isCall)

  return {
    house,
    uniswap,
    tokens,
    multiToken,
    venue,
    parameters
  }
}
/*
interface TokenFixture {
  tokenA: Contract
  tokenB: Contract
}

export async function tokenFixture([wallet]: Wallet[], provider): Promise<TokenFixture> {
  const amount = ethers.utils.parseEther('1000000000')
  const tokenA = await deployContract(wallet, TestERC20, ['COMP', 'COMP', amount])
  const tokenB = await deployContract(wallet, TestERC20, ['DAI', 'DAI', amount])
  return { tokenA, tokenB }
}

export interface OptionParameters {
  underlying: string
  strike: string
  base: BigNumber
  quote: BigNumber
  expiry: string
}

interface OptionFixture {
  registry: Contract
  optionToken: Contract
  redeemToken: Contract
  underlyingToken: Contract
  strikeToken: Contract
  params: OptionParameters
}

interface DeployedOptions {
  optionToken: Contract
  redeemToken: Contract
}

export async function deployOption(wallet: Wallet, registry: Contract, params: OptionParameters): Promise<DeployedOptions> {
  await registry.deployOption(params.underlying, params.strike, params.base, params.quote, params.expiry)
  const optionToken = new ethers.Contract(
    await registry.allOptionClones(((await registry.getAllOptionClonesLength()) - 1).toString()),
    Option.abi,
    wallet
  )
  const redeemToken = new ethers.Contract(await optionToken.redeemToken(), Redeem.abi, wallet)
  return { optionToken, redeemToken }
}
*/
/**
 * @notice  Gets a call option with a $100 strike price.
 */
 /*
export async function optionFixture([wallet]: Wallet[], provider): Promise<OptionFixture> {
  const { registry } = await registryFixture([wallet], provider)
  const { tokenA, tokenB } = await tokenFixture([wallet], provider)
  const underlyingToken = tokenA
  const strikeToken = tokenB
  await registry.verifyToken(underlyingToken.address)
  await registry.verifyToken(strikeToken.address)
  const base = parseEther('1')
  const quote = parseEther('100')
  const expiry = '1690868800'
  const params: OptionParameters = {
    underlying: underlyingToken.address,
    strike: strikeToken.address,
    base: base,
    quote: quote,
    expiry: expiry,
  }
  const { optionToken, redeemToken } = await deployOption(wallet, registry, params)
  return { registry, optionToken, redeemToken, underlyingToken, strikeToken, params }
}

export interface Options {
  callEth: Contract
  scallEth: Contract
  putEth: Contract
  sputEth: Contract
  call: Contract
  scall: Contract
  put: Contract
  sput: Contract
}

export interface PrimitiveV1Fixture {
  registry: Contract
  optionToken: Contract
  redeemToken: Contract
  underlyingToken: Contract
  strikeToken: Contract
  uniswapRouter: Contract
  uniswapFactory: Contract
  weth: Contract
  trader: Contract
  router: Contract
  core: Contract
  swaps: Contract
  liquidity: Contract
  params: OptionParameters
  options: Options
  dai: Contract
  connectorTest: Contract
}

export async function primitiveV1([wallet]: Wallet[], provider): Promise<PrimitiveV1Fixture> {
  const { registry, optionToken, redeemToken, underlyingToken, strikeToken, params } = await optionFixture(
    [wallet],
    provider
  )

  const { dai } = await daiFixture([wallet], provider)

  const { uniswapRouter, uniswapFactory, weth } = await uniswapFixture([wallet], provider)
  const callEthParams: OptionParameters = {
    underlying: weth.address,
    strike: strikeToken.address,
    base: params.base,
    quote: params.quote,
    expiry: params.expiry,
  }

  const putEthParams: OptionParameters = {
    underlying: dai.address,
    strike: weth.address,
    base: params.quote,
    quote: params.base,
    expiry: params.expiry,
  }

  const putParams: OptionParameters = {
    underlying: dai.address,
    strike: underlyingToken.address,
    base: params.quote,
    quote: params.base,
    expiry: params.expiry,
  }

  let callEth: Contract, scallEth: Contract
  {
    const { optionToken, redeemToken } = await deployOption(wallet, registry, callEthParams)
    callEth = optionToken
    scallEth = redeemToken
  }
  let putEth: Contract, sputEth: Contract
  {
    const { optionToken, redeemToken } = await deployOption(wallet, registry, putEthParams)
    putEth = optionToken
    sputEth = redeemToken
  }

  let put: Contract, sput: Contract
  {
    const { optionToken, redeemToken } = await deployOption(wallet, registry, putParams)
    put = optionToken
    sput = redeemToken
  }

  const options: Options = {
    callEth: callEth,
    scallEth: scallEth,
    putEth: putEth,
    sputEth: sputEth,
    call: optionToken,
    scall: redeemToken,
    put: put,
    sput: sput,
  }
  const trader = await deployContract(wallet, Trader, [weth.address], overrides)
  const router = await deployContract(wallet, PrimitiveRouter, [weth.address, registry.address], overrides)
  const core = await deployContract(wallet, PrimitiveCore, [weth.address, router.address], overrides)
  const swaps = await deployContract(
    wallet,
    PrimitiveSwaps,
    [weth.address, router.address, uniswapFactory.address, uniswapRouter.address],
    overrides
  )
  const liquidity = await deployContract(
    wallet,
    PrimitiveLiquidity,
    [weth.address, router.address, uniswapFactory.address, uniswapRouter.address],
    overrides
  )

  const connectorTest = await deployContract(wallet, PrimitiveConnectorTest, [weth.address, router.address], overrides)
  await router.setRegisteredConnectors(
    [core.address, swaps.address, liquidity.address, connectorTest.address],
    [true, true, true, true]
  )
  await router.setRegisteredOptions([callEth.address, putEth.address, optionToken.address, put.address])
  await batchApproval(
    [trader.address, router.address, uniswapRouter.address],
    [underlyingToken, strikeToken, optionToken, redeemToken, weth, dai, callEth, scallEth, putEth, sputEth, put, sput],
    [wallet]
  )
  return {
    registry,
    optionToken,
    redeemToken,
    underlyingToken,
    strikeToken,
    uniswapRouter,
    uniswapFactory,
    weth,
    trader,
    router,
    core,
    swaps,
    liquidity,
    params,
    options,
    dai,
    connectorTest,
  }
} */
