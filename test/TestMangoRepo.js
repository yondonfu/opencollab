const MangoRepo = artifacts.require('MangoRepo.sol');
const OpenCollabToken = artifacts.require('OpenCollabToken.sol');

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

// Change block time using rpc call evm_setTimestamp
// HT https://github.com/numerai/contract/blob/master/test/numeraire.js
// Originally https://github.com/numerai/contract/blob/master/test/numeraire.js
web3.evm = web3.evm || {};
web3.evm.increaseTime = function(time) {
  return rpc('evm_increaseTime', [time]);
};

contract('MangoRepo', function(accounts) {
  let repo;
  let token;

  before(async function() {
    repo = await MangoRepo.new('foo', {from: accounts[0], gas: 8000000});

    const tokenAddr = await repo.tokenAddr();
    token = OpenCollabToken.at(tokenAddr);

    // Initial token allocation
    await repo.mintOCT(100, {from: accounts[0]});
    await repo.transferOCT(accounts[0], 20, {from: accounts[0]});
    await repo.transferOCT(accounts[1], 20, {from: accounts[0]});
    await repo.transferOCT(accounts[2], 20, {from: accounts[0]});
    await repo.transferOCT(accounts[3], 20, {from: accounts[0]});
    await repo.transferOCT(accounts[4], 20, {from: accounts[0]});
  });

  it('should properly allocate tokens to different accounts', async function() {
    const balance0 = await token.balanceOf(accounts[0]);
    const balance1 = await token.balanceOf(accounts[1]);
    const balance2 = await token.balanceOf(accounts[2]);
    const balance3 = await token.balanceOf(accounts[3]);
    const balance4 = await token.balanceOf(accounts[4]);

    assert.equal(balance0.toNumber(), 20, 'should have the correct balance for account 0');
    assert.equal(balance1.toNumber(), 20, 'should have the correct balance for account 1');
    assert.equal(balance2.toNumber(), 20, 'should have the correct balance for account 2');
    assert.equal(balance3.toNumber(), 20, 'should have the correct balance for account 3');
    assert.equal(balance4.toNumber(), 20, 'should have the correct balance for account 4');
  });

  it('should create a new issue', async function() {
    const hash = 'foo';

    await repo.newIssue(hash, {from: accounts[0]});

    const count = await repo.issueCount();

    assert.equal(count.toNumber(), 1, 'should be one issue');
  });

  it('should vote for an issue by staking tokens', async function() {
    const balance1Start = await token.balanceOf(accounts[1]);
    const balance2Start = await token.balanceOf(accounts[2]);
    const repoBalanceStart = await token.balanceOf(repo.address);

    await repo.stakeIssue(0, 4, {from: accounts[1]});

    let issue = await repo.getIssue(0);
    let totalStake = issue[2];
    let repoBalance = await token.balanceOf(repo.address);

    const balance1End = await token.balanceOf(accounts[1]);

    assert.equal(totalStake, 4, 'issue should have correct total stake from 1 voter');
    assert.equal(repoBalance.toNumber() - repoBalanceStart.toNumber(), 4, 'repo balance should change by correct amount after 1 voter');
    assert.equal(balance1Start.toNumber() - balance1End.toNumber(), 4, 'voter 1 balance should change by correct amount');

    await repo.stakeIssue(0, 2, {from: accounts[2]});

    issue = await repo.getIssue(0);
    totalStake = issue[2];
    repoBalance = await token.balanceOf(repo.address);

    const balance2End = await token.balanceOf(accounts[2]);

    assert.equal(totalStake, 6, 'issue should have correct total stake from 2 voters');
    assert.equal(repoBalance.toNumber() - repoBalanceStart.toNumber(), 6, 'repo balance should change by correct amount after 2 voters');
    assert.equal(balance2Start.toNumber() - balance2End.toNumber(), 2, 'voter 2 balance should change by correct amount');
  });

  it('should open a pull request by staking tokens', async function() {
    const contributorBalanceStart = await token.balanceOf(accounts[3]);
    const repoBalanceStart = await token.balanceOf(repo.address);

    // Use an Ethereum account as a dummy contract address representing a fork
    await repo.openPullRequest(0, accounts[9], {from: accounts[3]});

    let pullRequest = await repo.getPullRequest(0);
    let fork = pullRequest[2];
    let repoBalance = await token.balanceOf(repo.address);

    const contributorBalanceEnd = await token.balanceOf(accounts[3]);

    assert.equal(fork, accounts[9], 'pull request should have the correct fork contract address');
    assert.equal(repoBalance.toNumber() - repoBalanceStart.toNumber(), 1, 'repo balance should change by correct balance from opened pull request');
    assert.equal(contributorBalanceStart.toNumber() - contributorBalanceEnd.toNumber(), 1, 'contributor balance should change by correct amount');
  });

  it('should destroy stake for closed and unmerged pull request', async function() {
    const repoBalanceStart = await token.balanceOf(repo.address);

    await repo.closePullRequest(0, {from: accounts[0]});

    let repoBalance = await token.balanceOf(repo.address);

    assert.equal(repoBalanceStart.toNumber() - repoBalance.toNumber(), 1, 'repo token balance should reflect destroyed stake');
  });

  it('should reject merge if challenge period is not over', async function() {
    // Use an Ethereum account as a dummy contract address representing a fork
    await repo.openPullRequest(0, accounts[9], {from: accounts[3]});

    await repo.initMergePullRequest(1, {from: accounts[0]});

    let threw = false;

    try {
      await repo.mergePullRequest(1, {from: accounts[0]});
    } catch (err) {
      threw = true;
    }

    assert.ok(threw, 'merge pull request should throw');
  });

  it('should distribute rewards for an unchallenged merged pull request', async function() {
    const maintainerBalanceStart = await token.balanceOf(accounts[0]);
    const contributorBalanceStart = await token.balanceOf(accounts[3]);
    const voter1BalanceStart = await token.balanceOf(accounts[1]);
    const voter2BalanceStart = await token.balanceOf(accounts[2]);

    // Increase block time by a day
    await web3.evm.increaseTime(24 * 60 * 60);

    await repo.mergePullRequest(1, {from: accounts[0]});

    // Maintainer claims reward
    await repo.reward({from: accounts[0]});

    // Contributor claims reward
    await repo.reward({from: accounts[3]});

    const maintainerBalanceEnd = await token.balanceOf(accounts[0]);
    const contributorBalanceEnd = await token.balanceOf(accounts[3]);

    assert.equal(maintainerBalanceEnd.toNumber() - maintainerBalanceStart.toNumber(), 4, 'maintainer should update token balance with reward');
    assert.equal(contributorBalanceEnd.toNumber() - contributorBalanceStart.toNumber(), 4, 'contributor should update token balance with reward');

    // Delete issue
    await repo.deleteIssue(0);

    // Voter 1 claims stake
    await repo.reward({from: accounts[1]});

    // Voter 2 claims stake
    await repo.reward({from: accounts[2]});

    const voter1BalanceEnd = await token.balanceOf(accounts[1]);
    const voter2BalanceEnd = await token.balanceOf(accounts[2]);

    assert.equal(voter1BalanceEnd.toNumber() - voter1BalanceStart.toNumber(), 4, 'voter 1 should update token balance with released stake');
    assert.equal(voter2BalanceEnd.toNumber() - voter2BalanceStart.toNumber(), 2, 'voter 2 should update token balance with released stake');
  });

  it('should run a voting round and uphold a challenged pull request', async function() {
    const hash = 'foo';

    await repo.newIssue(hash, {from: accounts[0]});

    await repo.stakeIssue(1, 6, {from: accounts[1]});

    // Use an Ethereum account as a dummy contract address representing a fork
    await repo.openPullRequest(1, accounts[9], {from: accounts[3]});

    await repo.initMergePullRequest(2, {from: accounts[0]});

    await repo.challenge(accounts[0], {from: accounts[4]});

    await repo.vote(true, {from: accounts[0]});
    await repo.vote(true, {from: accounts[1]});
    await repo.vote(true, {from: accounts[2]});
    await repo.vote(false, {from: accounts[3]});
    await repo.vote(false, {from: accounts[4]});

    // Increase block time by a day
    await web3.evm.increaseTime(24 * 60 * 60);

    const repoBalanceStart = await token.balanceOf(repo.address);

    await repo.voteResult({from: accounts[4]});

    const repoBalanceEnd = await token.balanceOf(repo.address);

    assert.equal(repoBalanceStart.toNumber() - repoBalanceEnd.toNumber(), 1, 'repo balance should reflect destroyed tokens');

    await repo.mergePullRequest(2, {from: accounts[0]});
  });

  it('should run a voting round and veto a challenged pull request', async function() {
    const hash = 'foo';

    await repo.newIssue(hash, {from: accounts[0]});

    await repo.stakeIssue(2, 6, {from: accounts[1]});

    // Use an Ethereum account as a dummy contract address representing a fork
    await repo.openPullRequest(2, accounts[9], {from: accounts[3]});

    await repo.initMergePullRequest(3, {from: accounts[0]});

    await repo.challenge(accounts[0], {from: accounts[4]});

    await repo.vote(false, {from: accounts[0]});
    await repo.vote(false, {from: accounts[1]});
    await repo.vote(false, {from: accounts[2]});
    await repo.vote(true, {from: accounts[3]});
    await repo.vote(true, {from: accounts[4]});

    // Increase block time by a day
    await web3.evm.increaseTime(24 * 60 * 60);

    const repoBalanceStart = await token.balanceOf(repo.address);

    await repo.voteResult({from: accounts[4]});

    const repoBalanceEnd = await token.balanceOf(repo.address);

    assert.equal(repoBalanceStart.toNumber() - repoBalanceEnd.toNumber(), 1, 'repo balance should reflect destroyed tokens');

    const isMaintainer = await repo.maintainers.call(accounts[0]);

    assert.isNotOk(isMaintainer, 'account should lose maintainer status due to veto');
  });

});
