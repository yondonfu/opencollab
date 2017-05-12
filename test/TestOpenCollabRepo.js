const OpenCollabRepo = artifacts.require('OpenCollabRepo.sol');
const OpenCollabToken = artifacts.require('OpenCollabToken.sol');

const BigNumber = require('bignumber.js');

function rpc(method, arg) {
  const req = {
    jsonrpc: '2.0',
    method: method,
    id: new Date().getTime()
  };

  if (arg) req.params = arg;

  return new Promise((resolve, reject) => {
    web3.currentProvider.sendAsync(req, (err, result) => {
      if (err) {
        reject(err);
      } else if (result && result.error) {
        reject(new Error("RPC Error: " + (result.error.message || result.error)));
      } else {
        resolve(result);
      }
    });
  });
}

function toSmallestUnit(value) {
  const bigVal = new BigNumber(value);
  const decimals = new BigNumber(1000000000000000000);

  return bigVal.times(decimals);
}

// Change block time using rpc call evm_setTimestamp
// HT https://github.com/numerai/contract/blob/master/test/numeraire.js
web3.evm = web3.evm || {};
web3.evm.increaseTime = function(time) {
  return rpc('evm_increaseTime', [time]);
};

contract("OpenCollabRepo", function(accounts) {
  let instance;
  let tokenAddress;
  let token;

  before(async function() {
    instance = await OpenCollabRepo.new("foo", {from: accounts[0], gas: 8000000});
    tokenAddress = await instance.token.call();
    token = await OpenCollabToken.at(tokenAddress);
  });

  describe("constructor", async function() {
    it("should initialize with the correct fields", async function() {
      const maintainerPercentage = await instance.maintainerPercentage.call();
      assert.equal(maintainerPercentage, 50, "constructor did not set maintainerPercentage");

      const isMaintainer = await instance.maintainers.call(accounts[0]);
      assert.isOk(isMaintainer, "constructor did not set account 0 as a maintainer");
    });

    it("should do an initial distribution of tokens", async function() {
      const balance = await token.balanceOf(accounts[0]);
      assert.equal(balance.toNumber(), toSmallestUnit(60), "constructor did not distribute tokens to initial maintainer");

      await token.transfer(accounts[1], toSmallestUnit(10), {from: accounts[0]});
      await token.transfer(accounts[2], toSmallestUnit(10), {from: accounts[0]});
      await token.transfer(accounts[3], toSmallestUnit(10), {from: accounts[0]});
      await token.transfer(accounts[4], toSmallestUnit(10), {from: accounts[0]});
      await token.transfer(accounts[5], toSmallestUnit(10), {from: accounts[0]});
    });
  });

  describe("new issue", async function() {
    it("should create a new issue", async function() {
      const hash = "foo";

      await instance.newIssue(hash, {from: accounts[0]});

      const count = await instance.issueCount();

      assert.equal(count.toNumber(), 1, "newIssue did not create a new issue");
    });
  });

  describe("stake issue", async function() {
    it("should stake tokens", async function() {
      const initialBalance = await token.balanceOf(accounts[1]);

      await token.approve(instance.address, 1000, {from: accounts[1]});
      await instance.stakeIssue(0, 1000, {from: accounts[1]});

      const issue = await instance.getIssue(0);
      assert.equal(issue[3], 1000, "stakeIssue did not update issue's total stake for single curator");

      const endBalance = await token.balanceOf(accounts[1]);
      assert.equal(initialBalance.minus(endBalance), 1000, "stakeIssue did not reduce curator's stake from curator balance");
    });

    it("should allow a curator to increase stake", async function() {
      await token.approve(instance.address, 1000, {from: accounts[1]});
      await instance.stakeIssue(0, 1000, {from: accounts[1]});

      const issue = await instance.getIssue(0);
      assert.equal(issue[3], 1000 + 1000, "stakeIssue did not update issue's total stake with single curator's increase");
    });

    it("should allow multiple curators staking", async function() {
      await token.approve(instance.address, 1000, {from: accounts[2]});
      await instance.stakeIssue(0, 1000, {from: accounts[2]});

      const issue = await instance.getIssue(0);
      assert.equal(issue[3], 1000 + 1000 + 1000, "stakeIssue did not update issue's total stake for multiple curators");
    });
  });

  describe("open pull request", async function() {
    it("should open a pull request", async function() {
      const initialBalance = await token.balanceOf(accounts[3]);

      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[3]});
      // Use an Ethereum account as a dummy contract address representing a fork
      await instance.openPullRequest(0, accounts[9], {from: accounts[3]});

      const pullRequest = await instance.getPullRequest(0);
      assert.equal(pullRequest[0], 0, "openPullRequest did not create a pull request with the correct id");
      assert.equal(pullRequest[1], 0, "openPullRequest did not create a pull request with the correct issue id");
      assert.equal(pullRequest[2], accounts[3], "openPullRequest did not create a pull request with the correct creator");
      assert.equal(pullRequest[3], accounts[9], "openPullRequest did not create a pull request with the correct fork");

      const endBalance = await token.balanceOf(accounts[3]);
      assert.equal(initialBalance.minus(endBalance).toNumber(), toSmallestUnit(1), "openPullRequest did not reduce contributor's stake from contributor balance");
    });

    it("should fail for invalid issue id", async function() {
      let threw = false;

      try {
        await instance.openPullRequest(1, accounts[9], {from: accounts[3]});
      } catch (err) {
        threw = true;
      }

      assert.isOk(threw, "openPullRequest did not throw for invalid issue id");
    });
  });

  describe("close pull request", async function() {
    it("should fail if called by a non-maintainer", async function() {
      let threw = false;

      try {
        await instance.closePullRequest(0, {from: accounts[1]});
      } catch (err) {
        threw = true;
      }

      assert.isOk(threw, "closePullRequest did not throw when called by non-maintainer");
    });

    it("should close pull request and destroy contributor's tokens", async function() {
      const repoInitialBalance = await token.balanceOf(instance.address);

      await instance.closePullRequest(0, {from: accounts[0]});

      const repoEndBalance = await token.balanceOf(instance.address);
      assert.equal(repoInitialBalance.minus(repoEndBalance).toNumber(), toSmallestUnit(1), "closePullRequest did not destroy contributor's tokens");
    });
  });

  describe("merge pull request", async function() {
    it("should fail if review period is not over", async function() {
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[3]});
      await instance.openPullRequest(0, accounts[9], {from: accounts[3]});

      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[0]});
      await instance.initMergePullRequest(1, {from: accounts[0]});

      let threw = false;

      try {
        await instance.mergePullRequest(1, {from: accounts[0]});
      } catch (err) {
        threw = true;
      }

      assert.isOk(threw, "mergePullRequest did not throw for ongoing review period");
    });

    it("should distribute rewards for unchallenged merge", async function() {
      // Increase block time by a day
      await web3.evm.increaseTime(24 * 60 * 60);

      const maintainerInitialBalance = await token.balanceOf(accounts[0]);
      const contributorInitialBalance = await token.balanceOf(accounts[3]);

      await instance.mergePullRequest(1, {from: accounts[0]});

      // Maintainer withdraws
      await instance.withdrawStakes({from: accounts[0]});

      // Contributor withdraws
      await instance.withdrawStakes({from: accounts[3]});

      const maintainerEndBalance = await token.balanceOf(accounts[0]);
      const contributorEndBalance = await token.balanceOf(accounts[3]);

      assert.equal(maintainerEndBalance.minus(maintainerInitialBalance).minus(toSmallestUnit(1)), 1500, "mergePullRequest did not correctly distribute maintainer reward");
      assert.equal(contributorEndBalance.minus(contributorInitialBalance).minus(toSmallestUnit(1)), 1500, "mergePullRequest did not correctly distribute contributor reward");
    });

    it("should close an issue", async function() {
      await instance.closeIssue(0, {from: accounts[0]});

      let threw = false;

      try {
        await instance.getIssue(0);
      } catch (err) {
        threw = true;
      }

      assert.isOk(threw, "closeIssue did not set issue as inactive");
    });

    it("should allow curators to withdraw stake", async function() {
      const initialBalance1 = await token.balanceOf(accounts[1]);
      const initialBalance2 = await token.balanceOf(accounts[2]);

      await instance.withdrawIssueStake(0, {from: accounts[1]});
      await instance.withdrawIssueStake(0, {from: accounts[2]});

      const endBalance1 = await token.balanceOf(accounts[1]);
      assert.equal(endBalance1.minus(initialBalance1), 2000, "withdrawIssueStake did not update curator 1's balance");
      const endBalance2 = await token.balanceOf(accounts[2]);
      assert.equal(endBalance2.minus(initialBalance2), 1000, "withdrawIssueStake did not update curator 2's balance");
    });

    it("should run a voting round and uphold a challenged merge", async function() {
      const hash = 'foo';

      await instance.newIssue(hash, {from: accounts[0]});

      await token.approve(instance.address, 3000, {from: accounts[1]});
      await instance.stakeIssue(1, 3000, {from: accounts[1]});

      // Use an Ethereum account as a dummy contract address representing a fork
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[3]});
      await instance.openPullRequest(1, accounts[9], {from: accounts[3]});

      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[0]});
      await instance.initMergePullRequest(2, {from: accounts[0]});

      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[4]});
      await instance.challenge(accounts[0], {from: accounts[4]});

      // Set up voters with deposits
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[0]});
      await instance.deposit({from: accounts[0]});
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[1]});
      await instance.deposit({from: accounts[1]});
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[2]});
      await instance.deposit({from: accounts[2]});
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[3]});
      await instance.deposit({from: accounts[3]});
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[4]});
      await instance.deposit({from: accounts[4]});

      // Generate keccak256 (SHA3) hash. Note using same secret pharse for ease of testing, but in practice secret phrase
      // would be different for every voter

      const secret = "secret";
      const upholdVote = "1" + secret;
      const vetoVote = "2" + secret;
      const upholdCommit = web3.sha3(upholdVote);
      const vetoCommit = web3.sha3(vetoVote);

      await instance.commitVote(upholdCommit, {from: accounts[0]});
      await instance.commitVote(upholdCommit, {from: accounts[1]});
      await instance.commitVote(upholdCommit, {from: accounts[2]});
      await instance.commitVote(vetoCommit, {from: accounts[3]});
      await instance.commitVote(vetoCommit, {from: accounts[4]});

      // Increase block time by a day
      await web3.evm.increaseTime(24 * 60 * 60);

      await instance.revealVote(upholdVote, {from: accounts[0]});
      await instance.revealVote(upholdVote, {from: accounts[1]});
      await instance.revealVote(upholdVote, {from: accounts[2]});
      await instance.revealVote(vetoVote, {from: accounts[3]});
      await instance.revealVote(vetoVote, {from: accounts[4]});

      // Increase block time by a day
      await web3.evm.increaseTime(24 * 60 * 60);

      const repoInitialBalance = await token.balanceOf(instance.address);

      await instance.voteResult({from: accounts[4]});

      const repoEndBalance = await token.balanceOf(instance.address);
      assert.equal(repoInitialBalance.minus(repoEndBalance).toNumber(), toSmallestUnit(1), "voteResult did not destroy challenger's stake after upheld merge");

      // Finalize merge
      await instance.mergePullRequest(2, {from: accounts[0]});

      // Maintainer withdraws
      await instance.withdrawStakes({from: accounts[0]});

      // Contributor withdraws
      await instance.withdrawStakes({from: accounts[3]});
    });

    it("should penalize and reward voters when checking in after upheld merge", async function() {
      await instance.voterCheckIn({from: accounts[0]});
      await instance.voterCheckIn({from: accounts[1]});
      await instance.voterCheckIn({from: accounts[2]});
      await instance.voterCheckIn({from: accounts[3]});
      await instance.voterCheckIn({from: accounts[4]});

      const rewardedVoter = await instance.voters.call(accounts[0]);
      assert.equal(rewardedVoter[1], toSmallestUnit(1) * 1.05, "voterCheckIn did not add reward to voter on winning side");

      const penalizedVoter = await instance.voters.call(accounts[3]);
      assert.equal(penalizedVoter[1], toSmallestUnit(1) * .8, "voterCheckIn did not deduct penalty from voter on losing side");
    });

    it("should run a voting round and veto a challenged merge", async function() {
      const hash = 'foo';

      await instance.newIssue(hash, {from: accounts[0]});

      await token.approve(instance.address, 3000, {from: accounts[1]});
      await instance.stakeIssue(2, 3000, {from: accounts[1]});

      // Use an Ethereum account as a dummy contract address representing a fork
      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[3]});
      await instance.openPullRequest(2, accounts[9], {from: accounts[3]});

      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[0]});
      await instance.initMergePullRequest(3, {from: accounts[0]});

      await token.approve(instance.address, toSmallestUnit(1), {from: accounts[4]});
      await instance.challenge(accounts[0], {from: accounts[4]});

      // Generate keccak256 (SHA3) hash. Note using same secret pharse for ease of testing, but in practice secret phrase
      // would be different for every voter

      const secret = "secret";
      const upholdVote = "1" + secret;
      const vetoVote = "2" + secret;
      const upholdCommit = web3.sha3(upholdVote);
      const vetoCommit = web3.sha3(vetoVote);

      await instance.commitVote(vetoCommit, {from: accounts[0]});
      await instance.commitVote(vetoCommit, {from: accounts[1]});
      await instance.commitVote(vetoCommit, {from: accounts[2]});
      await instance.commitVote(upholdCommit, {from: accounts[3]});
      await instance.commitVote(upholdCommit, {from: accounts[4]});

      // Increase block time by a day
      await web3.evm.increaseTime(24 * 60 * 60);

      await instance.revealVote(vetoVote, {from: accounts[0]});
      await instance.revealVote(vetoVote, {from: accounts[1]});
      await instance.revealVote(vetoVote, {from: accounts[2]});
      await instance.revealVote(upholdVote, {from: accounts[3]});
      await instance.revealVote(upholdVote, {from: accounts[4]});

      // Increase block time by a day
      await web3.evm.increaseTime(24 * 60 * 60);

      const repoInitialBalance = await token.balanceOf(instance.address);

      await instance.voteResult({from: accounts[4]});

      const repoEndBalance = await token.balanceOf(instance.address);
      assert.equal(repoInitialBalance.minus(repoEndBalance).toNumber(), toSmallestUnit(1), "voteResult did not destory maintainer's stake after veoted merge");

      const isMaintainer = await instance.maintainers.call(accounts[0]);
      assert.isNotOk(isMaintainer, "voteResult did not remove maintainer after vetoed merge");
    });

    it("should penalize and reward voters when checking in after vetoed merge", async function() {
      await instance.voterCheckIn({from: accounts[0]});
      await instance.voterCheckIn({from: accounts[1]});
      await instance.voterCheckIn({from: accounts[2]});
      await instance.voterCheckIn({from: accounts[3]});
      // Account 4 does not check in

      const rewardedVoter = await instance.voters.call(accounts[0]);
      assert.equal(rewardedVoter[1], toSmallestUnit(1) * 1.05 * 1.05, "voterCheckIn did not add reward to voter on winning side");

      const penalizedVoter = await instance.voters.call(accounts[3]);
      assert.equal(penalizedVoter[1], toSmallestUnit(1) * .8 * .8, "voterCheckIn did not deduct penalty from voter on losing side");
    });

    it("should allow voters to withdraw deposits", async function() {
      const initialBalance = await token.balanceOf(accounts[0]);

      await instance.voterWithdraw({from: accounts[0]});

      const endBalance = await token.balanceOf(accounts[0]);
      assert.equal(endBalance.minus(initialBalance).toNumber(), toSmallestUnit(1) * 1.05 * 1.05, "voterWithdraw did not update voter balance");
    });

    it("should fail to withdraw deposit if voter did not check in to last voting round", async function() {
      let threw = false;

      try {
        await instance.voterWithdraw({from: accounts[4]});
      } catch (err) {
        threw = true;
      }

      assert.isOk(threw, "voterWithdraw did not throw for voter that has not checked in to lasted voting round");
    });
  });
});
