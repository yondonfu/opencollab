const MangoRepo = artifacts.require('MangoRepo.sol');
const OpenCollabToken = artifacts.require('OpenCollabToken.sol');

contract('MangoRepo', function(accounts) {
  let repo;
  let token;

  before(async function() {
    repo = await MangoRepo.new('foo');

    const addr = await repo.token.call();

    token = await OpenCollabToken.at(addr);
    token.transferFrom(addr, accounts[0], 10);
  });

  it('should create a new issue', async function() {
    const hash = 'foo';

    await repo.newIssue(hash, {from: accounts[0]});

    const count = await repo.issueCount();

    assert.equal(count.toNumber(), 1, 'should be one issue');
  });
});
