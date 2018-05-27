pragma solidity ^0.4.20;
/*
 * Maintained utility class - modification of the Owned contract
 *
 * @req 1 'Maintainer' must be set to the creator of this contract
 * @req 2 'Maintainer' can be reassigned only by themselves
 * @req 3 Only the 'Maintainer' can execute transactions with the 
 *        'onlyMaintainer' modifier
 * @req 4 Maintainership reassignments shall have an event
 */

contract Maintained
{
    // @imp 1 'msg.sender' is the creator of this contract,
    //        or any it inherits
    address public maintainer = msg.sender;

    // @imp 4 event structure
    event MaintainershipTransferred(
        address indexed previousMaintainer,
        address indexed newMaintainer
    );
    
    // @imp 3 Functions with this modifier can only be
    //        executed by the maintainer
    modifier onlyMaintainer()
    {
        // @imp 3 will revert if maintainer is not sending this txn
        require(msg.sender == maintainer);
        _;
    }
    
    // @imp 2 Only maintainer can reassign
    function changeMaintainer(address newMaintainer)
        public
        onlyMaintainer
    {
        require(newMaintainer != address(0)); // Safe against null args
        maintainer = newMaintainer; // assign
        emit MaintainershipTransferred(maintainer, newMaintainer); // @imp 4 emit Event
    }
}
