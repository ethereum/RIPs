---
rip: 7755
title: Cross-L2-Call
description: Contract standard for cross-L2 calls facilitation
author: Wilson Cusack (@WilsonCusack), Jack Chuma (@jackchuma)
discussions-to: https://ethereum-magicians.org/t/rip-contract-standard-for-cross-l2-calls-facilitation
status: Draft
type: Standards Track
category: Core
created: 2024-08-11
---

## Abstract

Contracts for facilitating request, fulfillment, and fulfillment reward of cross-L2 calls.

## Motivation

Cross-chain actions are an increasingly important part of crypto user experience. Today, most solutions for Ethereum layer 2s (L2s) have one or more of the following drawbacks.

1. Reliance on privatized relayers with offchain access and incentives.
1. Reliance on protocols outside of Ethereum and its rollups.
1. High-level, intent-based systems that do not allow specifying exact calls to make.

Ethereum L2s, which all write state to a shared execution environment, are uniquely positioned to offer an alternative. Ethereum L2 users should have access to a public, decentralized utility for making cross L2 calls.

From any L2 chain, users should be able to request a call be made on any other L2 chain. Users should be able to guarantee a compensation for this call being made, and thus be able to control the likelihood this call will be made.

User should have full assurance that compensation will only be paid if the call was made. This assurance should depend ONLY on onchain information.

## Specification

To only rely on onchain information, we use

1. Layer 1 (L1), i.e. Ethereum Mainnet, blockhashes or beacon roots on the L2.
   - We take as an assumption that every Ethereum L2 should have a trusted L1 blockhash or state representation in the execution environment.
1. Ethereum L2 blockhashes or state roots on L1.
   - e.g. via an [L2 Output Oracle Contract](https://specs.optimism.io/glossary.html?#l2-output-oracle-contract)

Using these inputs, on any Ethereum L2, we can trustlessly verify [ERC-1186](https://eips.ethereum.org/EIPS/eip-1186) storage proofs of any other Ethereum L2.

Our contracts' job, then, is to represent call requests and fulfillment in storage on each chain.

### Structs

```solidity
/// @notice Low-level call specs representing the desired transaction on destination chain
struct Call {
    /// @dev The address to call
    address to;
    /// @dev The calldata to call with
    bytes data;
    /// @dev The native asset value of the call
    uint256 value;
}

/// @notice A cross chain call request formatted following the RIP-7755 spec
struct CrossChainRequest {
    /// @dev The account submitting the cross chain request
    address requester;
    /// @dev Array of calls to make on the destination chain
    Call[] calls;
    /// @dev The chainId of the destination chain
    uint256 destinationChainId;
    /// @dev The L2 contract on destination chain that's storage will be used to verify whether or not this call was made
    address inboxContract;
    /// @dev The L1 address of the contract that should have L2 block info stored
    address l2Oracle;
    /// @dev The storage key at which we expect to find the L2 block info on the l2Oracle
    bytes32 l2OracleStorageKey;
    /// @dev The address of the ERC20 reward asset to be paid to whoever proves they filled this call
    /// @dev Native asset specified as in ERC-7528 format
    address rewardAsset;
    /// @dev The reward amount to pay
    uint256 rewardAmount;
    /// @dev The minimum age of the L1 block used for the proof
    uint256 finalityDelaySeconds;
    /// @dev The nonce of this call, to differentiate from other calls with the same values
    uint256 nonce;
    /// @dev The timestamp at which this request will expire
    uint256 expiry;
    /// @dev Extra data to be included in the proof - this is extra data to be used for prechecks and special validation cases
    /// @dev The first element in the `extraData` array is reserved for the precheck
    /// @dev If no precheck is desired, set to an empty array. If no precheck is desired but other data is needed, set the first element in the array to the zero address
    bytes[] extraData;
}

/// @notice Execution receipt stored on Inbox contract and proved against in Outbox contract
struct FulfillmentInfo {
    /// @dev Block timestamp when fulfilled
    uint96 timestamp;
    /// @dev Msg.sender of fulfillment call
    address filler;
}
```

### Flow Diagrams

#### Happy Case

![image](../assets/rip-7755/happy_case.png "Happy case flow")

1. User calls to an `RIP7755Outbox` contract with `CrossChainRequest` and reward funds
1. `RIP7755Outbox` emits event for fulfillers to discover
1. Fulfiller relays `CrossChainRequest` to `RIP7755Inbox` contract, including any funds possibly needed to successfully complete the call
1. If included, `RIP7755Inbox` makes a precheck call to validate fulfillment condition(s)
1. `RIP7755Inbox` makes the call as specified by `CrossChainRequest`
1. `RIP7755Inbox` write to storage the `FulfillmentInfo` receipt of the call
1. After `CrossChainRequest.finalityDelaySeconds` have elapsed, the fulfiller can submit the proof
1. If the proof is valid and the call was successfully made, fulfiller is paid reward

### RIP7755Outbox Contract

On the origin chain, there is an outbox contract to receive cross-chain call requests and payout rewards on proof of their fulfillment.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

import {RIP7755Inbox} from "./RIP7755Inbox.sol";
import {CrossChainRequest} from "./RIP7755Structs.sol";

/// @notice A source contract for initiating RIP-7755 Cross Chain Requests as well as reward fulfillment to fulfillers that
/// submit the cross chain calls to destination chains.
abstract contract RIP7755Outbox {
    using Address for address payable;
    using SafeERC20 for IERC20;

    /// @notice An enum representing the status of an RIP-7755 cross chain call
    enum CrossChainCallStatus {
        None,
        Requested,
        Canceled,
        Completed
    }

    /// @notice A mapping from the keccak256 hash of a `CrossChainRequest` to its current status
    mapping(bytes32 requestHash => CrossChainCallStatus status) private _requestStatus;

    /// @notice The address representing the native currency of the blockchain this contract is deployed on following ERC-7528
    address private constant _NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // Main storage location in `RIP7755Inbox` used as the base for the fulfillmentInfo mapping following EIP-7201. (keccak256("RIP-7755"))
    bytes32 private constant _VERIFIER_STORAGE_LOCATION =
        0x43f1016e17bdb0194ec37b77cf476d255de00011d02616ab831d2e2ce63d9ee2;

    /// @notice The duration, in excess of CrossChainRequest.expiry, which must pass before a request can be canceled
    uint256 public constant CANCEL_DELAY_SECONDS = 1 days;

    /// @notice An incrementing nonce value to ensure no two `CrossChainRequest` can be exactly the same
    uint256 private _nonce;

    /// @notice Event emitted when a user requests a cross chain call to be made by a fulfiller
    /// @param requestHash The keccak256 hash of a `CrossChainRequest`
    /// @param request The requested cross chain call
    event CrossChainCallRequested(bytes32 indexed requestHash, CrossChainRequest request);

    /// @notice Event emitted when an expired cross chain call request is canceled
    /// @param requestHash The keccak256 hash of a `CrossChainRequest`
    event CrossChainCallCanceled(bytes32 indexed requestHash);

    /// @notice This error is thrown when a cross chain request specifies the native currency as the reward type but
    /// does not send the correct `msg.value`
    /// @param expected The expected `msg.value` that should have been sent with the transaction
    /// @param received The actual `msg.value` that was sent with the transaction
    error InvalidValue(uint256 expected, uint256 received);

    /// @notice This error is thrown if a user attempts to cancel a request or a fulfiller attempts to claim a reward for
    /// a request that is not in the `CrossChainCallStatus.Requested` state
    /// @param expected The expected status during the transaction
    /// @param actual The actual request status during the transaction
    error InvalidStatus(CrossChainCallStatus expected, CrossChainCallStatus actual);

    /// @notice This error is thrown if an attempt to cancel a request is made before the request's expiry timestamp
    /// @param currentTimestamp The current block timestamp
    /// @param expiry The timestamp at which the request expires
    error CannotCancelRequestBeforeExpiry(uint256 currentTimestamp, uint256 expiry);

    /// @notice This error is thrown if an account attempts to cancel a request that did not originate from that account
    /// @param caller The account attempting the request cancellation
    /// @param expectedCaller The account that created the request
    error InvalidCaller(address caller, address expectedCaller);

    /// @notice This error is thrown if a request expiry does not give enough time for `CrossChainRequest.finalityDelaySeconds` to pass
    error ExpiryTooSoon();

    /// @notice This error is thrown if the prover contract fails to validate the storage proof for a cross chain call
    /// being submitted to `RIP7755Inbox`
    error ProofValidationFailed();

    /// @notice Submits an RIP-7755 request for a cross chain call
    ///
    /// @param request A cross chain request structured as a `CrossChainRequest`
    function requestCrossChainCall(CrossChainRequest memory request) external payable {
        request.nonce = _getNextNonce();
        request.requester = msg.sender;
        bool usingNativeCurrency = request.rewardAsset == _NATIVE_ASSET;
        uint256 expectedValue = usingNativeCurrency ? request.rewardAmount : 0;

        if (msg.value != expectedValue) {
            revert InvalidValue(expectedValue, msg.value);
        }
        if (request.expiry < block.timestamp + request.finalityDelaySeconds) {
            revert ExpiryTooSoon();
        }

        bytes32 requestHash = hashRequestMemory(request);
        _requestStatus[requestHash] = CrossChainCallStatus.Requested;

        if (!usingNativeCurrency) {
            _pullERC20({owner: msg.sender, asset: request.rewardAsset, amount: request.rewardAmount});
        }

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
        bytes32 requestHash = hashRequest(request);

        _checkValidStatus({requestHash: requestHash, expectedStatus: CrossChainCallStatus.Requested});
        if (msg.sender != request.requester) {
            revert InvalidCaller({caller: msg.sender, expectedCaller: request.requester});
        }
        if (block.timestamp < request.expiry + CANCEL_DELAY_SECONDS) {
            revert CannotCancelRequestBeforeExpiry({
                currentTimestamp: block.timestamp,
                expiry: request.expiry + CANCEL_DELAY_SECONDS
            });
        }

        _requestStatus[requestHash] = CrossChainCallStatus.Canceled;

        // Return the stored reward back to the original requester
        _sendReward(request, request.requester);

        emit CrossChainCallCanceled(requestHash);
    }

    /// @notice Returns the cross chain call request status for a hashed request
    ///
    /// @param requestHash The keccak256 hash of a `CrossChainRequest`
    ///
    /// @return _ The `CrossChainCallStatus` status for the associated cross chain call request
    function getRequestStatus(bytes32 requestHash) external view returns (CrossChainCallStatus) {
        return _requestStatus[requestHash];
    }

    /// @notice Hashes a `CrossChainRequest` request to use as a request identifier
    ///
    /// @param request A cross chain request structured as a `CrossChainRequest`
    ///
    /// @return _ A keccak256 hash of the `CrossChainRequest`
    function hashRequest(CrossChainRequest calldata request) public pure returns (bytes32) {
        return keccak256(abi.encode(request));
    }

    /// @notice Hashes a `CrossChainRequest` request to use as a request identifier
    ///
    /// @param request A cross chain request structured as a `CrossChainRequest`
    ///
    /// @return _ A keccak256 hash of the `CrossChainRequest`
    function hashRequestMemory(CrossChainRequest memory request) public pure returns (bytes32) {
        return keccak256(abi.encode(request));
    }

    /// @notice Pulls `amount` of `asset` from `owner` to address(this)
    function _pullERC20(address owner, address asset, uint256 amount) private {
        IERC20(asset).safeTransferFrom(owner, address(this), amount);
    }

    /// @notice Sends `amount` of `asset` to `to`
    function _sendERC20(address to, address asset, uint256 amount) private {
        IERC20(asset).safeTransfer(to, amount);
    }

    function _getNextNonce() private returns (uint256) {
        unchecked {
            // It would take ~3,671,743,063,080,802,746,815,416,825,491,118,336,290,905,145,409,708,398,004 years
            // with a sustained request rate of 1 trillion requests per second to overflow the nonce counter
            return ++_nonce;
        }
    }

    function _checkValidStatus(bytes32 requestHash, CrossChainCallStatus expectedStatus) private view {
        CrossChainCallStatus status = _requestStatus[requestHash];

        if (status != expectedStatus) {
            revert InvalidStatus({expected: expectedStatus, actual: status});
        }
    }

    function _sendReward(CrossChainRequest calldata request, address to) private {
        if (request.rewardAsset == _NATIVE_ASSET) {
            payable(to).sendValue(request.rewardAmount);
        } else {
            _sendERC20(to, request.rewardAsset, request.rewardAmount);
        }
    }

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

    /// @notice Decodes the `FulfillmentInfo` struct from the `RIP7755Inbox` storage slot
    ///
    /// @param inboxContractStorageValue The storage value of the `RIP7755Inbox` storage slot
    ///
    /// @return fulfillmentInfo The decoded `FulfillmentInfo` struct
    function _decodeFulfillmentInfo(bytes32 inboxContractStorageValue)
        internal
        pure
        returns (RIP7755Inbox.FulfillmentInfo memory)
    {
        RIP7755Inbox.FulfillmentInfo memory fulfillmentInfo;
        fulfillmentInfo.filler = address(uint160((uint256(inboxContractStorageValue) >> 96) & type(uint160).max));
        fulfillmentInfo.timestamp = uint96(uint256(inboxContractStorageValue));
        return fulfillmentInfo;
    }
}
```

### RIP7755Inbox Contract

On the destination chain, there is an inbox contract to store a receipt of the call fulfillment.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

import {IPrecheckContract} from "./interfaces/IPrecheckContract.sol";
import {CrossChainRequest} from "./RIP7755Structs.sol";

/// @notice An inbox contract within RIP-7755. This contract's sole purpose is to route requested transactions on
/// destination chains and store record of their fulfillment.
contract RIP7755Inbox {
    using Address for address;
    using Address for address payable;

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

    /// @notice This error is thrown if a fulfiller submits a `msg.value` greater than the total value needed for all the calls
    /// @param expected The total value needed for all the calls
    /// @param actual The received `msg.value`
    error InvalidValue(uint256 expected, uint256 actual);

    /// @notice This error is thrown when the first element in the `extraData` array is less than 20 bytes
    error InvalidPrecheckData();

    /// @notice Returns the stored fulfillment info for a passed in call hash
    ///
    /// @param requestHash A keccak256 hash of a CrossChainRequest
    ///
    /// @return _ Fulfillment info stored for the call hash
    function getFulfillmentInfo(bytes32 requestHash) external view returns (FulfillmentInfo memory) {
        return _getFulfillmentInfo(requestHash);
    }

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

        _setFulfillmentInfo(requestHash, FulfillmentInfo({timestamp: uint96(block.timestamp), filler: fulfiller}));

        _sendCallsAndValidateMsgValue(request);

        emit CallFulfilled({requestHash: requestHash, fulfilledBy: fulfiller});
    }

    /// @notice Hashes a cross chain call request.
    ///
    /// @param request A cross chain call request formatted following the RIP-7755 spec. See {RIP7755Structs-CrossChainRequest}.
    ///
    /// @return _ A keccak256 hash of the cross chain call request.
    function hashRequest(CrossChainRequest calldata request) public pure returns (bytes32) {
        return keccak256(abi.encode(request));
    }

    /// @notice Runs the precheck for a cross chain call.
    ///
    /// @dev The first element in the `extraData` array is reserved for precheck validation.
    /// @dev The precheck step is optional. It will be skipped if the `extraData` array is empty or if the first 20 bytes of the first element are the zero address.
    ///
    /// @param request A cross chain call request formatted following the RIP-7755 spec. See {RIP7755Structs-CrossChainRequest}.
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

    function _sendCallsAndValidateMsgValue(CrossChainRequest calldata request) private {
        uint256 valueSent;

        for (uint256 i; i < request.calls.length; i++) {
            _call(payable(request.calls[i].to), request.calls[i].data, request.calls[i].value);

            unchecked {
                valueSent += request.calls[i].value;
            }
        }

        if (valueSent != msg.value) {
            revert InvalidValue(valueSent, msg.value);
        }
    }

    function _call(address payable to, bytes calldata data, uint256 value) private {
        if (data.length == 0) {
            to.sendValue(value);
        } else {
            to.functionCallWithValue(data, value);
        }
    }

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

### PrecheckContract Interface

On the destination chain, any valid precheck contract must adhere to the following interface.

```solidity
interface IPrecheckContract {
    /// @notice A precheck function declaration.
    ///
    /// @param request A cross chain call request formatted following the RIP-7755 spec. See {RIP7755Structs-CrossChainRequest}.
    /// @param caller The address of the fulfiller account that submitted the transaction to RIP7755Inbox.
    function precheckCall(CrossChainRequest calldata request, address caller) external;
}
```

### Storage Proof Validation

The implementation details for successful storage proof validation will vary depending on the destination chain. However, all implementations will adhere to the following fundamental pattern:

1. Verify that the beacon root used for the proof corresponds to the root exposed in the source chain's execution environment.
1. Validate the L1 execution client's state root against the beacon root.
1. Validate the destination chain's output contract storage root against the L1 execution client's state root.
1. Validate the destination chain's state root against the destination chain's output contract storage root.
1. Validate the destination chain's inbox contract storage root against the destination chain's state root.
1. Validate the `FulfillmentInfo` struct at the correct storage key against the destination chain's inbox contract storage root.

It is important to note that not all L2 chains directly store their state root on L1. In certain cases, the L2 chain stores an abstract "output root" which must be connected to its state root in some manner. In these instances, the storage proof validation necessitates an intermediate step between steps 4 and 5. This step involves providing the destination chain's state root along with custom logic to derive the output root using that state root and any other required information. This step is only considered successful if the derived output root matches the value proven to be stored in the destination chain's output contract on L1.

## Example Usage

_These examples are not intended to be comprehensive of every detail. First example is more verbose, in hopes of giving helpful understanding for all examples._

### Transfer native asset across chains.

**User at Address A on Chain X wants to send 0.1 ether to Address B on Chain Y.**

On Chain X, Address A calls `requestCrossChainCall` on a `RIP7755Outbox` contract of their choosing. `CrossChainRequest.calls` contains a single call.

```solidity
Call({
  to: <Address B>,
  value: 0.1 ether,
  data: ""
})
```

The `CrossChainRequest` includes info about the destination chain and `RIP7755Inbox` contract the user wants the call to be made through.

The destination chain has a 7 day challenge period, and so the user sets `CrossChainRequest.finalityDelaySeconds` to a 7 day equivalent for maximum security.

When calling to `requestCrossChainCall` on origin chain, the user sends 0.1001 ether in value, which matches `CrossChainRequest.rewardAmount`. The excess above 0.1 ether is intended to exceed the gas cost of the call on destination chain and serve as a compensation to the fulfiller. This reward amount would need to provide sufficient incentive for the fulfiller to wait `CrossChainRequest.finalityDelaySeconds`, in this case 7 days, to get their reward.

**Include custom exclusivity period for a specified fulfiller**

To enhance the previous example, we introduce a precheck condition where Address A authorizes only a specific fulfiller, referred to as Fulfiller A, to submit the transaction to the destination chain for a specified period of time.

To implement this, custom exclusivity logic must be incorporated into a precheck smart contract (PCSM) deployed on the destination chain. The `CrossChainRequest` will include the PCSM address concatenated with the encoded data for exclusivity validation in the `extraData` field.

```solidity
    CrossChainCall({
      ...
      extraData: abi.encodePacked(<PCSM address on destination chain>, abi.encode(<fulfiller address>, expirationTimestamp)),
      ...
    })
```

Once Address A invokes `requestCrossChainCall` on the origin chain, if an unintended fulfiller attempts to submit the transaction on the destination chain within the exclusivity period, the `fulfill` function call will revert due to the precheck failure. This ensures that only Fulfiller A can call `fulfill` before the `expirationTimestamp`.

### Transfer ERC20 asset across chains.

**User at Address A on Chain X wants to send 100 USDC to Address B on Chain Y.**

ERC20 transfers have unique challenges in our paradigm, because

<ol type="A">
  <li>The caller needs to specify the exact calls to make.</li>
  <li>The calls must be made through the inbox contract.</li>
</ol>

We show two example solutions below.

#### 1. With known fulfiller address

The following example requires the caller to know ahead of time the fulfillers address. This is not ideal because (1) the calls will only work for one fulfiller (2) requires offchain pre-coordination.

- Origin Chain:
  - Pre-steps:
    - Address A calls to USDC contract on origination chain to approve `RIP7755Outbox` to move 100 USDC.
  - Address A calls to outbox, with a two calls in `CrossChainRequest.calls`
    - ```solidity
        Call({
          to: <USDC contract on destination chain>,
          value: 0,
          data: abi.encodeWithSelector(ERC20.transferFrom.selector, <fulfiller address>, <RIP7755Inbox contract address>, 100 * (10 ** USDC.decimals()))
        })
      ```
    - ```solidity
        Call({
          to: <USDC contract on destination chain>,
          value: 0,
          data: abi.encodeWithSelector(ERC20.transfer.selector, <Address B>, 100 * (10 ** USDC.decimals()))
        })
      ```
- Destination Chain
  - Pre-steps
    - Fulfiller calls to USDC contract on destination chain to approve `RIP7755Inbox` to move 100 USDC.
  - Fulfiller calls `fulfill` on `RIP7755Inbox`
    - In the first call of `CrossChainRequest.calls`, 100 USDC is sent from fulfiller to `RIP7755Inbox`.
    - In second call, 100 USDC is sent from `RIP7755Inbox` to Address B.

#### 2. With helper contract

We could also solve the challenge by introducing a helper contract for facilitating the ERC20 transfer. This helper contract would accept calls in the format `transfer(address asset, address to, uint256 amount)` and then would use `tx.origin` to determine the `from` for the ERC20 `transferFrom` call (and check `msg.sender` is some known `RIP7755Inbox` contract). This would rely on fulfillers pre-depositing ERC20s in this helper contract, or having approvals set so it can pull funds at any time.

> [!NOTE]  
> In future drafts, we may specify an implementation of `HelperContract`. It may also be convenient for fulfillers to be able to auth with signature. This could maybe be accomplished via some `context` that could be passed to `fulfill` and stored in `RIP7755Inbox` for the duration of the call.

- Origin Chain:
  - Pre-steps:
    - Address A calls to USDC contract on origination chain to approve `RIP7755Outbox` to move 100 USDC.
  - Address A calls to outbox, with a one call in `CrossChainRequest.calls`
    - ```solidity
        Call({
          to: <USDC contract on destination chain>,
          value: 0,
          data: abi.encodeWithSelector(HelperContract.transfer.selector, CrossChainRequest.rewardAsset, <Address B>, 100 * (10 ** USDC.decimals()))
        })
      ```
- Destination Chain
  - Pre-steps
    - Fulfiller calls to USDC contract on destination chain to approve `HelperContract` to move 100 USDC.
  - Fulfiller calls `fulfill` on `RIP7755Inbox`
    - Call transfers 100 USDC to Address B via `HelperContract`.

### ERC20 swap on Chain B using assets from Chain A.

TODO

### Pay gas on Chain A for a smart account transaction on Chain B.

TODO

## Example \_validate implementation

### OP Stack

The following library is an example of how storage proof validation can be implemented for an OP Stack chain.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RLPReader} from "optimism/packages/contracts-bedrock/src/libraries/rlp/RLPReader.sol";

import {StateValidator} from "../StateValidator.sol";
import {RIP7755Inbox} from "../../RIP7755Inbox.sol";
import {RIP7755Outbox} from "../../RIP7755Outbox.sol";
import {CrossChainRequest} from "../../RIP7755Structs.sol";

/// @notice This is a utility library for validating OP Stack storage proofs.
library OPStackProver {
    using StateValidator for address;
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    /// @notice The address and storage keys to validate on L1 and L2
    struct Target {
        /// @dev The address of the L1 contract to validate. Should be Optimism's AnchorStateRegistry contract
        address l1Address;
        /// @dev The storage key on L1 to validate
        bytes32 l1StorageKey;
        /// @dev The address of the L2 contract to validate.
        address l2Address;
        /// @dev The storage key on L2 to validate.
        bytes32 l2StorageKey;
    }

    /// @notice Parameters needed for a full nested cross-L2 storage proof
    struct RIP7755Proof {
        /// @dev The storage root of Optimism's MessagePasser contract - used to compute our L1 storage value
        bytes32 l2MessagePasserStorageRoot;
        /// @dev The RLP-encoded array of block headers of the chain's L2 block used for the proof. Hashing this bytes string should produce the blockhash.
        bytes encodedBlockArray;
        /// @dev Parameters needed to validate the authenticity of Ethereum's execution client's state root
        StateValidator.StateProofParameters stateProofParams;
        /// @dev Parameters needed to validate the authenticity of the l2Oracle for the destination L2 chain on Eth
        /// mainnet
        StateValidator.AccountProofParameters dstL2StateRootProofParams;
        /// @dev Parameters needed to validate the authenticity of a specified storage location the destination L2 chain
        StateValidator.AccountProofParameters dstL2AccountProofParams;
    }

    /// @notice This error is thrown when verification of the authenticity of the l2Oracle for the destination L2 chain
    /// on Eth mainnet fails
    error InvalidL1Storage();

    /// @notice This error is thrown when verification of the authenticity of the `RIP7755Inbox` storage on the
    /// destination L2 chain fails
    error InvalidL2Storage();

    /// @notice This error is thrown when the supplied l2StateRoot does not correspond to our validated L1 state
    error InvalidL2StateRoot();

    /// @notice This error is thrown when the encoded block headers does not contain all 16 fields
    error InvalidBlockFieldRLP();

    /// @notice Validates storage proofs and verifies fulfillment
    ///
    /// @custom:reverts If storage proof invalid.
    /// @custom:reverts If fulfillmentInfo not found at inboxContractStorageKey on request.inboxContract
    /// @custom:reverts If fulfillmentInfo.timestamp is less than request.finalityDelaySeconds from current destination
    /// chain block timestamp.
    /// @custom:reverts If the L2StateRoot does not correspond to the validated L1 storage slot
    ///
    /// @dev Implementation will vary by L2
    ///
    /// @param proof The proof to validate
    /// @param target The proof target on L1 and dst L2
    ///
    /// @return l2Timestamp The timestamp of the validated L2 state root
    /// @return l2StorageValue The storage value of the `RIP7755Inbox` storage slot
    function validate(bytes calldata proof, Target memory target) internal view returns (uint256, bytes memory) {
        RIP7755Proof memory proofData = abi.decode(proof, (RIP7755Proof));

        // Set the expected storage key for the L1 storage slot
        proofData.dstL2StateRootProofParams.storageKey = abi.encode(target.l1StorageKey);
        // Set the expected storage key for the `RIP7755Inbox` storage slot
        proofData.dstL2AccountProofParams.storageKey = abi.encode(target.l2StorageKey);

        // We first need to validate knowledge of the destination L2 chain's state root.
        // StateValidator.validateState will accomplish each of the following 4 steps:
        //      1. Confirm beacon root
        //      2. Validate L1 state root
        //      3. Validate L1 account proof where `account` here is the destination chain's AnchorStateRegistry contract
        //      4. Validate storage proof proving destination L2 root stored in L1 AnchorStateRegistry contract
        bool validState =
            target.l1Address.validateState(proofData.stateProofParams, proofData.dstL2StateRootProofParams);

        if (!validState) {
            revert InvalidL1Storage();
        }

        // As an intermediate step, we need to prove that `proofData.dstL2StateRootProofParams.storageValue` is linked
        // to the correct l2StateRoot before we can prove l2Storage

        bytes32 version;
        // Extract the L2 stateRoot and timestamp from the RLP-encoded block array
        (bytes32 l2StateRoot, uint256 l2Timestamp) = _extractL2StateRootAndTimestamp(proofData.encodedBlockArray);
        // Derive the L2 blockhash
        bytes32 l2BlockHash = keccak256(proofData.encodedBlockArray);

        // Compute the expected destination chain output root (which is the value we just proved is in the L1 storage slot)
        bytes32 expectedOutputRoot =
            keccak256(abi.encodePacked(version, l2StateRoot, proofData.l2MessagePasserStorageRoot, l2BlockHash));
        // If this checks out, it means we know the correct l2StateRoot
        if (bytes32(proofData.dstL2StateRootProofParams.storageValue) != expectedOutputRoot) {
            revert InvalidL2StateRoot();
        }

        // Because the previous step confirmed L1 state, we do not need to repeat steps 1 and 2 again
        // We now just need to validate account storage on the destination L2 using StateValidator.validateAccountStorage
        // This library function will accomplish the following 2 steps:
        //      5. Validate L2 account proof where `account` here is `RIP7755Inbox` on destination chain
        //      6. Validate storage proof proving FulfillmentInfo in `RIP7755Inbox` storage
        bool validL2Storage = target.l2Address.validateAccountStorage(l2StateRoot, proofData.dstL2AccountProofParams);

        if (!validL2Storage) {
            revert InvalidL2Storage();
        }

        return (l2Timestamp, proofData.dstL2AccountProofParams.storageValue);
    }

    /// @notice Extracts the l2StateRoot and l2Timestamp from the RLP-encoded block headers array
    ///
    /// @custom:reverts If the encoded block array has less than 15 elements
    ///
    /// @dev The stateRoot should be the 4th element, and the timestamp should be the 12th element
    function _extractL2StateRootAndTimestamp(bytes memory encodedBlockArray) private pure returns (bytes32, uint256) {
        RLPReader.RLPItem[] memory blockFields = encodedBlockArray.readList();

        if (blockFields.length < 15) {
            revert InvalidBlockFieldRLP();
        }

        return (bytes32(blockFields[3].readBytes()), uint256(bytes32(blockFields[11].readBytes())));
    }
}
```

Where the `StateValidator` structs are defined as follows:

```solidity
/// @notice Parameters needed to validate the authenticity of Ethereum's execution client's state root
struct StateProofParameters {
    /// @dev The Beacon Chain root published to `BEACON_ROOTS_ORACLE` on this L2 chain
    bytes32 beaconRoot;
    /// @dev The timestamp associated with the provided Beacon Root
    uint256 beaconOracleTimestamp;
    /// @dev The state root of Ethereum's execution client
    bytes32 executionStateRoot;
    /// @dev A proof to verify the authenticity of `executionStateRoot`
    bytes32[] stateRootProof;
}

/// @notice Parameters needed to validate the authenticity of an EVM account's storage
struct AccountProofParameters {
    /// @dev The storage location to validate
    bytes storageKey;
    /// @dev The expected value at the specified storage location
    bytes storageValue;
    /// @dev A proof used to derive an account's storage root
    bytes[] accountProof;
    /// @dev A proof to validate the account's `storageValue` at `storageKey` location
    bytes[] storageProof;
}
```

This implementation example is designed with the assumption that the chain it is deployed on supports EIP-4788. It adheres to the general storage proof validation pattern previously outlined. The following lines highlight the specifics that are unique to the OP Stack:

```solidity
bytes32 version;
// Extract the L2 stateRoot and timestamp from the RLP-encoded block array
(bytes32 l2StateRoot, uint256 l2Timestamp) = _extractL2StateRootAndTimestamp(proofData.encodedBlockArray);
// Derive the L2 blockhash
bytes32 l2BlockHash = keccak256(proofData.encodedBlockArray);

// Compute the expected destination chain output root (which is the value we just proved is in the L1 storage slot)
bytes32 expectedOutputRoot =
    keccak256(abi.encodePacked(version, l2StateRoot, proofData.l2MessagePasserStorageRoot, l2BlockHash));
// If this checks out, it means we know the correct l2StateRoot
if (bytes32(proofData.dstL2StateRootProofParams.storageValue) != expectedOutputRoot) {
    revert InvalidL2StateRoot();
}
```

This example leverages Optimism's `AnchorStateRegistry` contract to utilize the most recent anchor state available at the time of proof. The anchor state represents the finalized state of the destination L2 chain. To verify the state root of the destination chain, we must provide the pre-image of the chain's anchor state output root. As of this writing, the pre-image consists of four `bytes32` values: `version`, `l2StateRoot`, `l2MessagePasserStorageRoot`, and `l2BlockHash`.

The `l2StateRoot` and `l2BlockHash` are extracted and derived from the RLP-encoded block headers array. Specifically, the `l2StateRoot` is the fourth element in this array, while the `l2BlockHash` is the hash of the entire RLP-encoded block headers array. With this information, we can compute the expected output root.

If the derived output root does not match the value stored in the L1 storage slot, the proof is deemed invalid.

### Arbitrum

The following library is an example of how storage proof validation can be implemented for Arbitrum.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RLPReader} from "optimism/packages/contracts-bedrock/src/libraries/rlp/RLPReader.sol";

import {StateValidator} from "../StateValidator.sol";
import {RIP7755Inbox} from "../../RIP7755Inbox.sol";
import {RIP7755Outbox} from "../../RIP7755Outbox.sol";
import {CrossChainRequest} from "../../RIP7755Structs.sol";

/// @notice This is a utility library for validating Arbitrum storage proofs.
library ArbitrumProver {
    using StateValidator for address;
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;

    /// @notice The address and storage keys to validate on L1 and L2
    struct Target {
        /// @dev The address of the L1 contract to validate. Should be Arbitrum's Rollup contract
        address l1Address;
        /// @dev The storage key on L1 to validate
        bytes32 l1StorageKey;
        /// @dev The address of the L2 contract to validate. Should be Arbitrum's `RIP7755Inbox` contract
        address l2Address;
        /// @dev The storage key on L2 to validate. Should be the `RIP7755Inbox` storage slot containing the
        /// `FulfillmentInfo` struct
        bytes32 l2StorageKey;
    }

    /// @notice Parameters needed for a full nested cross-L2 storage proof with Arbitrum as the destination chain
    struct RIP7755Proof {
        /// @dev The root hash of a Merkle tree that contains all the messages sent from Arbitrum to L1
        bytes sendRoot;
        /// @dev The index of Arbitrum's RBlock containing the state root to use in our storage proof
        uint64 nodeIndex;
        /// @dev The RLP-encoded array of block headers of Arbitrum's L2 block corresponding to the above RBlock. Hashing this bytes string should produce the blockhash.
        bytes encodedBlockArray;
        /// @dev Parameters needed to validate the authenticity of Ethereum's execution client's state root
        StateValidator.StateProofParameters stateProofParams;
        /// @dev Parameters needed to validate the authenticity of the l2Oracle for the destination L2 chain on Eth
        /// mainnet
        StateValidator.AccountProofParameters dstL2StateRootProofParams;
        /// @dev Parameters needed to validate the authenticity of a specified storage location in `RIP7755Inbox` on
        /// the destination L2 chain
        StateValidator.AccountProofParameters dstL2AccountProofParams;
    }

    /// @notice The storage slot offset of the `confirmData` field in an Arbitrum RBlock
    uint256 private constant _ARBITRUM_RBLOCK_CONFIRMDATA_STORAGE_OFFSET = 2;

    /// @notice This error is thrown when verification of the authenticity of the l2Oracle for the destination L2 chain
    /// on Eth mainnet fails
    error InvalidStateRoot();

    /// @notice This error is thrown when verification of the authenticity of the `RIP7755Inbox` storage on the
    /// destination L2 chain fails
    error InvalidL2Storage();

    /// @notice This error is thrown when the derived `confirmData` does not match the value in the validated L1 storage slot
    error InvalidConfirmData();

    /// @notice This error is thrown when the encoded block headers does not contain all 16 fields
    error InvalidBlockFieldRLP();

    /// @notice Validates storage proofs and verifies fulfillment
    ///
    /// @custom:reverts If storage proof invalid.
    /// @custom:reverts If fulfillmentInfo not found at verifyingContractStorageKey on request.verifyingContract
    /// @custom:reverts If fulfillmentInfo.timestamp is less than request.finalityDelaySeconds from current destination
    /// chain block timestamp.
    /// @custom:reverts If the L2StorageRoot does not correspond to our validated L1 storage slot
    ///
    /// @param proof The proof to validate
    /// @param target The proof target on L1 and dst L2
    ///
    /// @return l2Timestamp The timestamp of the validated L2 state root
    /// @return l2StorageValue The storage value of the `RIP7755Inbox` storage slot
    function validate(bytes calldata proof, Target memory target) internal view returns (uint256, bytes memory) {
        RIP7755Proof memory proofData = abi.decode(proof, (RIP7755Proof));

        // Set the expected storage key and value for the `RIP7755Inbox` on Arbitrum
        proofData.dstL2AccountProofParams.storageKey = abi.encode(target.l2StorageKey);

        // Derive the L1 storage key to use in the storage proof. For Arbitrum, we will use the storage slot containing
        // the `confirmData` field in a posted RBlock
        proofData.dstL2StateRootProofParams.storageKey = _deriveL1StorageKey(proofData, target.l1StorageKey);

        // We first need to validate knowledge of the destination L2 chain's state root.
        // StateValidator.validateState will accomplish each of the following 4 steps:
        //      1. Confirm beacon root
        //      2. Validate L1 state root
        //      3. Validate L1 account proof where `account` here is Arbitrum's Rollup contract
        //      4. Validate storage proof proving destination L2 root stored in Rollup contract
        bool validState =
            target.l1Address.validateState(proofData.stateProofParams, proofData.dstL2StateRootProofParams);

        if (!validState) {
            revert InvalidStateRoot();
        }

        // As an intermediate step, we need to prove that `proofData.dstL2StateRootProofParams.storageValue` is linked
        // to the correct l2StateRoot before we can prove l2Storage

        // Derive the L2 blockhash
        bytes32 l2BlockHash = keccak256(proofData.encodedBlockArray);
        // Derive the RBlock's `confirmData` field
        bytes32 confirmData = keccak256(abi.encodePacked(l2BlockHash, proofData.sendRoot));
        // Extract the L2 stateRoot and timestamp from the RLP-encoded block array
        (bytes32 l2StateRoot, uint256 l2Timestamp) = _extractL2StateRootAndTimestamp(proofData.encodedBlockArray);

        // The L1 storage value we proved was the node's confirmData
        if (bytes32(proofData.dstL2StateRootProofParams.storageValue) != confirmData) {
            revert InvalidConfirmData();
        }

        // Because the previous step confirmed L1 state, we do not need to repeat steps 1 and 2 again
        // We now just need to validate account storage on the destination L2 using StateValidator.validateAccountStorage
        // This library function will accomplish the following 2 steps:
        //      5. Validate L2 account proof where `account` here is `RIP7755Inbox` on destination chain
        //      6. Validate storage proof proving FulfillmentInfo in `RIP7755Inbox` storage
        bool validL2Storage = target.l2Address.validateAccountStorage(l2StateRoot, proofData.dstL2AccountProofParams);

        if (!validL2Storage) {
            revert InvalidL2Storage();
        }

        return (l2Timestamp, proofData.dstL2AccountProofParams.storageValue);
    }

    /// @notice Derives the L1 storageKey using the supplied `nodeIndex` and the `confirmData` storage slot offset
    function _deriveL1StorageKey(RIP7755Proof memory proofData, bytes32 l1StorageKey)
        private
        pure
        returns (bytes memory)
    {
        uint256 startingStorageSlot = uint256(keccak256(abi.encode(proofData.nodeIndex, l1StorageKey)));
        return abi.encodePacked(startingStorageSlot + _ARBITRUM_RBLOCK_CONFIRMDATA_STORAGE_OFFSET);
    }

    /// @notice Extracts the l2StateRoot and l2Timestamp from the RLP-encoded block headers array
    ///
    /// @custom:reverts If the encoded block array has less than 15 elements
    ///
    /// @dev The stateRoot should be the 4th element, and the timestamp should be the 12th element
    function _extractL2StateRootAndTimestamp(bytes memory encodedBlockArray) private pure returns (bytes32, uint256) {
        RLPReader.RLPItem[] memory blockFields = encodedBlockArray.readList();

        if (blockFields.length < 15) {
            revert InvalidBlockFieldRLP();
        }

        return (bytes32(blockFields[3].readBytes()), uint256(bytes32(blockFields[11].readBytes())));
    }
}
```

The process of verifying this proof is similar to the OP Stack example, but with specific nuances for Arbitrum. Below are the lines of code that are tailored for Arbitrum's unique architecture:

```solidity
// Derive the L2 blockhash
bytes32 l2BlockHash = keccak256(proofData.encodedBlockArray);
// Derive the RBlock's `confirmData` field
bytes32 confirmData = keccak256(abi.encodePacked(l2BlockHash, proofData.sendRoot));
// Extract the L2 stateRoot and timestamp from the RLP-encoded block array
(bytes32 l2StateRoot, uint256 l2Timestamp) = _extractL2StateRootAndTimestamp(proofData.encodedBlockArray);

// The L1 storage value we proved was the node's confirmData
if (bytes32(proofData.dstL2StateRootProofParams.storageValue) != confirmData) {
    revert InvalidConfirmData();
}
```

This step is crucial for verifying the authenticity of the destination L2 chain's state root. In Arbitrum, the `confirmData` field within an RBlock is utilized as the L1 storage value that we have proven. Similar to the OP Stack example, we must derive the expected storage value on L1 using the state root. Specifically, this is achieved by hashing the `l2BlockHash` together with the `sendRoot` found in the proof data structure. Given that the L2 state root is included in the pre-image of the block hash, a match between the derived value and the verified storage value confirms the authenticity of the state root.
