---
rip: xxxx
title: Store L1 origin execution block hashes and historic L2 block hashes in L2 state
description: Standardize the commitment of L1 origin block hashes and historic L2 block hashes in L2 state
author: Ian Norden (@i-norden), Bo Du (@notbdu)
discussions-to: 
status: Draft
type: Standards Track
category: Core
created: 2025-01-06
requires: 
---

## Abstract

In every L2 block store the block hash for the L1 block that the L2 block derives inputs from in a ring buffer inside
a pre-deployed smart contract. This ring buffer will hold the last `L1_ORIGIN_BUFFER_LENGTH` number of origin hashes and
will be referred to as the **L1 origin storage contract**.

Additionally, in every L2 block store the last `L2_HISTORY_BUFFER_LENGTH` historical L2 block hashes in a ring buffer inside
a pre-deployed smart contract. This contract will be referred to as the **L2 history storage contract**.

## Motivation

This RIP is the combination of [EIP-2935](https://eips.ethereum.org/EIPS/eip-2935) unmodified and
[EIP-4788](https://eips.ethereum.org/EIPS/eip-4788) with minor modification to store L1 execution block hashes
instead of beacon block roots.

In combination these two improvements enable L2s that settle and derive from Ethereum to verify arbitrary claims about
Ethereum and all the other L2s that settle to Ethereum.

### L1 origin storage contract

Maintaining inside the L2 execution environment a view of the L1 state that a given L2 block derives from is broadly
useful for L1<->L2 and L2<->L2 interoperability and composability. Some specific examples of where this is useful include:
[RIP-7755](https://ethereum-magicians.org/t/rip-7755-contract-standard-for-cross-l2-calls-facilitation/20776),
[RIP-7789](https://ethereum-magicians.org/t/rip-7789-cross-rollup-contingent-transactions/21402),
[RIP-7728](https://ethereum-magicians.org/t/rip-7728-l1sload-precompile/20388),
[ERC-3668](https://eips.ethereum.org/EIPS/eip-3668), and verifying AVS validator set state on the L1 for purposes of
EigenDA or Lagrange state committees or other AVS protocols. In general, it is useful to any contract on the L2 that
needs to verify arbitrary L1 state, storage, transaction, or receipt data inside the L2.

### L2 history storage contract

Maintaining inside the L2 execution environment historic L2 block hashes is useful for the stated side-benefit provided
as motivation for EIP-2935:

"A side benefit of this approach could be that it allows building/validating proofs related to last `L2_HISTORY_BUFFER_LENGTH`
ancestors directly against the current state."

The value provided by this capability is increased in the context of L2s as most L2s only submit L2 outputs to the L1 at
sparse intervals. If the `L2_HISTORY_BUFFER_LENGTH` is long enough to span the L2 outputs on the L1 then it is made possible
for any contract on the L1 to verify arbitrary L2 state, storage, transaction, or receipt data at any L2
height using the historical L2 block hashes stored in the L2 history storage contract of an L2 output.

## Specification

Specification mirrors the specifications of EIP-2935 and EIP-4788 with modification of EIP-4788 such that the ring
buffer stores L1 execution block hashes instead of beacon block roots. 

Some L2s already support EIP-4788 so to avoid a conflict we must select a different address for the pre-deployed
contract `L1_ORIGIN_STORAGE_ADDRESS`.

If an L2 already supports EIP-2935 no modification to that contract is needed to support the L2 history storage
contract. To fulfill this RIP's specification they only need to add support for the **L1 origin storage contract**.

### L1 origin storage contract

| Name                      | Value                                      |
|---------------------------|--------------------------------------------|
| L1_ORIGIN_BUFFER_LENGTH   | 8192                                       |
| L1_ORIGIN_SYSTEM_ADDRESS  | 0xfffffffffffffffffffffffffffffffffffffffe |
| L1_ORIGIN_STORAGE_ADDRESS | tbd                                        |
| L1_ORIGIN_FORK_TIMESTAMP  | variable - defined by the L2               |

The **L1 origin storage contract** has two operations: `get` and `set`. The input itself is not used to determine which function to execute, for that the result of `caller` is used. If `caller` is equal to `SYSTEM_ADDRESS` then the operation to perform is `set`. Otherwise, `get`.

##### `get`

* Callers provide the `timestamp` they are querying encoded as 32 bytes in big-endian format.
* If the input is not exactly 32 bytes, the contract must revert.
* If the input is equal to 0, the contract must revert.
* Given `timestamp`, the contract computes the storage index in which the timestamp is stored by computing the modulo `timestamp % L1_ORIGIN_BUFFER_LENGTH` and reads the value.
* If the `timestamp` does not match, the contract must revert.
* Finally, the L1 execution block hash associated with the timestamp is returned to the user. It is stored at `timestamp % L1_ORIGIN_BUFFER_LENGTH + L1_ORIGIN_BUFFER_LENGTH`.

##### `set`

* Caller (the sequencer) provides the L1 origin block hash as calldata to the contract.
* Set the storage value at `header.timestamp % L1_ORIGIN_BUFFER_LENGTH` to be `header.timestamp`
* Set the storage value at `header.timestamp % L1_ORIGIN_BUFFER_LENGTH + L1_ORIGIN_BUFFER_LENGTH` to be `calldata[0:32]`

##### Bytecode

The exact contract bytecode is shared below.

```asm
caller
push20 0xfffffffffffffffffffffffffffffffffffffffe
eq
push1 0x4d
jumpi

push1 0x20
calldatasize
eq
push1 0x24
jumpi

push0
push0
revert

jumpdest
push0
calldataload
dup1
iszero
push1 0x49
jumpi

push3 0x001fff
dup2
mod
swap1
dup2
sload
eq
push1 0x3c
jumpi

push0
push0
revert

jumpdest
push3 0x001fff
add
sload
push0
mstore
push1 0x20
push0
return

jumpdest
push0
push0
revert

jumpdest
push3 0x001fff
timestamp
mod
timestamp
dup2
sstore
push0
calldataload
swap1
push3 0x001fff
add
sstore
stop
```

#### Deployment

The **L1 origin storage contract** can be deployed as a [predeployed contract](https://github.com/ethereum-optimism/specs/blob/main/specs/protocol/predeploys.md).

### Block processing

At the top of every L2 block where `block.timestamp >= L1_ORIGIN_FORK_TIMESTAMP` the sequencer will call
`L1_ORIGIN_STORAGE_ADDRESS` as `L1_ORIGIN_SYSTEM_ADDRESS` with the 32-byte input of `l1origin.block.hash`,
a gas limit of `30_000_000`, and `0` value. This will trigger the `set()` routine of the beacon roots contract.
This is a system operation and therefore:

* the call must execute to completion
* the call does not count against the block's gas limit
* the call does not follow the [EIP-1559](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1559.md) burn
semantics - no value should be transferred as part of the call
* if no code exists at `L1_ORIGIN_STORAGE_ADDRESS`, the call must fail silently

If this EIP is active in a genesis block, no system transaction may occur.

`l1origin` is defined as the L1 block from which inputs were taken, _or would have been had inputs existed in that
L1 block_, in order to derive the nascent L2 block. If an L2 block is built without L1 inputs but the L2 maintains a
mapping of L2->L1 blocks based on timestamps then the L1 origin is the L1 block that satisfies this mapping.

The invariants are
1. Every L2 block has an L1 origin
2. For an L2 block N with timestamp/height greater than L2 block M the L1 origin of N must have a height/timestamp greater than the L1 origin of M or share the same L1 origin


### L2 history storage contract

| Name                       | Value                                      |
|----------------------------|--------------------------------------------|
| L2_HISTORY_BUFFER_LENGTH   | 8192                                       |
| L2_HISTORY_SYSTEM_ADDRESS  | 0xfffffffffffffffffffffffffffffffffffffffe |
| L2_HISTORY_STORAGE_ADDRESS | tbd                                        |
| L2_HISTORY_FORK_TIMESTAMP  | variable - defined by the L2               |

Note: an L2 could perform this upgrade incrementally such that `L1_ORIGIN_FORK_TIMESTAMP` != `L2_HISTORY_FORK_TIMESTAMP`

The history contract has two operations: `get` and `set`. The `set` operation is invoked only when the `caller` is equal to the `L2_HISTORY_SYSTEM_ADDRESS`. Otherwise, the `get` operation is performed.

#### `get`

It is used from the EVM for looking up block hashes.

* Callers provide the block number they are querying in a big-endian encoding.
* If calldata is bigger than 2^64-1, revert.
* For any output outside the range of [block.number-`L2_HISTORY_BUFFER_LENGTH`, block.number-1] return 0.

#### `set`

* Caller provides `block.parent.hash` as calldata to the contract.
* Set the storage value at `block.number-1 % L2_HISTORY_BUFFER_LENGTH` to be `calldata[0:32]`.

#### Bytecode

The exact contract bytecode is shared below.

```asm
// if system call then jump to the set operation
caller
push20 0xfffffffffffffffffffffffffffffffffffffffe
eq
push1 0x57
jumpi

// check if input > 8 byte value and revert if this isn't the case
// the check is performed by comparing the biggest 8 byte number with
// the call data, which is a right-padded 32 byte number.
push8 0xffffffffffffffff
push0
calldataload
gt
push1 0x53
jumpi

// check if input > blocknumber-1 then return 0
push1 0x1
number
sub
push0
calldataload
gt
push1 0x4b
jumpi

// check if blocknumber > input + 8192 then return 0, no overflow expected for input of < max 8 byte value
push0
calldataload
push2 0x2000
add
number
gt
push1 0x4b
jumpi

// mod 8192 and sload
push2 0x1fff
push0
calldataload
and
sload

// load into mem and return 32 bytes
push0
mstore
push1 0x20
push0
return

// 0x4b: return 0
jumpdest
push0
push0
mstore
push1 0x20
push0
return

// 0x53: revert
jumpdest
push0
push0
revert

// 0x57: set op - sstore the input to number-1 mod 8192
jumpdest
push0
calldataload
push2 0x1fff
push1 0x1
number
sub
and
sstore

stop
```

#### Deployment

The **L1 origin storage contract** can be deployed as a [predeployed contract](https://github.com/ethereum-optimism/specs/blob/main/specs/protocol/predeploys.md).

### Block processing

At the top of every L2 block where `block.timestamp >= L2_HISTORY_FORK_TIMESTAMP` the sequencer will call to `L2_HISTORY_STORAGE_ADDRESS` as
`L2_HISTORY_SYSTEM_ADDRESS` with the 32-byte input of `block.parent.hash`, a gas limit of `30_000_000`, and `0` value.
This will trigger the `set()` routine of the history contract.

* the call must execute to completion
* the call does not count against the block's gas limit
* the call does not follow the [EIP-1559](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1559.md) burn
semantics - no value should be transferred as part of the call
* if no code exists at `L2_HISTORY_SYSTEM_ADDRESS`, the call must fail silently

Note that, it will take `L2_HISTORY_SYSTEM_ADDRESS` blocks after the EIP's activation to completely fill up the ring
buffer. Initially the contract will only contain the parent hash of the fork block and no hashes prior to that.

## Rationale

### Execution block hashes instead of beacon block roots

EIP-4788 stores beacon block roots and while beacon block roots can be used to verify claims about the execution blocks
committed within this is less desirable than using the execution block hashes for two reasons:

1. More expensive proofs. To verify L1 account state, contract storage, transactions, or receipts (logs) using beacon
block roots we must first verify the execution header committed under that root using an SSZ merkle proof. By storing
the execution header hash directly in the ring buffer we avoid this step.
2. Requires supporting knowledge of and tracking changes to the beacon chain data structures. L2s can be expected to
retain a level of EVM equivalency meaning they can be expected to track and accommodate any changes to the L1 execution
data structures, but there is currently no reason for an L2 to track and accommodate changes to the L1 consensus data
structures beyond the engine API.

### Execution block hashes instead of state roots

Storing the entire L1 block header hash lets us verify claims about L1 transactions and receipts (logs), not just state
and storage.

### Length of the ring buffers

Ring buffer lengths are currently set to the lengths prescribed in EIP-2935 and EIP-4788.

For the **L2 history storage contract** 8192 L2 headers corresponds to ~4.55 hours worth of L2 blocks for an L2 with
block time of 2 seconds or ~34 minutes worth of blocks for an L2 with block time of 250 milliseconds.
The former is enough time to span the current average L2 output interval of major L2s today (~1 hour).
The latter is not and warrants discussing an extension of the ring buffer to accommodate L2s with faster block times or
longer output frequencies. For this reason it may make sense to not prescribe a set length for this ring buffer as L2s
can set the length that best fits their system.

## Backwards Compatibility

This RIP introduces backwards incompatible changes to the block derivation and verification of an L2.
These changes are purely additive and do not break anything related to current user activity and experience, but they do
require changes to the L2's L1->L2 derivation process and the verification logic in their output settlement contract(s).

## Test Cases

N/A 

##  Reference Implementation

N/A

## Security Considerations

N/A

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
