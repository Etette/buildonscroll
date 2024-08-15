// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Imports
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PayPool is ReentrancyGuard {
    // Data
    uint public totalBalance;
    address public owner;

    address[] public depositAddresses;
    mapping(address => uint256) public allowances;

    enum DepositStatus {
        Pending,
        Approved,
        Rejected
    }

    struct DepositRecord {
        address depositor;
        uint256 amount;
        uint256 timestamp;
        DepositStatus status;
    }

    DepositRecord[] public depositHistory;

    // Events
    event Deposit(address indexed depositor, uint256 amount);
    event AddressAdded(address indexed depositor);
    event AddressRemoved(address indexed depositor);
    event AllowanceGranted(address indexed user, uint amount);
    event AllowanceRemoved(address indexed user);
    event FundsRetrieved(address indexed recipient, uint amount);
    event DepositStatusUpdated(uint256 indexed index, DepositStatus status);

    modifier isOwner() {
        require(msg.sender == owner, "Not owner!");
        _;
    }

    modifier gotAllowance(address user) {
        require(hasAllowance(user), "This address has no allowance");
        _;
    }

    modifier canDepositTokens(address depositor) {
        require(canDeposit(depositor), "This address is not allowed to deposit tokens");
        _;
    }

    constructor() payable {
        totalBalance = msg.value;
        owner = msg.sender;
    }

    // Internal functions
    function hasAllowance(address user) internal view returns (bool) {
        return allowances[user] > 0;
    }

    function canDeposit(address depositor) internal view returns (bool) {
        for (uint i = 0; i < depositAddresses.length; i++) {
            if (depositAddresses[i] == depositor) {
                return true;
            }
        }
        return false;
    }

    // Execute Functions
    function addDepositAddress(address depositor) external isOwner {
        depositAddresses.push(depositor);
        emit AddressAdded(depositor);
    }

    function removeDepositAddress(uint index) external isOwner canDepositTokens(depositAddresses[index]) {
        depositAddresses[index] = address(0);
        emit AddressRemoved(depositAddresses[index]);
    }

    function deposit() external canDepositTokens(msg.sender) payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");

        totalBalance += msg.value;

        // Create a new deposit record
        DepositRecord memory newDeposit = DepositRecord({
            depositor: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp,
            status: DepositStatus.Pending
        });

        // Add the record to the history
        depositHistory.push(newDeposit);

        emit Deposit(msg.sender, msg.value);
    }

    function retrieveBalance() external isOwner nonReentrant {
        uint balance = totalBalance;
        (bool success, ) = owner.call{value: balance}("");
        require(success, "Transfer failed");
        totalBalance = 0;
        emit FundsRetrieved(owner, balance);
    }

    function giveAllowance(uint amount, address user) external isOwner {
        require(totalBalance >= amount, "Insufficient balance in the pool");
        allowances[user] = amount;
        unchecked {
            totalBalance -= amount;
        }
        emit AllowanceGranted(user, amount);
    }

    function removeAllowance(address user) external isOwner gotAllowance(user) {
        allowances[user] = 0;
        emit AllowanceRemoved(user);
    }

    function allowRetrieval() external gotAllowance(msg.sender) nonReentrant {
        uint amount = allowances[msg.sender];
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Retrieval failed");
        allowances[msg.sender] = 0;
        emit FundsRetrieved(msg.sender, amount);
    }

    function approveDeposit(uint256 index) external isOwner {
        require(index < depositHistory.length, "Invalid index");
        DepositRecord storage deposit = depositHistory[index];
        require(deposit.status == DepositStatus.Pending, "Deposit not pending");

        deposit.status = DepositStatus.Approved;
        emit DepositStatusUpdated(index, DepositStatus.Approved);
    }

    function rejectDeposit(uint256 index) external isOwner {
        require(index < depositHistory.length, "Invalid index");
        DepositRecord storage deposit = depositHistory[index];
        require(deposit.status == DepositStatus.Pending, "Deposit not pending");

        deposit.status = DepositStatus.Rejected;
        // Refund the deposit amount to the depositor
        require(totalBalance >= deposit.amount, "Insufficient balance to refund");
        require(payable(deposit.depositor).send(deposit.amount), "Refund failed");

        totalBalance -= deposit.amount;
        emit DepositStatusUpdated(index, DepositStatus.Rejected);
    }

    function getDepositHistory() external view returns (DepositRecord[] memory) {
        return depositHistory;
    }
}
