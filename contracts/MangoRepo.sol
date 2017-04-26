/*
 * Mango Repository
 * Copyright (C) 2016 Alex Beregszaszi
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 3 of the License only.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
pragma solidity ^0.4.6;

import "./SafeMath.sol";
import "./OpenCollabToken.sol";

contract MangoRepo is SafeMath {
  string public name;
  bool public obsolete;
  uint public maintainerPercentage;

  uint openPullRequestStake = 1;
  uint mergePullRequestStake = 1;
  uint challengeStake = 1;

  OpenCollabToken public token;

  address[] maintainerAddresses;
  mapping (address => bool) maintainers;

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

  function voteIssue(uint id, uint stake) returns (bool success) {
    if (id >= issues.length || id < 0) throw;
    if (bytes(issues[id].hash).length == 0) throw;

    // Transfer stake to repo
    token.stake(msg.sender, stake);

    issues[id].stakedTokens[msg.sender] = safeAdd(issues[id].stakedTokens[msg.sender], stake);
    issues[id].totalStake = safeAdd(issues[id].totalStake, stake);

    return true;
  }

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
    token.stake(msg.sender, openPullRequestStake);

    pullRequests.push(PullRequest(pullRequests.length - 1, issues[issueId], msg.sender, fork));
  }

  function closePullRequest(uint id) pullRequestPermissions(id) {
    if (id >= pullRequests.length || id < 0) throw;
    if (pullRequests[id].fork == address(0)) throw;

    // Destroy stake
    token.destroy(openPullRequestStake);

    delete pullRequests[id];
  }

  function setObsolete() maintainerOnly {
    obsolete = true;
  }

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

  function removeMaintainer(address addr) maintainerOnly {
    if (!maintainers[addr]) throw;

    maintainers[addr] = false;

    int pos = __findMaintainer(addr);

    if (pos != -1) {
      maintainerAddresses[uint(pos)] = address(0);
    }
  }
}
