pragma solidity ^0.4.6;

import "./ERC20.sol";
import "./SafeMath.sol";

contract OpenCollabToken is ERC20, SafeMath {
  string public standard = "ERC20";
  string public name = "OpenCollabToken";
  string public symbol = "OCT";
  uint256 public decimals = 18;

  mapping (address => uint) balances;
  mapping (address => mapping (address => uint256)) allowed;

  address public repoAddress;

  uint256 public supplyCap = 21000000000000000000000000;

  modifier onlyRepo() {
    if (msg.sender != repoAddress) throw;
    _;
  }

  function OpenCollabToken(address _repoAddress) {
    repoAddress = _repoAddress;
  }

  function mint(address to, uint256 value) onlyRepo returns (bool success) {
    // Cannot mint more than cap
    if ((totalSupply + value) > supplyCap) throw;

    balances[to] = safeAdd(balances[to], value);
    totalSupply = safeAdd(totalSupply, value);

    return true;
  }

  function destroy(uint256 value) onlyRepo returns (bool success) {
    // Cannot destroy such that supply is less than 0
    if ((totalSupply - value) < 0) throw;

    balances[repoAddress] = safeSub(balances[repoAddress], value);
    totalSupply = safeSub(totalSupply, value);

    return true;
  }

  // ERC20 standard functions

  function transfer(address to, uint256 value) returns (bool success) {
    balances[msg.sender] = safeSub(balances[msg.sender], value);
    balances[to] = safeAdd(balances[to], value);

    Transfer(msg.sender, to, value);

    return true;
  }

  function transferFrom(address from, address to, uint value) returns (bool success) {
    var allowance = allowed[from][msg.sender];

    balances[to] = safeAdd(balances[to], value);
    balances[from] = safeSub(balances[from], value);
    allowed[from][msg.sender] = safeSub(allowance, value); // safeSub throws if value > allowance, rolling everything back

    Transfer(from, to, value);

    return true;
  }

  function balanceOf(address owner) constant returns (uint balance) {
    return balances[owner];
  }

  function approve(address spender, uint value) returns (bool success) {
    allowed[msg.sender][spender] = value;

    Approval(msg.sender, spender, value);

    return true;
  }

  function allowance(address owner, address spender) constant returns (uint remaining) {
    return allowed[owner][spender];
  }
}
