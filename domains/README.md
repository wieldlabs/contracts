# `.cast` Details & Contract Deployment

See the `contracts/` folder for more details on how .cast handles work!

String names of domains are not stored on a contract level - token uri's are
`sha3` hashes of the lowercase name after `.beb`/`.cast` has been removed.

To map a token uri to metadata, you query: `build.far.quest/metadata/uri/{uri}`,
e.g. for
[playground.cast](https://build.far.quest/metadata/uri/28351188642621241456184943762989329996148978531966429149720007640204744112723).

This folder also contains applicable ABIs for .cast handles.

# Ethereum

- [OpenSea Collection](https://opensea.io/collection/casthandles)
- **BaseRegistrar** deployed to:
  [`0x427b8efEe2d6453Bb1c59849F164C867e4b2B376`](https://etherscan.io/address/0x427b8efEe2d6453Bb1c59849F164C867e4b2B376)
  (bebdomains.eth)
  - Base Registar = `.beb` TLD.
- **BebRegistryBetaController** deployed to:
  [`0x0F08FC2A63F4BfcDDfDa5c38e9896220d5468a64`](https://etherscan.io/address/0x0F08FC2A63F4BfcDDfDa5c38e9896220d5468a64)

# Optimism

- [OpenSea Collection](https://opensea.io/collection/castoptimism)
- **BaseRegistrar** deployed to:
  [`0xd14005cb9b40a1b7104eacdeae36f7fe112fae5f`](https://optimistic.etherscan.io/address/0xd14005cb9b40a1b7104eacdeae36f7fe112fae5f)
- **OPBebRegistryBetaController** deployed to:
  [`0x8db531fe6bea7b474c7735879e9a1000e819bd1d`](https://optimistic.etherscan.io/address/0x8db531fe6bea7b474c7735879e9a1000e819bd1d)
- Base Registar = `.cast` TLD with domains prefixed with `op_` (enforced by `OPBebRegistryBetaController`)

# Base

- [OpenSea Collection](https://opensea.io/collection/castbase)
- **BaseRegistrar** deployed to:
  [`0xf2b35faadbcded342a1a4f1e6c95b977e85439fa`](https://basescan.org/address/0xf2b35faadbcded342a1a4f1e6c95b977e85439fa)
- **BaseBebRegistryBetaController** deployed to:
  [`0xdd7672abb72542fd30307159bd898a273b1a14af`](https://basescan.org/address/0xdd7672abb72542fd30307159bd898a273b1a14af)
- Base Registar = `.cast` TLD with domains prefixed with `base_` (enforced by `BaseBebRegistryBetaController`)
