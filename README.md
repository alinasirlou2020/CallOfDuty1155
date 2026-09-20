<div align="center">

# 🎮 CallOfDuty1155

**ERC1155 smart contract for in-game assets — weapons, magazines & attachments**

[![Solidity](https://img.shields.io/badge/Solidity-0.8.27-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)](https://getfoundry.sh/)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-Contracts-4E5EE4)](https://openzeppelin.com/contracts/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![EIP-1155](https://img.shields.io/badge/EIP-1155-blue)](https://eips.ethereum.org/EIPS/eip-1155)
[![EIP-2981](https://img.shields.io/badge/EIP-2981-blue)](https://eips.ethereum.org/EIPS/eip-2981)

</div>

---

## 📖 About

`CallOfDuty1155` is a multi-token **ERC1155** contract that manages in-game assets — weapons, magazines, and attachments — entirely on-chain. Each asset has its own hard-capped max supply, access is controlled through a role-based system, and the contract implements the industry-standard royalty interface.

## ✨ Features

| Feature | Description |
|---|---|
| 🔫 **Dynamic asset catalog** | New items can be added anytime via `registerAsset`, not just the initial set |
| 🎯 **Per-asset supply cap** | Every asset has its own independent `maxSupply` that can never be exceeded |
| 🔐 **Role-based access control** | Separate `MINTER_ROLE`, `ASSET_MANAGER_ROLE`, and `PAUSER_ROLE` |
| ⏸️ **Emergency pause** | All mints/burns/transfers can be halted with a single transaction |
| 💰 **On-chain royalties (EIP-2981)** | Global default royalty plus optional per-token overrides |
| 🖼️ **IPFS metadata** | Standard `{id}.json` template + `contractURI()` for collection-level metadata |
| 📦 **Safe batch mint/burn** | Duplicate ids within a batch are aggregated, and `MAX_BATCH_SIZE` bounds gas risk |
| 🧾 **Custom errors** | Precise, gas-efficient errors instead of `require` strings |

## 🗂️ Current Asset Catalog

| Category | Name | Asset ID | Max Supply |
|---|---|:---:|---:|
| 🔫 Weapon | AR01 | `1` | 1,000 |
| 🔫 Weapon | SMG01 | `2` | 1,000 |
| 🔫 Weapon | DMR01 | `3` | 500 |
| 🧲 Magazine | Standard Mag | `100` | 5,000 |
| 🧲 Magazine | Extended Mag | `101` | 3,000 |
| 🧲 Magazine | Drum Mag | `102` | 2,000 |
| 🎯 Attachment | Red Dot | `200` | 3,000 |
| 🎯 Attachment | Holographic | `201` | 2,000 |
| 🎯 Attachment | Suppressor | `202` | 2,000 |

## 🏗️ Architecture

```
src/
└── CallOfDuty1155.sol       # Main contract (ERC1155 + AccessControl + Pausable + ERC2981)
script/
└── Deploy.s.sol             # Foundry deploy script (env-driven)
metadata/
├── <hex-id>.json × 9        # Per-asset metadata (name/description/image/attributes)
└── contract-metadata.json   # Collection-level metadata (for OpenSea and similar)
```

## 🔑 Roles

| Role | Grants access to |
|---|---|
| `DEFAULT_ADMIN_ROLE` | Granting/revoking all other roles |
| `MINTER_ROLE` | `mint`, `mintBatch` |
| `ASSET_MANAGER_ROLE` | `registerAsset`, `setURI`, `setContractURI`, `setDefaultRoyalty`, `setTokenRoyalty`, `resetTokenRoyalty` |
| `PAUSER_ROLE` | `pause`, `unpause` |

The deployer is granted all four roles by default.

## 🚀 Getting Started

### Prerequisites
- [Foundry](https://getfoundry.sh/) (`forge`, `cast`, `anvil`)
- A wallet funded with gas on the target network

### Install
```bash
git clone <repo-url>
cd CallOfDuty1155
forge install
```

### Build & Test
```bash
forge build
forge test
forge fmt
```

### Configure Environment Variables
```bash
cp .env.example .env
# fill in PRIVATE_KEY, RPC_URL, CONTRACT_METADATA_URI, etc.
```

### Deploy
```bash
source .env
forge script script/Deploy.s.sol:DeployCallOfDuty1155 \
    --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
```

## 🖼️ Metadata & IPFS

Token metadata follows the standard ERC1155 URI pattern:
```solidity
constructor() ERC1155("ipfs://<CID>/{id}.json")
```
Each token id maps to a JSON file named with its 64-character zero-padded hex representation (e.g. id=1 → `...0001.json`). Full details live in the `metadata/` folder and the project docs.

## 💰 Royalties (EIP-2981)

- Deployment default: 5% to the deployer address.
- Adjustable via `setDefaultRoyalty(receiver, feeNumerator)`.
- Can be overridden per asset via `setTokenRoyalty(id, receiver, feeNumerator)`.

## 🛡️ Security Notes

- Checks-Effects-Interactions is followed in `mint`/`mintBatch`.
- `burn`/`burnBatch` can only be called by the token owner or an approved operator (`setApprovalForAll`).
- `MAX_BATCH_SIZE = 50` protects against gas-griefing via oversized arrays.
- Duplicate ids within a batch are aggregated before validation, preventing supply-cap bypass.

## 📄 License

MIT — see [`LICENSE`](./LICENSE).
