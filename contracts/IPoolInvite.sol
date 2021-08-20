pragma solidity ^0.6.0;

interface IPoolInvite {
    function invite(address bind) external;
    function getRelationShip(address who) view external returns (address, address);
}