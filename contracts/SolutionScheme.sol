pragma solidity ^0.5.2;

import "@daostack/infra/contracts/votingMachines/ProposalExecuteInterface.sol";
import "@daostack/arc/contracts/universalSchemes/UniversalScheme.sol";
import "@daostack/arc/contracts/controller/ControllerInterface.sol";
import "@daostack/arc/contracts/votingMachines/VotingMachineCallbacks.sol";

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

import "./TaskInterface.sol";


/**
 * @title A universal scheme for proposing coins amount for a task
 * @dev A memmber can propose the space a task solution to send.
 * if accepted the coins for that task will be sent to the member
 */
contract SolutionScheme is UniversalScheme, VotingMachineCallbacks, ProposalExecuteInterface {

    //allocate contract address on the ethereum blockchain (testnet or mainnet)
    address public constant TASK = 0x802388aB7eF5c1dCAFE4e161C89431417e35551c; //not a valid TASK contract address

    address public taskContract;

    event TaskRegistered(address indexed _avatar, string _name, uint256 _coins);

    event NewSolutionProposal(
        address indexed _avatar,
        bytes32 indexed _proposalId,
        address indexed _intVoteInterface,
        address _proposer
    );

    event SolutionExecuted(address indexed _avatar, bytes32 indexed _proposalId, int _param);

    // A struct representing a task solution proposal
    struct SolutionProposal {
        address proposer; // The proposer of the allocation amount
        bytes32 taskId;
        bytes32 solutionId;
        string solutionHash; // The IPFS hash of the task solution description
    }

    event ProposalExecuted(address indexed _avatar, bytes32 indexed _proposalId, int _param);

    // A mapping from the space (Avatar) address to the saved task solution proposals of the space:
    mapping(address=>mapping(bytes32=>mapping(bytes32=>SolutionProposal))) public spacesProposals;

    //A mapping frm a prposal to the task
    mapping(bytes32=>bytes32) public proposalTask;

    // A mapping from hashes to parameters (use to store a particular configuration on the controller)
    mapping(bytes32 => Parameters) public parameters;

    // A struct representing organization parameters in the Universal Scheme.
    // The parameters represent a specific configuration set for an organization.
    // The parameters should be approved and registered in the controller of the organization.
    struct Parameters {
        bytes32 voteApproveParams; // The hash of the approved parameters of a Voting Machine for a specific organization.
                                    // Used in the voting machine as the key in the parameters mapping to 
                                    // Note that these settings should be registered in the Voting Machine prior of using this scheme.
        IntVoteInterface intVote; // The address of the Voting Machine to be used to propose and vote on a proposal.
    }

    constructor(address _taskContract) public {
        taskContract = _taskContract;
    }

    /**
    * @dev hash the parameters, save them if necessary, and return the hash value
    */
    function setParameters( bytes32 _voteApproveParams, IntVoteInterface _intVote) public returns(bytes32) {
        bytes32 paramsHash = getParametersHash(
            _voteApproveParams,
            _intVote
        );
        parameters[paramsHash].voteApproveParams = _voteApproveParams;
        parameters[paramsHash].intVote = _intVote;
        return paramsHash;
    }

    /**
    * @dev hash the parameters and return the hash
    */
    function getParametersHash(bytes32 _voteApproveParams, IntVoteInterface _intVote) public pure returns(bytes32) {
        return (keccak256(abi.encodePacked(_voteApproveParams, _intVote)));
    }

    /**
    * @dev Registers a task for the space(avatar)
    * @param _avatar the avatar of the space to register to task
    * @param _name the task name
    * @param _coins coins amount to allocate for task
    */
    function registerTask(address payable _avatar, string memory _name, uint256 _coins) public {      
        ControllerInterface controller = ControllerInterface(Avatar(_avatar).owner());
        // Sends a call to the Task contract to issue a task
        // The call will be made from the avatar address such that when received by the Task contract, the msg.sender value will be the avatar's address
        controller.genericCall(
            taskContract, 
            abi.encodeWithSelector(TaskInterface(taskContract).createTask.selector, keccak256(abi.encodePacked(_name)), 1000, false),
            Avatar(_avatar)
        );
        
        emit TaskRegistered(_avatar, _name, _coins);
    }

    function proposeSolution(
        Avatar _avatar,
        bytes32 _taskId, 
        string memory _solutionHash
    ) public
      returns(bytes32)
    {
        Parameters memory controllerParams = parameters[getParametersFromController(_avatar)];

        bytes32 solutionId = controllerParams.intVote.propose(
            3,
            controllerParams.voteApproveParams,
            msg.sender,
            address(_avatar)
        );

        // Set the struct:
        SolutionProposal memory proposal = SolutionProposal({
            proposer: msg.sender,
            taskId: _taskId,
            solutionId: solutionId,
            solutionHash: _solutionHash
        });
        spacesProposals[address(_avatar)][_taskId][solutionId] = proposal;
        proposalTask[solutionId] = _taskId;

        emit NewSolutionProposal(
            address(_avatar),
            solutionId,
            address(controllerParams.intVote),
            msg.sender
        );

        return solutionId;
    }

    /**
    * @dev execution of proposals, can only be called by the voting machine in which the vote is held.
    * @param _proposalId the ID of the voting in the voting machine
    * @param _param a parameter of the voting result, 1 yes and 2 is no.
    */
    function executeProposal(bytes32 _proposalId, int _param)  public returns(bool) {
        address payable avatar = address(proposalsInfo[_proposalId].avatar);

        // Check the caller is indeed the voting machine:
        require(
            address(parameters[getParametersFromController(Avatar(avatar))].intVote) == msg.sender, 
            "Only the voting machine can execute proposal"
        );

        //get the task id realted to the proposal
        bytes32 taskId = proposalTask[_proposalId];

        // Check if vote was successful:
        if (_param == 1) {
            SolutionProposal memory proposal = spacesProposals[avatar][taskId][_proposalId];
            
            ControllerInterface controller = ControllerInterface(Avatar(avatar).owner());
            // Sends a call to the Task contract to send coins to proposer
            // The call will be made from the avatar address such that when received by the Task contract, the msg.sender value will be the avatar's address
            controller.genericCall(taskContract, abi.encodeWithSelector(TaskInterface(taskContract).validateSolution.selector, taskId, _proposalId), Avatar(avatar));
            
            // Send coins to the proposer of the Peep.
            IERC20 erc20Coin = IERC20(address(0));
            //TODO: replace fixed coin number with a variable
            require(
                ControllerInterface(Avatar(avatar).owner()).externalTokenTransferFrom(erc20Coin, avatar, proposal.proposer, 10, Avatar(avatar)),
                "Failed to mint reputation to proposer"
            );
        } else {
            delete spacesProposals[avatar][taskId][_proposalId];
        }

        emit ProposalExecuted(avatar, _proposalId, _param);

        return true;
    }

}