pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './BaseLPPool.sol';
import './utils/ContractGuard.sol';
import './utils/Epoch.sol';
import './IERC20Plus.sol';

contract FilerUSDTLPPool is Ownable, Epoch, BaseLPPool, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
    }

    struct BoardSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerToken;
    }
    
    struct RewardTokenMintRecode {
        uint256 time;
        uint256 amount;
        uint256 currentTotalSupply;
    }
    
    RewardTokenMintRecode[] private rewardMintRecodes;
    
    address private rewardToken;
    mapping(address => Boardseat) private directors;
    BoardSnapshot[] private boardHistory;
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    
    constructor(
        address _rewardToken,
        address _token,
        uint256 _startTime,
        uint256 _period
    ) public Epoch(_period, _startTime, 0) {
        rewardToken = _rewardToken;
        token = _token;

        BoardSnapshot memory genesisSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: 0,
            rewardPerToken: 0
        });
        boardHistory.push(genesisSnapshot);
    }
    
    modifier directorExists {
        require(
            balanceOf(msg.sender) > 0,
            'Pool: The director does not exist'
        );
        _;
    }
    
    modifier updateReward(address director) {
        if (director != address(0)) {
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            directors[director] = seat;
        }
        _;
    }
    
    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address director) public view returns (uint256) {
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director) internal view returns (BoardSnapshot memory) {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    function rewardPerToken() public view returns (uint256) {
        return getLatestSnapshot().rewardPerToken;
    }

    function earned(address director) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerToken;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerToken;

        return balanceOf(director).mul(latestRPS.sub(storedRPS)).div(1e18).add(
                directors[director].rewardEarned
            );
    }
    
    function stake(uint256 amount)
        public
        override
        onlyOneBlock
        checkStartTime
        updateReward(msg.sender)
    {
        require(amount > 0, 'Pool: Cannot stake 0');
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }
    
    function withdraw(uint256 amount)
        public
        override
        onlyOneBlock
        directorExists
        updateReward(msg.sender)
    {
        require(amount > 0, 'Pool: Cannot withdraw 0');
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        claimReward();
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = directors[msg.sender].rewardEarned;
        if (reward > 0) {
            directors[msg.sender].rewardEarned = 0;
            IERC20(rewardToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }
    
    function allocateReward(uint256 amount) 
        external
        onlyOneBlock
        checkStartTime
        checkEpoch
        onlyOwner
    {
        rewardMintRecodes.push(RewardTokenMintRecode(block.timestamp, amount, totalSupply()));

        if (amount <= 0) { return; }
        if (totalSupply() <= 0) { return; }
        
        IERC20Plus(rewardToken).mint(address(this), amount);
        
        _allocateReward(amount);
    }
    
    function getRewardMintRecodeSize() public view returns (uint256) {
        return rewardMintRecodes.length;
    }
    
    function getRewardMintRecodeInfoByIndex(uint256 idx) public view returns (uint256, uint256, uint256) {
        RewardTokenMintRecode memory item = rewardMintRecodes[idx];
        return (item.time, item.amount, item.currentTotalSupply);
    }
    
    function _allocateReward(uint256 amount) internal {
        require(amount > 0, 'Pool: Cannot allocate 0');
        require(totalSupply() > 0,'Pool: Cannot allocate when totalSupply is 0');

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerToken;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardSnapshot memory newSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerToken: nextRPS
        });
        boardHistory.push(newSnapshot);

        emit RewardAdded(msg.sender, amount);
    }
}
