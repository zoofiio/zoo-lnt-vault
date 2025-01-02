
## Getting Started

### Compile Contracts

```sh
$ yarn
$ hh compile
```

### Deploy Contracts

#### Prepare `.env` 

With same keys to `.env-example`

```sh
$ hh run scripts/1-deploy.ts --network <mainnet/sepolia/bera-bartio>

# Etherscan verify
$ hh clean
$ yarn verify <mainnet/sepolia/bera-bartio>
```

### Run Test Cases

```sh
$ hh test
# To run test cases of a test file:
$ hh test ./test/xxx.ts
```

**To run forge tests**

```sh
$ forge test
```

## License

Distributed under the Apache License. See [LICENSE](./LICENSE) for more information.