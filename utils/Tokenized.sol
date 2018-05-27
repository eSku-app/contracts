pragma solidity ^0.4.20;
/*
 * Tokenized - utility class for working with ERC20 tokens
 *
 * @req 1 The 'token' storage variable is set on initialization
 * @req 2 Only the 'maintainer' can reassign the token to a different address
 * @req 3 Inheriting this contract gives access to safe versions of ERC20 calls
 */

import "utils/ERC20Token.sol";
import "utils/Maintained.sol";

contract Tokenized is Maintained
{
    // ERC20 Token we are using for all token-delegated calls
    ERC20Token public token; //ERC20 Compatible

    // @imp 1 Set 'token' at init
    function Tokenized(address _token) public
    {
        token = ERC20Token(_token);
    }

    // @imp 2 Maintainer can change the ERC20 Token we are using
    function setToken(address _token)
        public
        onlyMaintainer()
    {
        token = ERC20Token(_token);
    }

    // @imp 3 Safe calls of ERC20 methods
    function tokenBalanceOf(address account)
        internal constant
        returns (uint256)
    {
        return token.balanceOf(account);
    }

    // @imp 3 Safe calls of ERC20 methods
    function tokenAllowance(address account, address spender)
        internal constant
        returns (uint256)
    {
        return token.allowance(account, spender);
    }

    // @imp 3 Safe calls of ERC20 methods
    function tokenApprove(address spender, uint256 amount)
        internal
    {
        // Require success
        assert(token.approve(spender, amount));
    }

    // @imp 3 Safe calls of ERC20 methods
    function tokenTransferFrom(address _from, address _to, uint256 _amount)
        internal
    {
        // Must have an allowance set (duplicates code, but stronger guarentee)
        require(tokenAllowance(_from, this) >= _amount);
        // Skip if no amount is being sent
        // Require success
        if (_amount > 0) assert(token.transferFrom(_from, _to, _amount));
    }

    // @imp 3 Safe calls of ERC20 methods
    function tokenTransfer(address _to, uint256 _amount)
        internal
    {
        // Skip if no amount is being sent
        // Require success
        if (_amount > 0) assert(token.transfer(_to, _amount));
    }
}

contract TestTokenized is Tokenized
{
    function TestTokenized(address _token) public
        Tokenized(_token)
    { }
    
    function balanceOf(address account)
        public constant
        returns (uint256)
    {
        return tokenBalanceOf(account);
    }
    
    function allowance(address account, address spender)
        public constant
        returns (uint256)
    {
        return tokenAllowance(account, spender);
    }

    function approve(address spender, uint256 amount)
        public
    {
        tokenApprove(spender, amount);
    }

    function transferFrom(address _from, address _to, uint256 _amount)
        public
    {
        tokenTransferFrom(_from, _to, _amount);
    }

    function transfer(address _to, uint256 _amount)
        public
    {
        tokenTransfer(_to, _amount);
    }
}
