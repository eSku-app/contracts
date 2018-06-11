pragma solidity ^0.4.24;

import "utils/Owned.sol";
import "utils/Tokenized.sol";
import "utils/TimeLimited.sol";

contract ICO is Owned, Tokenized, TimeLimited
{
    // ICO Information
    uint256 public tokenPrice;
    uint256 public hardCap; // 250 million (100k ether)
    uint256 public softCap; //  18.75 million (7500 ether)
    uint256 public sold = 0;
    mapping(address => uint256) spent; // incase of refund
    bool public failed = false; // Allows for refund in case of failure

    event TokenBuy(
        address account,
        uint256 valueSent,
        uint256 tokensBought,
        uint256 refund
    );
    
    event TokenRefund(
        address account,
        uint256 tokensReturned,
        uint256 refund
    );
    
    constructor (
        uint256 _tokenPrice,
        uint256 _hardCap,
        uint256 _softCap,
        uint _duration,
        address _token
    )
        public
        TimeLimited(_duration)
        Tokenized(_token)
    {
        tokenPrice = _tokenPrice; // X tokens/ether
        hardCap = _hardCap; // 250 million tokens
        softCap = _softCap; //  18.75 million tokens
    }
    
    function softCapReached()
        public
        constant
        returns (bool isReached)
    {
        return sold >= softCap;
    }
    
    function hardCapReached()
        public
        constant
        returns (bool isReached)
    {
        return sold >= hardCap;
    }

    // Override TimeLimited.active()
    function active()
        public
        view
        returns (bool)
    {
        // HardCap hasn't been reached and contract isn't expired
        // Also contract has not been declared failed
        return !failed && !hardCapReached() && super.active();
    }


    function buyToken()
        public
        payable
        inProgress()
    {
        require(!hardCapReached());
        // Can only buy whole tokens
        uint256 amount = msg.value / tokenPrice;
        assert(amount > 0);
        uint256 refund = msg.value - (amount * tokenPrice);
        assert(refund < tokenPrice);
        // Purchase the amount of tokens specified
        sold += amount;
        spent[msg.sender] += (amount*tokenPrice);
        tokenTransferFrom(owner, msg.sender, amount);
        emit TokenBuy(msg.sender, msg.value, amount, refund);
        // Send a refund for the remainder
        msg.sender.transfer(refund);
    }

    // This method is required to re-adjust levels based on Eth prices
    // Updates will be provided daily and in accordance with 24-hr Eth price trends
    function updateTokenPrice(
        uint256 _tokenPrice
    )
        public
        inProgress()
        onlyOwner()
    {
        tokenPrice = _tokenPrice;
    }

    // If the ICO is successful (hits hard cap or hits soft cap and
    // campaign is over), return the funds to the owner and destroy this
    function declareSuccess()
        public
        inProgress()
        onlyOwner()
    {
        require( hardCapReached() || (softCapReached() && !active()) );
        selfdestruct(owner);
    }

    // We can declare failure at any time up to SoftCap
    function declareFailure()
        public
        inProgress()
        onlyOwner()
    {
        require(!softCapReached());
        failed = true;
    }
    
    modifier failure()
    {
        require(failed);
        _;
    }
    
    function refundToken()
        public
        failure()
    {
        // Send tokens back
        uint256 amount = tokenBalanceOf(msg.sender);
        require(amount > 0); // Protect against re-entrancy
        tokenTransferFrom(msg.sender, owner, amount);
        sold -= amount;
        // Refund ether
        uint256 refund = spent[msg.sender];
        spent[msg.sender] = 0; // Re-entrancy risk mitigated
        emit TokenRefund(msg.sender, amount, refund);
        msg.sender.transfer(refund);
    }

    // If the ICO fails (does not hit soft cap)
    // We can destroy this once everyone has extracted their funds
    function destroy()
        public
        failure()
        onlyOwner()
    {
        // Only if everyone has given their tokens back
        if (sold == 0) selfdestruct(owner);
    }
}
