// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import './utils/ContractGuard.sol';
import './utils/Epoch.sol';
// import './interfaces/IEIP20.sol';
import './IERC20Plus.sol';

contract SwapFIL is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct History {
        address account;
        uint256 amount;
        string  dest; //FIL address
        string  txID; //FIL Tx ID
        uint256 actual;
        uint256 fee;
        uint256 status;
        uint256 timestamp;
        uint256 userIndex;
    }

    address public token;
    uint256 public swapFee = 2;

    uint256 public swapCount;
    mapping (uint256 => History) swapHistory;

    mapping (address => mapping (uint256 => History)) yourSwapHistory;
    mapping (address => uint256) yourSwapCount;

    constructor(address token_) public {
        token = token_;
    }

    event Swap(address account, uint256 amount);

    //set
    //@fee: fee/1000
    function setFee(uint256 fee_) public onlyOwner {
        swapFee = fee_;
    } 

    //================== view =======================//

    //user
    function getYourCount(address account_) public view returns(uint256) {
        return yourSwapCount[account_];
    }

    function getYourHistory1(address account_, uint256 nonce_) public view returns(address,uint256, uint256, uint256, uint256, uint256) {
        return (
            yourSwapHistory[account_][nonce_].account,
            yourSwapHistory[account_][nonce_].amount,
            yourSwapHistory[account_][nonce_].actual,
            yourSwapHistory[account_][nonce_].fee,
            yourSwapHistory[account_][nonce_].status,
            yourSwapHistory[account_][nonce_].timestamp
        );
    }

    function getYourHistory2(address account_, uint256 nonce_) public view returns(string memory, string memory) {
        return (yourSwapHistory[account_][nonce_].dest, yourSwapHistory[account_][nonce_].txID);
    }

    //global
    function getCount() public view returns(uint256) {
        return swapCount;
    }

    function getHistory1(uint256 nonce_) public view returns(address, uint256, uint256, uint256, uint256, uint256) {
        return (
            swapHistory[nonce_].account,
            swapHistory[nonce_].amount,
            swapHistory[nonce_].actual,
            swapHistory[nonce_].fee,
            swapHistory[nonce_].status,
            swapHistory[nonce_].timestamp
        );
    }

    function getHistory2(uint256 nonce_) public view returns(string memory, string memory) {
        return (swapHistory[nonce_].dest, swapHistory[nonce_].txID);
    }

    //@status_: 2(agree)||3(refuse)
    function confirm(uint256 nonce_, uint256 status_, string memory txID_) external onlyOwner {
        require(status_ == 2 || status_ == 3, "SwapFIL: invalid status");
        require(swapHistory[nonce_].status == 1, "SwapFIL: invalid nonce");
        uint256 amount = swapHistory[nonce_].amount;
        address account = swapHistory[nonce_].account;
        uint256 userIndex = swapHistory[nonce_].userIndex;

        if (status_ == 2) {
            //agree
            IERC20Plus(token).burn(address(this), amount);
        } else if (status_ == 3) {
            //refuse
            IERC20(token).safeTransfer(account, amount);
        } else {
            return;
        }

        swapHistory[nonce_].status = status_;
        swapHistory[nonce_].txID = txID_;
        yourSwapHistory[account][userIndex].status = status_;
        yourSwapHistory[account][userIndex].txID = txID_;
    }

    function swap(string memory dest, uint256 amount) external {
        require(amount > 0, "Swap: amount must > 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 fee = amount.mul(swapFee).div(1000);
        uint256 actual = amount.sub(fee);

        swapCount = swapCount.add(1);
        yourSwapCount[msg.sender] = yourSwapCount[msg.sender].add(1);

        uint256 yCount = yourSwapCount[msg.sender];
        History memory record = History({
            account: msg.sender,
            amount: amount,
            dest: dest,
            txID: "",
            actual: actual,
            fee: fee,
            status: 1,
            timestamp: block.timestamp,
            userIndex: yCount
        });
        swapHistory[swapCount] = record;
    
        yourSwapHistory[msg.sender][yCount] = record;

        emit Swap(msg.sender, amount);
    }
}