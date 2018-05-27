pragma solidity ^0.4.20;
/*
 * Campaign reward contract - Pay users for a promotional campaign
 *
 * This reward contract is owned by a brand who sets it up and
 * allocates the correct amount of tokens (via transfer()) to the
 * contract in order to pay a pool of influencers for their work
 * when a campaign ends. The brand can increase the amount of bounty
 * tokens to pay out in order to increase the work done for the
 * campaign. At the end of the campign, the influencers are allowed
 * to withdraw their portion of the bounty. The owner
 *
 * @req 1 Owner creates contract, and sets a minimum amount of
 *        influence required to pay bounty
 * @req 2 Token bounty starts at zero
 * @req 3 Owner can increase the token bounty at any point while
 *        the contract is active
 * @req 4 Any user who earned tokens can withdraw their tokens after
 *        the contract is expired (Owner must finalize expiration)
 * @req 5 The Owner can cancel the contract at any time, as long
 *        as the minimum influence is not hit
 * @req 6 The Owner can destroy the contract after it is expired,
 *        only if all users have taken their rewards
 */

import "utils/Owned.sol";
import "utils/TimeLimited.sol";
import "utils/Tokenized.sol";
import "platform/Influenced.sol";

contract Campaign is
    Owned,      // by a Brand @imp 1
    TimeLimited,// by given duration
    Tokenized,  // with eSKU token
    Influenced  // By eSKU Metrics
{
    // Amount of unclaimed rewards
    // @imp 2 starts at 0
    uint256 public bounty = 0;

    // @imp 4 Tracking claim status
    mapping(address => bool) claimed;

    // @imp 1, 5 Minimum that must be hit for success
    uint public minimumInfluence;

    function Campaign (
        address _token,
        uint _duration,
        uint _minimumInfluence
    )
        public
        Tokenized(_token)
        TimeLimited(_duration)
        Influenced(_token, 0) // Start influence fee at 0 tokens
    {
        // @imp 1 Set minimum influence
        minimumInfluence = _minimumInfluence;
    }

    // @imp 3 Owner can increase bounty any time contract is active
    function setBounty()
        public
        inProgress()
        onlyOwner()
    {
        // Starts at 0 at deployment, so brand needs to add tokens to this
        // contract in order to incentivize users to join
        // Also, if they decide to up the ante on the contract, allow them
        require(tokenBalanceOf(this) > bounty);
        bounty = tokenBalanceOf(this);
    }

    // @imp 4 User can get their reward when contract is over
    function getReward()
        public
        expired()
    {
        // Re-entrancy protection
        require(!claimed[msg.sender]);
        claimed[msg.sender] = true;

        // Get user's piece of the reward
        uint256 amount = getInfluenceOf(bounty, msg.sender);

        // Give the user their tokens!
        tokenTransfer(msg.sender, amount);
    }

   function destroy()
        public
        onlyOwner()
   {
        // @imp 5 If minimum influence is not hit, return the tokens to the owner
        if (totalInfluence < minimumInfluence)
            // This allows the next part to continue
            tokenTransfer(owner, tokenBalanceOf(this));

        // @imp 6 In case there are straggling tokens left (must be less than 1e-7%)
        require(tokenBalanceOf(this) < bounty / 10**9);
        // NOTE: Remainder (which is very small) is destroyed
        //       This is done to ensure imprecise calculations cannot stop this

        // @imp 5,6 Only remove contract if all tokens are claimed
        selfdestruct(owner);
   }
}
