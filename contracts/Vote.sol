// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import './IERC20Plus.sol';

contract Vote is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    enum ProposalType {
        Airdrop,    // 空投
        Repurchase, // 回购
        FILRate     // FIL比例
    }
    
    // struct ProposalChangeFee {
    //     uint256 newFee;
    // }
    
    struct Proposal {
        ProposalType cType;
        string note;
        string en_note;
        uint256 startTime;
        uint256 endTime;
        uint256 reward;
        uint256 createTime;
        uint256 yesVotesSize;
        uint256 noVotesSize;
        uint256 result; // 0 => unconfirm, 1 => yes, 2 => no
        mapping(address => uint256) perVotes; 
        mapping(address => bool) alreadyReceived;
    }
    
    mapping(uint256 => Proposal) private proposals;
    // mapping(uint256 => ProposalChangeFee) private proposalsChangeFee;
    
    uint256 public proposalIndex = 0;
    uint256 public currentProposalIndex = 0;
    uint256 public oneTicket = 1 * 10 ** 18;
    
    
    // uint256 public currentFee;
    
    // vote
    address public token;
    // reward
    address public rewardToken;
    
    constructor(address _token, address _rewardToken) public {
        token = _token;
        rewardToken = _rewardToken;
    }
    
    function addProposal(
            uint256 validIndex,
            ProposalType aType,
            string memory _note,
            string memory _en_note,
            uint256 _startTime,
            uint256 _endTime,
            uint256 _reward
        ) public onlyOwner {
        require(_reward > 0, "reward must > 0");
        require(_endTime > _startTime, "endTime > startTime");
        require(currentProposalIndex == 0, "proposal exist");
        require(validIndex == proposalIndex.add(1), "valid index error");
        // require(_newFee > 0, "new fee must > 0");
        
        Proposal memory _new = Proposal(
            aType,
            _note,
            _en_note,
            _startTime,
            _endTime,
            _reward,
            block.timestamp,
            0,
            0,
            0
        );
        // ProposalChangeFee memory _newChangeFee = ProposalChangeFee(_newFee);
        
        proposalIndex = proposalIndex.add(1);
        
        proposals[proposalIndex] = _new;
        // proposalsChangeFee[proposalIndex] = _newChangeFee;
        
        currentProposalIndex = proposalIndex;
    }
    
    function vote(uint256 count, bool flag) public {
        require(count > 0, "amount must > 0");
        require(currentProposalIndex > 0, "currentProposalIndex > 0");
        require(proposals[currentProposalIndex].endTime > block.timestamp, "current proposal is end");
        if (flag) {
            proposals[currentProposalIndex].yesVotesSize = proposals[currentProposalIndex].yesVotesSize.add(count);
        } else {
            proposals[currentProposalIndex].noVotesSize = proposals[currentProposalIndex].noVotesSize.add(count);
        }
        proposals[currentProposalIndex].perVotes[msg.sender] = (proposals[currentProposalIndex].perVotes[msg.sender]).add(count.mul(oneTicket));
        
        // transfer
        IERC20(token).safeTransferFrom(msg.sender, address(this), count.mul(oneTicket));
    }
    
    function getMyVotesCount(uint256 idx) public view returns (uint256) {
        return proposals[idx].perVotes[msg.sender];
    }
    
    function confirm() external onlyOwner {
        require(currentProposalIndex > 0, "currentProposalIndex <= 0");
        require(proposals[currentProposalIndex].endTime < block.timestamp, "assert endTime");
        
        Proposal memory item = proposals[currentProposalIndex];
        uint256 _totalVoteSize = item.yesVotesSize.add(item.noVotesSize);
        uint256 _halfVoteSize = _totalVoteSize.div(2);
        if (item.yesVotesSize > _halfVoteSize) {
            proposals[currentProposalIndex].result = 1; ///< yes
        } else {
            proposals[currentProposalIndex].result = 2; ///< no
        }
        
        /// do other something
        // if (item.cType == ProposalType.ChangeFee && proposals[currentProposalIndex].result == 1) {
            // _changeFee();
        // }
        
        currentProposalIndex = 0;
    }
    
    // function _changeFee() internal {
    //     currentFee = proposalsChangeFee[currentProposalIndex].newFee;
    // }

    function getProposalByIndex(uint256 idx) public view returns (
        ProposalType,
        string memory,
        string memory,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
        ) {
        Proposal memory item = proposals[idx];
        return (
            item.cType,
            item.note,
            item.en_note,
            item.startTime,
            item.endTime,
            item.createTime,
            item.reward,
            item.yesVotesSize,
            item.noVotesSize,
            item.result
            );
    }
    
    // function getChangeFeeProposalByIndex(uint256 idx) public view returns (uint256) {
    //     return proposalsChangeFee[idx].newFee;
    // }
    
    function editProposal(uint256 _idx, string memory _note, string memory _en_note) public onlyOwner {
        // require(proposals[currentProposalIndex].startTime > block.timestamp, "proposal did start");
        require(_idx <= proposalIndex && _idx > 0, "no find");
        proposals[_idx].note = _note;
        proposals[_idx].en_note = _en_note;
    }
    
    modifier checkSettlement(uint256 _idx) {
        require(_idx <= proposalIndex && _idx > 0, "no find");
        require(proposals[_idx].result != 0, "need markEnd");
        _;
    }
    
    function exchangeAllReward(uint256 _proposalIdx) public checkSettlement(_proposalIdx) {
        // asset no received
        require(proposals[_proposalIdx].alreadyReceived[msg.sender] == false, "already received");
        
        // myVote and myReward 
        (uint256 myVoteAmount, uint256 myReward) = _calcReward(_proposalIdx, msg.sender);
        
        // transfer
        IERC20(token).transfer(msg.sender, myVoteAmount);
        // IERC20(rewardToken).transfer(msg.sender, myReward);
        IERC20Plus(rewardToken).mint(msg.sender, myReward);
        
        // make already received
        proposals[_proposalIdx].alreadyReceived[msg.sender] = true;
    }
    
    function _calcReward(uint256 _proposalIdx, address who) internal view returns (uint256, uint256) {
        // myVoteSize / totalVote * reward
        uint256 totalVote = proposals[_proposalIdx].yesVotesSize.add(proposals[_proposalIdx].noVotesSize);
        if (totalVote <= 0) { return (0, 0); }
        uint256 myVoteAmount = proposals[_proposalIdx].perVotes[who];
        uint256 myReward = myVoteAmount.mul(proposals[_proposalIdx].reward).div(totalVote.mul(oneTicket));
        return (myVoteAmount, myReward);
    }
    
    function getMyVoteInfo(uint256 _proposalIdx, address who) public view returns (uint256, uint256, uint256, bool) {
        uint256 myVoteCount = proposals[_proposalIdx].perVotes[who].div(oneTicket);
        (uint256 myVoteAmount, uint256 myReward) = _calcReward(_proposalIdx, who);
        bool can = proposals[_proposalIdx].alreadyReceived[who] == false;
        return (myVoteCount, myVoteAmount, myReward, can);
    }
}