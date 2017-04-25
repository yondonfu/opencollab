pragma solidity ^0.4.6;

// ERC20 interface
// https://github.com/ethereum/EIPs/issues/20

contract ERC20 {
  uint public totalSupply;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  function balanceOf(address owner) constant returns (uint256 balance);
  function transfer(address to, uint256 value) returns (bool success);
  function transferFrom(address from, address to, uint256 value) returns (bool success);
  function approve(address spender, uint256 value) returns (bool success);
  function allowance(address owner, address spender) constant returns (uint256 remaining);
}
