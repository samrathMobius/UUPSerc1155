const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("OptimizedERC1155", function () {
    let contract;
    let AuctionLibrary, MarketplaceLibrary, auctionLibrary, marketplaceLibrary;
    let owner, user1, user2, attacker, user3, DEFAULT_ADMIN_ROLE;
    let tokenId = 1;
    let mintAmount = 5;
    let tokenURI = "https://example.com/token-metadata.json";

    before(async function () {
        [owner, user1, user2, user3, attacker] = await ethers.getSigners();

        AuctionLibrary = await ethers.getContractFactory("AuctionLibrary");
        auctionLibrary = await AuctionLibrary.deploy();
        
        MarketplaceLibrary = await ethers.getContractFactory("MarketplaceLibrary");
        marketplaceLibrary = await MarketplaceLibrary.deploy();

        const OptimizedERC1155 = await ethers.getContractFactory("OptimizedERC1155",{
            libraries: {
                AuctionLibrary: auctionLibrary.target,
                MarketplaceLibrary: marketplaceLibrary.target,
            },
        });
        contract = await OptimizedERC1155.deploy();
        await contract.initialize(owner.address);
        console.log("UpgradeERc1155 deployed to:", contract.target);
    });

    describe("Contract Initialization", function () {
        it("should set the correct roles", async function () {
            expect(await contract.hasRole(await contract.DEFAULT_ADMIN_ROLE(), owner.address)).to.be.true;
            expect(await contract.hasRole(await contract.UPGRADER_ROLE(), owner.address)).to.be.true;
        });
    });

    describe("Minting", function () {
        it("should mint a new token successfully", async function () {
            await contract.mint(user1.address, mintAmount, tokenURI);
            expect(await contract.balanceOf(user1.address, tokenId)).to.equal(mintAmount);
        });

        it("should not allow minting to blacklisted users", async function () {
            await contract.addToBlacklist(user1.address);
            await expect(contract.mint(user1.address, 1, tokenURI)).to.be.revertedWith("User is blacklisted");
            await contract.removeFromBlacklist(user1.address);
        });
    });

    describe("Listing NFTs for Sale", function () {
        it("should allow listing for sale", async function () {
            await contract.connect(user1).listForSale(tokenId, ethers.parseEther("1"), 2);
            // Verify that the contract holds the NFT
            expect(await contract.balanceOf(contract.target, tokenId)).to.equal(2);
        });

        it("should not allow listing without enough balance", async function () {
            await expect(contract.connect(user2).listForSale(tokenId, ethers.parseEther("1"), 10))
                .to.be.revertedWith("Insufficient tokens");
        });
    });

    describe("Buying NFTs", function () {
        it("should allow buying an NFT", async function () {
            await contract.connect(user2).buyNFT(tokenId, 1, {  value: ethers.parseUnits('1', 'ether')});
            expect(await contract.balanceOf(user2.address, tokenId)).to.equal(1);
        });

        it("should not allow buying with insufficient ETH", async function () {
            await expect(contract.connect(user2).buyNFT(tokenId, 1, {  value: ethers.parseUnits('0.5', 'ether')}))
                .to.be.revertedWith("Incorrect price");
        });

        it("should not allow buying if blacklisted", async function () {
            await contract.addToBlacklist(user2.address);
            await expect(contract.connect(user2).buyNFT(tokenId, 1, {  value: ethers.parseUnits('1', 'ether')}))
                .to.be.revertedWith("User is blacklisted");
            await contract.removeFromBlacklist(user2.address);
        });
    });

    describe("Auction", function () {
        it("should start an auction successfully", async function () {
            await contract.connect(user1).startAuction(tokenId, 1, ethers.parseEther("1"), 300);
        });

        it("should not allow starting an auction without enough tokens", async function () {
            await expect(contract.connect(user2).startAuction(tokenId, 2, ethers.parseEther("1"), 300))
                .to.be.revertedWith("Insufficient tokens");
        });

        it("should refund previous bidder when a higher bid is placed", async function () {
            const initialBalanceUser2 = await ethers.provider.getBalance(user2.address);
    
            // user2 places initial bid
            await contract.connect(user2).placeBid(1, 1, ethers.parseEther("2"),  {  value: ethers.parseUnits('2', 'ether')});

            // user3 places a higher bid
            const initialBalanceUser3 = await ethers.provider.getBalance(user3.address);
            await contract.connect(user3).placeBid(1, 1, ethers.parseEther("3"), { value: ethers.parseUnits('3', 'ether')});
    
            // Check user2 got refunded
            const finalBalanceUser2 = await ethers.provider.getBalance(user2.address);
            expect(finalBalanceUser2).to.be.closeTo(initialBalanceUser2, ethers.parseEther("2")); // Check refund
    
            // Ensure user3's balance decreased correctly
            const finalBalanceUser3 = await ethers.provider.getBalance(user3.address);
            expect(finalBalanceUser3).to.be.closeTo(initialBalanceUser3 - (ethers.parseEther("3")), ethers.parseEther("0.01")); // Account for gas
        });

        it("should not allow placing a lower bid", async function () {
            await expect(contract.connect(attacker).placeBid(1, 1, ethers.parseEther("0.5"),  {  value: ethers.parseUnits('0.5', 'ether')}))
                .to.be.revertedWith("Bid per NFT too low");
        });

        it("should allow ending an auction successfully", async function () {
            await ethers.provider.send("evm_increaseTime", [301]);
            await ethers.provider.send("evm_mine");

            await contract.connect(user1).endAuction(1);
        });
    });

    describe("Blacklisting", function () {

        it("should mint a new token successfully", async function () {
            await contract.mint(attacker.address, mintAmount, tokenURI);
            expect(await contract.balanceOf(attacker.address, 2)).to.equal(mintAmount);
        });

        it("should blacklist a user successfully", async function () {
            await contract.addToBlacklist(attacker.address);
            expect(await contract.blacklisted(attacker.address)).to.equal(true);
        });


        it("should not allow blacklisted user to list an NFT", async function () {
            await expect(contract.connect(attacker).listForSale(2, ethers.parseEther("1"), 1))
                .to.be.revertedWith("User is blacklisted");
        });

        it("should remove a user from the blacklist successfully", async function () {
            await contract.removeFromBlacklist(attacker.address);
            expect(await contract.blacklisted(attacker.address)).to.equal(false);
        });
    });
    
    describe("Pause", function () {

        it("Should prevent non-owners from pausing the contract", async function () {
            await expect(contract.connect(user1).pause())
            .to.be.revertedWithCustomError(contract, "AccessControlUnauthorizedAccount");
          });
          

        it("should pause contract and prevent actions", async function () {
            await contract.connect(owner).pause();
            await expect(contract.mint(user1.address, 1, tokenURI))
            .to.be.revertedWithCustomError(contract, "EnforcedPause")
            .withArgs();
            await contract.unpause();
        });

    });
});
