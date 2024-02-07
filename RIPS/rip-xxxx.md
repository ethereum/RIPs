---
rip: TBD
title: Expose call stack to contracts
description: Implement a call stack to record opcodes, addresses and function signatures and expose through a precompiled contract.
author: Caner Çıdam (@canercidam) <caner@openzeppelin.com>, Jonathan Alexander (@jalex206) <jonathan@openzeppelin.com>, Andrew Beal (@ajbealETH) <andy@forta.org>, Ariel Tempelhof (@ArielTM) <ariel.t@spherex.xyz>, Oren Fine (@orenfine) <orenfine@spherex.xyz>, Assaf Eli (@assafIronblocks) <assaf@ironblocks.com>, Or Dadosh (@ordd) <or@ironblocks.com>, Idan Levin <idan@collider.vc>, Alejandro Navarro (Grover-a5) <anavarro@neurablock.ai>
discussions-to: https://ethereum-magicians.org/t/rip-expose-call-stack-to-contracts/18535
status: Draft
type: Standards Track
category: Core
created: 2024-07-02
---

## Abstract

Implement a call stack to record opcodes, addresses and function signatures and expose through a precompiled contract. If implemented, the precompile will give protocols deeper visibility into addresses involved at any point in execution.

## Motivation

This proposal seeks to advance smart contract security in the Ethereum L2 ecosystem by enabling more robust exploit prevention solutions that depend on deeper visibility into the transaction call stack.

Threat detection has advanced a lot in the last year. There are at least a dozen security projects focused on monitoring and exploit detection, and collectively they are proving that attackers can be identified in advance. Early detection hinges on being able to identify malicious smart contracts as soon as they are deployed on-chain using a combination of static and dynamic analysis. Once malicious contracts are flagged, protocols can screen incoming transactions and revert if they include one of these addresses.  In parallel, anomaly detection - identifying transactions outside of normal user behavior - is also emerging as a legitimate approach to preventing exploits. Being able to consistently identify attackers and anomalies in advance opens the door to transaction screening, where protocols can choose to automatically revert transactions from high risk entities, or transactions that fall significantly outside “expected behavior”. 

One technical challenge limiting the long-term effectiveness of transaction screening is address visibility. Today, a smart contract only has visibility into msg.sender and tx.origin, not the full call stack. An attacker can use various forms of proxies to “obfuscate” the true source of the call and circumvent detection. While these circumvention techniques aren’t being used today, we expect hackers to quickly adopt them once transaction screening becomes more pervasive. 

This proposal introduces a non-intrusive way to increase visibility into hackers’ obfuscation techniques by keeping track of the call stack and exposing the latest list via an EVM precompiled contract when requested at any specific point of EVM execution. This helps the contracts screen more addresses and patterns before proceeding.

## Specification

### Constants

| Name                  | Value                                                                           |
|-----------------------|---------------------------------------------------------------------------------|
| PRECOMPILE_ADDRESS    | TBD                                                                             |
| BASE_GAS_COST         | TBD                                                                             |
| PER_ADDRESS_GAS_COST  | 2                                                                               |

### Call

A Call is defined by an opcode, an address and a function signature.

### CallStack

`CALL`, `CALLCODE`, `DELEGATECALL` and `STATICCALL` opcodes must push a Call to the CallStack before executing code and must pop after execution has completed.

### Precompiled contract encoding

The encoder must follow Solidity Contract ABI Specification to encode the list of Calls. The encoder writes each value as a 32-byte padded word and the pseudocode is as follows:

```
let b: ByteArray

b.append(0x20) // default offset
b.append(len(CallStack))

for call in CallStack:
	b.append(call.Op)
	b.append(call.Address)
	b.append(call.Signature)
```

### Total gas cost

```
BASE_GAS_COST + PER_ADDRESS_GAS_COST * len(CallStack)
```

### Precompile call example

```solidity
contract CallStack {
    address constant PRECOMPILE_ADDRESS = address(...); // TBD

    struct Call {
        uint8 op;
        address addr;
        uint32 sig;
    }

    function getCallStack() internal returns (Call[] memory) {
        (, bytes memory returndata) = address(PRECOMPILE_ADDRESS).call(bytes(""));
        Call[] memory calls = abi.decode(returndata, (Call[]));
        return calls;
    }
}
```

## Rationale

### Observing addresses beyond tx.origin and msg.sender

This functionality is useful in determining the other contracts involved in a transaction up to the point of execution, between tx.origin and the latest msg.sender.

Moreover, blackhats deploy attack contracts before launching the attack and that gives a time frame to scan and detect the malicious contract. If the attack transaction does a `DELEGATECALL` from a proxy to the attack contract, to call the victim contract, then the msg.sender observed by the victim contract is the proxy contract (and not the actual malicious attack contract). The call stack breaks this evasion by exposing the `DELEGATECALL`ed addresses in the call stack.

### Gas cost

The call stack implementation adds minimal and negligible overhead to EVM execution. Encoder overhead at the time of precompile execution is at a reasonable level when a reference implementation is benchmarked against readily available precompiled contracts. For this reason, a `BASE_GAS_COST` is introduced, to cover any overhead from encoding and the call stack push/pop cost until the precompiled contract is more widely adopted.

`PER_ADDRESS_GAS_COST` value is chosen to match with `CALLER` and `ADDRESS` opcode gas cost. Total cost scales per address in CallStack so that the cost of checking a deeper call stack can be compensated.

### Account abstraction support

By design, the call stack and the precompiled contract support the account abstraction outlined in ERC-4337.

In ERC-4337, UserOperations are calls to (non-EOA) smart wallets validated and bundled into a single transaction to be executed. In the reference implementations, each UserOperation is executed sequentially and isolated from each other. The call stack implementation maintains this isolation by not exposing addresses from one UserOperation to another. A smart wallet and any deeper callees are only exposed to the global singleton EntryPoint contract commonly with other UserOperation execution.

### Pattern checks

With the help of the opcodes and function signatures, contracts can implement security mechanisms which reason about the call patterns in a transaction.

### Address checks

While this proposal enhances visibility into addresses involved in a transaction, it does not prescribe how such addresses should be checked. Combining this call stack precompile with complimentary checks for contract reputation and age checks will further enhance transaction screening, but those checks are also outside the scope of this proposal.

### Impact on composability

By itself, the precompile does not impact composability. However, if implemented and leveraged in conjunction with a transaction screening solution, composability may be impacted. Nevertheless, this is viewed as an acceptable result as the authors believe each protocol has the right to manage its own risk and decide for itself what transactions it allows/disallows.

## Backwards Compatibility

The call stack does not affect any previous execution and requires no consensus changes. The precompiled contract, however, can affect how contracts react during transaction execution and should require all clients to upgrade.

## Reference Implementation

https://github.com/ethereum/go-ethereum/pull/28947

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).