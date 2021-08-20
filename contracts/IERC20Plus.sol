pragma solidity ^0.6.0;

interface IERC20Plus {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}