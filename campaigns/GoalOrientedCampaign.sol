pragma solidity ^0.4.24;
/*
 * Goal-Oriented Campaign contract - Pay users for acheiving a goal in a limited time
 *
 * This reward contract is owned by a brand who sets it up and
 * allocates the correct amount of tokens (via transfer()) to the
 * contract in order to pay a pool of influencers for their work
 * when a goal is met. The brand can increase the amount of bounty
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
 *        the contract is expired
 * @req 5 The Owner can cancel the contract at any time, as long
 *        as the minimum influence is not exceeded
 * @req 6 The Owner can destroy the contract after it is expired,
 *        only if all users have taken their rewards
 *
 * @req 7  Goal progress starts at zero
 * @req 8  Only Maintainer can increase goal progress
 * @req 9  Rewards are calculated using the percentage of the goal hit
 * @req 10 If goal is met, the contract is set expired
 *
 */

import "campaigns/TimeboundCampaign.sol";
import "utils/Maintained.sol";

contract GoalOrientedCampaign is
    Maintained,         // by a Maintainer @imp 8
    TimeboundCampaign   // inherits from @imp 1,2,3,5,6
{
    // @imp 7 Goal progress starts at 0
    uint public progress = 0;

    constructor (
        address _token,
        uint _duration,
        uint _minimumInfluence
    )
        public
        TimeboundCampaign(_token, _duration, _minimumInfluence)
    { }

    function addProgress(
        uint newProgress
    )
        public
        inProgress()
        // @imp 8 Only maintainer can increase progress
        onlyMaintainer()
    {
        if (progress + newProgress >= 100) // No overflows possible
        {
            progress = 100; // Goal is met!

            // NOTE: Overrides behavior of TimeLimited
            // @imp 10 Immediately set contract "expired"
            //         Shouls not have any side effects
            finished = true;
        } else {
            progress += newProgress;
        }
    }

    // Helper to figure out how much of the bounty is claimed
    function reward()
        public
        view
        returns (
            uint
        )
    {
        // Percentage of goal progress times bounty
        return (bounty * progress) / 100;
    }
    
    // OVERRIDES Campaign::getReward()
    // @imp 4 User can get their reward when contract is "expired"
    //        NOTE: "expired" means goal is met or contract exceeded it's time
    function getReward()
        public
        expired()
    {
        // Re-entrancy protection
        require(!claimed[msg.sender]);
        claimed[msg.sender] = true;

        // Get user's piece of the reward
        // @imp 9 Reward is calculated based on percentage of goal hit
        uint256 amount = getInfluenceOf(reward(), msg.sender); // diff from override

        // Give the user their tokens!
        tokenTransfer(msg.sender, amount);
    }

    // @imp 9 Withdraw unlocked tokens after expiration
    function withdrawal()
        public
        onlyOwner()
        expired()
    {
        uint unlocked = bounty-reward();
        require(unlocked > 0);
        tokenTransfer(owner, unlocked);
    }

    // without withdrawal(), you could not @imp 6 because of inflated token balance
}
