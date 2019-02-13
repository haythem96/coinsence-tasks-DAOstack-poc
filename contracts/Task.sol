// This is just a mock
pragma solidity ^0.4.24;


contract Task {

    event TaskCreated(bytes32 _taskId, uint256 _coinsAmount);
    event SolutionValidated(bytes32 _taskId, bytes32 _solutionId);

    function createTask(bytes32 _taskId, uint256 _coinsAmount, bool isConfirmed) public returns (bool) {
        emit TaskCreated(_taskId, _coinsAmount);
        return true;
    }

    function validateSolution(bytes32 _taskId, bytes32 _solutionId) public returns (bool) {
        emit SolutionValidated(_taskId, _solutionId);
        return true;
    }
}