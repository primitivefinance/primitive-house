import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'
import { parseEther } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { deploy } from '../scripts/deploy'
import { deployTokens, deployWeth, batchApproval } from './lib/erc20'
const { AddressZero } = ethers.constants

describe('Contract', function () {
  let signers: SignerWithAddress[]
  let signer: SignerWithAddress

  before(async function () {
    signers = await ethers.getSigners()
    signer = signers[0]
  })

  describe('Contract.fn', function () {
    beforeEach(async function () {})

    it('Contract.fn.test', async () => {})
  })
})
