pragma solidity ^0.4.6;

import "./SafeMath.sol";
import "./OpenCollabToken.sol";

contract OpenCollabRepo is SafeMath {
  string public name;
  bool public obsolete;

  // Repo params

  uint256 maintainerPercentage;
  uint256 voterRewardPercentage;
  uint256 voterPenaltyPercentage;

  uint256 voterDeposit;
  uint256 contributorStake;
  uint256 maintainerStake;
  uint256 challengerStake;

  enum Period { Challenge, Voting, Regular }
  Period currentPeriod;

  uint256 challengePeriod = 1 days;
  uint256 challengePeriodEnd;
  uint256 votingCommitPeriod = 1 days;
  uint256 votingCommitPeriodEnd;
  uint256 votingRevealPeriod = 1 days;
  uint256 votingRevealPeriodEnd;

  struct VotingRound {
    uint256 startTime;
    address maintainer;
    address challenger;
    uint256 uphold;
    uint256 veto;
    mapping (address => Vote) votes;
  }

  struct Vote {
    bytes32 commit;
    uint256 vote;
    bool commited;
    bool revealed;
  }

  VotingRound[] votingRounds;

  // Ledger for how much anyone can currently withdraw
  mapping (address => uint256) funds;

  // Ledger for token holders with deposits for governance voting
  address[] voters;
  mapping (address => uint256) public voterDeposits;

  OpenCollabToken token;

  address[] maintainerAddresses;
  mapping (address => bool) public maintainers;

  string[] refKeys;
  mapping (string => string) refs;

  string[] snapshots;

  struct Issue {
    uint id;
    address creator;
    string hash;
    uint totalStake;
    address[] stakers;
    mapping (address => uint) stakedTokens;
  }

  struct PullRequest {
    uint id;
    Issue issue;
    address creator;
    address fork;
  }

  Issue[] issues;
  PullRequest[] pullRequests;

  modifier maintainerOnly {
    if (!maintainers[msg.sender]) throw;
    _;
  }

  modifier issuePermissions(uint id) {
    if (issues[id].creator != msg.sender && !maintainers[msg.sender]) throw;
    _;
  }

  modifier pullRequestPermissions(uint id) {
    if (pullRequests[id].creator != msg.sender && !maintainers[msg.sender]) throw;
    _;
  }

  function OpenCollabRepo(string _name) {
    name = _name;
    maintainers[msg.sender] = true;
    maintainerAddresses.push(msg.sender);
    currentPeriod = Period.Regular;
    obsolete = false;
    token = new OpenCollabToken(address(this));

    // Default repo params
    maintainerPercentage = 50;
    voterRewardPercentage = 5;
    voterPenaltyPercentage = 20;

    voterDeposit = 2000000000000000000;
    maintainerStake = 1000000000000000000;
    contributorStake = 1000000000000000000;
    challengerStake = 1000000000000000000;
  }

  // Token functions

  function tokenAddr() constant returns (address addr) {
    return address(token);
  }

  function mintOCT(uint256 amount) maintainerOnly {
    token.mint(amount);
  }

  function transferOCT(address to, uint256 value) maintainerOnly {
    token.transfer(to, value);
  }

  // Ref functions

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

  // Snapshot functions

  function snapshotCount() constant returns (uint) {
    return snapshots.length;
  }

  function getSnapshot(uint index) constant returns (string) {
    return snapshots[index];
  }

  function addSnapshot(string hash) maintainerOnly {
    snapshots.push(hash);
  }

  // Issue functions

  function issueCount() constant returns (uint count) {
    return issues.length;
  }

  function getIssue(uint id) constant returns (address creator, string hash, uint totalStake) {
    if (id >= issues.length || id < 0) throw;
    if (bytes(issues[id].hash).length == 0) throw;

    return (issues[id].creator, issues[id].hash, issues[id].totalStake);
  }

  function newIssue(string hash) {
    Issue memory issue;
    issue.id = issues.length - 1;
    issue.creator = msg.sender;
    issue.hash = hash;
    issue.totalStake = 0;

    issues.push(issue);
  }

  function setIssue(uint id, string hash) issuePermissions(id) {
    if (id >= issues.length || id < 0) throw;

    issues[id].hash = hash;
  }

  function deleteIssue(uint id) issuePermissions(id) {
    if (id >= issues.length || id < 0) throw;
    if (bytes(issues[id].hash).length == 0) throw;

    // Release all stakes
    for (uint i = 0; i < issues[id].stakers.length; i++) {
      var staker = issues[id].stakers[i];

      funds[staker] = safeAdd(funds[staker], issues[id].stakedTokens[staker]);
    }

    delete issues[id];
  }

  function stakeIssue(uint id, uint stake) returns (bool success) {
    if (id >= issues.length || id < 0) throw;
    if (bytes(issues[id].hash).length == 0) throw;

    // Transfer stake to repo
    token.stake(msg.sender, stake);

    if (issues[id].stakedTokens[msg.sender] == 0) {
      issues[id].stakers.push(msg.sender);
    }

    issues[id].stakedTokens[msg.sender] = safeAdd(issues[id].stakedTokens[msg.sender], stake);
    issues[id].totalStake = safeAdd(issues[id].totalStake, stake);

    return true;
  }

  // Pull request functions

  function pullRequestCount() constant returns (uint count) {
    return pullRequests.length;
  }

  function getPullRequest(uint id) constant returns (address creator, uint issueId, address fork) {
    if (id >= pullRequests.length || id < 0) throw;
    if (pullRequests[id].fork == address(0)) throw;

    return (pullRequests[id].creator, pullRequests[id].issue.id, pullRequests[id].fork);
  }

  function openPullRequest(uint issueId, address fork) {
    if (bytes(issues[issueId].hash).length == 0) throw;

    // Transfer stake to repo
    token.stake(msg.sender, contributorStake);

    pullRequests.push(PullRequest(pullRequests.length - 1, issues[issueId], msg.sender, fork));
  }

  function closePullRequest(uint id) pullRequestPermissions(id) {
    if (id >= pullRequests.length || id < 0) throw;
    if (pullRequests[id].fork == address(0)) throw;

    // Destroy stake
    token.destroy(contributorStake);

    delete pullRequests[id];
  }

  function initMergePullRequest(uint id) maintainerOnly {
    if (id >= pullRequests.length || id < 0) throw;
    if (pullRequests[id].fork == address(0)) throw;
    // Already in a challenge or voting period
    if (currentPeriod == Period.Challenge || currentPeriod == Period.Voting) throw;

    // Transfer stake to repo
    token.stake(msg.sender, maintainerStake);

    currentPeriod = Period.Challenge;
    challengePeriodEnd = block.timestamp + challengePeriod;
  }

  function mergePullRequest(uint id) maintainerOnly {
    if (id >= pullRequests.length || id < 0) throw;
    if (pullRequests[id].fork == address(0)) throw;
    // Not in challenge or voting period
    if (currentPeriod == Period.Regular) throw;
    // Challenge period not over yet
    if (currentPeriod == Period.Challenge
        && block.timestamp < challengePeriodEnd) {
      throw;
    }
    // Voting period not over yet
    if (currentPeriod == Period.Voting
        && block.timestamp < votingRevealPeriodEnd) {
      throw;
    }

    var totalStake = pullRequests[id].issue.totalStake;

    // Mint issue reward
    token.mint(totalStake);

    // Calculate rewards
    uint256 maintainerReward = calcMaintainerReward(totalStake);
    uint256 contributorReward = totalStake - maintainerReward;

    // Include stakes
    funds[msg.sender] = safeAdd(funds[msg.sender], maintainerReward + maintainerStake);
    funds[pullRequests[id].creator] = safeAdd(funds[pullRequests[id].creator], contributorReward + contributorStake);

    delete pullRequests[id];

    currentPeriod = Period.Regular;
  }

  function calcMaintainerReward(uint256 amount) constant returns (uint256 reward) {
    return (amount * maintainerPercentage) / 100;
  }

  // Governance voting functions

  function deposit() {
    // Check if already deposited
    if (voterDeposits[msg.sender] > 0) throw;
    // Check for insufficient balance
    if (token.balanceOf(msg.sender) < voterDeposit) throw;

    // Transfer stake to repo
    token.stake(msg.sender, voterDeposit);

    voters.push(msg.sender);
    voterDeposits[msg.sender] = safeAdd(voterDeposits[msg.sender], voterDeposit);
  }

  function challenge(address maintainer) {
    // Not in challenge period
    if (currentPeriod != Period.Challenge) throw;
    // Check for insufficient balance
    if (token.balanceOf(msg.sender) < challengerStake) throw;

    // Transfer stake to repo
    token.stake(msg.sender, challengerStake);

    currentPeriod = Period.Voting;
    votingCommitPeriodEnd = block.timestamp + votingCommitPeriod;
    votingRevealPeriodEnd = block.timestamp + votingCommitPeriod + votingRevealPeriod;
    votingRounds.push(VotingRound(block.timestamp, maintainer, msg.sender, 0, 0));
  }

  function commitVote(bytes32 commit) {
    // Not in voting period
    if (currentPeriod != Period.Voting) throw;
    // Not in voting commit period
    if (block.timestamp >= votingCommitPeriodEnd) throw;
    // Check if sender has a voter deposit
    if (voterDeposits[msg.sender] == 0) throw;
    // Already voted
    if (votingRounds[votingRounds.length - 1].votes[msg.sender].commited) throw;

    votingRounds[votingRounds.length - 1].votes[msg.sender] = Vote(commit, 0, true, false);
  }

  function revealVote(string vote) {
    // Not in voting period
    if (currentPeriod != Period.Voting) throw;
    // Not in voting reveal period
    if (block.timestamp >= votingRevealPeriodEnd) throw;
    // Check if sender has a voter deposit
    if (voterDeposits[msg.sender] == 0) throw;
    // Vote already revealed
    if (votingRounds[votingRounds.length - 1].votes[msg.sender].revealed) throw;
    // Revealed vote does not match commit
    if (keccak256(vote) != votingRounds[votingRounds.length - 1].votes[msg.sender].commit) throw;

    // Count vote
    bytes memory bytesVote = bytes(vote);

    if (bytesVote[0] == '1') {
      votingRounds[votingRounds.length - 1].uphold += 1;
      votingRounds[votingRounds.length - 1].votes[msg.sender].vote = 1;
    } else {
      votingRounds[votingRounds.length - 1].veto += 1;
      votingRounds[votingRounds.length - 1].votes[msg.sender].vote = 2;
    }

    votingRounds[votingRounds.length - 1].votes[msg.sender].revealed = true;
  }

  function voteResult() {
    // Not in voting period
    if (currentPeriod != Period.Voting) throw;
    // Voting reveal period not over
    if (block.timestamp < votingRevealPeriodEnd) throw;

    bool upheld = false;

    if (votingRounds[votingRounds.length - 1].uphold >= votingRounds[votingRounds.length - 1].veto) {
      // Decision upheld
      // Destroy challenger staked tokens
      token.destroy(challengerStake);
      upheld = true;
    } else {
      // Decision vetoed
      // Destroy maintainer staked tokens
      token.destroy(maintainerStake);
      // Remove maintainer
      removeMaintainer(votingRounds[votingRounds.length - 1].maintainer);
      upheld = false;
    }

    VotingRound vr = votingRounds[votingRounds.length - 1];

    for (uint256 i = 0; i < voters.length; i++) {
      if (upheld) {
        if (vr.votes[voters[i]].revealed && vr.votes[voters[i]].vote == 1) {
          rewardVoter(voters[i]);
        } else {
          penalizeVoter(voters[i]);
        }
      } else {
        if (vr.votes[voters[i]].revealed && vr.votes[voters[i]].vote == 2) {
          rewardVoter(voters[i]);
        } else {
          penalizeVoter(voters[i]);
        }
      }
    }
  }

  function rewardVoter(address addr) internal {
    uint256 reward = (voterDeposits[addr] * voterRewardPercentage) / 100;
    voterDeposits[addr] = safeAdd(voterDeposits[addr], reward);
  }

  function penalizeVoter(address addr) internal {
    uint256 penalty = (voterDeposits[addr] * voterPenaltyPercentage) / 100;
    voterDeposits[addr] = safeSub(voterDeposits[addr], penalty);
  }

  function reward() external {
    uint256 reward = funds[msg.sender];

    if (reward == 0) throw;
    if (token.balanceOf(address(this)) < reward) throw;

    funds[msg.sender] = 0;

    token.transfer(msg.sender, reward);
  }

  // Maintainer functions

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

  // Utility functions

  function setObsolete() maintainerOnly {
    obsolete = true;
  }

  function strEqual(string a, string b) private returns (bool) {
    return sha3(a) == sha3(b);
  }
}
