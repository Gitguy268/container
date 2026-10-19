# Contributing

## To this fork

Issues and pull requests for the features this fork adds (`container here`, `container dash` and the changes listed in the README) are welcome here. Problems that also happen in upstream `container` are better reported to [apple/container](https://github.com/apple/container), so everyone gets the fix.

Before you open a pull request:

1. Open an issue first for anything larger than a small fix.
2. Run `make check` (formatting and licence headers), `make all` and `make test`. If you only have CommandLineTools, see "Build this fork" in the README for the extra `make test` flag.
3. For changes to `container here` or the runtime, also run the matching integration tests locally with `make integration`, since CI can't boot VMs.
4. Keep commits small and focused, and update the docs in `docs/` when behaviour changes.

Everyone taking part is expected to follow the [code of conduct](./CODE_OF_CONDUCT.md).

## To upstream

Contributions are welcome and encouraged! Read our [main contributing guide](https://github.com/apple/containerization/blob/main/CONTRIBUTING.md) to get started.
