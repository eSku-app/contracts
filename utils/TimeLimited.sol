pragma solidity ^0.4.24;
/*
 * TimeLimited - utility contract that allows controlling contract access through
 *               a deadline, and provides modifiers and events for reference.
 *
 * @req 1 The contract shall log the time it was created
 * @req 2 The 'duration' parameter controls the deadline
 *        (deadline = creation + duration)
 * @req 3 Only the owner (who deployed the contract) can lock change the state
 *        access, and only after the deadline has passed.
 * @req 4 An event must be emitted when the state has been locked by the owner
 */

import "utils/Owned.sol";

contract TimeLimited is Owned
{
    /* Timeline of contract */
    // @imp 1 'now' is the creation time of this contract
    uint public creationTime = now;
    uint public duration; // Must be set by inheriting contract
    bool public finished; // Owner sets the finished flag after duration is expired

    // @imp 4 Event occurs when deadline passes and owner declares state locked
    event Expired();

    constructor (
        uint _duration
    )
        public
    {
        // Protect against overflow condition on input arg
        require(creationTime + _duration > creationTime);
        // @imp 2 set the duration parameter
        duration = _duration;
    }

    function active()
        public
        view
        returns (bool)
    {
        // @imp 2 access the state of the deadline
        return now < creationTime + duration;
    }

    modifier inProgress()
    {

        // @imp 2 Both together avoids block-time manipulation issues
        require(active() && !finished);
        _;
    }

    function setExpired()
        public
        onlyOwner()
    {
        // @imp 2 Duration must be expired
        require(!active());

        // @imp 3 owner changes state
        // NOTE: Owner is trusted not to manipulate block times
        finished = true;

        // @imp 4 emit Event
        emit Expired();
    }

    modifier expired()
    {
        // @imp 2 Avoids block-time manipulation issues
        require(!active() || finished);
        _;
    }
}

contract TestTimeLimited is TimeLimited
{
    constructor (
        uint _duration
    )
        public
        TimeLimited(_duration)
    { }

    function destroy()
        public
        expired()
    {
        require(finished);
        selfdestruct(msg.sender);
    }
}
