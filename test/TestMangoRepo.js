const MangoRepo = artifacts.require('MangoRepo.sol');
const OpenCollabToken = artifacts.require('OpenCollabToken.sol');

contract('MangoRepo', function(accounts) {
  let repo;
  let token;

  before(async function() {
    repo = await MangoRepo.new('foo', {from: accounts[0]});

    const tokenAddr = await repo.tokenAddr();
    token = OpenCollabToken.at(tokenAddr);

    // Initial token allocation
    await repo.mintOCT(100, {from: accounts[0]});
    await repo.transferOCT(accounts[1], 20, {from: accounts[0]});
    await repo.transferOCT(accounts[2], 20, {from: accounts[0]});
    await repo.transferOCT(accounts[3], 20, {from: accounts[0]});
  });

  it('should properly allocate tokens to differerent accounts', async function() {
    const balance1 = await token.balanceOf(accounts[1]);
    const balance2 = await token.balanceOf(accounts[2]);
    const balance3 = await token.balanceOf(accounts[3]);

    assert.equal(balance1.toNumber(), 20, 'should have the correct balance for account 1');
    assert.equal(balance2.toNumber(), 20, 'should have the correct balance for account 2');
    assert.equal(balance3.toNumber(), 20, 'should have the correct balance for account 3');
  });

  it('should create a new issue', async function() {
    const hash = 'foo';

    await repo.newIssue(hash, {from: accounts[0]});

    const count = await repo.issueCount();

    assert.equal(count.toNumber(), 1, 'should be one issue');
  });

  it('should vote for an issue by staking tokens', async function() {
    await repo.voteIssue(0, 4, {from: accounts[1]});

    let issue = await repo.getIssue(0);
    let totalStake = issue[2];
    let repoBalance = await token.balanceOf(repo.address);

    assert.equal(totalStake, 4, 'issue should have correct total stake from 1 voter');
    assert.equal(repoBalance.toNumber(), 44, 'repo should have correct balance from 1 voter');

    await repo.voteIssue(0, 2, {from: accounts[2]});

    issue = await repo.getIssue(0);
    totalStake = issue[2];
    repoBalance = await token.balanceOf(repo.address);

    assert.equal(totalStake, 6, 'issue should have correct total stake from 2 voters');
    assert.equal(repoBalance.toNumber(), 46, 'repo should have correct balance from 2 voters');
  });

  it('should open a pull request by staking tokens', async function() {
    // Use an Ethereum account as a dummy contract address representing a fork
    await repo.openPullRequest(0, accounts[9], {from: accounts[3]});

    let pullRequest = await repo.getPullRequest(0);
    let fork = pullRequest[2];
    let repoBalance = await token.balanceOf(repo.address);

    assert.equal(fork, accounts[9], 'pull request should have the correct fork contract address');
    assert.equal(repoBalance.toNumber(), 47, 'repos should have the correct balance from an opened pull request');
  });

  it('should destroy stake for closed and unmerged pull request', async function() {
    await repo.closePullRequest(0, {from: accounts[0]});

    const repoBalance = await token.balanceOf(repo.address);

    assert.equal(repoBalance.toNumber(), 46, 'repo token balance should reflect destroyed stake');
  });
});
