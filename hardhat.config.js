require("dotenv").config()
require("@nomiclabs/hardhat-ethers")
require("@nomiclabs/hardhat-etherscan")

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      gasPrice: 225000000000,
      chainId: 31337,
      forking:
        process.env.USE_LOCAL_TESTNET == "1"
          ? {
              url: "https://api.avax.network/ext/bc/C/rpc"
            }
          : undefined
    },
    mainnet: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      gasPrice: 225000000000,
      chainId: 43114,
      accounts: { mnemonic: process.env.MNEMONIC }
    }
  },

  etherscan: {
    apiKey: process.env.SNOWTRACE_API_KEY
  },

  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }
}
