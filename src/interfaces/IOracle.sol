// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/**
 * @title IOracle
 * @notice Interface for price oracle implementations
 * @dev Compatible with Chainlink AggregatorV3Interface and similar oracle providers
 */
interface IOracle {
    /**
     * @notice Returns the number of decimals the oracle response is given in
     * @dev Usually 8 for Chainlink price feeds, but can vary by implementation
     * @return The number of decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the latest round data from the oracle
     * @dev Provides comprehensive information about the latest price update
     * @return roundId The round ID of the latest valid data
     * @return answer The price answer (actual price scaled by decimals())
     * @return startedAt The timestamp when the round started
     * @return updatedAt The timestamp when the round was last updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Returns the latest price from the oracle
     * @dev Simplified method that returns only the price answer
     * @return The latest price scaled by decimals()
     */
    function latestAnswer() external view returns (int256);
}
