pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2; // Used for addInfluence() function
/*
 * Influenced - Inherited contract that adds influence logging
 *
 * Influence is calculated by a proprietary formula that
 * reduces the recent social media outreach of an influencer
 * (e.g. since last checked) for a given product to a single
 * score denoting their overall level of effort promoting the
 * products present in a contract. That score is added to the
 * influencer's current score, and the overall amount of
 * influence is raised by the same amount. For a multitude of
 * users, this means that ratio of a user's influence to the
 * total influence in the system represents the degree to which
 * that user has influence on the system. As the total influence
 * is increased at a rate proportional to the amount of users
 * times the amount of work they have done, this ratio (versus
 * the average influence across all users) is a proxy for how
 * much more work the user is putting into the system, and
 * therefore can be used to produce dividends of a given reward.
 *
 * NOTE: Maintainer computes influence score and maintains
 *       influence state for a given contract in return for a
 *       portion of the rewarded funds.
 *
 * @req 1 The logged influence starts at 0
 * @req 2 Only the maintainer can update a user's score
 * @req 3 When the maintainer changes a user's score, the total changes
 *        by the same amount
 * @req 4 Any score updates must be communicated through an event
 * @req 5 The maintainer earns a fee for updating the score (it can be zero)
 * @req 6 The maintainer can change this fee at any time
 *        (disincentivizes sybil attacks)
 * @req 7 Any fee changes must be communicated through an event
 * @req 8 The maintainer can eliminate any user's score (blacklist)
 * @req 9 A user's share of a token reward can be computed using a ratio
 *        of their score to the total score, without loss of more than 1e-7%
 */
import "utils/Maintained.sol";

contract Influenced is Maintained
{ 
    // Influencer -> Influence mapping for all accounts
    mapping(address => uint256) public influence;
    uint256 public totalInfluence = 0; // @imp 1 Total starts at 0
        
    // Precision math variables (accurate to 1/10^18 places)
    // Handles a TOTAL_SUPPLY < 10**32 @ 18 decimals
    // @imp 9 Ratio computations are computed multiplied by PREC_MULT
    uint256 private PREC_MULT = 100000000000000000000000000; // 10**27
    // @imp 9 Which means user influence x reward must be leq than UINT256_MAX
    uint256 private PREC_MAX =  // 2**256-1 / PREC_MULT
        115792089237316195423570985008687907853269984665640;

    // @imp 4 Influence updating event
    event AddInfluence(
        address[] indexed influencers,
        uint256[] indexed amounts
    );

    function addInfluence(
        uint256[] amounts,
        address[] accounts
    )
        public
        onlyMaintainer()
    {
        // Arrays must be same length
        require(amounts.length == accounts.length);

        for (uint i = 0; i < amounts.length; i++)
        {
            // Overflow protection and zero _score avoidence
            // NOTE: influence[_account] <= total_influence,
            // so we don't need to check that
            require(totalInfluence + amounts[i] > totalInfluence);
            // @imp 9 Make sure we're within our bounds for precise math
            require(totalInfluence + amounts[i] < PREC_MAX);

            // @imp 2 Increase user's score
            influence[accounts[i]] += amounts[i];
            // @imp 3 as well as total
            totalInfluence += amounts[i];
        }

        // @imp 4 Feedback event
        emit AddInfluence(accounts, amounts);
    }

    // In case someone does something bad
    // or we discover that someone hijacked a user's
    // account and replaced with their own address
    function blackball(
        address account
    )
        public
        onlyMaintainer()
    {
        //require( influence[account] <= totalInfluence ); // This should hold by design, but Mythril yells
        // @imp 3 Decrement the total by the blacklisted user's score
        totalInfluence -= influence[account];
        // @imp 8 Remove the blacklisted user's score
        influence[account] = 0;
    }

    // @imp 9 Get user's portion of share using decimal-pt accuracy
    // NOTE: Token maximum to ensure share is accurately computed is 1.1579e57 units
    //       (Assuming max decimals is 18 places)
    function getInfluenceOf(
        uint256 amount,
        address account
    )
        public constant
        returns (
            uint256
        )
    {
        require(amount > 0);
        // Call to internal routine
        return computePreciseResult(amount, influence[account], totalInfluence);
    }

    // @imp 9 Compute 'share = amount * (numerator/denominator)' precisely for given precision
    function computePreciseResult(
        uint256 amount,
        uint256 numerator,
        uint256 denominator
    )
        internal
        constant
        returns (
            uint256
        )
    {
        // There is nothing to reward
        if (numerator == 0) return 0;

        // No divide by zeros
        require(denominator > 0);

        // Ensure amount doesn't overflow
        require(amount <= PREC_MAX);

        // Multiply by our precision multiplier
        uint256 share = PREC_MULT * numerator;

        // NOTE: influenceRatio * PREC_MULT <= PREC_MULT
        //       since numerator <= denominator
        share /= denominator;

        // NOTE: influenceRatio * amount * PREC_MULT <= amount * PREC_MULT
        share *= amount;

        // Ensure above is true
        assert(share <= amount * PREC_MULT);

        // Round result to precise number of units
        if (share % PREC_MULT >= PREC_MULT / 2)
            // Add the difference
            share += ( PREC_MULT - (share % PREC_MULT) );

        // Finally floor divide the result
        // NOTE: share <= amount
        share /= PREC_MULT;

        // Guarenteed share <= amount, and precise to 1e-7%
        return share;
    }
}
