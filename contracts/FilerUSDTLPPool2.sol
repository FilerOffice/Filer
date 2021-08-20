pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './IERC20Plus.sol';


contract FilerUSDTLPPool2 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct RewardHistory {
        uint256 reward;
        uint256 startTime;
        uint256 endTime;
        uint256 timestamp;
    }

    address public token;
    address public rewardToken;
    address public blackhole;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    uint256 public rewardEpoch = 0;
    mapping(uint256 => RewardHistory) rewardHistoryList;

    uint256 public constant duration0 = 30 minutes; //抵押缓存时间（这段时间没有奖励）
    uint256 public constant DURATION = 2 hours; //正常周期时间

    uint256 public periodFinish0 = 0;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    
    uint256 public notifyEpoch = 0;
    uint256 public lastDuratuonEpoch = 0;
    
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        address _rewardToken,
        address _token,
        uint256 _startTime
    ) public {
        // 项目方 0x3fc71e207705C271fb3CA974A69279723A2f96b5
        rewardToken = _rewardToken;
        token = _token;
        starttime = _startTime;

        require(starttime.add(duration0) > block.timestamp, "pool: periodFinish can not > now");
        lastUpdateTime = starttime;
        periodFinish = starttime.add(duration0);
        periodFinish0 = periodFinish;
    }

    //=============== modifier ===============//
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    modifier checkStart() {
        require(block.timestamp >= starttime, 'pool: not start');
        _;
    }

    function startTime() public view returns (uint256) {
        return starttime;
    }
    
    function isPeriodFinished() public view returns (bool) {
        return block.timestamp >= periodFinish;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function lastUpdateTimeOK() public view returns (uint256) {
        return Math.max(lastUpdateTime, periodFinish - DURATION);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTimeOK())
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount)
        public
        updateReward(msg.sender)
        checkStart
    {
        require(amount > 0, 'Cannot stake 0');
        
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        updateReward(msg.sender)
    {
        require(amount > 0, 'Cannot withdraw 0');
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            IERC20(rewardToken).safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    //history of reward
    function getRewardHistory(uint256 epoch_) public view returns (uint256, uint256, uint256, uint256) {
        return (rewardHistoryList[epoch_].reward,
            rewardHistoryList[epoch_].startTime,
            rewardHistoryList[epoch_].endTime,
            rewardHistoryList[epoch_].timestamp);
    }

    function canNotifyReward() public view returns(bool) {
        return block.timestamp > starttime && block.timestamp > periodFinish0;
    }
    
    function getDurationEpoch() public view returns (uint256) {
        if (block.timestamp < periodFinish0) { 
            return 0;
        }
        return block.timestamp.sub(periodFinish0).div(DURATION).add(1);
    }
    
    /// 检查是否符合 notify 
    function checkNotifyEpoch() public view returns (bool) {
        return getDurationEpoch() > lastDuratuonEpoch;
    }

    function notifyRewardAmount(uint256 reward)
        external
        onlyOwner
        updateReward(address(0))
    {
        //过了抵押缓冲区才可以通知奖励
        if (canNotifyReward() && checkNotifyEpoch()) {
            if (block.timestamp >= periodFinish) {
                rewardRate = reward.div(DURATION);
            } else {
                uint256 remaining = periodFinish.sub(block.timestamp);
                uint256 leftover = remaining.mul(rewardRate);
                rewardRate = reward.add(leftover).div(DURATION);
            }
            lastUpdateTime = block.timestamp;
            periodFinish = block.timestamp.add(DURATION);

            rewardEpoch = rewardEpoch.add(1);
            RewardHistory memory r = RewardHistory({
                reward: reward,
                startTime: block.timestamp,
                endTime: periodFinish,
                timestamp: block.timestamp
            });
            rewardHistoryList[rewardEpoch] = r;

            lastDuratuonEpoch = getDurationEpoch();

            //动态铸币
            IERC20Plus(rewardToken).mint(address(this), reward);
            
            emit RewardAdded(reward);
        }
    }
}