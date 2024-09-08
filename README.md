## Foundry DEFI Stablecoin
This project aims to create a stablecoin where users can deposit WETH (Wrapped Ether) and WBTC (Wrapped Bitcoin) as collateral and receive a USD-pegged stablecoin in return.

## Installation
**To get started install both Git and Foundry**

- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git): After installation make sure to run *****git --version***** to confirm installation if you see a response like *****git version 2.34.1*****
then it was successful.

- [Foundry](https://getfoundry.sh/): After installation run *****forge --version***** if you see a response like *****forge 0.2.0 (8549aad 2024-08-19T00:21:29.325298874Z)***** then it was successful.

## Clone the repository
```shell
git clone https://github.com/Joewizyskills/foundry-defi-stablecoin
cd foundry-defi-stablecoin
forge build
```
## Test

```shell
$ forge test
```
### Test Coverage
```shell
$ forge coverage
```
To view detailed test coverage reports for your contracts
## Usage
### Start a local node
```shell
$ make anvil
```
### Deploy
By default, your local node will be used here. For it to deploy, it must be running in a separate terminal.
```shell
$ make deploy
```

### Deploy to a Testnet or Mainnet
By default, your local node will be used here. For it to deploy, it must be running in a separate terminal. All this varaibles should be added to your **.env** file. 
1. Setup your environment variables PRIVATE_KEY , ETHERSCAN_API_KEY and SEPOLIA_RPC_URL.
- PRIVATE_KEY: Import your metamask private key. It is recommended you use a wallet with no funds or a burner wallet. Learn how to export private key [HERE](https://support.metamask.io/managing-my-wallet/secret-recovery-phrase-and-private-keys/how-to-export-an-accounts-private-key/)
- SEPOLIA_RPC_URL: This is URL of the sepolia testnet node you're working with. You can get setup with one for free from [Alchemy](https://www.alchemy.com/?a=673c802981)
- ETHERSCAN_API_KEY: for verification of your contract on [Etherscan](https://etherscan.io/). Learn how to get one [HERE](https://docs.etherscan.io/getting-started/viewing-api-usage-statistics)
2. Get ETH testnet tokens by heading over to [faucets.chain.link](https://faucets.chain.link/) and claim some testnet ETH. 
3. Deploy
```shell
source .env
make deploy ARGS="--network sepolia"
```

### Scripts
We can communicate with the contract directly with the ***cast*** command in place of scripts.
For example, on Sepolia:
* Get some WETH
```shell
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "deposit()" --value 0.1ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```
0xdd13E55209Fd76AfE204dBda4007C227904f0a81 = WETH address
* Approve the WETH
```shell
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "approve(address,uint256)" 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 1000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```
* Deposit and Mint Decentralized Stablecoin (DSC)
```shell
cast send 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 "depositCollateralAndMintDsc(address,uint256,uint256)" 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 100000000000000000 10000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```
### Gas Snapshots
You can estimate how much gas things cost by running:

```shell
$ forge snapshot
```
And you'll see an output file called **.gas-snapshot**

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
# Decentralized-Stablecoin-Contract
