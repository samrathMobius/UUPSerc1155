// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library AuctionLibrary {
    struct Auction {
        address seller;
        uint256 tokenId;
        uint256 amount;
        uint256 highestBidPerNFT;
        address highestBidder;
        mapping(address => uint256) userBids;
        mapping(address => uint256) userBidAmounts;
        uint256 endTime;
        bool ended;
    }

    struct AuctionStorage {
        mapping(uint256 => Auction) auctions;
        uint256 auctionCounter;
    }

    event AuctionStarted(uint256 indexed auctionId, address seller, uint256 tokenId, uint256 amount, uint256 startingPrice, uint256 endTime);
    event BidPlaced(uint256 indexed auctionId, address bidder, uint256 amount, uint256 bidPerNFT);
    event AuctionEnded(uint256 indexed auctionId, address winner, uint256 highestBidPerNFT, uint256 totalAmountWon);

    function startAuction(
        AuctionStorage storage self,
        uint256 tokenId,
        uint256 amount,
        uint256 startingPricePerNFT,
        uint256 duration,
        address seller
    ) external returns (uint256) {
        require(amount > 0, "Invalid amount");
        require(startingPricePerNFT > 0, "Starting price must be > 0");
        require(duration > 0, "Invalid duration");

        self.auctionCounter++;
        Auction storage auction = self.auctions[self.auctionCounter];
        auction.seller = seller;
        auction.tokenId = tokenId;
        auction.amount = amount;
        auction.highestBidPerNFT = startingPricePerNFT;
        auction.endTime = block.timestamp + duration;

        emit AuctionStarted(self.auctionCounter, seller, tokenId, amount, startingPricePerNFT, auction.endTime);
        return self.auctionCounter;
    }

    function placeBid(
        AuctionStorage storage self,
        uint256 auctionId,
        uint256 bidAmount,
        uint256 bidPerNFT,
        address bidder,
        uint256 bidValue
    ) external {
        Auction storage auction = self.auctions[auctionId];
        require(block.timestamp < auction.endTime, "Auction ended");
        require(bidAmount > 0 && bidAmount <= auction.amount, "Invalid bid amount");
        require(bidPerNFT > auction.highestBidPerNFT, "Bid per NFT too low");
        require(bidValue == bidAmount * bidPerNFT, "Incorrect bid value");

        if (auction.highestBidder != address(0)) {
            payable(auction.highestBidder).transfer(auction.userBids[auction.highestBidder]);
        }

        auction.highestBidPerNFT = bidPerNFT;
        auction.highestBidder = bidder;
        auction.userBids[bidder] = bidValue;
        auction.userBidAmounts[bidder] = bidAmount;

        emit BidPlaced(auctionId, bidder, bidAmount, bidPerNFT);
    }

    function endAuction(AuctionStorage storage self, uint256 auctionId) external returns (bool, address, uint256, uint256) {
        Auction storage auction = self.auctions[auctionId];
        require(block.timestamp >= auction.endTime, "Auction ongoing");
        require(!auction.ended, "Auction already ended");

        auction.ended = true;

        if (auction.highestBidder != address(0)) {
            return (true, auction.highestBidder, auction.highestBidPerNFT, auction.userBidAmounts[auction.highestBidder]);
        }

        return (false, auction.seller, 0, auction.amount);
    }    
}
