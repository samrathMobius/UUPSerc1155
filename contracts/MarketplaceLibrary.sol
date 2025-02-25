// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library MarketplaceLibrary {
    struct SaleListing {
        address seller;
        uint256 price;
        uint256 amount;
    }

    struct MarketplaceStorage {
        mapping(uint256 => SaleListing) listings;
    }

    event ListedForSale(address indexed seller, uint256 tokenId, uint256 price, uint256 amount);
    event Purchased(address indexed buyer, uint256 tokenId, uint256 amount, uint256 price);
    event ListingRemoved(uint256 tokenId);

    function listForSale(
        MarketplaceStorage storage self,
        uint256 tokenId,
        uint256 pricePerNFT,
        uint256 amount,
        address seller
    ) internal {
        require(pricePerNFT > 0, "Price must be greater than 0");
        require(amount > 0, "Invalid amount");

        self.listings[tokenId] = SaleListing({ seller: seller, price: pricePerNFT, amount: amount });

        emit ListedForSale(seller, tokenId, pricePerNFT, amount);
    }

    function buyNFT(
        MarketplaceStorage storage self,
        uint256 tokenId,
        uint256 amount,
        address buyer,
        uint256 paymentValue
    ) external returns (address seller, uint256 price) {
        SaleListing storage listing = self.listings[tokenId];
        require(listing.seller != address(0), "Token not listed for sale");
        require(amount > 0 && amount <= listing.amount, "Invalid amount");
        require(paymentValue == listing.price * amount, "Incorrect price");

        seller = listing.seller;
        price = listing.price * amount;

        // If all NFTs are sold, remove the listing
        if (listing.amount == amount) {
            delete self.listings[tokenId];
        } else {
            listing.amount -= amount;
        }

        emit Purchased(buyer, tokenId, amount, price);
    }

    function removeListing(MarketplaceStorage storage self, uint256 tokenId, address sender) external {
        require(self.listings[tokenId].seller == sender, "Not the seller");

        delete self.listings[tokenId];

        emit ListingRemoved(tokenId);
    }
}
