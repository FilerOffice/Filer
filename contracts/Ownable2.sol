import '@openzeppelin/contracts/GSN/Context.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

contract Ownable2 is Context {
    using SafeMath for uint256;

    mapping(address => bool) public owners;
    uint256 public ownerSize;
    
    event OwnershipsChangeds();
    
    constructor() internal {
        owners[_msgSender()] = true;
        ownerSize = ownerSize.add(1);
        emit OwnershipsChangeds();
    }
    
    modifier onlyOwner2() {
        require(owners[_msgSender()], "Ownable2: caller is not the owner");
        _;
    }
    
    function addOwner(address _new) public virtual onlyOwner2 {
        require(_new != address(0), "Ownable2: new owner is the zero address");
        require(owners[_new] == false, "Ownable2: this address alse is owner");
        owners[_new] = true;
        ownerSize = ownerSize.add(1);
        emit OwnershipsChangeds();
    }
    
    function removeOwner(address _owner) public virtual onlyOwner2 {
        require(_owner != address(0), "Ownable2: new owner is the zero address");
        require(owners[_owner] == true, "Ownable2: this address is not owner");
        owners[_owner] = false;
        ownerSize = ownerSize.sub(1);
        emit OwnershipsChangeds();
    }
    
    function isOwner(address own) public view returns (bool) {
        return owners[own];
    }
}