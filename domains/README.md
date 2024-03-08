# `Wield` Details & Contract Deployment

See the `contracts/` folder for more details on how Wield Dimensions work.

String names of domains are not stored on a contract level - token uri's are
`sha3` hashes of the lowercase name after `.beb`/`.cast` has been removed.

To map a token uri to metadata, you query: `build.far.quest/metadata/uri/{uri}`,
e.g. for
[playground.cast](https://build.far.quest/metadata/uri/28351188642621241456184943762989329996148978531966429149720007640204744112723).

See this folder for the applicable ABIs for [Wield](https://wield.xyz).

- **BaseRegistrar** deployed to: `0x427b8efEe2d6453Bb1c59849F164C867e4b2B376`
  (bebdomains.eth)
  - Base Registar = `.beb` TLD.
- **BebRegistryBetaController** deployed to:
  `0x0F08FC2A63F4BfcDDfDa5c38e9896220d5468a64`
