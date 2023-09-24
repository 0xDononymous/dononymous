// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";

import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Dononymous is BaseHook, ERC1155 {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // mapping organization => share of fee
    mapping(address organization => uint256 share) public organizationShare;
    address relayer;
    int256 LIQUIDITY_DELTA = 10 ether;

    constructor(
        IPoolManager _poolManager,
        string memory _uri,
        address _relayer
    ) BaseHook(_poolManager) ERC1155(_uri) {
        relayer = _relayer;
    }

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            });
    }

    // Main functionality
    function provideCrumble(
        PoolKey calldata key,
        address org,
        int24 _tickLower,
        int24 _tickUpper
    ) public {
        // add fund to the smart contract
        _infuseFund(key);

        // Setup the modifyPosition parameters
        IPoolManager.ModifyPositionParams
            memory modifyPositionParams = IPoolManager.ModifyPositionParams({
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                liquidityDelta: LIQUIDITY_DELTA
            });

        BalanceDelta delta = abi.decode(
            poolManager.lock(
                abi.encodeCall(
                    this._handleModifyPosition,
                    (key, modifyPositionParams, abi.encode(true, org))
                )
            ),
            (BalanceDelta)
        );

        int256 delta0 = delta.amount0();
        int256 delta1 = delta.amount1();

        if (delta0 > 0) {
            IERC20(Currency.unwrap(key.currency0)).transfer(
                address(poolManager),
                uint256(delta0)
            );
            poolManager.settle(key.currency0);
        }

        if (delta1 > 0) {
            IERC20(Currency.unwrap(key.currency1)).transfer(
                address(poolManager),
                uint256(delta1)
            );
            poolManager.settle(key.currency1);
        }
    }

    // Hook
    function beforeModifyPosition(
        address,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata params,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4) {
        if (params.liquidityDelta > 0) {
            console.logString("Provide Liquidity");
            if (hookData.length > 0) {
                console.logString("hookData");
                address org = abi.decode(hookData, (address));
                console.logAddress(org);
                organizationShare[org]++;
            }
        } else {
            console.logString("Remove Liquidity");
            // verify identity
        }

        return BaseHook.beforeModifyPosition.selector;
    }

    // Helper
    function _handleModifyPosition(
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams memory params,
        bytes calldata hookData
    ) public returns (BalanceDelta) {
        BalanceDelta delta = poolManager.modifyPosition(key, params, hookData);
        return delta;
    }

    function _infuseFund(PoolKey calldata key) public {
        IERC20(Currency.unwrap(key.currency0)).transferFrom(
            relayer,
            address(this),
            IERC20(Currency.unwrap(key.currency0)).balanceOf(relayer)
        );
        IERC20(Currency.unwrap(key.currency1)).transferFrom(
            relayer,
            address(this),
            IERC20(Currency.unwrap(key.currency1)).balanceOf(relayer)
        );
    }
}