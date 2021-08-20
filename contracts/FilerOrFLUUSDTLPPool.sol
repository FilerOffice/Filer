pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './BaseLPPool.sol';
import './utils/ContractGuard.sol';
import './utils/Epoch.sol';
import './IPoolInvite.sol';

contract FilerOrFLUUSDTLPPool is Ownable, Epoch, BaseLPPool, ContractGuard {
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
    
    struct RewardHistory {
        address who;
        uint256 whoAmount;
        address a;
        uint256 aAmount;
        address b;
        uint256 bAmount;
        uint256 createTime;
    }
    
    IERC20 private rewardToken;
    uint256 public dailyLiquidity;
    mapping(address => Boardseat) private directors;
    BoardSnapshot[] private boardHistory;
    address public invitePool;

    RewardTokenMintRecode[] private rewardMintRecodes;
    
    uint256 public circulation;
    uint256 public largeEpoch = 28;
    
    uint256 public aFeeRate = 10;
    uint256 public bFeeRate = 5;

    /// 合伙人账户
    address public partnerAddr;

    mapping(uint256 => RewardHistory) public rewardHistoryList;
    uint256 public rewardHistoryIndex = 1;
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);
    
    constructor(
        IERC20 _rewardToken,
        address _token,
        uint256 _dailyLiquidity,
        uint256 _startTime,
        uint256 _period,
        address _invitePool
    ) public Epoch(_period, _startTime, 0) {
        rewardToken = _rewardToken;
        token = _token;
        dailyLiquidity = _dailyLiquidity;
        invitePool = _invitePool;

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
            (address a, address b) = IPoolInvite(invitePool).getRelationShip(msg.sender);
            uint256 aFee = 0;
            uint256 bFee = 0;
            uint256 actual = reward;
            // 没有上级, 自然也没有上上级, 则自己直接转到合伙人账户
            // if (a == address(0) && b == address(0)) {
            //     otherFee = reward.mul(aFeeRate.add(bFeeRate)).div(100);
            //     actual = actual.sub(otherFee);
            //     rewardToken.safeTransfer(other, value);
            // } else {
                
            // }
            if (a != address(0)) { 
                aFee = reward.mul(aFeeRate).div(100);
                actual = actual.sub(aFee);
                rewardToken.safeTransfer(a, aFee);
            }
            if (b != address(0)) { 
                bFee = reward.mul(bFeeRate).div(100);
                actual = actual.sub(bFee);
                rewardToken.safeTransfer(b, bFee);
            }
            rewardToken.safeTransfer(msg.sender, actual);
            directors[msg.sender].rewardEarned = 0;

            RewardHistory memory r = RewardHistory({
                who: msg.sender,
                whoAmount: actual,
                a: a,
                aAmount: aFee,
                b: b,
                bAmount: bFee,
                createTime: block.timestamp
            });
            rewardHistoryList[rewardHistoryIndex] = r;
            rewardHistoryIndex = rewardHistoryIndex.add(1);
            
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getRewardHistoryItem(uint256 idx) view public returns (address, uint256, address, uint256, address, uint256, uint256) {
        RewardHistory memory x = rewardHistoryList[idx];
        return (
            x.who,
            x.whoAmount,
            x.a,
            x.aAmount,
            x.b,
            x.bAmount,
            x.createTime
        );
    }
    
    function setAFeeRate(uint256 _aRate) external onlyOwner returns (uint256, uint256) {
        require(_aRate >= 0 && _aRate <= 100, "val must 0 ~ 100");
        require(_aRate.add(bFeeRate) <= 100, "total rate must <= 100");
        aFeeRate = _aRate;
        return (aFeeRate, bFeeRate);
    }
    
    function setBFeeRate(uint256 _bRate) external onlyOwner returns (uint256, uint256) {
        require(_bRate >= 0 && _bRate <= 100, "val must 0 ~ 100");
        require(_bRate.add(aFeeRate) <= 100, "total rate must <= 100");
        bFeeRate = _bRate;
        return (aFeeRate, bFeeRate);
    }
    
    function allocateReward() 
        external
        onlyOneBlock
        checkStartTime
        checkEpoch
    {
        // 90% => 45000*10^18 * 9^2 / 10^2
        uint256 amount = nextAllocateReward();
        rewardMintRecodes.push(RewardTokenMintRecode(block.timestamp, amount, totalSupply()));

        if (amount <= 0) { return; }
        if (totalSupply() <= 0) { return; }

        _allocateReward(amount);

        circulation = circulation.add(amount);
    }

    function nextAllocateReward() public view returns (uint256) {
        uint256 large = currentLargeEpoch();
        return dailyLiquidity.mul(1e18).mul(9 ** large).div(10 ** large);
    }
    
    function currentLargeEpoch() public view returns (uint256) {
        return getCurrentEpoch().div(largeEpoch);
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