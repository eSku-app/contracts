pragma solidity ^0.4.20;
/*
 * Owned utility class - modification of Zeppelin 'Ownable'
 *
 * @req 1 'Owner' must be set to the creator of this contract
 * @req 2 'Owner' can be reassigned only by themselves
 * @req 3 Only the 'Owner' can execute transactions with the 
 *        'onlyOwner' modifier
 * @req 4 Ownership reassignments shall have an event
 */

contract Owned
{
    // @imp 1 'msg.sender' is the creator of this contract,
    //        or any it inherits
    address public owner = msg.sender;

    // @imp 4 event structure
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    
    // @imp 3 Functions with this modifier can only be
    //        executed by the owner
    modifier onlyOwner()
    {
        // @imp 3 will revert if owner is not sending this txn
        require(msg.sender == owner);
        _;
    }
    
    // @imp 2 Only owner can reassign
    function changeOwner(address newOwner)
        public
        onlyOwner
    {
        require(newOwner != address(0)); // Safe against null args
        owner = newOwner; // assign
        emit OwnershipTransferred(owner, newOwner); // @imp 4 emit Event
    }
}
