# Guestbook launch

A fixed-supply ERC-20 and a small, permanent on-chain guestbook. Signing does not require tokens, an allowance, or a fee beyond transaction gas.

## Contracts and rules

`src/LaunchToken.sol:LaunchToken` has no constructor arguments. Its name is **Guestbook**, symbol **GUEST**, and decimals **18**. Construction mints exactly **1,000,000,000 tokens (10^27 minor units)** to `msg.sender`. There are no external mint, burn, owner, pause, blocklist, fee, initialization, or upgrade functions. ERC-20 transfers and allowances use the vendored OpenZeppelin implementation, including the standard non-decreasing maximum allowance convention.

`src/Guestbook.sol:Guestbook` takes one nonzero `address initialOwner`. This explicit address is the immutable owner; a deploying factory does not acquire authority merely by deploying it. The owner can pause and resume signing, and has no additional powers. There is no ownership transfer, renunciation, upgrade, entry editing, deletion, or signer reset.

Each calling address can append one entry while unpaused. The exact message bytes, signer address, and block timestamp are stored. The limit is **140 bytes**, not 140 characters. Empty messages are accepted and consume the address's one entry. Strings are not validated as UTF-8. Different addresses may submit identical messages. Failed calls never consume a signature slot. All writes are nonpayable, and the contract makes no external calls.

| Guestbook call | Behavior |
| --- | --- |
| `sign(string)` | Appends once for `msg.sender`; returns the zero-based index; emits `Signed(index, signer, message, signedAt)`. |
| `entryCount()` | Number of stored entries. |
| `entryAt(uint256)` | Returns `Entry { signer, signedAt, message }`; out-of-range indices revert with `EntryNotFound`. |
| `entryBySigner(address)` | Returns the same entry; an unknown signer reverts with `SignerNotFound`. |
| `hasSigned(address)` | Distinguishes an absent signer from an entry with an empty message. |
| `setPaused(bool)` | Owner only; emits `PauseChanged`. Repeating the current state is allowed. |
| `owner()`, `paused()`, `MAX_MESSAGE_BYTES()` | Configuration and status. |

Signing checks pause status, then duplicate signer, then byte length, reverting with `SigningPaused`, `AlreadySigned`, or `MessageTooLong`, respectively. Existing entries and all read methods remain available while paused. Enumeration is by individual index; no unbounded on-chain enumeration operation is needed.

## Assumptions and operational responsibilities

- “Once” means once per address per deployment, not once per human. Contract accounts are supported. A person can use multiple wallets. Calls through an intermediary are attributed to that intermediary, without meta-transaction or off-chain signature support.
- The owner may pause indefinitely. Because ownership is immutable, a lost owner account can leave the current pause state permanent. The launch operator must select a usable owner address, such as the policy-selected multisig, before deployment.
- Entries are public and permanent, including abusive content or accidentally submitted personal information. Neither the owner nor a signer can moderate them on chain. Any future UI must render messages as untrusted text, safely handle arbitrary bytes, and calculate UTF-8 byte length before sending.
- The recorded timestamp is chain-provided information, not trusted wall-clock proof or randomness. Entry order is transaction execution order.
- Guestbook has no custody or withdrawals. Ordinary ETH payments revert. Force-sent ETH or tokens sent to its address cannot be recovered. The launch token and guestbook are independent: pausing the guestbook cannot pause token transfers.

## Offline build and checks

Foundry 1.8.3 and cached Solidity **0.8.26** are used. `foundry.toml` pins the compiler, enables the optimizer at 200 runs, targets Paris, and sets `bytecode_hash = "none"`, `offline = true`, `ffi = false`, and `fs_permissions = []`. Dependencies are ordinary files under `lib/`, with licenses and exact hashes recorded in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md). No network, package install, compiler download, submodule, RPC, or environment configuration is needed for the delivered tests.

```sh
forge build --offline
forge test --offline
forge test --offline --fuzz-seed 0x9654 --fuzz-runs 1024
forge fmt --check
```

The 36 tests cover successful signing, both lookup methods, empty messages, the 140/141-byte boundary, UTF-8 byte length, contract callers, duplicate attempts, unauthorized pause/resume, failure atomicity, immutable history through generated signing/pause sequences, token metadata/supply/transfers/allowances, factory ownership, runtime limits, forbidden opcodes, and script chain guards. No project test reads or changes environment variables or makes network calls.

## Deployment parameters and handoff

The target is **Sepolia, chain ID 11155111**. The production launch is performed by the network's deployer through `ProjectFactory`, after review. This assignment does not deploy or broadcast transactions.

| Artifact | Constructor arguments | Launch configuration |
| --- | --- | --- |
| `src/LaunchToken.sol:LaunchToken` | None | Launch token; 18 decimals; supply `1000000000000000000000000000`. |
| `src/Guestbook.sol:Guestbook` | `address initialOwner` | Application identifier `Guestbook`; pass the policy's `$owner`, never the factory address by default. |

The token must be created by the factory so the factory initially holds its whole supply. Guestbook is fully configured in its nonpayable constructor and needs no initialization call or token reference. There are no application dependencies. The network handles allocation, liquidity, its supplied guard, and its distributor. No contributor distributor, fee logic, or pool contract is included. The separate manifest step should derive `launch.json` from these artifacts and constructor arguments.

The network operator is responsible for verifying the compiler settings and artifacts, checking the final manifest's owner and chain, executing the reviewed factory deployment with the managed signer, verifying source, and recording deployed addresses. The owner is responsible for pause/resume decisions and maintaining access to its account. Independent review remains a release responsibility; these tests are not an independent audit.

`script/Deploy.s.sol:Deploy` provides standalone operator simulations, one deployment per entry point. `run()` deploys only the token; `runGuestbook(address)` deploys only the guestbook. These standalone entry points do not implement a factory launch or its supply allocation. Each reads only `EXPECTED_CHAIN_ID`; the address is an explicit function argument. Only 31337 and 11155111 are allowed. Expected ID 0 is allowed only on local chain 31337; Sepolia requires 11155111 explicitly.

Local simulations, with an example owner that must be replaced for a real deployment:

```sh
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline
EXPECTED_CHAIN_ID=0 forge script script/Deploy.s.sol:Deploy --offline \
  --sig 'runGuestbook(address)' 0x00000000000000000000000000000000000A11cE
```

Only the network operator may initiate a real deployment through its managed factory workflow; no wallet secret or RPC configuration is embedded in this project. Do not substitute the standalone token simulation for that launch workflow.
