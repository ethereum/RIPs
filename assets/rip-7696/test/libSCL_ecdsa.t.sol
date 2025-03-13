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


import "forge-std/Test.sol";

import "@solidity/lib/libSCL_ecdsab4.sol";
import "@solidity/fields/SCL_secp256r1.sol";


contract SCL_ECDSATest is Test {

  //test helper to precompute P**128 and Q**128
 function ecPow128(uint256 X, uint256 Y, uint256 ZZ, uint256 ZZZ) public returns(uint256 x128, uint256 y128){
   assembly{
   function vecDbl(x, y, zz, zzz) -> _x, _y, _zz, _zzz{
            let T1 := mulmod(2, y, p) //U = 2*Y1, y free
                let T2 := mulmod(T1, T1, p) // V=U^2
                let T3 := mulmod(x, T2, p) // S = X1*V
                T1 := mulmod(T1, T2, p) // W=UV
                let T4 := addmod(mulmod(3, mulmod(x,x,p),p),mulmod(a,mulmod(zz,zz,p),p),p)//M=3*X12+aZZ12  
                _zzz := mulmod(T1, zzz, p) //zzz3=W*zzz1
                _zz := mulmod(T2, zz, p) //zz3=V*ZZ1

                _x := addmod(mulmod(T4, T4, p), mulmod(pMINUS_2, T3, p), p) //X3=M^2-2S
                T2 := mulmod(T4, addmod(_x, sub(p, T3), p), p) //-M(S-X3)=M(X3-S)
                _y := addmod(mulmod(T1, y, p), T2, p) //-Y3= W*Y1-M(S-X3), we replace Y by -Y to avoid a sub in ecAdd
                _y:= sub(p, _y)
         }
         for {x128:=0} lt(x128, 128) { x128:=add(x128,1) }{
           X, Y, ZZ, ZZZ := vecDbl(X, Y, ZZ, ZZZ)
         }
         }
      ZZ=ModInv(ZZ, p);
      ZZZ=ModInv(ZZZ,p);
      x128=mulmod(X, ZZ, p);
      y128=mulmod(Y, ZZZ, p);
}

 //ecdsa using the 4 dimensional shamir's trick
 function test_secp256r1() public  returns (bool){

   console.log("           * Shamir 4 dimensions");
   
   
  uint256[7] memory vec=[
   0xbb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023 ,//message
   0x741dd5bda817d95e4626537320e5d55179983028b2f82c99d500c5ee8624e3c4,//r
   0x974efc58adfdad357aa487b13f3c58272d20327820a078e930c5f2ccc63a8f2b,//s
   0x5ecbe4d1a6330a44c8f7ef951d4bf165e6c6b721efada985fb41661bc6e7fd6c ,//Q start here
   0x8734640c4998ff7e374b06ce1a64a2ecd82ab036384fb83d9a79b127a27d5032,
   112495727131302244506157669471790202209849926651017016481532073180322115017576,
   88228053145992414849958298035823172674083888062809552550982514976029750463913];
   
   uint256[10] memory Qpa=[vec[3], vec[4], vec[5], vec[6] ,p, a, gx, gy, gpow2p128_x, gpow2p128_y];


   bool res= SCL_ECDSAB4.verify(bytes32(vec[0]), vec[1], vec[2], Qpa,n);
   

   assertEq(res,true); 
   
   return res;
 }



 //ecdsa using the shamir's trick with 4 points, wycheproofing tests Daimo
function test_ecdsaB4_wycheproof() public{
  
   
 // This is the most comprehensive test, covering many edge cases. See vector
    // generation and validation in the test-vectors directory.
    uint cpt=0;
    uint256[10] memory Qpa=[0,0,0,0 ,p, a, gx, gy, gpow2p128_x, gpow2p128_y];



   // console.log("           * Wycheproof");      
	   
        string memory file = "./test/vectors_wycheproof.jsonl";
        while (true) {
           
            string memory vector = vm.readLine(file);
            if (bytes(vector).length == 0) {
                break;
            }
            cpt=cpt+1;
         
            uint256 Qx = uint256(stdJson.readBytes32(vector, ".x"));
            uint256 Qy = uint256(stdJson.readBytes32(vector,".y"));
            Qpa[0]=Qx;
            Qpa[1]=Qy;
            
            (Qpa[2], Qpa[3])=ecPow128(Qx, Qy, 1, 1);//compute Q^128

            uint256 r = uint256(stdJson.readBytes32(vector,".r"));
            uint256 s = uint256(stdJson.readBytes32(vector,".s"));
            bytes32 hash = stdJson.readBytes32(vector,".hash");
            bool expected =stdJson.readBool(vector, ".valid");
            string memory comment = stdJson.readString(vector, ".comment");
  
            bool result= SCL_ECDSAB4.verify(hash, r,s, Qpa,n);
   

            string memory err = string(
                abi.encodePacked(
                    "exp ",
                    expected ? "1" : "0",
                    ", we return ",
                    result ? "1" : "0",
                    ": ",
                    comment
                )
            );
            assertTrue(result == expected, err);
            
        }

    }


}