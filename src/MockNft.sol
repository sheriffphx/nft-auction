//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNft is ERC721 {
    uint256 private tokenIdCounter = 0;
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address _to) external returns(uint256){
        tokenIdCounter++;
        _safeMint(_to, tokenIdCounter);
        return tokenIdCounter;
    }
}
