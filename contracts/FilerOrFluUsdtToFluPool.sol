pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./IPoolInvite.sol";

contract FilerOrFluUsdtToFluPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    IERC20 public token;

    uint256 public maxPeriod = 36;
    uint256 public constant DURATION = 28 days;
    // uint256 public initreward = 84375 * 10**18; //Shares
    uint256 public starttime; // starttime
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public currentPeriod = 0;
    uint256 public initReward = 0;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public circulation;

    uint256 public aFeeRate = 10;
    uint256 public bFeeRate = 5;

    /// 合伙人账户
    address public partnerAddr;

    struct RewardHistory {
        address who;
        uint256 whoAmount;
        address a;
        uint256 aAmount;
        address b;
        uint256 bAmount;
        address partnerAddr;
        uint256 partnerAmount;
        uint256 createTime;
    }

    address public invitePool;

    mapping(uint256 => RewardHistory) public rewardHistoryList;
    uint256 public rewardHistoryIndex = 0;

    struct AllocateRewardHistory {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
    }
    mapping(uint256 => AllocateRewardHistory) public allocateRewardHistoryList;
    uint256 public allocateRewardHistoryIndex = 0;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        address rewardToken_,
        address token_,
        uint256 initReward_,
        uint256 starttime_,
        address _invitePool,
        address _partnerAddr
    ) public {
        rewardToken = IERC20(rewardToken_);
        token = IERC20(token_);
        starttime = starttime_;
        initReward = initReward_;
        invitePool = _invitePool;
        partnerAddr = _partnerAddr;

        uint256 _reward = nextAllocateReward();
        rewardRate = _reward.div(DURATION);
        lastUpdateTime = starttime;
        periodFinish = starttime.add(DURATION);
        circulation = circulation.add(_reward);
        allocateRewardHistoryIndex = allocateRewardHistoryIndex.add(1);
        allocateRewardHistoryList[
            allocateRewardHistoryIndex
        ] = AllocateRewardHistory(_reward, block.timestamp, periodFinish);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function setStartTime(uint256 starttime_) public onlyOwner {
        starttime = starttime_;
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

    function stake(uint256 amount)
        public
        updateReward(msg.sender)
        checkhalve
        checkStart
    {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        updateReward(msg.sender)
        checkhalve
    {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        claimReward();
    }

    function claimReward() public updateReward(msg.sender) checkhalve {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            (address a, address b) = IPoolInvite(invitePool).getRelationShip(
                msg.sender
            );
            uint256 aFee = 0;
            uint256 bFee = 0;
            uint256 actual = reward;
            uint256 partnerDividend = 0;

            // 没有绑定推荐关系
            if (a == address(0)) {
                // 合伙人拿走15%
                partnerDividend = reward.mul(aFeeRate.add(bFeeRate)).div(100);
                actual = actual.sub(partnerDividend);
                rewardToken.safeTransfer(partnerAddr, partnerDividend);
            
            // 绑定了上级, 但是没有绑定上上级, 合伙人拿走5%
            } else if (a != address(0) && b == address(0)) {
                aFee = reward.mul(aFeeRate).div(100);
                partnerDividend = reward.mul(bFeeRate).div(100);
                actual = actual.sub(aFee).sub(partnerDividend);
                
                /// 合伙人拿走5%, 上级拿走10%
                rewardToken.safeTransfer(partnerAddr, partnerDividend);
                rewardToken.safeTransfer(a, aFee);
            
            // 绑定了上级, 也绑定了上上级
            } else if (a != address(0) && b != address(0)) {
                aFee = reward.mul(aFeeRate).div(100);
                bFee = reward.mul(bFeeRate).div(100);
                actual = actual.sub(aFee).sub(bFee);
                rewardToken.safeTransfer(a, aFee);
                rewardToken.safeTransfer(b, bFee);
            }

            rewardToken.safeTransfer(msg.sender, actual);
            rewards[msg.sender] = 0;


            /// 没有上级分成
            // if (a == address(0) && b == address(0)) {
            //     partnerDividend = reward.mul(aFeeRate.add(bFeeRate)).div(100);
            //     actual = actual.sub(partnerDividend);
            //     rewardToken.safeTransfer(partnerAddr, partnerDividend);
            // } else {
            //     if (a != address(0)) {
            //         aFee = reward.mul(aFeeRate).div(100);
            //         actual = actual.sub(aFee);
            //         rewardToken.safeTransfer(a, aFee);
            //     }
            //     if (b != address(0)) {
            //         bFee = reward.mul(bFeeRate).div(100);
            //         actual = actual.sub(bFee);
            //         rewardToken.safeTransfer(b, bFee);
            //     }
            // }
            // rewardToken.safeTransfer(msg.sender, actual);
            // rewards[msg.sender] = 0;

            RewardHistory memory r = RewardHistory({
                who: msg.sender,
                whoAmount: actual,
                a: a,
                aAmount: aFee,
                b: b,
                bAmount: bFee,
                partnerAddr: partnerAddr,
                partnerAmount: partnerDividend,
                createTime: block.timestamp
            });
            rewardHistoryIndex = rewardHistoryIndex.add(1);
            rewardHistoryList[rewardHistoryIndex] = r;

            emit RewardPaid(msg.sender, reward);
        }
    }

    function getRewardHistoryItem(uint256 idx)
        public
        view
        returns (
            address,
            uint256,
            address,
            uint256,
            address,
            uint256,
            address,
            uint256,
            uint256
        )
    {
        RewardHistory memory x = rewardHistoryList[idx];
        return (
            x.who,
            x.whoAmount,
            x.a,
            x.aAmount,
            x.b,
            x.bAmount,
            x.partnerAddr,
            x.partnerAmount,
            x.createTime
        );
    }

    function getAllocateRewardHistoryItem(uint256 idx)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            allocateRewardHistoryList[idx].amount,
            allocateRewardHistoryList[idx].startTime,
            allocateRewardHistoryList[idx].endTime
        );
    }

    modifier checkhalve() {
        if (canHalve()) {
            uint256 reward = nextAllocateReward();
            rewardRate = reward.div(DURATION);
            periodFinish = block.timestamp.add(DURATION);
            currentPeriod = currentPeriod.add(1);

            allocateRewardHistoryIndex = allocateRewardHistoryIndex.add(1);
            allocateRewardHistoryList[
                allocateRewardHistoryIndex
            ] = AllocateRewardHistory(reward, block.timestamp, periodFinish);

            circulation = circulation.add(reward);

            emit RewardAdded(reward);
        }
        _;
    }

    function canHalve() public view returns (bool) {
        return
            block.timestamp >= starttime &&
            block.timestamp >= periodFinish &&
            currentPeriod < maxPeriod;
    }

    function setAFeeRate(uint256 _aRate)
        external
        onlyOwner
        returns (uint256, uint256)
    {
        require(_aRate >= 0 && _aRate <= 100, "val must 0 ~ 100");
        require(_aRate.add(bFeeRate) <= 100, "total rate must <= 100");
        aFeeRate = _aRate;
        return (aFeeRate, bFeeRate);
    }

    function setBFeeRate(uint256 _bRate)
        external
        onlyOwner
        returns (uint256, uint256)
    {
        require(_bRate >= 0 && _bRate <= 100, "val must 0 ~ 100");
        require(_bRate.add(aFeeRate) <= 100, "total rate must <= 100");
        bFeeRate = _bRate;
        return (aFeeRate, bFeeRate);
    }

    function nextAllocateReward() public view returns (uint256) {
        return initReward.mul(9**currentPeriod).div(10**currentPeriod);
    }

    function updatePeriod() public checkhalve() {}

    modifier checkStart() {
        require(block.timestamp >= starttime, "not start");
        _;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
}
