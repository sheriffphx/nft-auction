//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {NftAuction} from "../src/NftAuction.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {MockNft} from "../src/MockNft.sol";

contract NftAuctionHandler is Script {
    // Define accounts
    address public owner = makeAddr("owner");
    address public seller = makeAddr("seller");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charles = makeAddr("charles");

    uint256 internal constant NFT_ID = 1;
    uint256 internal constant STARTING_BID = 1 ether;
    uint256 internal constant DURATION = 2; //2 days

    // contracts
    MockNft internal mockNft;
    NftAuction internal nftAuction;

    function setUp() public {
        // Give Accounts fund
        vm.deal(owner, 10 ether);
        vm.deal(seller, 5 ether);
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);
        vm.deal(charles, 5 ether);
    }

    function run() external {
        // =============== Owner Deploying contracts
        //Deploy MockNft
        // Deploy Nft
        // Set fee recipient as himself
        console.log("1. Deploying Contracts...");
        vm.startBroadcast(owner);
        mockNft = new MockNft();
        nftAuction = new NftAuction();
        nftAuction.setFeeRecipient(owner);
        nftAuction.setPlatformFee(250);
        vm.stopBroadcast();

        // =============== Seller Minting the NFT process ready for auction
        // Mint the NFT to the seller
        // And approval of NFTAuction to move NFT
        vm.startBroadcast(seller);
        console.log("2. Minting NFT to Seller and Seller Approves Auction Contract...");
        mockNft.mint(seller);
        console.log("Mock NFT contract address: ", address(mockNft));
        mockNft.approve(address(nftAuction), NFT_ID);
        vm.stopBroadcast();

        // ============= Seller Making the Auction
        vm.startBroadcast(seller);
        console.log("3. Seller creates auction...");
        // Create the auction using 1 ether bid, and 2 days (2,2)
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopBroadcast();

        // ============= Alice making a Bid with 1.5 ether
        vm.startBroadcast(alice);
        console.log("4. Alice places first bid (1.5 ETH)...");
        nftAuction.bid{value: 1.5 ether}(address(mockNft), NFT_ID);
        vm.stopBroadcast();

        // =========== Bob bidding with 1.6 ether
        vm.startBroadcast(bob);
        console.log("5. Bob places high bid (1.6 ETH)...");
        nftAuction.bid{value: 1.6 ether}(address(mockNft), NFT_ID);
        vm.stopBroadcast();

        // ============ Charles bid with 1.7 ether
        vm.startBroadcast(charles);
        console.log("5. Charles places high bid (1.7 ETH)...");
        nftAuction.bid{value: 1.7 ether}(address(mockNft), NFT_ID);
        vm.stopBroadcast();

        // =========== Refund for those that didn't get the highestBidder slot
        // Alice Refund
        vm.startBroadcast(alice);
        uint256 beforeAliceRefund = alice.balance;
        nftAuction.withdrawRefund();
        console.log("6. Alicewithdraws refund. Refund Amount: ", alice.balance - beforeAliceRefund);
        vm.stopBroadcast();

        // Bob Refund
        vm.startBroadcast(bob);
        uint256 beforeBobRefund = bob.balance;
        nftAuction.withdrawRefund();
        console.log("6. Bob withdraws refund. Refund Amount: ", bob.balance - beforeBobRefund);
        vm.stopBroadcast();

        // ======= End and Withdraw
        // Warp time forward to end time
        uint256 afterTwoDays = nftAuction.toSeconds(DURATION, NftAuction.TimeUnit(2));
        console.log("After Two Days: " , afterTwoDays);
        vm.warp(block.timestamp + 172800 + 1);

        vm.startBroadcast(owner);
        uint256 sellerBalanceBefore = seller.balance;
        uint256 feeRecipientBalanceBefore = owner.balance;
        
        console.log("7. Ending auction...");

        nftAuction.endAuction(address(mockNft), NFT_ID);
        vm.stopBroadcast();

        // --- 8. Final Checks (Assertions) ---
        console.log("--- Final Checks ---");

        // NFT Check: Highest bidder (BIDDER_B) owns the NFT
        require(IERC721(address(mockNft)).ownerOf(NFT_ID) == charles, "NFT transfer failed");
        console.log("NFT check: Highest bidder Charles now owns the NFT.");

        // Funds Check: Seller received their cut (1.6 ETH - 2.5% fee)
        uint256 finalBid = 1.7 ether;
        uint256 feeAmount = (finalBid * 250) / 10000; // 2.5% of 1.6 ETH
        uint256 expectedSellerCut = finalBid - feeAmount;

        // Since balances are tracked precisely by the VM, we can check the delta
        require(seller.balance > sellerBalanceBefore, "Seller was not paid");
        require(owner.balance == feeRecipientBalanceBefore + feeAmount, "Fee recipient was not paid");
        console.log("Funds check: Seller and Fee Recipient were paid correctly.");
        console.log("Sellers Cut: ", expectedSellerCut);
        console.log(" Auction Lifecycle Script Complete!");
    }
}
