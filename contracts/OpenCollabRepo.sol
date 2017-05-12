pragma solidity ^0.4.6;

import "./SafeMath.sol";
import "./OpenCollabToken.sol";

contract OpenCollabRepo is SafeMath {
  string public name;
  bool public obsolete;

  address[] maintainerAddresses;
  mapping (address => bool) public maintainers;

  string[] refKeys;
  mapping (string => string) refs;

  string[] snapshots;

  struct Issue {
    uint id;                                 // Issue id
    address creator;                         // Address of issue creator
    string hash;                             // Swarm hash of issue contents
    uint totalStake;                         // Total amount staked to this issue
    mapping (address => uint) stakedTokens;  // Mapping curator addresses to staked amounts for this issue
    bool openPullRequest;                    // Is there a pull request open for this issue
    uint pullRequestId;                      // Id for open pull request for this issue
    bool active;                             // Is this issue active
  }

  Issue[] issues;

  struct PullRequest {
    uint id;                                 // Pull request id
    Issue issue;                             // Issue being resolved
    address creator;                         // Address of pull request creator
    address fork;                            // Contract address of repo fork
    bool active;                             // Is this pull request active
  }

  PullRequest[] pullRequests;

  // OpenCollab protocol params

  // Token address
  OpenCollabToken public token;

  // Maintainer percentage of issue token reward
  uint256 public maintainerPercentage;
  // Percentage to increase voter deposit by if voter is on winning side of vote
  uint256 public voterRewardPercentage;
  // Percentage to decrease voter deposity by if voter is on losing side of vote
  uint256 public voterPenaltyPercentage;

  // Required deposit to be a voter
  uint256 public voterDeposit;
  // Required stake to be a contributor and open a pull request
  uint256 public contributorStake;
  // Required stake to initiate a pull request merge
  uint256 public maintainerStake;
  // Required stake to challenge a maintainer
  uint256 public challengerStake;

  // Protocol period
  enum Period { Review, Voting, Regular }
  // Current protocol period
  Period currentPeriod;

  // Length of maintainer merge review period in days
  uint256 public reviewPeriodLength;
  // Timestamp for end of review period
  uint256 public reviewPeriodEnd;
  // Length of voting commit period
  uint256 public votingCommitPeriodLength;
  // Timestamp for end of voting commit period in days
  uint256 public votingCommitPeriodEnd;
  // Length of voting reveal period in days
  uint256 public votingRevealPeriodLength;
  // Timestamp for end of voting reveal period
  uint256 public votingRevealPeriodEnd;

  // Represents a challenge voting round
  struct VotingRound {
    address maintainer;               // Address of maintainer challenged
    address challenger;               // Address of challenger
    uint256 uphold;                   // Number of uphold votes
    uint256 veto;                     // Number of veto votes
    mapping (address => Vote) votes;  // Votes casted
    VoteValue result;                 // Result of vote
  }

  // Track all voting rounds
  VotingRound[] votingRounds;

  // Represents a vote
  struct Vote {
    bytes32 commit;                   // Vote commitment hash
    VoteValue voteValue;              // Revealed vote value
    bool commited;                    // Was the vote committed
    bool revealed;                    // Was the vote revealed
  }

  // Values of votes
  enum VoteValue { Uphold, Veto, None }

  // Represents a voter
  struct Voter {
    address voterAddress;             // Address of voter
    uint deposit;                     // Voter deposit
    uint lastCheckIn;                 // Last voting round voter checked in
    bool active;                 // Is the voter active
  }

  // Track registered voters
  mapping (address => Voter) public voters;

  // Track stakes for pull requests (opening, merging and challenging)
  mapping (address => uint256) public pullRequestStakes;

  // Checks for valid issue
  modifier validIssue(uint id) {
    // Check for valid issue id
    if (id >= issues.length || id < 0) throw;
    // Check for active issue
    if (!issues[id].active) throw;
    _;
  }

  // Checks for valid pull request
  modifier validPullRequest(uint id) {
    // Check for valid pull request id
    if (id >= pullRequests.length || id < 0) throw;
    // Check for active pull request
    if (!pullRequests[id].active) throw;
    _;
  }

  // Only maintainer can call functions with this modifier
  modifier maintainerOnly {
    if (!maintainers[msg.sender]) throw;
    _;
  }

  // Only an issue creator or a maintainer can call functions with this modifier
  modifier issuePermissions(uint id) {
    if (issues[id].creator != msg.sender && !maintainers[msg.sender]) throw;
    _;
  }

  // Only a pull request creator or a maintainer can call functions with this modifier
  modifier pullRequestPermissions(uint id) {
    if (pullRequests[id].creator != msg.sender && !maintainers[msg.sender]) throw;
    _;
  }

  /*
   * Constructor
   * @param _name Name of repo
   */
  function OpenCollabRepo(string _name) {
    name = _name;
    maintainers[msg.sender] = true;
    maintainerAddresses.push(msg.sender);
    currentPeriod = Period.Regular;
    obsolete = false;
    token = new OpenCollabToken(address(this));

    // Default protocol params
    maintainerPercentage = 50;
    voterRewardPercentage = 5;
    voterPenaltyPercentage = 20;

    voterDeposit = 1000000000000000000;
    maintainerStake = 1000000000000000000;
    contributorStake = 1000000000000000000;
    challengerStake = 1000000000000000000;

    reviewPeriodLength = 1 days;
    votingCommitPeriodLength = 1 days;
    votingRevealPeriodLength = 1 days;

    // Initial token distribution
    token.mint(msg.sender, 60000000000000000000);
  }

  // Mango ref functions

  function refCount() constant returns (uint) {
    return refKeys.length;
  }

  function refName(uint index) constant returns (string ref) {
    ref = refKeys[index];
  }

  function getRef(string ref) constant returns (string hash) {
    hash = refs[ref];
  }

  function __findRef(string ref) private returns (int) {
    /* Horrible way to add a new key to the list */

    for (var i = 0; i < refKeys.length; i++)
      if (strEqual(refKeys[i], ref))
        return i;

    return -1;
  }

  function setRef(string ref, string hash) maintainerOnly {
    if (__findRef(ref) == -1)
      refKeys.push(ref);

    refs[ref] = hash;
  }

  function deleteRef(string ref) maintainerOnly {
    int pos = __findRef(ref);
    if (pos != -1) {
      // FIXME: shrink the array?
      refKeys[uint(pos)] = "";
    }

    // FIXME: null? string(0)?
    refs[ref] = "";
  }

  // Mango snapshot functions

  function snapshotCount() constant returns (uint) {
    return snapshots.length;
  }

  function getSnapshot(uint index) constant returns (string) {
    return snapshots[index];
  }

  function addSnapshot(string hash) maintainerOnly {
    snapshots.push(hash);
  }

  // Mango maintainer functions

  function maintainerCount() constant returns (uint) {
    return maintainerAddresses.length;
  }

  function __findMaintainer(address addr) private returns (int) {
    for (var i = 0; i < maintainerAddresses.length; i++) {
      if (maintainerAddresses[i] == addr)
        return i;
    }

    return -1;
  }

  function getMaintainer(uint idx) constant returns (address) {
    return maintainerAddresses[idx];
  }

  function addMaintainer(address addr) maintainerOnly {
    if (maintainers[addr]) throw;

    maintainers[addr] = true;
    maintainerAddresses.push(addr);
  }

  function removeMaintainer(address addr) internal {
    if (!maintainers[addr]) throw;

    maintainers[addr] = false;

    int pos = __findMaintainer(addr);

    if (pos != -1) {
      maintainerAddresses[uint(pos)] = address(0);
    }
  }

  // Mango utility functions

  function setObsolete() maintainerOnly {
    obsolete = true;
  }

  function strEqual(string a, string b) private returns (bool) {
    return sha3(a) == sha3(b);
  }

  /*
   * Returns number of issues
   */
  function issueCount() constant returns (uint count) {
    return issues.length;
  }

  /*
   * Create new issue
   * @param hash Swarm hash of issue contents
   */
  function newIssue(string hash) returns (bool success) {
    Issue memory issue;

    issue.id = issues.length;
    issue.creator = msg.sender;
    issue.hash = hash;
    issue.totalStake = 0;
    issue.openPullRequest = false;
    issue.pullRequestId = 0;
    issue.active = true;

    issues.push(issue);

    return true;
  }

  function getIssue(uint id) validIssue(id) constant returns (uint, address, string, uint) {
    return (issues[id].id, issues[id].creator, issues[id].hash, issues[id].totalStake);
  }

  /*
   * Set Swarm hash for issue
   * @param id Issue id
   * @param hash Swarm hash of issue contents
   */
  function setIssue(uint id, string hash) validIssue(id) issuePermissions(id) {
    issues[id].hash = hash;
  }

  /*
   * Close issue
   * @param id Issue id
   */
  function closeIssue(uint id) validIssue(id) issuePermissions(id) {
    // Set issue to be inactive
    issues[id].active = false;
  }

  /*
   * Stake tokens to an issue as a curator
   * @param id Issue id
   * @param stake The amount of OCT to stake
   */
  function stakeIssue(uint id, uint stake) validIssue(id) returns (bool success) {
    // Transfer tokens. This call throws if it fails
    token.transferFrom(msg.sender, this, stake);

    // Update sender's staked tokens for this issue
    issues[id].stakedTokens[msg.sender] = safeAdd(issues[id].stakedTokens[msg.sender], stake);

    // Update issue's total stake
    issues[id].totalStake = safeAdd(issues[id].totalStake, stake);

    return true;
  }

  /*
   * Unbond tokens staked to an issue
   * @param id Issue id
   */
  function withdrawIssueStake(uint id) returns (bool success) {
    // Check for valid issue id
    if (id >= issues.length || id < 0) throw;
    // Check if there is an open pull request
    if (issues[id].openPullRequest) throw;
    // Check if sender staked to this issue
    if (issues[id].stakedTokens[msg.sender] == 0) throw;

    // Transfer token. This call throws if it fails
    token.transfer(msg.sender, issues[id].stakedTokens[msg.sender]);

    delete issues[id].stakedTokens[msg.sender];
  }

  /*
   * Returns number of pull requests
   */
  function pullRequestCount() constant returns (uint count) {
    return pullRequests.length;
  }

  /*
   * Get pull request by id
   * @param id Pull request id
   */
  function getPullRequest(uint id) validPullRequest(id) constant returns (uint, uint, address, address) {
    return (pullRequests[id].id, pullRequests[id].issue.id, pullRequests[id].creator, pullRequests[id].fork);
  }

  /*
   * Opens pull request
   * @param issueId Issue id
   * @param fork Contract address for repo fork
   */
  function openPullRequest(uint issueId, address fork) validIssue(issueId) {
    // Transfer tokens. This call throws if it fails
    token.transferFrom(msg.sender, this, contributorStake);

    // Update pullRequestStakes for sender
    pullRequestStakes[msg.sender] = safeAdd(pullRequestStakes[msg.sender], contributorStake);

    PullRequest memory pullRequest;

    pullRequest.id = pullRequests.length;
    pullRequest.issue = issues[issueId];
    issues[issueId].openPullRequest = true;
    issues[issueId].pullRequestId = pullRequest.id;
    pullRequest.creator = msg.sender;
    pullRequest.fork = fork;
    pullRequest.active = true;

    pullRequests.push(pullRequest);
  }

  /*
   * Close pull request. Only used if pull request is not being merged
   * @param id Pull request id
   */
  function closePullRequest(uint id) validPullRequest(id) pullRequestPermissions(id) {
    // Destroy stake
    token.destroy(contributorStake);

    // Update pullRequestStakes for sender
    pullRequestStakes[pullRequests[id].creator] = safeSub(pullRequestStakes[pullRequests[id].creator], contributorStake);

    delete pullRequests[id];
  }

  /*
   * Initialize a pull request merge
   * @param id Pull request id
   */
  function initMergePullRequest(uint id) validPullRequest(id) maintainerOnly {
    // Check if already in a review or voting period
    if (currentPeriod == Period.Review || currentPeriod == Period.Voting) throw;

    // Transfer tokens. This call throws if it fails
    token.transferFrom(msg.sender, this, maintainerStake);

    // Update pullRequestStakes for sender
    pullRequestStakes[msg.sender] = safeAdd(pullRequestStakes[msg.sender], maintainerStake);

    currentPeriod = Period.Review;
    reviewPeriodEnd = block.timestamp + reviewPeriodLength;
  }

  /*
   * Finalize a pull request merge
   * @param id Pull request id
   */
  function mergePullRequest(uint id) validPullRequest(id) maintainerOnly returns (bool success) {
    // Check if in regular period
    if (currentPeriod == Period.Regular) throw;
    // If in review period check if it is over
    if (currentPeriod == Period.Review
        && block.timestamp < reviewPeriodEnd) {
      throw;
    }
    // If in voting period check if voting reveal period is over
    if (currentPeriod == Period.Voting
        && block.timestamp < votingRevealPeriodEnd) {
      throw;
    }

    var totalStake = pullRequests[id].issue.totalStake;

    // Mint issue reward
    token.mint(this, totalStake);

    // Calculate rewards
    uint256 maintainerReward = (totalStake * maintainerPercentage) / 100;
    uint256 contributorReward = totalStake - maintainerReward;

    // Update pullRequestStakes with rewards
    pullRequestStakes[msg.sender] = safeAdd(pullRequestStakes[msg.sender], maintainerReward);
    pullRequestStakes[pullRequests[id].creator] = safeAdd(pullRequestStakes[pullRequests[id].creator], contributorReward);

    // Zero out issue pull request id
    uint issueId = pullRequests[id].issue.id;
    issues[issueId].openPullRequest = false;
    issues[issueId].pullRequestId = 0;

    delete pullRequests[id];

    currentPeriod = Period.Regular;

    return true;
  }

  // Governance voting functions

  /*
   * Deposit tokens to participate as a voter
   */
  function deposit() returns (bool success) {
    // Check if active voter
    if (voters[msg.sender].active) throw;

    // Transfer tokens. This call throws if it fails
    token.transferFrom(msg.sender, this, voterDeposit);

    // Add voter
    voters[msg.sender] = Voter(msg.sender, voterDeposit, 0, true);

    return true;
  }

  /*
   * Challenge a maintainer
   * @param maintainer Address of maintainer
   */
  function challenge(address maintainer) {
    // Check if in review period
    if (currentPeriod != Period.Review) throw;

    // Transfer tokens. This call throws if it fails
    token.transferFrom(msg.sender, this, challengerStake);

    // Update pullRequestStakes for sender
    pullRequestStakes[msg.sender] = safeAdd(pullRequestStakes[msg.sender], challengerStake);

    currentPeriod = Period.Voting;
    votingCommitPeriodEnd = block.timestamp + votingCommitPeriodLength;
    votingRevealPeriodEnd = block.timestamp + votingCommitPeriodLength + votingRevealPeriodLength;
    votingRounds.push(VotingRound(maintainer, msg.sender, 0, 0, VoteValue.None));
  }

  /*
   * Submit a hash as a vote commitment
   * @param commit Vote commitment hash
   */
  function commitVote(bytes32 commit) {
    // Check if in voting period
    if (currentPeriod != Period.Voting) throw;
    // Check if in voting commit period
    if (block.timestamp >= votingCommitPeriodEnd) throw;
    // Check if active voter
    if (!voters[msg.sender].active) throw;
    // Check if sender already voted
    if (votingRounds[votingRounds.length - 1].votes[msg.sender].commited) throw;

    votingRounds[votingRounds.length - 1].votes[msg.sender] = Vote(commit, VoteValue.None, true, false);
  }

  /*
   * Submit a revealed vote
   * @param vote Revealed vote
   */
  function revealVote(string vote) {
    // Check if in voting period
    if (currentPeriod != Period.Voting) throw;
    // Check if in voting reveal period
    if (block.timestamp >= votingRevealPeriodEnd) throw;
    // Check if active voter
    if (!voters[msg.sender].active) throw;
    // Check if sender already revealed
    if (votingRounds[votingRounds.length - 1].votes[msg.sender].revealed) throw;
    // Check if sender's revealed vote matches previous commitment
    if (keccak256(vote) != votingRounds[votingRounds.length - 1].votes[msg.sender].commit) throw;

    // Count vote
    bytes memory bytesVote = bytes(vote);

    if (bytesVote[0] == '1') {
      votingRounds[votingRounds.length - 1].uphold += 1;
      votingRounds[votingRounds.length - 1].votes[msg.sender].voteValue = VoteValue.Uphold;
    } else {
      votingRounds[votingRounds.length - 1].veto += 1;
      votingRounds[votingRounds.length - 1].votes[msg.sender].voteValue = VoteValue.Veto;
    }

    votingRounds[votingRounds.length - 1].votes[msg.sender].revealed = true;
  }

  /*
   * Compute result of vote
   */
  function voteResult() returns (bool success) {
    // Not in voting period
    if (currentPeriod != Period.Voting) throw;
    // Voting reveal period not over
    if (block.timestamp < votingRevealPeriodEnd) throw;

    if (votingRounds[votingRounds.length - 1].uphold >= votingRounds[votingRounds.length - 1].veto) {
      // Decision upheld
      // Destroy challenger staked tokens
      token.destroy(challengerStake);
      // Update stakes for challenger
      // Set vote result to uphold
      votingRounds[votingRounds.length - 1].result = VoteValue.Uphold;
    } else {
      // Decision vetoed
      // Destroy maintainer staked tokens
      token.destroy(maintainerStake);
      // Update stakes for maintainer
      // Remove maintainer
      removeMaintainer(votingRounds[votingRounds.length - 1].maintainer);
      // Set vote result to veto
      votingRounds[votingRounds.length - 1].result = VoteValue.Veto;
    }

    return true;
  }

  /*
   * Check in voter to update deposit based on voting rounds since last check in
   */
  function voterCheckIn() returns (bool success) {
    // Check for valid voter
    if (!voters[msg.sender].active) throw;
    // Check if there has been a voting round since last check in
    if (voters[msg.sender].lastCheckIn > 0 && votingRounds.length - 1 == voters[msg.sender].lastCheckIn) throw;

    uint depositBalance = voters[msg.sender].deposit;

    uint startRound = voters[msg.sender].lastCheckIn + 1;

    if (votingRounds.length - 1 == 0) {
      startRound = 0;
    }

    // Iterate through voting rounds since last check in
    for (uint i = startRound; i < votingRounds.length; i++) {
      if (votingRounds[i].votes[msg.sender].voteValue == VoteValue.None) {
        // Voter abstained
        // Penalize voter
        depositBalance = safeSub(depositBalance, calcVoterPenalty(msg.sender));
      } else {
        if (votingRounds[i].result == votingRounds[i].votes[msg.sender].voteValue) {
          // Voter on winning side
          // Reward voter
          depositBalance = safeAdd(depositBalance, calcVoterReward(msg.sender));
        } else {
          // Voter on losing side
          // Penalize voter
          depositBalance = safeSub(depositBalance, calcVoterPenalty(msg.sender));
        }
      }
    }

    if (depositBalance > voters[msg.sender].deposit) {
      // More rewards than penalties
      uint netReward = safeSub(depositBalance, voters[msg.sender].deposit);
      // Mint the difference
      token.mint(this, netReward);
    } else {
      // More penalties than rewards
      uint netPenalty = safeSub(voters[msg.sender].deposit, depositBalance);
      // Destroy the difference
      token.destroy(netPenalty);
    }

    // Update voter deposit
    voters[msg.sender].deposit = depositBalance;

    // Update voter last check in
    voters[msg.sender].lastCheckIn = votingRounds.length - 1;

    return true;
  }

  /*
   * Withdraw voter deposit
   */
  function voterWithdraw() returns (bool success) {
    // Check for valid voter
    if (!voters[msg.sender].active) throw;
    // Check if voter checked in to the lastest voting round
    if (voters[msg.sender].lastCheckIn == 0 || votingRounds.length - 1 != voters[msg.sender].lastCheckIn) throw;

    // Transfer token. This call will throw if it fails
    token.transfer(msg.sender, voters[msg.sender].deposit);

    delete voters[msg.sender];
  }

  function calcVoterReward(address addr) internal constant returns (uint reward) {
    return (voters[addr].deposit * voterRewardPercentage) / 100;
  }

  function calcVoterPenalty(address addr) internal constant returns (uint penalty) {
    return (voters[addr].deposit * voterPenaltyPercentage) / 100;
  }

  function withdrawStakes() external {
    uint256 stakes = pullRequestStakes[msg.sender];

    if (stakes == 0) throw;
    if (token.balanceOf(address(this)) < stakes) throw;

    pullRequestStakes[msg.sender] = 0;

    token.transfer(msg.sender, stakes);
  }

 }
