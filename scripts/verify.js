/**
 * @dev Verifies the Trader and UniswapConnector contracts.
 */
const verifyContract = async () => {
  let UniswapConnector = await deployments.get('UniswapConnector03')
  try {
    await run('verify', {
      address: UniswapConnector.address,
      contractName: 'contracts/UniswapConnector03.sol:UniswapConnector03',
      constructorArguments: UniswapConnector.args,
    })
  } catch (err) {
    console.error(err)
  }
}
/**
 * @dev Calling this verify script with the --network tag will verify them on etherscan automatically.
 */
async function main() {
  await verifyContract()
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
