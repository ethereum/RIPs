//********************************************************************************************/
///*
///*     ___                _   _       ___               _         _    _ _    
///*    / __|_ __  ___  ___| |_| |_    / __|_ _ _  _ _ __| |_ ___  | |  (_) |__ 
///*    \__ \ '  \/ _ \/ _ \  _| ' \  | (__| '_| || | '_ \  _/ _ \ | |__| | '_ \
///*   |___/_|_|_\___/\___/\__|_||_|  \___|_|  \_, | .__/\__\___/ |____|_|_.__/
///*                                         |__/|_|           
///*              
///* Copyright (C) 2023 - Renaud Dubois - This file is part of SCL (Smooth CryptoLib) project
///* License: This software is licensed under MIT License                                        
//********************************************************************************************/

pragma solidity >=0.8.19 <0.9.0;


//choose the field to import
import {deux_d,  unscaling_factor, d, scaling_factor, p, pp1div4, a,b,gx, gy, gpow2p128_x, gpow2p128_y, n, pMINUS_2, nMINUS_2, MINUS_1, _HIBIT_CURVE, _MODEXP_PRECOMPILE, FIELD_OID } from "@solidity/fields/SCL_secp256r1.sol";
//import { p, gx, gy, gpow2p128_x, gpow2p128_y, n, pMINUS_2, nMINUS_2, MINUS_1, _HIBIT_CURVE, FIELD_OID } from "@solidity/fields/SCL_ed25519.sol";
//import { deux_d, p, pp1div4, a,b,gx, gy, gpow2p128_x, gpow2p128_y, n, pMINUS_2, nMINUS_2, MINUS_1, _HIBIT_CURVE, _MODEXP_PRECOMPILE, FIELD_OID } from "@solidity/fields/SCL_ecstark.sol";

//import {unscaling_factor, d, scaling_factor, FIELD_OID,  MINUS_1, p,n, gx, gy, pMINUS_2, nMINUS_2, deux_d,a, _HIBIT_CURVE,b , gpow2p128_x, gpow2p128_y, _MODEXP_PRECOMPILE , pp1div4 } from "@solidity/fields/SCL_babyjujub.sol";
