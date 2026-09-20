// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script, console } from "forge-std/Script.sol";
import { CallOfDuty1155 } from "../src/CallOfDuty1155.sol";

/// @notice Deploys CallOfDuty1155 and optionally wires up the collection-level
///         (contract) metadata URI and a royalty override in the same run.
/// @dev Run with:
///      source .env
///      forge script script/Deploy.s.sol:DeployCallOfDuty1155 \
///          --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
contract DeployCallOfDuty1155 is Script {
    function run() external returns (CallOfDuty1155 token) {
        // ---- Required ----
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // ---- Optional ----
        // Collection-level metadata (contract-metadata.json) CID, already pinned.
        // Leave empty in .env to skip this step and call setContractURI() manually later.
        string memory contractMetadataUri = vm.envOr("CONTRACT_METADATA_URI", string(""));

        // Override the constructor's default royalty (deployer, 5%). Leave both
        // empty/zero in .env to keep that default untouched.
        address royaltyReceiver = vm.envOr("ROYALTY_RECEIVER", address(0));
        uint256 royaltyBps = vm.envOr("ROYALTY_BPS", uint256(0));

        vm.startBroadcast(deployerPrivateKey);

        token = new CallOfDuty1155();
        console.log("CallOfDuty1155 deployed at:", address(token));
        console.log("Deployer / initial admin / initial MINTER_ROLE / ASSET_MANAGER_ROLE / PAUSER_ROLE:", deployer);

        if (bytes(contractMetadataUri).length > 0) {
            token.setContractURI(contractMetadataUri);
            console.log("contractURI set to:", contractMetadataUri);
        } else {
            console.log("!! CONTRACT_METADATA_URI not set in .env -- call setContractURI() manually later.");
        }

        if (royaltyReceiver != address(0) && royaltyBps > 0) {
            // Explicit bounds check before the narrowing cast: ERC2981 royalty
            // fractions are basis points out of 10_000, so anything above that
            // is already invalid. Checking first avoids silently truncating an
            // unexpectedly large ROYALTY_BPS value down to a meaningless uint96
            // before OpenZeppelin's own >10_000 validation ever runs.
            require(royaltyBps <= 10_000, "ROYALTY_BPS must be <= 10000 (100%)");
            // forge-lint: disable-next-line(unsafe-typecast)
            token.setDefaultRoyalty(royaltyReceiver, uint96(royaltyBps));
            console.log("Default royalty overridden -> receiver:", royaltyReceiver);
            console.log("Default royalty overridden -> bps:", royaltyBps);
        } else {
            console.log("Using constructor default royalty (deployer, 5%).");
        }

        vm.stopBroadcast();
    }
}
