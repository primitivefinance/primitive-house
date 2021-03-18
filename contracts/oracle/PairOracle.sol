pragma solidity ^0.7.1;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";

contract PairOracle {
    using FixedPoint for *;
    uint256 public constant PERIOD = 24 hours;

    struct Snapshot {
        uint112 price0Cumulative;
        uint112 price1Cumulative;
        uint32 timestamp;
    }

    mapping(address => Snapshot[]) internal _snapshots;
    mapping(address => boolean) internal _active;
    address[] internal _pairs;
    address internal _factory;
    // --- Math ---
    uint256 constant WAD = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0 && (z = x / y) * y == x, "ds-math-divide-by-zero");
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

    constructor(address factory_) public {
        _factory = factory_;
    }

    // ===== Admin =====

    /**
     * @notice Adds a pair to `_pairs`.
     */
    function add(address tokenA, address tokenB) external {
        address pair = UniswapV2Library.pairFor(_factory, tokenA, tokenB);
        require(!_active[pair], "PairOracle: INACTIVE");
        _active[pair] = true;
        _pairs.push(pair);
        (uint256 price0Cumulative, uint256 price1Cumulative, ) =
            UniswapV2OracleLibrary.currentCumulativePrices(pair);
        Snapshot memory next =
            Snapshot(block.timestamp, price0Cumulative, price1Cumulative);
        _snapshots[pair].push(next);
    }

    // ===== Update =====

    /**
     * @notice Updates a pair's most recent snapshot if the period has elapsed.
     */
    function updatePair(address pair) external returns (bool) {
        return _update(pair);
    }

    /**
     * @notice Updates the pair of `tokenA` and `tokenB` with most recent snapshot if the period has elapsed.
     */
    function update(address tokenA, address tokenB) external returns (bool) {
        address pair = UniswapV2Library.pairFor(_factory, tokenA, tokenB);
        return _update(pair);
    }

    /**
     * @notice Updates all pairs.
     */
    function _updateAll() internal returns (bool updated) {
        for (uint256 i = 0; i < _pairs.length; i++) {
            if (_update(_pairs[i])) {
                updated = true;
            }
        }
    }

    /**
     * @notice Updates a pair at index `i` for the `_pairs` address array.
     */
    function updateFor(uint256 i, uint256 length)
        external
        returns (bool updated)
    {
        for (; i < length; i++) {
            if (_update(_pairs[i])) {
                updated = true;
            }
        }
    }

    /**
     * @notice Internal fn to update a `pair`s most recent Snapshot. Only updates if period has elapsed.
     */
    function _update(address pair) internal returns (bool) {
        Snapshot memory last = getSnapshotLast(pair);
        uint256 timeElapsed = block.timestamp - last.timestamp;
        if (timeElapsed > PERIOD) {
            (
                uint256 price0Cumulative,
                uint256 price1Cumulative,
                uint32 blockTimestamp
            ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
            Snapshot memory next =
                Snapshot(block.timestamp, price0Cumulative, price1Cumulative);
            _snapshots[pair].push(next);
            return true;
        }

        return false;
    }

    // ===== View Prices =====

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        address pair = UniswapV2Library.pairFor(_factory, tokenA, tokenB);
        if (tokenA == token0) {
            amountOut = getPrice0TWAP(pair).mul(amountIn);
        } else {
            require(tokenA == token1, "ExampleOracleSimple: INVALID_TOKEN");
            amountOut = getPrice1TWAP(pair).mul(amountIn);
        }
    }

    function getNormalizer0(address pair) public view returns (uint256) {
        return
            10 **
                sub(
                    18,
                    uint256(IERC20(IUniswapV2Pair(pair).token0()).decimals())
                ); // Calculate normalization factor of token0
    }

    function getNormalizer1(address pair) public view returns (uint256) {
        return
            10 **
                sub(
                    18,
                    uint256(IERC20(IUniswapV2Pair(pair).token1()).decimals())
                ); // Calculate normalization factor of token1
    }

    /**
     * @notice Source: https://github.com/makerdao/univ2-lp-oracle/blob/master/src/Univ2LpOracle.sol
     */
    function getLPTokenPrice(address pair)
        external
        returns (uint128 quote, uint32 ts)
    {
        // Sync up reserves of uniswap liquidity pool
        IUniswapV2Pair(pair).sync();

        // Get reserves of uniswap liquidity pool
        (uint112 res0, uint112 res1, uint32 _ts) =
            IUniswapV2Pair(pair).getReserves();
        require(res0 > 0 && res1 > 0, "UNIV2LPOracle/invalid-reserves");
        ts = _ts;
        require(ts == block.timestamp);

        // Adjust reserves w/ respect to decimals
        // TODO: is the risk of overflow here worth mitigating? (consider an attacker who can mint a token at will)
        uint256 normalizer0 = getNormalizer0(pair);
        uint256 normalizer1 = getNormalizer1(pair);
        if (normalizer0 > 1) res0 = uint112(res0 * normalizer0);
        if (normalizer1 > 1) res1 = uint112(res1 * normalizer1);

        // Calculate constant product invariant k (WAD * WAD)
        uint256 k = mul(res0, res1);

        // All Oracle prices are priced with 18 decimals against USD
        uint256 val0 = getPrice0TWAP(pair); // Query token0 price from oracle (WAD)
        uint256 val1 = getPrice1Twap(pair); // Query token1 price from oracle (WAD)
        require(val0 != 0, "UNIV2LPOracle/invalid-oracle-0-price");
        require(val1 != 0, "UNIV2LPOracle/invalid-oracle-1-price");

        // Get LP token supply
        uint256 supply = IERC20(pair).totalSupply();

        // No need to check that the supply is nonzero, Solidity reverts on division by zero.
        quote = uint128(mul(2 * WAD, sqrt(wmul(k, wmul(val0, val1)))) / supply);
    }

    function getPrice0TWAP(address pair) external view returns (uint256) {
        uint256 len = getSnapshotsLength(pair);
        require(len > 0, "PairOracle: SNAPSHOT_LEN");
        (uint256 price0CumulativeLast, , uint32 blockTimestamp) =
            _snapshots[pair][len - 1];
        uint256 elapsedTime = block.timestamp - blockTimestamp;
        require(elapsedTime >= PERIOD, "PairOracle: ELAPSED_PERIOD");
        (uint256 price0Cumulative, , ) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        return price0Average.decode144();
    }

    function getPrice1TWAP(address pair) external view returns (uint256) {
        uint256 len = getSnapshotsLength(pair);
        require(len > 0, "PairOracle: SNAPSHOT_LEN");
        (, uint256 price1CumulativeLast, uint32 blockTimestamp) =
            _snapshots[pair][len - 1];
        uint256 elapsedTime = block.timestamp - blockTimestamp;
        require(elapsedTime >= PERIOD, "PairOracle: ELAPSED_PERIOD");
        (, uint256 price1Cumulative, ) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );
        return price1Average.decode144();
    }

    // ===== View =====
    function getSnapshots(address pair)
        public
        view
        returns (Snapshot[] memory)
    {
        return _snapshots;
    }

    function getPairs() public view returns (address[] memory) {
        return _pairs;
    }

    function getSnapshotsLength(address pair) public view returns (uint256) {
        return _snapshots[pair].length;
    }

    function getSnapshotLast(address pair)
        public
        view
        returns (Snapshot memory)
    {
        return _snapshots[pair][_snapshots[pair].length - 1];
    }
}
