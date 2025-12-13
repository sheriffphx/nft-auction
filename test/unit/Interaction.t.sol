//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
// Import the script to be tested
import {NftAuctionHandler} from "../../script/Interaction.s.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NftAuctionHandlerTest is Test {
    NftAuctionHandler public handler;

    function setUp() public {
        handler = new NftAuctionHandler();
    }

    function test_FullAuctionLifecycleSuccess() public {
        // Execute the entire auction lifecycle script
        // This includes deployment, minting, bidding, refunding, time warp, and ending the auction
        handler.run();

        // Retrieve key addresses and constants from the public variables of the script
        address mockNftAddress = address(handler.mockNft());
        address charles = handler.charles();
        uint256 nftId = handler.NFT_ID();

        // --- Final NFT Ownership Check ---
        // Assert that the NFT was successfully transferred to the highest bidder (Charles)
        assertEq(
            IERC721(mockNftAddress).ownerOf(nftId), charles, "NFT transfer failed: Highest bidder does not own NFT"
        );

        // --- Final Contract Balance Check ---
        // Assert that the auction contract is empty after funds were distributed to seller and fee recipient
        assertEq(address(handler.nftAuction()).balance, 0, "Auction contract balance should be zero after endAuction");

        // --- Final Auction State Check ---
        // Check the auction struct to ensure the auction is marked as ended
        (,,,,,,,, bool ended) = handler.nftAuction().auctions(mockNftAddress, nftId);
        assertTrue(ended, "Auction should be marked as ended in storage");
    }
}
