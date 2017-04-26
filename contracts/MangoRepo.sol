pragma solidity ^0.4.6;

import "./SafeMath.sol";
import "./OpenCollabToken.sol";

contract MangoRepo is SafeMath {
  string public name;
  bool public obsolete;
  uint maintainerPercentage = 50;

  uint contributorStake = 1;
  uint maintainerStake = 1;
  uint challengerStake = 1;

  enum Period { Challenge, Voting, Regular }
  Period currentPeriod;

  uint256 challengePeriod = 1 days;
  uint256 challengePeriodEnd;
  uint256 votingPeriod = 1 days;
  uint256 votingPeriodEnd;

  struct VotingRound {
    uint256 startTime;
    address maintainer;
    address challenger;
    uint256 uphold;
    uint256 veto;
    mapping (address => bool) voted;
  }

  VotingRound[] votingRounds;

  mapping (address => uint) rewards;

  OpenCollabToken public token;

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

  function MangoRepo(string _name) {
    name = _name;
    maintainers[msg.sender] = true;
    maintainerAddresses.push(msg.sender);
    currentPeriod = Period.Regular;
    obsolete = false;
    token = new OpenCollabToken(address(this));
  }

  function tokenAddr() constant returns (address addr) {
    return address(token);
  }

  function mintOCT(uint256 amount) maintainerOnly {
    token.mint(amount);
  }

  function transferOCT(address to, uint256 value) maintainerOnly {
    token.transfer(to, value);
  }

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

  function strEqual(string a, string b) private returns (bool) {
    return sha3(a) == sha3(b);
  }

  function snapshotCount() constant returns (uint) {
    return snapshots.length;
  }

  function getSnapshot(uint index) constant returns (string) {
    return snapshots[index];
  }

  function addSnapshot(string hash) maintainerOnly {
    snapshots.push(hash);
  }

  // Issue operations

  function issueCount() constant returns (uint count) {
    return issues.length;
  }

  function getIssue(uint id) constant returns (address creator, string hash, uint totalStake) {
    if (id >= issues.length || id < 0) throw;
    if (bytes(issues[id].hash).length == 0) throw;

    return (issues[id].creator, issues[id].hash, issues[id].totalStake);
  }

  function newIssue(string hash) {
    issues.push(Issue(issues.length - 1, msg.sender, hash, 0));
  }

  function setIssue(uint id, string hash) issuePermissions(id) {
    if (id >= issues.length || id < 0) throw;

    issues[id].hash = hash;
  }

  function deleteIssue(uint id) issuePermissions(id) {
    if (id >= issues.length || id < 0) throw;
    if (bytes(issues[id].hash).length == 0) throw;

    delete issues[id];
  }

  function stakeIssue(uint id, uint stake) returns (bool success) {
    if (id >= issues.length || id < 0) throw;
    if (bytes(issues[id].hash).length == 0) throw;

    // Transfer stake to repo
    token.stake(msg.sender, stake);

    issues[id].stakedTokens[msg.sender] = safeAdd(issues[id].stakedTokens[msg.sender], stake);
    issues[id].totalStake = safeAdd(issues[id].totalStake, stake);

    return true;
  }

  // Pull request operations

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
        && block.timestamp < votingPeriodEnd) {
      throw;
    }

    // Mint issue reward
    token.mint(pullRequests[id].issue.totalStake);

    // Calculate rewards
    uint256 maintainerReward = calcMaintainerReward(pullRequests[id].issue.totalStake);
    uint256 contributorReward = pullRequests[id].issue.totalStake - maintainerReward;

    // Include stakes
    rewards[msg.sender] = safeAdd(rewards[msg.sender], maintainerReward + maintainerStake);
    rewards[pullRequests[id].creator] = safeAdd(rewards[pullRequests[id].creator], contributorReward + contributorStake);

    delete pullRequests[id];

    currentPeriod = Period.Regular;
  }

  function calcMaintainerReward(uint256 amount) constant returns (uint256 reward) {
    return (amount * maintainerPercentage) / 100;
  }

  function challenge(address maintainer) {
    // Not in challenge period
    if (currentPeriod != Period.Challenge) throw;
    // Check for insufficient balance
    if (token.balanceOf(msg.sender) < challengerStake) throw;

    // Transfer stake to repo
    token.stake(msg.sender, challengerStake);

    currentPeriod = Period.Voting;
    votingPeriodEnd = block.timestamp + votingPeriod;
    votingRounds.push(VotingRound(block.timestamp, maintainer, msg.sender, 0, 0));
  }

  function vote(bool uphold) {
    // Not in voting period
    if (currentPeriod != Period.Voting) throw;
    // Check if sender is a token holder
    if (token.balanceOf(msg.sender) == 0) throw;
    // Already voted
    if (votingRounds[votingRounds.length - 1].voted[msg.sender]) throw;

    if (uphold) {
      votingRounds[votingRounds.length - 1].uphold += 1;
    } else {
      votingRounds[votingRounds.length - 1].veto += 1;
    }

    votingRounds[votingRounds.length - 1].voted[msg.sender] = true;
  }

  function voteResult() {
    // Not in voting period
    if (currentPeriod != Period.Voting) throw;
    // Voting period not over
    if (block.timestamp < votingPeriodEnd) throw;

    // TODO: what if there is a tie?
    if (votingRounds[votingRounds.length - 1].uphold > votingRounds[votingRounds.length - 1].veto) {
      // Decision upheld
      // Destroy challenger staked tokens
      token.destroy(challengerStake);
    } else {
      // Decision vetoed
      // Destroy maintainer staked tokens
      token.destroy(maintainerStake);
      // Remove maintainer
      removeMaintainer(votingRounds[votingRounds.length - 1].maintainer);
    }
  }

  function reward() external {
    uint256 reward = rewards[msg.sender];

    if (reward == 0) throw;
    if (token.balanceOf(address(this)) < reward) throw;

    rewards[msg.sender] = 0;

    token.transfer(msg.sender, reward);
  }

  function setObsolete() maintainerOnly {
    obsolete = true;
  }

  // Maintainer operations

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
}
