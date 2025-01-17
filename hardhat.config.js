require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("hardhat-abi-exporter");
require("hardhat-gas-reporter");
require('@openzeppelin/hardhat-upgrades');
require("@nomiclabs/hardhat-etherscan");
const config = require("./.config.json");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000
          }
        }
      },
    ]
  }, 
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        blockNumber: 12786615,
        url: `https://eth-mainnet.alchemyapi.io/v2/${config.alchemyKey}`
      },
      blockGasLimit: 12e6
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${config.alchemyKey}`,
      accounts: config.keys,
      blockGasLimit: 12e6
    }
  },
  gasReporter: {
    currency: "USD",
    coinmarketcap: config.coinmarketcapKey,
    showTimeSpent: true,
  },
  mocha: {
    timeout: 120000,
    retries: 0,
    bail: true,
  },
  abiExporter: {
    flat: true
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: config.etherscanApiKey
  }
};
