# OpenCollab Protocol Contracts

The OpenCollab protocol is a proof-of-concept blockchain based protocol for incentivizing open source software development using the OpenCollab token (an ERC20 token). The protocol is implemented by a set of Ethereum smart contracts.

# Setup

`opencollab-contracts` can be used with [TestRPC](https://github.com/ethereumjs/testrpc), a Node.js based Ethereum client for testing and development.

If you do not already have TestRPC installed globally:

`npm install -g ethereum-testrpc`

You will also need [Truffle](https://github.com/trufflesuite/truffle), an Ethereum smart contract development framework, installed in order to run the contract tests.

If you do not already have Truffle installed globally:

`npm install -g truffle`

# Usage

Make sure TestRPC is running. Gas usage has not been addressed so it is likely necessary to run TestRPC with a high block gas limit.

`testrpc -l 1000000000`

Run the contract tests:

```
git clone https://github.com/yondonfu/opencollab-contracts.git
cd opencollab-contracts
truffle test
```
