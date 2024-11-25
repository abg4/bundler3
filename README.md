# Morpho Blue Bundler v3

The [`Bundler`](./src/Bundler.sol) executes a sequence of calls atomically. EOAs should use the Bundler to execute multiple actions in a single transaction.

## Structure

<img width="586" alt="bundler structure" src="https://github.com/user-attachments/assets/983b7e48-ba0c-4fda-a31b-e7c9cc212da4">

The Bundler's entrypoint is `multicall(Call[] calldata bundle)`. A bundle is a sequence of calls, and each call specifies an arbitrary address and arbitrary calldata.

A contract called by the Bundler is called a module.

For instance, [`EthereumModule1`](./src/ethereum/EthereumModule1.sol) contains generic as well as ethereum-specific actions. It must be approved by the user to e.g. transfer the initiator's assets.

Users should not approve untrusted modules, just like they should not approve untrusted contracts in general.

Before calling a contract, the Bundler stores its own caller as the bundle's `initiator`. Modules can read the current initiator during bundle execution. This is useful to make a secure module: for instance, a module should only move funds owner by the current initiator.

The Bundler can be called back by its most-recently-called module using `multicallFromModule(Call[] calldata bundle)`. This is useful for callback-based flows such as flashloans.

To minimize the number of transactions and signatures, it is preferable to use Permit2's [batch permitting](https://github.com/Uniswap/permit2/blob/main/src/AllowanceTransfer.sol#L43-L56) through `GenericModule1`'s `approve2Batch` action.

All modules inherit from [`BaseModule`](./src/BaseModule.sol), which provides essential features such as reading the current initiator address.

## Development

Run tests with `yarn test --chain <chainid>` (chainid can be 1 or 8453).

## Audits

TBA.

## License

Bundlers are licensed under `GPL-2.0-or-later`, see [`LICENSE`](./LICENSE).

## Links

- Deployments: TBA.
- SDK: TBA.
