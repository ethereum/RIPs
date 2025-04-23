/********************************************************************************************/
/*
/*     ___                _   _       ___               _         _    _ _    
/*    / __|_ __  ___  ___| |_| |_    / __|_ _ _  _ _ __| |_ ___  | |  (_) |__ 
/*    \__ \ '  \/ _ \/ _ \  _| ' \  | (__| '_| || | '_ \  _/ _ \ | |__| | '_ \
/*   |___/_|_|_\___/\___/\__|_||_|  \___|_|  \_, | .__/\__\___/ |____|_|_.__/
/*                                         |__/|_|           
/*              
/* Copyright (C) 2023 - Renaud Dubois - This file is part of SCL (Smooth CryptoLib) project
/* License: This software is licensed under MIT License                                        
/********************************************************************************************/

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;


// prime field modulus of the ed25519 curve
uint256 constant p = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed;
// -2 mod(p), used to accelerate inversion and doubling operations by avoiding negation
// the representation of -1 in this field
uint256 constant pMINUS_1 = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffec;
uint256 constant pMINUS_2 = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeb;

// short weierstrass first coefficient 
uint256 constant a = 19298681539552699237261830834781317975544997444273427339909597334573241639236;
// short weierstrass second coefficient 0x41a3b6bfc668778ebe2954a4b1df36d1485ecef1ea614295796e102240891faa
uint256 constant b =55751746669818908907645289078257140818241103727901012315294400837956729358436;
uint256 constant n = 0x1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed;
uint256 constant nMINUS_2 = 0x1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3eb;

uint256 constant gx=0x2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaad245a;
uint256 constant gy=0x20ae19a1b8a086b4e01edd2c7748d14c923d4d7e6d7c61b229e9c5a27eced3d9;
//Computed with sage:
//wei25519_gx2pow128=12508890695284219941432954705462464418216687521194464129735840385450754660239;
//wei25519_gy2pow128=38799853089443519372474884917849014410429794312182895329810583938938235910009;
//0x1ba7c7ff0d602e0108a3dd49027e624914307ae10b22d566e567558e115f578f
uint256 constant gpow2p128_x =12508890695284219941432954705462464418216687521194464129735840385450754660239;
//0x55c7f0494056ac055fdb19191577ef9b2055b5b165e04291aaf7187e6519f779
uint256 constant gpow2p128_y =38799853089443519372474884917849014410429794312182895329810583938938235910009;

/* edwards representation */

uint256 constant A=0x076d06;//486662, montgomery representation coefficient A
uint256 constant delta=0x2aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaad2451;//(p + A) / 3 mod p
uint256 constant c=0x70d9120b9f5ff9442d84f723fc03b0813a5e2c2eb482e57d3391fb5500ba81e7;// = sqrt(-(A + 2)) mod 255^19
//sqrt of -1
uint256 constant sqrtm1=0x2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0;
uint256 constant d = 0x52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3;//edwards form d coefficient

uint256 constant edX = 0x216936D3CD6E53FEC0A4E231FDD6DC5C692CC7609525A7B2C9562D608F25D51A;//base point X
uint256 constant edY = 0x6666666666666666666666666666666666666666666666666666666666666658;//base point Y
//P+3 div 8
uint256 constant pp3div8=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe;



