pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract Filer is Ownable {
    using SafeMath for uint256;
    
    struct MintPBRecoding {
        uint256 number;
        uint256 time;
    }
    
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    
    MintPBRecoding[] private _mintPBRecoding;
    
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /// 1PB代表的金额
    uint256 public onePB = 1024 * 1000;
    
    /// 四种预留账户
    address public token0;
    address public token1;
    address public token2;
    address public token3;
    
    /// 四种预留账户的分配比例(总计100)
    uint256 public token0Rate;
    uint256 public token1Rate;
    uint256 public token2Rate;
    uint256 public token3Rate;

    /// 增加的总金额
    uint256 public circulation;
    /// 增发的总PB数量
    uint256 public circulationPB;
    
    constructor(
        address _token0,
        uint256 _rate0,
        address _token1,
        uint256 _rate1,
        address _token2,
        uint256 _rate2,
        address _token3,
        uint256 _rate3
        ) public {

        _name     = "Filer";
        _symbol   = "Filer";
        _decimals = 18;
        
        token0 = _token0;
        token1 = _token1;
        token2 = _token2;
        token3 = _token3;
        
        token0Rate = _rate0;
        token1Rate = _rate1;
        token2Rate = _rate2;
        token3Rate = _rate3;

        // 预留流动性
        _mint(msg.sender, 2 * 10**uint256(_decimals));
        // 默认铸造3PB
        mintPB(3);
    }
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mintPB(uint256 _p) public onlyOwner {
        require(_p > 0, "pb must > 0");
        uint256 amount = _p.mul(onePB).mul(10 ** uint256(_decimals));
        
        uint256 amount0 = amount.mul(token0Rate).div(100);
        uint256 amount1 = amount.mul(token1Rate).div(100);
        uint256 amount2 = amount.mul(token2Rate).div(100);
        uint256 amount3 = amount.sub(amount0).sub(amount1).sub(amount2);
        
        _mint(token0, amount0);
        _mint(token1, amount1);
        _mint(token2, amount2);
        _mint(token3, amount3);

        circulation = circulation.add(amount);
        circulationPB = circulationPB.add(_p);
        
        _mintPBRecoding.push(MintPBRecoding(_p, block.timestamp));
    }

    function setOnePBValue(uint256 newVal_) public onlyOwner {
        require(newVal_ > 0, "newVal > 0");
        onePB = newVal_;
    }

    function pbMintRecodingLength() public view returns (uint256) {
        return _mintPBRecoding.length;
    }
    
    function getPBMintRecodingByIndex(uint256 _idx) public view returns (uint256, uint256) {
        MintPBRecoding memory item = _mintPBRecoding[_idx];
        return (item.number, item.time);
    }
    
    /*
        ERC-20 Protocol
    */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _setupDecimals(uint8 decimals_) internal virtual {
        _decimals = decimals_;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}