pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2; // Used for setReward(), addInfluence() functions
/*
 * Item Sale Campaign contract - Reward users for continuous sales promotions
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
 * @req 1  Owner creates contract, it starts unfunded
 * @req 2  Rewards (allocated per SKU) can be set by Owner (starts at 0)
 *         at any time during the contract
 * @req 3  Any reward updates must be communicated through an event
 * @req 4  A sale is only successful if there are tokens to back it
 * @req 5  When a sale is made, a snapshot is taken of the current influence
 *         to be used to determine the distribution ratio of a reward
 * @req 6  A sale must be communicated through an event
 * @req 7  A user's share is determined over each sale by their relative
 *         influence ratio at the time each sale occurs (via snapshot)
 * @req 8  Any user who earned tokens can withdraw their tokens at any time
 * @req 9  The Owner can withdraw any unlocked tokens at any time
 * @req 10 The Owner can destroy the contract and return the remaining tokens
 *         if less than 1e-7% of the contract's reward payouts are unclaimed
 *
 * NOTE: The Owner can allow the contract to run out by disabling
 *       the sales oracle and not funding it any more
 */

import "utils/Owned.sol";
import "utils/Maintained.sol";
import "utils/Tokenized.sol";
import "platform/Influenced.sol";

contract ItemSaleCampaign is
    Owned,      // by a Brand, @imp 1 Sets Owner to deployer
    Maintained, // by eSKU
    Tokenized,  // with eSKU token
    Influenced  // by eSKU Metrics
{
    // @imp 2 SKU bytestring -> Token Reward mappping, everything starts at 0 tokens
    mapping(bytes32 => uint) reward;
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
        bytes32[] sku,
        uint[] reward
    );
    // @imp 6 Sale Recorded
    event SaleRecorded(
        bytes32 indexed sku,
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
        bytes32[] skus,
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

    // Helper to obtain number of unlocked tokens
    function unlockedTokens()
        public
        view
        returns (
            uint
        )
    {
        return tokenBalanceOf(this)-unclaimed;
    }

    // Maintainer can record the sale of a specific SKU
    function recordSale(
        bytes32 sku
    )
        public
        onlyMaintainer()
    {
        // Useless to update if no influence is logged
        require(totalInfluence > 0);

        // @imp 4 Must be enough unlocked tokens to back reward
        uint amount = reward[sku];
        require(amount <= unlockedTokens());
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
    {
        // Check that there is work to do now before we do any further processing
        require(claimsLeft(msg.sender) > 0);

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

        // @imp 8 Give the person their tokens if they've earned any
        if (amount > 0) // Also protects against re-entrancy a bit
        {
            tokenTransfer(msg.sender, amount);
            unclaimed -= amount;
        }
    }

    // NOTE: Testing shows 98k gas for 1 claim,
    //       +15k for each one after that.
    //       This is about 0.08 ETH for 100 claims @ 50gwei gasprice
    //       This is about 0.0012 ETH for 10 claims @ 5gwei gasprice
    function claimsLeft (
        address _claimer
    )
        public
        view
        returns (uint)
    {
        // @imp 8 Helper, returns number of claims left on stack
        return salesStack.length - claimIndex[_claimer];
    }

    // @imp 9 Withdraw unlocked tokens at any time
    function withdrawal()
        public
        onlyOwner()
    {
        uint unlocked = unlockedTokens();
        require(unlocked > 0);
        tokenTransfer(owner, unlocked);
    }

    // @imp 10 Give the tokens back if we clean this up for whatever reason
    function destroy()
        public
        onlyOwner()
    {
        // Hold this in memory
        uint tokenBalance = tokenBalanceOf(this);

        // NOTE: Less than 1e-7% of the contract's balance is unclaimed
        //       This ensures imprecision cannot prevent this from working
        // NOTE: Potential attack vector for Owner is to fund this with
        //       significantly more tokens, then call this method.
        //       The response to this is that such actors would be noticed
        //       and suffer a reputational decline as a result.
        require(unclaimed * 10**9 <= tokenBalance);
        if (tokenBalance > 0) tokenTransfer(owner, tokenBalance);
        selfdestruct(owner);
    }
}
