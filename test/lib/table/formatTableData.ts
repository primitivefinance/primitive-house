import { Contract } from 'ethers'

const { formatEther } = require('ethers/lib/utils')

const formatTableData = async (
  contractNamesArray: string[],
  contractsArray: Contract[],
  tokensArray: Contract[],
  addressArray: string[],
  addressNamesArray: string[]
) => {
  const info = {
    balances: [
      {
        contract: 'Test contract',
        tokenName: 'Test Token',
        tokenBalance: 'Test Balance',
      },
    ],
  }

  // for each contract, get each token balance
  for (let i = 0; i < contractsArray.length; i++) {
    let name = contractNamesArray[i]
    let contract = contractsArray[i]

    for (let x = 0; x < tokensArray.length; x++) {
      let token = tokensArray[x]
      let balance = await token.balanceOf(contract.address)
      let formattedBalance = formatEther(balance)
      let tokenName = await token.symbol()
      let totalSupply = formatEther(await token.totalSupply())

      let data = {
        contract: name,
        tokenName: tokenName,
        tokenBalance: formattedBalance,
        totalSupply: totalSupply,
      }
      info.balances.push(data)
    }
  }

  // for each address, get each token balance
  for (let i = 0; i < addressArray.length; i++) {
    let addressName = addressNamesArray[i]
    let address = addressArray[i]
    for (let x = 0; x < tokensArray.length; x++) {
      let token = tokensArray[x]
      let balance = await token.balanceOf(address)
      let formattedBalance = formatEther(balance)
      let tokenName = await token.symbol()
      let totalSupply = formatEther(await token.totalSupply())
      let data = {
        contract: addressName,
        tokenName: tokenName,
        tokenBalance: formattedBalance,
        totalSupply: totalSupply,
      }
      info.balances.push(data)
    }
  }

  return info
}

export default formatTableData
