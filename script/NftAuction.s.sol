//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NftAuction} from "../src/NftAuction.sol";

contract DeployNftAuction is Script {
    NftAuction nftAuction;

    function run() external {
        vm.startBroadcast();
        nftAuction = new NftAuction();
        vm.stopBroadcast();
        console.log("NftAuction deployed at:", address(nftAuction));
    }
}
