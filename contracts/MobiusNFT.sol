// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Burnable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import {ERC1155Pausable} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
 * @title MobiusNFT
 * @dev ERC1155 contract with pausable, burnable, and ownable functionalities.
 * Supports NFT and FT minting, marketplace listings, and auctions.
 */
contract MobiusNFT is
    ERC1155,
    Ownable,
    ERC1155Pausable,
    ERC1155Burnable,
    ERC1155Supply,
    ERC1155Holder
{
    // Events
    event Minted(
        address indexed user,
        uint256 tokenId,
        uint256 amount,
        string tokenURI
    );
    event ListedForSale(
        address indexed seller,
        uint256 tokenId,
        uint256 price,
        uint256 amount
    );
    event Purchased(
        address indexed buyer,
        uint256 tokenId,
        uint256 amount,
        uint256 price
    );
    event ListingRemoved(uint256 tokenId);
    event AuctionStarted(
        address indexed seller,
        uint256 auctionId,
        uint256 tokenId,
        uint256 amount,
        uint256 startingPrice,
        uint256 endTime
    );
    event BidPlaced(
        address indexed bidder,
        uint256 auctionId,
        uint256 amount,
        uint256 bidPerNFT
    );
    event AuctionEnded(
        uint256 auctionId,
        address indexed winner,
        uint256 highestBidPerNFT,
        uint256 totalAmountWon
    );
    event UserBlacklisted(address indexed user);
    event UserRemovedFromBlacklist(address indexed user);

    // Mapping for token-specific URIs
    mapping(uint256 => string) private _tokenURIs;

    // Counter for unique token IDs
    uint256 private _tokenID;

    // Struct for sale listings
    struct SaleListing {
        address seller;
        uint256 price;
        uint256 amount;
    }

    // Struct for auction listings
    struct Auction {
        address seller;
        uint256 tokenId;
        uint256 amount;
        uint256 highestBidPerNFT;
        address highestBidder;
        mapping(address => uint256) userBids; // Bids per user
        mapping(address => uint256) userBidAmounts; // Amount of NFTs each bidder bids for
        uint256 endTime;
        bool ended;
    }

    mapping(uint256 => SaleListing) public listings;
    mapping(uint256 => Auction) public auctions;
    mapping(address => bool) public blacklisted;
    uint256 public auctionCounter;

    constructor(address initialOwner) ERC1155("") Ownable(initialOwner) {}
    
    /**
     * @dev Pauses all contract functionalities.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Mints a new token.
     * @param userAddress Recipient of the minted token.
     * @param amount Number of tokens to mint.
     * @param tokenURI URI of the token metadata.
     */
    function mint(
        address userAddress,
        uint256 amount,
        string memory tokenURI
    ) external onlyOwner whenNotPaused {
        require(amount > 0, "Amount should be greater than 0");
        require(!blacklisted[userAddress], "User is blacklisted");

        uint32 size;
        assembly {
            size := extcodesize(userAddress)
        }
        require(size == 0, "Cannot mint to a contract");

        _tokenID++;
        _mint(userAddress, _tokenID, amount, "");

        if (bytes(tokenURI).length > 0) {
            _setTokenURI(_tokenID, tokenURI);
            emit Minted(userAddress, _tokenID, 1, tokenURI);
        } else {
            // If no URI, treat it as a fungible token (FT)
            emit Minted(userAddress, _tokenID, amount, "");
        }
    }
    
    /**
     * @dev Lists an NFT for sale.
     * @param tokenId The ID of the token to be listed.
     * @param pricePerNFT Price per NFT unit.
     * @param amount The amount of tokens to list for sale.
     */
    function listForSale(
        uint256 tokenId,
        uint256 pricePerNFT,
        uint256 amount
    ) external whenNotPaused {
        require(
            balanceOf(msg.sender, tokenId) >= amount,
            "Insufficient tokens"
        );
        require(pricePerNFT > 0, "Price must be greater than 0");
        require(!blacklisted[msg.sender], "User is blacklisted");

        listings[tokenId] = SaleListing({
            seller: msg.sender,
            price: pricePerNFT,
            amount: amount
        });

        safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        emit ListedForSale(msg.sender, tokenId, pricePerNFT, amount);
    }
    
    /**
     * @dev Purchases an NFT.
     * @param tokenId ID of the token to buy.
     * @param amount Amount of tokens to purchase.
     */
    function buyNFT(
        uint256 tokenId,
        uint256 amount
    ) external payable whenNotPaused {
        SaleListing storage listing = listings[tokenId];
        require(listing.seller != address(0), "Token not listed for sale");
        require(amount > 0 && amount <= listing.amount, "Invalid amount");
        require(msg.value == listing.price * amount, "Incorrect price");
        require(!blacklisted[msg.sender], "User is blacklisted");

        payable(listing.seller).transfer(msg.value);

        if (listing.amount == amount) {
            delete listings[tokenId];
        } else {
            listing.amount -= amount;
        }

        _safeInternalTransfer(address(this), msg.sender, tokenId, amount);

        emit Purchased(msg.sender, tokenId, amount, msg.value);
    }

    function removeListing(uint256 tokenId) external whenNotPaused {
        require(listings[tokenId].seller == msg.sender, "Not the seller");
        delete listings[tokenId];

        emit ListingRemoved(tokenId);
    }

    function startAuction(
        uint256 tokenId,
        uint256 amount,
        uint256 startingPricePerNFT,
        uint256 duration
    ) external whenNotPaused {
        require(
            balanceOf(msg.sender, tokenId) >= amount,
            "Insufficient tokens"
        );
        require(startingPricePerNFT > 0, "Price must be greater than 0");
        require(duration > 0, "Invalid duration");
        require(!blacklisted[msg.sender], "User is blacklisted");

        auctionCounter++;
        Auction storage auction = auctions[auctionCounter];
        auction.seller = msg.sender;
        auction.tokenId = tokenId;
        auction.amount = amount;
        auction.highestBidPerNFT = startingPricePerNFT;
        auction.endTime = block.timestamp + duration;
        auction.ended = false;

        safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        emit AuctionStarted(
            msg.sender,
            auctionCounter,
            tokenId,
            amount,
            startingPricePerNFT,
            auction.endTime
        );
    }

    function placeBid(
        uint256 auctionId,
        uint256 bidAmount,
        uint256 bidPerNFT
    ) external payable whenNotPaused {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp < auction.endTime, "Auction ended");
        require(
            bidAmount > 0 && bidAmount <= auction.amount,
            "Invalid bid amount"
        );
        require(bidPerNFT > auction.highestBidPerNFT, "Bid per NFT too low");
        require(msg.value == bidAmount * bidPerNFT, "Incorrect bid amount");
        require(!blacklisted[msg.sender], "User is blacklisted");

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(
                auction.userBids[auction.highestBidder]
            );
        }

        auction.highestBidPerNFT = bidPerNFT;
        auction.highestBidder = msg.sender;
        auction.userBids[msg.sender] = msg.value;
        auction.userBidAmounts[msg.sender] = bidAmount;

        emit BidPlaced(msg.sender, auctionId, bidAmount, bidPerNFT);
    }

    function endAuction(uint256 auctionId) external whenNotPaused {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.endTime, "Auction ongoing");
        require(!auction.ended, "Auction already ended");

        auction.ended = true;

        if (auction.highestBidder != address(0)) {
            uint256 totalAmountWon = auction.userBidAmounts[
                auction.highestBidder
            ];
            _safeTransferFrom(
                address(this),
                auction.highestBidder,
                auction.tokenId,
                totalAmountWon,
                ""
            );
            payable(auction.seller).transfer(
                auction.userBids[auction.highestBidder]
            );

            emit AuctionEnded(
                auctionId,
                auction.highestBidder,
                auction.highestBidPerNFT,
                totalAmountWon
            );
        } else {
            _safeTransferFrom(
                address(this),
                auction.seller,
                auction.tokenId,
                auction.amount,
                ""
            );
        }
    }

    function addToBlacklist(address user) external onlyOwner {
        blacklisted[user] = true;
        emit UserBlacklisted(user);
    }

    function removeFromBlacklist(address user) external onlyOwner {
        blacklisted[user] = false;
        emit UserRemovedFromBlacklist(user);
    }

    function _safeInternalTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) internal {
        require(!blacklisted[from], "Sender blacklisted");
        require(!blacklisted[to], "Recipient blacklisted");
        _safeTransferFrom(from, to, tokenId, amount, "");
    }

    function _setTokenURI(uint256 tokenId, string memory tokenURI) internal {
        _tokenURIs[tokenId] = tokenURI;
    }
    
    /**
     * @dev Fetches the URI of a token.
     * @param tokenId The ID of the token.
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override(ERC1155, ERC1155Pausable, ERC1155Supply) {
        super._update(from, to, ids, values);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155, ERC1155Holder) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
