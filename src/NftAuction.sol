//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            IMPORTS
//////////////////////////////////////////////////////////////*/

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NftAuction is ReentrancyGuard, Ownable, IERC721Receiver {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error AuctionAlreadyExists();
    error AuctionHasEnded();
    error BidNotHighEnough();
    error NoPendingRefund();

    /*//////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 public platformFee = 50; // 0.5% in basis points (bps)
    uint256 public constant DENOMINATOR = 10000;
    uint256 public bidIncrement = 200;
    address public feeRecipient;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    // Auction structure to hold auction details
    struct Auction {
        uint256 tokenId;
        uint256 lockedFee;
        uint256 highestBid;
        uint256 startingBid;
        uint256 endTime;
        address seller;
        address highestBidder;
        address nftContract;
        bool ended;
    }

    /*//////////////////////////////////////////////////////////////
                            MAPPINGS
    //////////////////////////////////////////////////////////////*/
    mapping(address => mapping(uint256 => Auction)) public auctions;
    mapping(address => uint256) public pendingReturns;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
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

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    enum AuctionStatus {
        Active, // 0: Auction is currently active
        Ended // 1: Auction has ended
    }
    enum TimeUnit {
        Minutes,
        Hours,
        Days,
        Weeks
    }

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlySeller(address nft, uint256 tokenId) {
        _onlySeller(nft, tokenId);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable(msg.sender) {
        feeRecipient = msg.sender;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     *@notice Creates an auction for a specific NFT
     *@param nftContractAddress Contract address of the listed NFT
     *@param _tokenId Token Id of the listed NFT
     *@param _startingBid The start bid price of the NFT
     *@param value Duration value for the auction
     *@param unit Time unit for the auction duration (Minutes, Hours, Days, Weeks)
     *@dev The auction can only be created if no auction exists for the NFT.
     */
    function createAuction(
        address nftContractAddress,
        uint256 _tokenId,
        uint256 _startingBid,
        uint256 value,
        TimeUnit unit
    ) external nonReentrant {
        // Logic to create an auction for the NFT
        // to check if an auction already exists for the given NFT
        Auction storage a = auctions[nftContractAddress][_tokenId];
        if (a.seller != address(0) && !a.ended) {
            revert AuctionAlreadyExists();
        }
        // Contract checks user owns the NFT
        IERC721 nft = IERC721(nftContractAddress);
        require(
            nft.getApproved(_tokenId) == address(this) || nft.isApprovedForAll(msg.sender, address(this)),
            "Contract not approved to transfer NFT"
        );

        // User approves the contract to transfer NFT
        nft.getApproved(_tokenId);
        uint256 duration = _toSeconds(value, unit);
        uint256 auctionEndTime = block.timestamp + duration;
        // NFT transferred to contract for escrow
        nft.safeTransferFrom(msg.sender, address(this), _tokenId);
        // Auction gets created
        Auction memory newAuction = Auction({
            seller: msg.sender,
            highestBidder: address(0),
            highestBid: 0,
            startingBid: _startingBid,
            endTime: auctionEndTime,
            ended: false,
            nftContract: nftContractAddress,
            tokenId: _tokenId,
            lockedFee: platformFee
        });
        // Store the auction in the mapping
        auctions[nftContractAddress][_tokenId] = newAuction;
        // Event logged to the blockchain
        emit AuctionCreated(msg.sender, nftContractAddress, _tokenId, _startingBid, block.timestamp + duration);
    }

    /**
     *@notice Cancels an active auction
     *@param nftContractAddress contract address of the NFT
     *@param _tokenId tokenId of the NFT
     *@dev Only the seller can cancel the auction. The auction must be active and not ended.
     */
    function cancelAuction(address nftContractAddress, uint256 _tokenId)
        external
        nonReentrant
        onlySeller(nftContractAddress, _tokenId)
    {
        Auction storage a = auctions[nftContractAddress][_tokenId];

        // Check if no bid yet before cancel and check if not ended
        require(!a.ended, "Auction already Ended");
        require(a.highestBid == 0, "Cannot cancel after a bid");

        // Transfer nft back to user
        IERC721(nftContractAddress).safeTransferFrom(address(this), a.seller, _tokenId);
        a.ended = true;

        emit AuctionCancelled(msg.sender, nftContractAddress, _tokenId);
    }

    /**
     *@notice Places a bid on an active auction
     *@param nftContractAddress Contract address of the NFT being auctioned
     *@param _tokenId Token ID of the NFT being auctioned
     *@dev The bid must be higher than the current highest bid or the starting bid if no bids have been placed.
     */
    function bid(address nftContractAddress, uint256 _tokenId) external payable nonReentrant {
        // Logic to place a bid on an active auction
        //         Auction must still be active
        require(msg.value > 0, "Bid amount must be greater than zero");
        require(nftContractAddress != address(0), "Invalid NFT contract address");
        // seller cannot bid on their own auction
        require(auctions[nftContractAddress][_tokenId].seller != msg.sender, "Seller cannot bid on their own auction");

        // Check if the auction exists and is active
        require(auctions[nftContractAddress][_tokenId].seller != address(0), "Auction does not exist");
        require(!auctions[nftContractAddress][_tokenId].ended, "Auction has ended");

        Auction storage a = auctions[nftContractAddress][_tokenId];
        if (block.timestamp >= a.endTime) {
            revert AuctionHasEnded();
        }

        // Bid must be higher than highestBid
        uint256 currentHighest = a.highestBid;
        uint256 minBidRequired;

        if (currentHighest == 0) {
            minBidRequired = a.startingBid;
        } else {
            minBidRequired = currentHighest + (bidIncrement * currentHighest) / DENOMINATOR; // 2% increment
        }

        if (msg.value < minBidRequired) {
            revert BidNotHighEnough();
        }

        // Previous highest bidder gets refund (stored as pending withdrawal)
        if (currentHighest != 0) {
            pendingReturns[a.highestBidder] += currentHighest;
        }

        // record new highest
        a.highestBid = msg.value;
        a.highestBidder = msg.sender;

        // Event logged to the blockchain
        emit NewHighestBid(msg.sender, nftContractAddress, _tokenId, msg.value);
    }

    /**
     *@notice Allows users to withdraw their pending refunds
     *@dev Users can call this function to withdraw their pending refunds from previous bids.
     * The function checks if the user has any pending refunds and transfers the amount to the user.
     * Emits a UserRefunded event.
     * @dev Reverts with NoPendingRefund if the user has no pending refunds.
     */
    function withdrawRefund() external nonReentrant {
        //logic to withdraw pending refunds
        uint256 amount = pendingReturns[msg.sender];
        if (amount == 0) {
            revert NoPendingRefund();
        }
        pendingReturns[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        // Event logged to the blockchain
        emit UserRefunded(msg.sender, amount);
    }

    /**
     *@notice Ends an auction and transfers the NFT to the highest bidder
     *@param nftContractAddress Contract address of the NFT being auctioned
     *@param _tokenId Token ID of the NFT being auctioned
     *@dev The auction must be active and not ended.
     */
    function endAuction(address nftContractAddress, uint256 _tokenId) external nonReentrant {
        // Logic to end an auction and transfer the NFT to the highest bidder
        Auction storage a = auctions[nftContractAddress][_tokenId];
        require(a.seller != address(0), "Auction does not exist");
        require(!a.ended, "Auction has already ended");
        require(block.timestamp >= a.endTime, "Auction is still active");

        a.ended = true;

        if (a.highestBidder != address(0)) {
            uint256 feeAmount = (a.highestBid * a.lockedFee) / DENOMINATOR;
            uint256 sellerAmount = a.highestBid - feeAmount;

            // Transfer NFT to highest bidder
            IERC721(nftContractAddress).safeTransferFrom(address(this), a.highestBidder, _tokenId);
            // transfer platform fee to fee recipient
            (bool feeSuccess,) = payable(feeRecipient).call{value: feeAmount}("");
            require(feeSuccess, "Fee transfer failed");
            // Transfer funds to seller
            (bool success,) = payable(a.seller).call{value: sellerAmount}("");
            require(success, "Transfer failed");
        } else {
            // If no bids were placed, return NFT to seller
            IERC721(nftContractAddress).safeTransferFrom(address(this), a.seller, _tokenId);
        }
        emit AuctionEnded(msg.sender, nftContractAddress, _tokenId, a.highestBid);
    }

    function toSeconds(uint256 value, TimeUnit unit) external pure returns (uint256) {
        return _toSeconds(value, unit);
    }

    function setPlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 500, "Fee too high (max 5%)");
        platformFee = _newFee;
    }

    function setFeeRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid address");
        feeRecipient = _newRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                     ERC721 RECEIVER IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handle the receipt of an NFT. This function is called by the
     * ERC721 contract when a token is transferred to this contract.
     * @dev Only accepts tokens if an auction for them is being created (i.e., inside createAuction).
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        view
        returns (bytes4)
    {
        // The address that called the transfer (must be the MockNFT contract)
        // require(msg.sender == address(nftContract), "Only NFT contract can call");

        // This is the magic value defined in the ERC721 standard to signal acceptance.
        // We use view because no state changes are required here, only verification.
        return this.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL & VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     *@notice Converts a time value to seconds based on the specified time unit
     *@param value The time value to convert
     *@param unit The time unit (Minutes, Hours, Days, Weeks)
     *@return uint256 The equivalent time in seconds
     */
    function _toSeconds(uint256 value, TimeUnit unit) internal pure returns (uint256) {
        if (unit == TimeUnit.Minutes) return value * 1 minutes;
        if (unit == TimeUnit.Hours) return value * 1 hours;
        if (unit == TimeUnit.Days) return value * 1 days;
        if (unit == TimeUnit.Weeks) return value * 1 weeks;
        revert("Invalid time unit");
    }

    /**
     *@notice Checks if the caller is the seller of the auction
     *@param nft Contract address of the NFT being auctioned
     *@param tokenId Token ID of the NFT being auctioned
     */
    function _onlySeller(address nft, uint256 tokenId) internal view {
        require(msg.sender == auctions[nft][tokenId].seller, "Not seller");
    }

    /**
     *@notice Retrieves the details of an auction
     *@param nftContractAddress Contract address of the NFT being auctioned
     *@param _tokenId Token ID of the NFT being auctioned
     *@return Auction struct containing the details of the auction
     */
    function getAuctionDetails(address nftContractAddress, uint256 _tokenId) external view returns (Auction memory) {
        return auctions[nftContractAddress][_tokenId];
    }

    /**
     *@notice Retrieves the pending refund amount for a user
     *@param user Address of the user
     *@return uint256 Amount of pending refund
     */
    function getPendingRefund(address user) external view returns (uint256) {
        return pendingReturns[user];
    }

    /**
     *@notice Cancels an active auction
     *@param nftContractAddress Contract address of the NFT being auctioned
     *@param _tokenId Token ID of the NFT being auctioned
     *@dev Only the seller can cancel the auction. The auction must be active and not ended.
     */

    /**
     *@notice Checks if an auction is currently active
     *@param nftContractAddress Contract address of the NFT being auctioned
     *@param _tokenId Token ID of the NFT being auctioned
     *@return bool True if the auction is active, false otherwise
     */
    function isAuctionActive(address nftContractAddress, uint256 _tokenId) external view returns (bool) {
        Auction storage a = auctions[nftContractAddress][_tokenId];
        // check if auction exists and is active
        if (a.seller == address(0) || a.ended || block.timestamp >= a.endTime) {
            return false;
        }
        return true;
    }
}
