import { Contract } from 'ethers'
import { BalanceTable } from './balanceTable'
import formatTableData from './formatTableData'
const table = new BalanceTable({})

const generateReport = async (contractNames: string[], contracts: Contract[], tokens: Contract[], addresses: string[]) => {
  let data = await formatTableData(contractNames, contracts, tokens, addresses)
  table.generate(data)
}

export default generateReport
