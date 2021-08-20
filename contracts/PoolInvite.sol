// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;
import '@openzeppelin/contracts/math/SafeMath.sol';

contract PoolInvite {
    using SafeMath for uint256;
    
    struct InviteRelation {
        address a;
        address b;
        uint256 createdAt;
    }
    
    struct InviteWho {
        address addr;
        uint256 createdAt;
    }
    
    // 被邀请人 => 邀请人
    mapping(address => InviteWho) public relationships;
    mapping(uint256 => InviteRelation) public inviteRelations;
    uint256 public inviteRelationIndex = 1;
    
    constructor() public {}
    
    function invite(address bind) external {
        require(msg.sender != bind, "bind is yourself");
        require(relationships[msg.sender].addr == address(0), "did invited");
        
        uint256 currentTime = block.timestamp;
        relationships[msg.sender] = InviteWho(bind, currentTime);
        inviteRelations[inviteRelationIndex] = InviteRelation(msg.sender, bind, currentTime);
        inviteRelationIndex = inviteRelationIndex.add(1);
    }
    
    function getRelationShip(address who) view public returns (address, address, uint256, uint256) {
        address a = relationships[who].addr;
        address b = address(0);
        uint256 aTime = relationships[who].createdAt;
        uint256 bTime = 0;
        if (a != address(0)) {
            b = relationships[a].addr;
            bTime = relationships[a].createdAt;
        }
        return (a, b, aTime, bTime);
    }
    
    function getInviteRelationByIndex(uint256 idx) view public returns (address, address, uint256) {
        return (inviteRelations[idx].a, inviteRelations[idx].b, inviteRelations[idx].createdAt);
    }
}
