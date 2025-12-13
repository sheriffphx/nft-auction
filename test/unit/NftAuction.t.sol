//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NftAuction} from "../../src/NftAuction.sol";
import {MockNft} from "../../src/MockNft.sol";

contract NftAuctionTest is Test {
    NftAuction nftAuction;
    MockNft mockNft;

    // Define accounts
    address public owner = makeAddr("owner");
    address public seller = makeAddr("seller");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charles = makeAddr("charles");

    uint256 internal constant NFT_ID = 1;
    uint256 internal constant STARTING_BID = 1 ether;
    uint256 internal constant DURATION = 2; //2 days

    event AuctionCreated(
        address indexed seller,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 startingPrice,
        uint256 endTime
    );
    event NewHighestBid(address indexed bidder, address indexed nftContract, uint256 indexed tokenId, uint256 amount);
    event UserRefunded(address indexed user, uint256 amount);
    event AuctionEnded(address indexed user, address indexed nftContract, uint256 indexed tokenId, uint256 highestBid);
    event AuctionCancelled(address indexed user, address indexed nftContractAddress, uint256 tokenId);

    function setUp() public {
        vm.startPrank(owner);
        mockNft = new MockNft();
        nftAuction = new NftAuction();

        nftAuction.setFeeRecipient(owner);

        nftAuction.setPlatformFee(250);
        vm.stopPrank();

        vm.startPrank(seller);
        mockNft.mint(seller);
        mockNft.approve(address(nftAuction), NFT_ID);
        vm.stopPrank();

        // Fund bidders
        vm.deal(seller, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charles, 10 ether);
    }

    function testCreateAuction_Success() public {
        vm.startPrank(seller);

        uint256 value = DURATION;
        NftAuction.TimeUnit unit = NftAuction.TimeUnit.Days;
        uint256 expectedEndTime = block.timestamp + nftAuction.toSeconds(value, unit);
        vm.expectEmit(true, true, true, true);
        emit NftAuction.AuctionCreated(seller, address(mockNft), NFT_ID, STARTING_BID, expectedEndTime);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        assertEq(mockNft.ownerOf(NFT_ID), address(nftAuction));
        vm.stopPrank();

        NftAuction.Auction memory a = nftAuction.getAuctionDetails(address(mockNft), NFT_ID);
        assertEq(a.seller, seller);
        assertEq(a.startingBid, STARTING_BID);
        assertEq(a.highestBid, 0);
        assertEq(a.highestBidder, address(0));
        assertEq(a.nftContract, address(mockNft));
        assertEq(a.ended, false);
        assertEq(a.endTime, expectedEndTime);
        assertEq(a.tokenId, NFT_ID);
        assertEq(a.lockedFee, nftAuction.platformFee());
    }

    function testCreateExistingAuctionRevert() public {
        vm.startPrank(seller);
        // first create auction
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);

        vm.expectRevert(NftAuction.AuctionAlreadyExists.selector);
        // try to create again
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();
    }

    function testCreateAuctionAfterEndedRevert() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);

        // Fast forward time to after auction end
        vm.warp(block.timestamp + nftAuction.toSeconds(DURATION, NftAuction.TimeUnit.Days) + 1);
        vm.expectRevert(NftAuction.AuctionAlreadyExists.selector);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();
    }

    function testCreateAuction_NotNftOwnerRevert() public {
        vm.startPrank(alice);
        vm.expectRevert(NftAuction.NotNftOwner.selector);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();
    }

    function testCreateAuction_Revert_InvalidPrice() public {
        vm.startPrank(seller);
        vm.expectRevert(NftAuction.InvalidPrice.selector);
        nftAuction.createAuction(address(mockNft), NFT_ID, 0, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();
    }

    function testCreateAuction_RevertInvalidTime() public {
        vm.startPrank(seller);
        vm.expectRevert("Duration must be greater than 30 minutes");
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, 29, NftAuction.TimeUnit.Minutes);
        vm.stopPrank();
    }

    function testCancelAuction() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);

        vm.expectEmit(true, true, true, true);
        emit NftAuction.AuctionCancelled(seller, address(mockNft), NFT_ID);
        nftAuction.cancelAuction(address(mockNft), NFT_ID);

        assertEq(mockNft.ownerOf(NFT_ID), seller);
        vm.stopPrank();
    }

    function testCancelAuction_Revert_NotSeller() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert();
        nftAuction.cancelAuction(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testCancelAuction_RevertIfAuctionEnded() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);

        // Fast forward time to after auction end
        vm.warp(block.timestamp + nftAuction.toSeconds(DURATION, NftAuction.TimeUnit.Days) + 1);

        vm.startPrank(seller);
        vm.expectRevert(NftAuction.AuctionHasEnded.selector);
        nftAuction.cancelAuction(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testCancelAuction_RevertIfBidsPlaced() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(alice);
        nftAuction.bid{value: 2 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Cannot cancel after a bid");
        nftAuction.cancelAuction(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testCancelAuction_RevertIfNoAuction() public {
        vm.startPrank(seller);
        vm.expectRevert(bytes("Not seller"));
        nftAuction.cancelAuction(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testNoBidExistBeforeCancel() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(alice);
        nftAuction.bid{value: 2 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Cannot cancel after a bid");
        nftAuction.cancelAuction(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testReturnNftToSellerOnCancel() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);

        nftAuction.cancelAuction(address(mockNft), NFT_ID);

        assertEq(mockNft.ownerOf(NFT_ID), seller);
        vm.stopPrank();
        console.log("NFT returned to seller ", mockNft.ownerOf(NFT_ID), " on cancel auction");
    }

    function testCancelAuction_EndAuction() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        nftAuction.cancelAuction(address(mockNft), NFT_ID);

        vm.startPrank(alice);
        vm.expectRevert();
        nftAuction.bid{value: 2 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testToSeconds() public {
        uint256 expectedMinutes = 2 * 60;
        uint256 expectedHours = 2 * 60 * 60;
        uint256 expectedDay = 2 * 60 * 60 * 24;
        uint256 expectedWeek = 2 * 60 * 60 * 24 * 7;

        assertEq(nftAuction.toSeconds(2, NftAuction.TimeUnit.Minutes), expectedMinutes);
        assertEq(nftAuction.toSeconds(2, NftAuction.TimeUnit.Hours), expectedHours);
        assertEq(nftAuction.toSeconds(2, NftAuction.TimeUnit.Days), expectedDay);
        assertEq(nftAuction.toSeconds(2, NftAuction.TimeUnit.Weeks), expectedWeek);
    }

    function testBid() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(alice);
        nftAuction.bid{value: 2 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();

        vm.startPrank(bob);
        nftAuction.bid{value: 3 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();

        vm.assertEq(address(nftAuction).balance, 5 ether);
    }

    function testBid_AmountMustBeGreaterThanZero() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Bid amount must be greater than zero");
        nftAuction.bid{value: 0}(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testRevertWhen_BidWithInvalidNftContractAddress() public {
        // Try to bid on auction with address(0) as NFT contract
        vm.prank(alice);
        vm.expectRevert("Invalid NFT contract address");
        nftAuction.bid{value: STARTING_BID}(address(0), NFT_ID);
    }

    function testRevertIfBidderIsSeller() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(seller);
        vm.expectRevert("Seller cannot bid on their own auction");
        nftAuction.bid{value: 2 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testBid_AuctionMustExist() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert("Auction does not exist");
        nftAuction.bid{value: 2 ether}(address(mockNft), 2);
        vm.stopPrank();
    }

    function testBid_AuctionShouldBeActive() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.warp(block.timestamp + nftAuction.toSeconds(2, NftAuction.TimeUnit.Days) + 2);
        vm.startPrank(bob);
        vm.expectRevert(NftAuction.AuctionHasEnded.selector);
        nftAuction.bid{value: 1.5 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testBidAmountMustBeGreaterThanStartingBid() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(NftAuction.BidNotHighEnough.selector);
        nftAuction.bid{value: 0.5 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testEmitBidDataCorrectly() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        uint256 bidAmount = 2 ether;
        vm.startPrank(charles);
        vm.expectEmit(true, true, true, true);
        emit NftAuction.NewHighestBid(charles, address(mockNft), NFT_ID, bidAmount);
        nftAuction.bid{value: bidAmount}(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testBidMustSurpassPreviousHighestBid() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        uint256 aliceBidAmount = 1.5 ether;
        uint256 bobBidAmount = 1.5 ether;

        vm.startPrank(alice);
        nftAuction.bid{value: aliceBidAmount}(address(mockNft), NFT_ID);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(NftAuction.BidNotHighEnough.selector);
        nftAuction.bid{value: bobBidAmount}(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testRefundWorks() public {
        // seller list auction
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        uint256 aliceBidAmount = 1.5 ether;
        uint256 bobBidAmount = 2 ether;
        // Alice bid
        vm.startPrank(alice);
        nftAuction.bid{value: aliceBidAmount}(address(mockNft), NFT_ID);
        vm.stopPrank();
        uint256 balanceAfterBid = alice.balance;
        console.log("Balance after alice initial bid: ", balanceAfterBid);
        // Bob bid
        vm.startPrank(bob);
        nftAuction.bid{value: bobBidAmount}(address(mockNft), NFT_ID);
        vm.stopPrank();

        // alice call refund

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit NftAuction.UserRefunded(alice, 1.5 ether);
        nftAuction.withdrawRefund();
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(NftAuction.NoPendingRefund.selector);
        nftAuction.withdrawRefund();
        vm.stopPrank();

        uint256 balanceAfterHigherBid = alice.balance;
        uint256 refundAmount = balanceAfterHigherBid - balanceAfterBid;

        console.log("balance after bob bid: ", balanceAfterHigherBid);
        assertEq(address(nftAuction).balance, 2 ether);
    }

    function testEndAuction() public {
        // seller list auction
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        uint256 aliceBidAmount = 1.5 ether;
        uint256 bobBidAmount = 2 ether;
        // Alice bid
        vm.startPrank(alice);
        nftAuction.bid{value: aliceBidAmount}(address(mockNft), NFT_ID);
        vm.stopPrank();
        // uint256 balanceAfterBid = alice.balance;
        // console.log("Balance after alice initial bid: ", balanceAfterBid);

        // Bob bid
        vm.startPrank(bob);
        nftAuction.bid{value: bobBidAmount}(address(mockNft), NFT_ID);
        vm.stopPrank();

        // alice call refund
        vm.startPrank(alice);
        nftAuction.withdrawRefund();
        vm.stopPrank();

        vm.warp(block.timestamp + nftAuction.toSeconds(DURATION, NftAuction.TimeUnit.Days) + 1);

        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit NftAuction.AuctionEnded(alice, address(mockNft), NFT_ID, bobBidAmount);
        nftAuction.endAuction(address(mockNft), NFT_ID);
        vm.stopPrank();
    }

    function testSetPlatformFee() public {
        vm.startPrank(owner);
        nftAuction.setPlatformFee(300);
        assertEq(nftAuction.platformFee(), 300);
        vm.stopPrank();
    }

    function testSetFeeRecipient() public {
        vm.startPrank(owner);
        nftAuction.setFeeRecipient(seller);
        assertEq(nftAuction.feeRecipient(), seller);
        vm.stopPrank();
    }

    function testSetPlatformFee_RevertIfNotOwner() public {
        vm.startPrank(seller);
        vm.expectRevert();
        nftAuction.setPlatformFee(300);
        vm.stopPrank();
    }

    function testSetFeeRecipient_RevertIfNotOwner() public {
        vm.startPrank(seller);
        vm.expectRevert();
        nftAuction.setFeeRecipient(seller);
        vm.stopPrank();
    }

    function testGetAuctionDetails() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        NftAuction.Auction memory a = nftAuction.getAuctionDetails(address(mockNft), NFT_ID);
        assertEq(a.seller, seller);
        assertEq(a.startingBid, STARTING_BID);
        assertEq(a.highestBid, 0);
        assertEq(a.highestBidder, address(0));
        assertEq(a.nftContract, address(mockNft));
        assertEq(a.ended, false);
        assertEq(a.endTime, block.timestamp + nftAuction.toSeconds(DURATION, NftAuction.TimeUnit.Days));
        assertEq(a.tokenId, NFT_ID);
        assertEq(a.lockedFee, nftAuction.platformFee());
    }

    function testGetPendingRefund() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        vm.startPrank(alice);
        nftAuction.bid{value: 2 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();

        vm.startPrank(bob);
        nftAuction.bid{value: 3 ether}(address(mockNft), NFT_ID);
        vm.stopPrank();

        uint256 pendingRefundAlice = nftAuction.getPendingRefund(alice);
        assertEq(pendingRefundAlice, 2 ether);
    }

    function testIsAuctionActive() public {
        vm.startPrank(seller);
        nftAuction.createAuction(address(mockNft), NFT_ID, STARTING_BID, DURATION, NftAuction.TimeUnit.Days);
        vm.stopPrank();

        bool isActive = nftAuction.isAuctionActive(address(mockNft), NFT_ID);
        assertEq(isActive, true);

        vm.warp(block.timestamp + nftAuction.toSeconds(DURATION, NftAuction.TimeUnit.Days) + 1);

        isActive = nftAuction.isAuctionActive(address(mockNft), NFT_ID);
        assertEq(isActive, false);
    }

    // Constructor test
    function testConstructor() public {
        vm.startPrank(owner);
        NftAuction newNftAuction = new NftAuction();
        assertEq(newNftAuction.platformFee(), 50);
        assertEq(newNftAuction.feeRecipient(), owner);
        vm.stopPrank();
    }
}
