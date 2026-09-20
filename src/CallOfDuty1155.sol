// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ERC2981 } from "@openzeppelin/contracts/token/common/ERC2981.sol";

/// @title CallOfDuty1155
/// @notice ERC1155 in-game asset contract for weapons, magazines and attachments,
///         with per-id max supply enforcement, role-based access control, pausability
///         and EIP-2981 royalties.
contract CallOfDuty1155 is ERC1155, AccessControl, Pausable, ERC2981 {
    // =============================================================
    //                           ROLES
    // =============================================================

    /// @notice Allowed to mint new assets (single or batch).
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Allowed to register new assets, update URIs and royalty settings.
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

    /// @notice Allowed to pause/unpause all transfers, mints and burns.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // =============================================================
    //                        ASSET IDs
    // =============================================================

    // Weapons
    uint256 public constant AR01 = 1;
    uint256 public constant SMG01 = 2;
    uint256 public constant DMR01 = 3;

    // Magazines
    uint256 public constant STANDARD_MAG = 100;
    uint256 public constant EXTENDED_MAG = 101;
    uint256 public constant DRUM_MAG = 102;

    // Attachments
    uint256 public constant RED_DOT = 200;
    uint256 public constant HOLOGRAPHIC = 201;
    uint256 public constant SUPPRESSOR = 202;

    // =============================================================
    //                    INITIAL SUPPLY CAPS
    // =============================================================
    // Named separately from the id constants above so the linter doesn't flag
    // coincidental repeats (e.g. DRUM_MAG and HOLOGRAPHIC both happening to
    // start at 2000) as "the same value used in multiple places" -- these are
    // independent per-asset caps that just happen to share a number today.

    uint256 public constant AR01_MAX_SUPPLY = 1000;
    uint256 public constant SMG01_MAX_SUPPLY = 1000;
    uint256 public constant DMR01_MAX_SUPPLY = 500;

    uint256 public constant STANDARD_MAG_MAX_SUPPLY = 5000;
    uint256 public constant EXTENDED_MAG_MAX_SUPPLY = 3000;
    uint256 public constant DRUM_MAG_MAX_SUPPLY = 2000;

    uint256 public constant RED_DOT_MAX_SUPPLY = 3000;
    uint256 public constant HOLOGRAPHIC_MAX_SUPPLY = 2000;
    uint256 public constant SUPPRESSOR_MAX_SUPPLY = 2000;

    /// @notice Default royalty (basis points out of 10_000) applied at deploy time.
    uint96 public constant DEFAULT_ROYALTY_BPS = 500;

    // =============================================================
    //                       BATCH LIMITS
    // =============================================================

    /// @notice Maximum number of ids allowed in a single mintBatch/burnBatch call,
    ///         to bound gas usage and protect against griefing with oversized arrays.
    uint256 public constant MAX_BATCH_SIZE = 50;

    // =============================================================
    //                        ASSET SYSTEM
    // =============================================================

    enum AssetCategory {
        Weapon,
        Magazine,
        Attachment
    }

    struct Asset {
        bool exists;
        AssetCategory category;
        uint256 maxSupply;
        uint256 currentSupply;
    }

    /// @dev id => Asset metadata / supply tracking.
    mapping(uint256 => Asset) private _assets;

    /// @dev Ordered list of every registered asset id, for on-chain enumeration.
    uint256[] private _assetIds;

    // =============================================================
    //                           EVENTS
    // =============================================================

    event AssetRegistered(uint256 indexed id, AssetCategory indexed category, uint256 maxSupply);
    event AssetSupplyUpdated(uint256 indexed id, uint256 currentSupply);
    event BaseURIUpdated(string newUri);
    event ContractURIUpdated(string newUri);

    // =============================================================
    //                       CUSTOM ERRORS
    // =============================================================

    error AssetAlreadyExists(uint256 id);
    error AssetNotRegistered(uint256 id);
    error InvalidMaxSupply();
    error MaxSupplyExceeded(uint256 id, uint256 requested, uint256 available);
    error InvalidAmount();
    error ArrayLengthMismatch();
    error InvalidRecipient();
    error CannotBurnMoreThanOwned(uint256 id, uint256 requested, uint256 balance);
    error BatchSizeExceeded(uint256 provided, uint256 max);

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor() ERC1155("ipfs://bafybeieohh755cpjkwox3f7rxd7taxbglmzlg5fjrtn4qz3tkvvfmoauba/{id}.json") {
        // Deployer becomes admin.
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Initial roles.
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(ASSET_MANAGER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        // Default royalty: 5% to the deployer.
        // Update via setDefaultRoyalty() once the real treasury address is known.
        _setDefaultRoyalty(msg.sender, DEFAULT_ROYALTY_BPS);

        // Register initial assets.

        // Weapons
        _registerAsset(AR01, AssetCategory.Weapon, AR01_MAX_SUPPLY);
        _registerAsset(SMG01, AssetCategory.Weapon, SMG01_MAX_SUPPLY);
        _registerAsset(DMR01, AssetCategory.Weapon, DMR01_MAX_SUPPLY);

        // Magazines
        _registerAsset(STANDARD_MAG, AssetCategory.Magazine, STANDARD_MAG_MAX_SUPPLY);
        _registerAsset(EXTENDED_MAG, AssetCategory.Magazine, EXTENDED_MAG_MAX_SUPPLY);
        _registerAsset(DRUM_MAG, AssetCategory.Magazine, DRUM_MAG_MAX_SUPPLY);

        // Attachments
        _registerAsset(RED_DOT, AssetCategory.Attachment, RED_DOT_MAX_SUPPLY);
        _registerAsset(HOLOGRAPHIC, AssetCategory.Attachment, HOLOGRAPHIC_MAX_SUPPLY);
        _registerAsset(SUPPRESSOR, AssetCategory.Attachment, SUPPRESSOR_MAX_SUPPLY);
    }

    // =============================================================
    //                       ASSET REGISTRY
    // =============================================================

    /// @notice Registers a new asset id with a hard-capped max supply.
    /// @dev Can only be called once per id; reverts if the id already exists.
    function registerAsset(uint256 id, AssetCategory category, uint256 maxSupplyValue)
        external
        onlyRole(ASSET_MANAGER_ROLE)
    {
        _registerAsset(id, category, maxSupplyValue);
    }

    function _registerAsset(uint256 id, AssetCategory category, uint256 maxSupplyValue) internal {
        if (_assets[id].exists) {
            revert AssetAlreadyExists(id);
        }

        if (maxSupplyValue == 0) {
            revert InvalidMaxSupply();
        }

        _assets[id] = Asset({ exists: true, category: category, maxSupply: maxSupplyValue, currentSupply: 0 });
        _assetIds.push(id);

        emit AssetRegistered(id, category, maxSupplyValue);
    }

    // =============================================================
    //                            MINT
    // =============================================================

    /// @notice Mints `amount` of asset `id` to `to`, respecting the asset's max supply.
    function mint(address to, uint256 id, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) {
            revert InvalidRecipient();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        _validateMint(id, amount);

        // Effects before interactions: update accounting before the external
        // safeTransfer callback that _mint may trigger on `to`.
        _assets[id].currentSupply += amount;
        emit AssetSupplyUpdated(id, _assets[id].currentSupply);

        _mint(to, id, amount, "");
    }

    /// @notice Batch-mints multiple asset ids/amounts to `to` in a single call.
    /// @dev Duplicate ids within the same batch are aggregated before the max-supply
    ///      check, so splitting one id across several array slots cannot bypass the cap.
    ///      Batch length is capped at MAX_BATCH_SIZE.
    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        if (to == address(0)) {
            revert InvalidRecipient();
        }

        uint256 length = ids.length;
        if (length != amounts.length) {
            revert ArrayLengthMismatch();
        }

        if (length > MAX_BATCH_SIZE) {
            revert BatchSizeExceeded(length, MAX_BATCH_SIZE);
        }

        // First pass: validate each id, aggregating amounts for repeated ids
        // in the same batch so the max supply check can't be bypassed by
        // splitting one id into multiple array entries.
        // NOTE: the linter flags revert-in-loop and storage-write-in-loop
        // below as gas-cost notes -- both are intentional here, and array
        // length is already hard-capped by MAX_BATCH_SIZE just above, so
        // worst-case gas is bounded and predictable.
        for (uint256 i = 0; i < length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            if (amount == 0) {
                revert InvalidAmount();
            }

            if (!_assets[id].exists) {
                revert AssetNotRegistered(id);
            }

            uint256 cumulativeRequested = amount;
            for (uint256 j = 0; j < i; j++) {
                if (ids[j] == id) {
                    cumulativeRequested += amounts[j];
                }
            }

            uint256 available = _assets[id].maxSupply - _assets[id].currentSupply;
            if (cumulativeRequested > available) {
                revert MaxSupplyExceeded(id, cumulativeRequested, available);
            }
        }

        // Second pass: update accounting (effects) before the external call.
        for (uint256 i = 0; i < length; i++) {
            _assets[ids[i]].currentSupply += amounts[i];
            emit AssetSupplyUpdated(ids[i], _assets[ids[i]].currentSupply);
        }

        _mintBatch(to, ids, amounts, "");
    }

    /// @dev Reverts if `id` is not registered or `amount` would exceed its max supply.
    function _validateMint(uint256 id, uint256 amount) internal view {
        if (!_assets[id].exists) {
            revert AssetNotRegistered(id);
        }

        uint256 current = _assets[id].currentSupply;
        uint256 max = _assets[id].maxSupply;

        if (amount > max - current) {
            revert MaxSupplyExceeded(id, amount, max - current);
        }
    }

    // =============================================================
    //                            BURN
    // =============================================================

    /// @notice Burns `amount` of asset `id` from `from`.
    /// @dev Only `from` itself, or an operator approved via `setApprovalForAll`,
    ///      may burn `from`'s tokens.
    function burn(address from, uint256 id, uint256 amount) external whenNotPaused {
        if (amount == 0) {
            revert InvalidAmount();
        }

        if (!_assets[id].exists) {
            revert AssetNotRegistered(id);
        }

        if (from != _msgSender() && !isApprovedForAll(from, _msgSender())) {
            revert ERC1155MissingApprovalForAll(_msgSender(), from);
        }

        uint256 balance = balanceOf(from, id);
        if (balance < amount) {
            revert CannotBurnMoreThanOwned(id, amount, balance);
        }

        _assets[id].currentSupply -= amount;
        emit AssetSupplyUpdated(id, _assets[id].currentSupply);

        _burn(from, id, amount);
    }

    /// @notice Batch-burns multiple asset ids/amounts from `from`.
    /// @dev Only `from` itself, or an operator approved via `setApprovalForAll`,
    ///      may burn `from`'s tokens. Batch length is capped at MAX_BATCH_SIZE.
    function burnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) external whenNotPaused {
        uint256 length = ids.length;
        if (length != amounts.length) {
            revert ArrayLengthMismatch();
        }

        if (length > MAX_BATCH_SIZE) {
            revert BatchSizeExceeded(length, MAX_BATCH_SIZE);
        }

        if (from != _msgSender() && !isApprovedForAll(from, _msgSender())) {
            revert ERC1155MissingApprovalForAll(_msgSender(), from);
        }

        for (uint256 i = 0; i < length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];

            if (amount == 0) {
                revert InvalidAmount();
            }

            if (!_assets[id].exists) {
                revert AssetNotRegistered(id);
            }

            uint256 balance = balanceOf(from, id);
            if (balance < amount) {
                revert CannotBurnMoreThanOwned(id, amount, balance);
            }
        }

        // NOTE: same MAX_BATCH_SIZE-bounded loop as in mintBatch above --
        // revert-in-loop / storage-write-in-loop here are intentional.
        for (uint256 i = 0; i < length; i++) {
            _assets[ids[i]].currentSupply -= amounts[i];
            emit AssetSupplyUpdated(ids[i], _assets[ids[i]].currentSupply);
        }

        _burnBatch(from, ids, amounts);
    }

    // =============================================================
    //                       ASSET QUERIES
    // =============================================================

    function getAsset(uint256 id) external view returns (Asset memory) {
        if (!_assets[id].exists) {
            revert AssetNotRegistered(id);
        }

        return _assets[id];
    }

    function assetExists(uint256 id) external view returns (bool) {
        return _assets[id].exists;
    }

    function maxSupply(uint256 id) external view returns (uint256) {
        if (!_assets[id].exists) {
            revert AssetNotRegistered(id);
        }

        return _assets[id].maxSupply;
    }

    function currentSupply(uint256 id) external view returns (uint256) {
        if (!_assets[id].exists) {
            revert AssetNotRegistered(id);
        }

        return _assets[id].currentSupply;
    }

    /// @notice Returns the total number of distinct asset ids ever registered.
    function assetCount() external view returns (uint256) {
        return _assetIds.length;
    }

    /// @notice Returns every registered asset id, in registration order.
    /// @dev Unbounded — fine for a catalog of this size, but avoid calling this
    ///      on-chain from another contract if the catalog grows very large.
    function getAllAssetIds() external view returns (uint256[] memory) {
        return _assetIds;
    }

    /// @notice Returns the registered asset id at a given index in registration order.
    function assetIdAt(uint256 index) external view returns (uint256) {
        return _assetIds[index];
    }

    // =============================================================
    //                       URI MANAGEMENT
    // =============================================================

    /// @notice Updates the per-token metadata URI template (the "{id}.json" pattern).
    /// @dev OpenZeppelin's _setURI does not emit the standard ERC1155 `URI` event
    ///      (it can't know which token ids are affected by a wildcard template).
    ///      We emit it manually for every currently-registered id so marketplaces
    ///      and indexers that listen for `URI` know to refresh metadata. This loop
    ///      is unbounded in the number of registered assets — fine at this catalog
    ///      size, but if the collection grows very large, consider a paginated
    ///      variant that emits for a caller-supplied slice of ids instead.
    function setURI(string calldata newUri) external onlyRole(ASSET_MANAGER_ROLE) {
        _setURI(newUri);
        emit BaseURIUpdated(newUri);

        uint256 length = _assetIds.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 id = _assetIds[i];
            emit URI(uri(id), id);
        }
    }

    /// @dev Collection-level metadata URI, read by marketplaces (e.g. OpenSea's
    ///      `contractURI()` convention) to display collection name, image, royalties, etc.
    string private _contractUri;

    /// @notice Returns the URI for the collection-level metadata JSON.
    function contractURI() external view returns (string memory) {
        return _contractUri;
    }

    /// @notice Updates the collection-level metadata URI.
    function setContractURI(string calldata newUri) external onlyRole(ASSET_MANAGER_ROLE) {
        _contractUri = newUri;
        emit ContractURIUpdated(newUri);
    }

    // =============================================================
    //                          ROYALTIES (EIP-2981)
    // =============================================================

    /// @notice Sets the default royalty applied to all token ids that don't have
    ///         a token-specific override.
    /// @param receiver The address that should receive royalty payments.
    /// @param feeNumerator Royalty in basis points out of 10_000 (e.g. 500 = 5%).
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyRole(ASSET_MANAGER_ROLE) {
        if (receiver == address(0)) {
            revert InvalidRecipient();
        }

        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Sets a royalty override for a single asset id.
    /// @param id The asset id to override.
    /// @param receiver The address that should receive royalty payments for this id.
    /// @param feeNumerator Royalty in basis points out of 10_000 (e.g. 750 = 7.5%).
    function setTokenRoyalty(uint256 id, address receiver, uint96 feeNumerator) external onlyRole(ASSET_MANAGER_ROLE) {
        if (!_assets[id].exists) {
            revert AssetNotRegistered(id);
        }

        if (receiver == address(0)) {
            revert InvalidRecipient();
        }

        _setTokenRoyalty(id, receiver, feeNumerator);
    }

    /// @notice Removes the token-specific royalty override for `id`, falling back
    ///         to the default royalty.
    function resetTokenRoyalty(uint256 id) external onlyRole(ASSET_MANAGER_ROLE) {
        _resetTokenRoyalty(id);
    }

    // =============================================================
    //                          PAUSABLE
    // =============================================================

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // =============================================================
    //                    ERC1155 + PAUSABLE HOOK
    // =============================================================

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        if (paused()) {
            revert EnforcedPause();
        }

        super._update(from, to, ids, values);
    }

    // =============================================================
    //                     ACCESS CONTROL SUPPORT
    // =============================================================

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
