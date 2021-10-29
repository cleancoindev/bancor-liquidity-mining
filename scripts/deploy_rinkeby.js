// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  await hre.run('compile');

  // We get the contract to deploy
  const dappStakingPoolFactory = await hre.ethers.getContractFactory("DappStakingPool");
  const funderFactory = await hre.ethers.getContractFactory("Funder");

  const dappStakingPoolProxy = await upgrades.deployProxy(dappStakingPoolFactory, [
    "0xa10a7ba303a4b635d28c0ad9e0317f2962a7c907", // liquidity protection
    "0xa10a7ba303a4b635d28c0ad9e0317f2962a7c907", // liq protection store
    "0xa10a7ba303a4b635d28c0ad9e0317f2962a7c907", // dapp bnt anchor
    "0xa10a7ba303a4b635d28c0ad9e0317f2962a7c907", // dapp token
    "0xa10a7ba303a4b635d28c0ad9e0317f2962a7c907", // bnt token
    await hre.ethers.provider.getBlockNumber(), // start block
    205000 // 20.5 DAPPs per block with 4 decimal precision
  ]);
  console.log("dapp Staking Pool Proxy deployed to:", dappStakingPoolProxy.address);
  await dappStakingPoolFactory.attach(dappStakingPoolProxy.address);

  // start at 0% for rewards so all goes to IL
  const funderProxy = await upgrades.deployProxy(funderFactory, [dappStakingPoolProxy.address,"0x939b462ee3311f8926c047d2b576c389092b1649",0]);
  console.log("funder Proxy deployed to:", funderProxy.address);
  await funderFactory.attach(funderProxy.address);

  const gnosisSafe = '0x5288d36112fe21be1a24b236be887C90c3AE7090';

  console.log("Transferring ownership of ProxyAdmin...");
  // The owner of the ProxyAdmin can upgrade our contracts
  await upgrades.admin.transferProxyAdminOwnership(gnosisSafe);
  console.log("Transferred ownership of ProxyAdmin to:", gnosisSafe);

  const poolContract = await upgrades.erc1967.getImplementationAddress(dappStakingPoolProxy.address);
  const funderContract = await upgrades.erc1967.getImplementationAddress(funderProxy.address);
  
  console.log("verifying on etherscan...");
  console.log(`pool contract: ${poolContract}`);
  console.log(`funder contract: ${funderContract}`);
  await hre.run("verify:verify", {
    address: poolContract,
    constructorArguments: []
  });
  await hre.run("verify:verify", {
    address: funderContract,
    constructorArguments: []
  });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });