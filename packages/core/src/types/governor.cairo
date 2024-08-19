use starknet::ContractAddress;

// Market param update proposal.
//
// * `proposer` - proposer address
// * `proposal_id` - proposal id
// * `market_id` - market id
// * `expiry` - expiry time (unix timestamp)
// TODO: add store packing
#[derive(Drop, Serde, starknet::Store)]
pub struct Proposal {
    pub proposer: ContractAddress,
    pub proposal_id: felt252,
    pub market_id: felt252,
    pub expiry: u64,
}

// Governor parameters.
//
// * `quorum` - percentage of votes required to pass a proposal (base 10000, e.g. 5000 = 50%)
// * `min_ownership` - minimum ownership required to propose a vote (base 10000000, e.g. 1000 = 0.1%)
// * `duration` - duration in seconds that a proposal lasts for
// TODO: add store packing
#[derive(Drop, Copy, Serde, PartialEq, Default, starknet::Store)]
pub struct GovernorParams {
    pub quorum: u16,
    pub min_ownership: u32,
    pub duration: u64,
}
