pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

contract BaseLPPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address public token;
    
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        // 累加总量
        _totalSupply = _totalSupply.add(amount);
        // 保存新余额
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        // 委托转账
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        // 获取我的余额
        uint256 directorToken = _balances[msg.sender];
        // 确保不超过
        require(
            directorToken >= amount,
            'Pool: withdraw request greater than staked amount'
        );
        // 总量减少
        _totalSupply = _totalSupply.sub(amount);
        // 更新余额
        _balances[msg.sender] = directorToken.sub(amount);
        // 转账
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}