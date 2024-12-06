```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ... omitting imports

/// @notice A source contract for initiating RIP-7755 Cross Chain Requests as well as reward fulfillment to fulfillers that
/// submit the cross chain calls to destination chains.
abstract contract RIP7755Outbox {
    /// @notice An enum representing the status of an RIP-7755 cross chain call
    enum CrossChainCallStatus {
        None,
        Requested,
        Canceled,
        Completed
    }

    /// @notice A mapping from the keccak256 hash of a `CrossChainRequest` to its current status
    mapping(bytes32 requestHash => CrossChainCallStatus status) private _requestStatus;

    // Main storage location in `RIP7755Inbox` used as the base for the fulfillmentInfo mapping following EIP-7201. (keccak256("RIP-7755"))
    bytes32 private constant _VERIFIER_STORAGE_LOCATION =
        0x43f1016e17bdb0194ec37b77cf476d255de00011d02616ab831d2e2ce63d9ee2;

    /// @notice An incrementing nonce value to ensure no two `CrossChainRequest` can be exactly the same
    uint256 private _nonce;

    /// @notice Event emitted when a user requests a cross chain call to be made by a fulfiller
    /// @param requestHash The keccak256 hash of a `CrossChainRequest`
    /// @param request The requested cross chain call
    event CrossChainCallRequested(bytes32 indexed requestHash, CrossChainRequest request);

    /// @notice Event emitted when an expired cross chain call request is canceled
    /// @param requestHash The keccak256 hash of a `CrossChainRequest`
    event CrossChainCallCanceled(bytes32 indexed requestHash);

    /// @notice Submits an RIP-7755 request for a cross chain call
    ///
    /// @param request A cross chain request structured as a `CrossChainRequest`
    function requestCrossChainCall(CrossChainRequest memory request) external payable {
        // ... validation steps

        _requestStatus[requestHash] = CrossChainCallStatus.Requested;

        emit CrossChainCallRequested(requestHash, request);
    }

    /// @notice To be called by a fulfiller that successfully submitted a cross chain request to the destination chain and
    /// can prove it with a valid nested storage proof
    ///
    /// @param request A cross chain request structured as a `CrossChainRequest`
    /// @param proof A proof that cryptographically verifies that `fulfillmentInfo` does, indeed, exist in
    /// storage on the destination chain
    /// @param payTo The address the fulfiller wants to receive the reward
    function claimReward(CrossChainRequest calldata request, bytes calldata proof, address payTo) external {
        bytes32 requestHash = hashRequest(request);
        bytes memory storageKey = abi.encode(keccak256(abi.encodePacked(requestHash, _VERIFIER_STORAGE_LOCATION)));

        _checkValidStatus({requestHash: requestHash, expectedStatus: CrossChainCallStatus.Requested});

        _validateProof(storageKey, request, proof);

        _requestStatus[requestHash] = CrossChainCallStatus.Completed;

        _sendReward(request, payTo);
    }

    /// @notice Cancels a pending request that has expired
    ///
    /// @dev Can only be called if the request is in the `CrossChainCallStatus.Requested` state
    ///
    /// @param request A cross chain request structured as a `CrossChainRequest`
    function cancelRequest(CrossChainRequest calldata request) external {
        // ... validation steps

        _requestStatus[requestHash] = CrossChainCallStatus.Canceled;

        // Return the stored reward back to the original requester
        _sendReward(request, request.requester);

        emit CrossChainCallCanceled(requestHash);
    }

    /// @dev Reverts if the request status is not as expected
    function _checkValidStatus(bytes32 requestHash, CrossChainCallStatus expectedStatus) private view {}

    /// @dev Sends `request.rewardAmount` of `request.rewardAsset` to `to`
    function _sendReward(CrossChainRequest calldata request, address to) private {}

    /// @notice Validates storage proofs and verifies fill
    ///
    /// @custom:reverts If storage proof invalid.
    /// @custom:reverts If fillInfo not found at inboxContractStorageKey on crossChainCall.verifyingContract
    /// @custom:reverts If fillInfo.timestamp is less than
    /// crossChainCall.finalityDelaySeconds from current destination chain block timestamp.
    ///
    /// @dev Implementation will vary by L2
    ///
    /// @param inboxContractStorageKey The storage location of the data to verify on the destination chain
    /// `RIP7755Inbox` contract
    /// @param request The original cross chain request submitted to this contract
    /// @param proofData The proof to validate
    function _validateProof(
        bytes memory inboxContractStorageKey,
        CrossChainRequest calldata request,
        bytes calldata proofData
    ) internal virtual;
}
```
