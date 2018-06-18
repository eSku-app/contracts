pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2; // Used for setReward(), addInfluence() functions
/*
 * ItemSale reward contract - Reward users for continuous sales promotions
 *
 * Reward contract is owned by a brand who sets it up and allocates
 * the correct amount of tokens (via transfer()) to the contract
 * in order to pay a pool of influencers for their work when an
 * item sale is made. The items that are for sale must be specified
 * before the sale is made. When the funds are exhausted, no more
 * sales can be recorded (preventing payout exceedances). After a
 * period of time declared at construction of this contract the
 * maintainer (eSKU) can remove this countract IFF all users have
 * withdrawn their share of tokens.
 *
 * @req 1 Owner creates contract, it starts unfunded
 * @req 2 Rewards (allocated per SKU) can be set by Owner (starts at 0)
 *        at any time during the contract
 * @req 3 Any reward updates must be communicated through an event
 * @req 4 A sale is only successful if there are tokens to back it
 * @req 5 When a sale is made, a snapshot is taken of the current influence
 *        to be used to determine the distribution ratio of a reward
 * @req 6 A sale must be communicated through an event
 * @req 7 A user's share is determined over each sale by their relative
 *        influence ratio at the time each sale occurs (via snapshot)
 * @req 8 Any user who earned tokens can withdraw their tokens at any time
 * @req 9 The Owner can destroy the contract and return the remaining tokens
 *        if less than 1e-7% of the contract's reward payouts are unclaimed
 *
 * NOTE: The Owner can allow the contract to run out by disabling
 *       the sales oracle and not funding it any more
 */

import "utils/Owned.sol";
import "utils/Maintained.sol";
import "utils/Tokenized.sol";
import "platform/Influenced.sol";

contract ItemSale is
    Owned,      // by a Brand, @imp 1 Sets Owner to deployer
    Maintained, // by eSKU
    Tokenized,  // with eSKU token
    Influenced  // by eSKU Metrics
{
    // @imp 2 SKU string -> Token Reward mappping, everything starts at 0 tokens
    mapping(string => uint) reward;
    // @imp 4 Reserved for dispersements, ensures tokens are not removed
    uint public unclaimed = 0;

    // @imp 5,7 Recursive Stack of Sales Reward tracking (see platform/Influenced.sol)
    //          Indexed by claimIndex during withdrawal, part of "snapshot"
    struct SalesRecord
    {
        uint reward;
        uint totalInfluence;
    }
    SalesRecord[] salesStack;

    // @imp 5 Mapping of Mappings to store the amount of
    //        influence gained during each block, part of "snapshot"
    mapping(address => mapping(uint => uint)) influenceHistory;
    // @imp 7 Influencer's current location in reward stack, for withdrawals
    mapping(address => uint) claimIndex;

    // @imp 3 New SKU Reward(s) added/updated
    event RewardsAdded(
        string[] sku,
        uint[] reward
    );
    // @imp 6 Sale Recorded
    event SaleRecorded(
        string indexed sku,
        uint indexed reward,
        uint indexed saleIndex,
        uint totalInfluence
    );

    constructor (
        address _token
    )
        public
        Tokenized(_token)
    { }
    
    // @imp 2 Brand can add/reset Rewards for the sale of a specific SKU
    function setReward(
        string[] skus, 
        uint[] amounts
    )
        public
        onlyOwner()
    {
        // Dynamic arrays should be same size
        require(skus.length == amounts.length);
        for (uint i = 0; i < skus.length; i++)
        {
            // Set each SKU's reward bounty
            reward[skus[i]] = amounts[i];
        }
        // Emit updated Reward Payouts
        emit RewardsAdded(skus, amounts);
    }

    // Maintainer can record the sale of a specific SKU
    function recordSale(
        string sku
    )
        public
        onlyMaintainer()
    {
        // Useless to update if no influence is logged
        require(totalInfluence > 0);

        // @imp 4 Must be enough tokens to back reward
        uint amount = reward[sku];
        require(amount <= tokenBalanceOf(this)-unclaimed);
        // @imp 8 This locks away Owner from getting these tokens back
        unclaimed += amount;
        
        // @imp 5 Push current influence metrics and reward amount on influence stack
        SalesRecord memory record = SalesRecord(amount, totalInfluence);
        // @imp 5 Increments salesStack.length, causing synchroization of next record
        salesStack.push(record);
        // @imp 6 Record Sale event for UI
        emit SaleRecorded(sku, amount, salesStack.length-1, totalInfluence);
    }

    // @imp 7 Precede supercall with update to historical storage
    function addInfluence(
        uint256[] amounts,
        address[] accounts
    )
        public
        onlyMaintainer()
    {
        // Log influence here
        super.addInfluence(amounts, accounts);
        // Synchronize with current data (length of array is current)
        for (uint i = 0; i < accounts.length; i++)
            influenceHistory[accounts[i]][salesStack.length] = influence[accounts[i]];
    }

    // User runs this periodically to collect their snapshotted rewards
    // May have to withdrawl multiple times not to exhaust block gas usage
    function getReward()
        public
        returns (
            bool allClaimed // Communicate that everything is claimed
        )
    {
        // Check that there is work to do now before we do any further processing
        require(claimIndex[msg.sender] < salesStack.length);

        // i@imp 7 Loop over unchecked dispersements and accrue payout amount
        // NOTE: Will stop when we reached location of currently logged data
        uint amount = 0;
        for (uint i = claimIndex[msg.sender]; i < salesStack.length; i++)
        {
            // Break out before we run out of gas
            // NOTE: We can run this method multiple times
            //       to extract all of our rewards
            // Estimate:
            //      12000 - one loop pass
            //      60000 - tokenTransfer() external call
            //       3000 - unclaimed logic + bool return calculation
            if (gasleft() < 75000) break;
 
            // Compute amount of reward for this record and add to running total
            // NOTE: Influence historical data is correct up to salesStack.length
            //       as we are logging current data using that location
            SalesRecord storage sale = salesStack[i];
            amount += computePreciseResult(sale.reward,
                                           influenceHistory[msg.sender][i],
                                           sale.totalInfluence);
            // Set loop start position for next time
            claimIndex[msg.sender] = i+1;
        }

        // @imp 8 Give the person their tokens
        if (amount > 0) tokenTransfer(msg.sender, amount);
        unclaimed -= amount;
        // @imp 8 We've claimed everything if we're up to date on the stack
        return (claimIndex[msg.sender] == salesStack.length);
    }

    // @imp 9 Give the tokens back if we clean this up for whatever reason
    function destroy()
        public
        onlyOwner()
    {
        // NOTE: Less than 1e-7% of the contract's balance is unclaimed
        //       This ensures imprecision cannot prevent this from working
        // NOTE: Potential attack vector for Owner is to fund this with
        //       significantly more tokens, then call this method.
        //       The response to this is that such actors would be noticed
        //       and suffer a reputational decline as a result.
        require(unclaimed < tokenBalanceOf(this) / 10**9);
        tokenTransfer(owner, tokenBalanceOf(this));
        selfdestruct(owner);
    }
}
