// This is just a mock
pragma solidity ^0.4.24;


interface TaskInterface {
    function createTask(bytes32 _taskId, uint256 _coinsAmount, bool isConfirmed) external;
    function validateSolution(bytes32 _taskId, bytes32 _solutionId) external;
}