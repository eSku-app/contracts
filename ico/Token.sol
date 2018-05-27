pragma solidity ^0.4.20;

import "utils/Owned.sol";
import "utils/ERC20Token.sol";

contract TokenNoDecimals is Owned, ERC20Token
{
    string public symbol;
    string public name;
    uint256 _totalSupply;
 
    // Balances for each account
    mapping(address => uint256) public balances;
 
    // Owner of account approves the transfer of an amount to another account
    mapping(address => mapping (address => uint256)) allowed;
 
    // Constructor
    function TokenNoDecimals (
        string _symbol,
        string _name,
        uint256 initialSupply
    )
        public
    {
        symbol = _symbol;
        name = _name;
        _totalSupply = initialSupply;
        balances[owner] = _totalSupply;
    }
 
    function totalSupply()
        public
        constant
        returns (
            uint256
        )
    {
        return _totalSupply;
    }
 
    // What is the balance of a particular account?
    function balanceOf (
        address _owner
    )
        public
        constant
        returns (
            uint256
        )
    {
        return balances[_owner];
    }
 
    // Transfer the balance from owner's account to another account
    function transfer (
        address _to,
        uint256 _amount
    )
        public
        returns (
            bool success
        )
    {
        require(balances[msg.sender] >= _amount);
        require(_amount > 0);
        require(balances[_to] + _amount > balances[_to]);

        balances[msg.sender] -= _amount;
        balances[_to] += _amount;
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    // Send _value amount of tokens from address _from to address _to
    function transferFrom (
        address _from,
        address _to,
        uint256 _amount
    )
        public
        returns (
            bool success
        )
    {
        require(balances[_from] >= _amount);
        require(allowed[_from][msg.sender] >= _amount);
        require(_amount > 0);
        require(balances[_to] + _amount > balances[_to]);

        balances[_from] -= _amount;
        allowed[_from][msg.sender] -= _amount;
        balances[_to] += _amount;
        emit Transfer(_from, _to, _amount);
        return true;
    }
 
    // Allow _spender to withdraw from your account, multiple times, up to the _value amount.
    // If this function is called again it overwrites the current allowance with _value.
    function approve (
        address _spender,
        uint256 _amount
    )
        public
        returns (
            bool success
        )
    {
        allowed[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }
 
    function allowance (
        address _owner,
        address _spender
    ) 
        public
        constant
        returns (
            uint256 remaining
        )
    {
        return allowed[_owner][_spender];
    }
}

// This is broken out to show that functionality works with/without decimals
contract Token is TokenNoDecimals
{
    uint8 public decimals;
    
    function Token (
        string _symbol, 
        string _name, 
        uint8 _decimals,
        uint256 initialSupply
    )
        public
        TokenNoDecimals(_symbol, _name, initialSupply * (10**uint256(_decimals)))
    {
        decimals = _decimals;
    }
}
