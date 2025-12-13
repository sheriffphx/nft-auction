//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployNftAuction} from "../../script/NftAuction.s.sol";

contract DeployNftAuctionTest is Test {
    DeployNftAuction public deployer;

    function setUp() public {
        deployer = new DeployNftAuction();
    }

    function test_DeploymentSuccess() public {
        deployer.run();

        // The deployed contract is retrieved from the public variable set by the script's run() function
        address deployedAddress = address(deployer.nftAuction());

        // Assert that the address is not the zero address (i.e., deployment was successful)
        assertNotEq(deployedAddress, address(0), "NFT Auction contract deployment failed");
    }
}
