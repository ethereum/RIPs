---
rip: 77XX
title: Predeploys for deterministic deployments
description: Proposal to add predeployed factory contracts at common addresses that enable determinstic contract deployment.
author: Richard Meissner (@rmeissner)
discussions-to: https://ethereum-magicians.org/t/eip-proposal-create2-contract-factory-precompile-for-deployment-at-consistent-addresses-across-networks/6083/29
status: Draft
type: Standards Track
category: Core
created: 2024-06-24
---

## Abstract

This proposal introduces a set of predeployed factory contracts at common addresses that enable deterministic deployment at the same address across different networks.

## Motivation

- There are multiple factory contracts that are common
 - [Deterministic Deployment Proxy](https://github.com/Arachnid/deterministic-deployment-proxy)
 - [Safe Singleton Factory](https://github.com/safe-global/safe-singleton-factory?tab=readme-ov-file)
 - [CreateX](https://github.com/pcaversaccio/createx)
- Risk of centralized keys
- Risk of parameters (gas price or gas limit) changes
- 7702 uses an address

## Specification

### Factories

### Addresses

### Gas Cost

### References

- OP Genesis definition

## Rationale

### Why not align on one factory?

## Backwards Compatibility

No backward compatibility issues found as the precompiled contract will be added to `PRECOMPILED_ADDRESS` at the next available address in the precompiled address set.
