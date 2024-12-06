```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// ... omitting imports

/// @notice An inbox contract within RIP-7755. This contract's sole purpose is to route requested transactions on
/// destination chains and store record of their fulfillment.
contract RIP7755Inbox {
    struct MainStorage {
        /// @notice A mapping from the keccak256 hash of a `CrossChainRequest` to its `FulfillmentInfo`. This can only be set once per call
        mapping(bytes32 requestHash => FulfillmentInfo) fulfillmentInfo;
    }

    /// @notice Stored on verifyingContract and proved against in originationContract
    struct FulfillmentInfo {
        /// @dev Block timestamp when fulfilled
        uint96 timestamp;
        /// @dev Msg.sender of fulfillment call
        address filler;
    }

    // Main storage location used as the base for the fulfillmentInfo mapping following EIP-7201. (keccak256("RIP-7755"))
    bytes32 private constant _MAIN_STORAGE_LOCATION = 0x43f1016e17bdb0194ec37b77cf476d255de00011d02616ab831d2e2ce63d9ee2;

    /// @notice Event emitted when a cross chain call is fulfilled
    /// @param requestHash The keccak256 hash of a `CrossChainRequest`
    /// @param fulfilledBy The account that fulfilled the cross chain call
    event CallFulfilled(bytes32 indexed requestHash, address indexed fulfilledBy);

    /// @notice This error is thrown when an account submits a cross chain call with a `destinationChainId` different than the blockchain chain ID that this is deployed to
    error InvalidChainId();

    /// @notice This error is thrown when an account submits a cross chain call with an `inboxContract` different than this contract's address
    error InvalidInboxContract();

    /// @notice This error is thrown when an account attempts to submit a cross chain call that has already been fulfilled
    error CallAlreadyFulfilled();

    /// @notice This error is thrown when the first element in the `extraData` array is less than 20 bytes
    error InvalidPrecheckData();

    /// @notice A fulfillment entrypoint for RIP7755 cross chain calls.
    ///
    /// @param request A cross chain call request formatted following the RIP-7755 spec. See {RIP7755Structs-CrossChainRequest}.
    /// @param fulfiller The address that the fulfiller expects to use to claim their reward on the source chain.
    function fulfill(CrossChainRequest calldata request, address fulfiller) external payable {
        if (block.chainid != request.destinationChainId) {
            revert InvalidChainId();
        }

        if (address(this) != request.inboxContract) {
            revert InvalidInboxContract();
        }

        // Run precheck - call expected to revert if precheck condition(s) not met.
        _runPrecheck(request);

        bytes32 requestHash = hashRequest(request);

        if (_getFulfillmentInfo(requestHash).timestamp != 0) {
            revert CallAlreadyFulfilled();
        }

        // Store fulfillment info (execution receipt)
        _setFulfillmentInfo(requestHash, FulfillmentInfo({timestamp: uint96(block.timestamp), filler: fulfiller}));

        _sendCallsAndValidateMsgValue(request);

        emit CallFulfilled({requestHash: requestHash, fulfilledBy: fulfiller});
    }

    /// @notice Runs the precheck for a cross chain call.
    ///
    /// @dev The first element in the `extraData` array is reserved for precheck validation.
    /// @dev The precheck step is optional. It will be skipped if the `extraData` array is empty or if the first 20 bytes of the first element are the zero address.
    function _runPrecheck(CrossChainRequest calldata request) private {
        if (request.extraData.length == 0) return;

        bytes calldata precheckData = request.extraData[0];

        if (precheckData.length < 20) {
            revert InvalidPrecheckData();
        }

        address precheckContract = address(bytes20(precheckData[0:20]));

        if (precheckContract != address(0)) {
            IPrecheckContract(precheckContract).precheckCall(request, msg.sender);
        }
    }

    /// @dev Iterates through request.calls and makes each low level call.
    /// @dev Reverts if the total value sent does not match the `msg.value` provided by the fulfiller.
    function _sendCallsAndValidateMsgValue(CrossChainRequest calldata request) private {}

    function _getMainStorage() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := _MAIN_STORAGE_LOCATION
        }
    }

    function _getFulfillmentInfo(bytes32 requestHash) private view returns (FulfillmentInfo memory) {
        MainStorage storage $ = _getMainStorage();
        return $.fulfillmentInfo[requestHash];
    }

    function _setFulfillmentInfo(bytes32 requestHash, FulfillmentInfo memory fulfillmentInfo) private {
        MainStorage storage $ = _getMainStorage();
        $.fulfillmentInfo[requestHash] = fulfillmentInfo;
    }
}
```
