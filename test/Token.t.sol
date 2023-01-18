// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "../lib/forge-std/src/Test.sol";
import "./Utility.sol";
import { Inuvation } from "../src/Token.sol";
import { IUniswapV2Router02, IUniswapV2Pair, IUniswapV2Router01, IERC20 } from "../src/interfaces/Interfaces.sol";

contract TokenTest is Utility, Test {
    Inuvation inuvationToken;

    address constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    function setUp() public {
        createActors();
        setUpTokens();
        
        // deploy token.
        inuvationToken = new Inuvation(
            address(joe),
            address(jon),
            address(nik),
            address(tim)
        );

        uint WETH_DEPOSIT = 5 ether;
        uint TOKEN_DEPOSIT = 55_000_000 * NIN;

        deal(WETH, address(this), WETH_DEPOSIT);

        // Approve TaxToken for UniswapV2Router.
        IERC20(address(inuvationToken)).approve(
            address(UNIV2_ROUTER), TOKEN_DEPOSIT
        );

        // Create liquidity pool.
        // https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02#addliquidityeth
        // NOTE: ETH_DEPOSIT = The amount of ETH to add as liquidity if the token/WETH price is <= amountTokenDesired/msg.value (WETH depreciates).
        IUniswapV2Router01(UNIV2_ROUTER).addLiquidityETH{value: 100 ether}(
            address(inuvationToken),    // A pool token.
            TOKEN_DEPOSIT,              // The amount of token to add as liquidity if the WETH/token price is <= msg.value/amountTokenDesired (token depreciates).
            TOKEN_DEPOSIT,              // Bounds the extent to which the WETH/token price can go up before the transaction reverts. Must be <= amountTokenDesired.
            WETH_DEPOSIT,               // Bounds the extent to which the token/WETH price can go up before the transaction reverts. Must be <= msg.value.
            address(this),              // Recipient of the liquidity tokens.
            block.timestamp + 300       // Unix timestamp after which the transaction will revert.
        );

        inuvationToken.enableTrading();
    }


    // ~~ Utility ~~


    // ~~ Utility Functions ~~


    // Return a quote of PROVE tokens for WETH
    function get_quote_tokens(uint256 weth_amt) internal returns (uint256) {
        // create path
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(inuvationToken);

        // Get Quoted amount
        uint[] memory amounts = IUniswapV2Router01(UNIV2_ROUTER).getAmountsOut( weth_amt, path );

        // return amount
        return amounts[1];
    }

    // Return a quote of WETH for PROVE tokens
    function get_quote_weth(uint256 token_amt) internal returns (uint256) {
        // create path
        address[] memory path = new address[](2);
        path[0] = address(inuvationToken);
        path[1] = WETH;

        // Get Quoted amount
        uint[] memory amounts = IUniswapV2Router01(UNIV2_ROUTER).getAmountsOut( token_amt, path );

        // return amount
        return amounts[1];
    }

    // Perform a buy to generate fees
    function buy_generateFees(uint256 tradeAmt) internal {
        // approve
        IERC20(WETH).approve(address(UNIV2_ROUTER), tradeAmt);

        // create path
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(inuvationToken);

        // execute buy
        IUniswapV2Router02(UNIV2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tradeAmt,
            0,
            path,
            address(this),
            block.timestamp + 300
        );
    }

    // Perform a buy to generate fees
    function sell_generateFees(uint256 tradeAmt) internal {
        // approve
        inuvationToken.approve(address(UNIV2_ROUTER), tradeAmt);

        // create path
        address[] memory path = new address[](2);
        path[0] = address(inuvationToken);
        path[1] = WETH;

        // execute sell
        IUniswapV2Router02(UNIV2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tradeAmt,
            0,
            path,
            address(this),
            block.timestamp + 300
        );
    }


    // ~~ Unit Tests ~~


    // Initial state test.
    function test_inuvationToken_init_state() public {
        assertEq(inuvationToken.totalSupply(),     100_000_000 * 10 ** inuvationToken.decimals());
        assertEq(inuvationToken.balanceOf(address(this)), 45_000_000 * 10 ** inuvationToken.decimals());
        assertEq(inuvationToken.owner(), address(this));
    }

    // verify taxed buy
    function test_inuvationToken_buy_tax() public {
        inuvationToken.excludeFromFees(address(this), false);

        // Verify address(this) is NOT excluded from fees and grab pre balance.
        assert(!inuvationToken._isExcludedFromFees(address(this)));
        uint256 preBal = inuvationToken.balanceOf(address(this));

        // Deposit 10 WETH
        deal(WETH, address(this), 10 ether);

        // get quote
        uint256 amountQuoted = get_quote_tokens(10 ether);

        // execute purchase
        buy_generateFees(10 ether);

        // Grab post balanace and calc amount goge tokens received.
        uint256 postBal        = inuvationToken.balanceOf(address(this));
        uint256 amountReceived = (postBal - preBal);
        uint256 taxedAmount    = amountQuoted * 10/100;

        uint256 amountForBurn  = taxedAmount * 1/10;
        uint256 amountForVault = taxedAmount * 9/10;

        // Verify the quoted amount (minus taxed amount) is the amount received.
        assertEq(amountQuoted - taxedAmount, amountReceived);
        withinDiff(taxedAmount, amountForBurn + amountForVault, 1);
        assertEq(inuvationToken.balanceOf(address(inuvationToken)), amountForVault);

        // Log
        emit log_named_uint("amount for burn",  amountForBurn);  // 49_863.599163408
        emit log_named_uint("amount for vault", amountForVault); // 448_772.392470673
        emit log_named_uint("amount quoted", amountQuoted);      // 4_986_359.916340820
        emit log_named_uint("amount received", amountReceived);  // 4_487_723.924706738
        emit log_named_uint("quoted tax", taxedAmount);          // 498_635.991634082
        emit log_named_uint("actual tax", inuvationToken.balanceOf(address(inuvationToken)));   // 448_772.392470674
    }

    // verify whitelisted buy
    function test_inuvationToken_buy_noTax() public {
        // Verify address(this) is excluded from fees and grab pre balance.
        assert(inuvationToken._isExcludedFromFees(address(this)));
        uint256 preBal = inuvationToken.balanceOf(address(this));

        // Deposit 10 WETH
        deal(WETH, address(this), 10 ether);

        // get quote
        uint256 amountQuoted = get_quote_tokens(10 ether);

        // execute purchase
        buy_generateFees(10 ether);

        // Grab post balanace and calc amount goge tokens received.
        uint256 postBal        = inuvationToken.balanceOf(address(this));
        uint256 amountReceived = (postBal - preBal);

        // Verify the quoted amount is the amount received and no royalties were generated.
        assertEq(amountQuoted, amountReceived);
        assertEq(IERC20(address(inuvationToken)).balanceOf(address(inuvationToken)), 0);

        // Log
        emit log_uint(amountQuoted);
        emit log_uint(amountReceived);
        emit log_uint(IERC20(address(inuvationToken)).balanceOf(address(inuvationToken)));
    }

    // verify taxed buy with fuzzing. Random amounts between .001 ether ($1.4) and 100 ether ($1.4M).
    // NOTE: maxTx is set to MAX for address(this) thus no limitation on buy amount.
    function test_inuvationToken_buy_tax_fuzzing_noLimit(uint256 _amount) public {
        _amount = bound(_amount, 0.001 ether, 1_000 ether);

        // Set maxWalletSize and maxTx to MAX and remove address(this) from whitelist
        inuvationToken.excludeFromFees(address(this), false);

        // Verify address(this) is NOT excluded from fees and grab pre balance
        assert(!inuvationToken._isExcludedFromFees(address(this)));
        uint256 preBal = inuvationToken.balanceOf(address(this));

        // Deposit 10 WETH
        deal(WETH, address(this), _amount);

        // get quote
        uint256 amountQuoted = get_quote_tokens(_amount);

        // execute purchase
        buy_generateFees(_amount);

        // Grab post balanace and calc amount goge tokens received
        uint256 postBal        = inuvationToken.balanceOf(address(this));
        uint256 amountReceived = (postBal - preBal);
        uint256 taxedAmount    = amountQuoted * 10/100;

        uint256 amountForBurn  = taxedAmount * 1/10;
        uint256 amountForVault = taxedAmount * 9/10;

        // Verify the quoted amount (minus taxed amount) is the amount received
        assertEq(amountQuoted - taxedAmount, amountReceived);
        withinDiff(taxedAmount, amountForBurn + amountForVault, 1);
        assertEq(inuvationToken.balanceOf(address(inuvationToken)), amountForVault);

        // Log
        emit log_named_uint("amount quoted", amountQuoted);
        emit log_named_uint("amount received", amountReceived);
        emit log_named_uint("quoted tax", taxedAmount);
        emit log_named_uint("actual tax", inuvationToken.balanceOf(address(inuvationToken)));
    }

    // verify taxed sell
    function test_inuvationToken_sell_tax() public {
        inuvationToken.excludeFromFees(address(this), false);

        // Verify address(this) is NOT excluded from fees and grab pre balance.
        assert(!inuvationToken._isExcludedFromFees(address(this)));
        uint256 preBal = IERC20(WETH).balanceOf(address(this));

        // get quote
        uint256 amountQuoted = get_quote_weth(1_000_000 * NIN);

        // execute purchase
        sell_generateFees(1_000_000 * NIN);

        // Grab post balanace and calc amount goge tokens received.
        uint256 postBal        = IERC20(WETH).balanceOf(address(this));
        uint256 amountReceived = (postBal - preBal);
        uint256 afterTaxAmount = amountQuoted * (100 - 10) / 100;

        uint256 amountForBurn  = afterTaxAmount * 1/10;
        uint256 amountForVault = afterTaxAmount * 9/10;

        // Verify the quoted amount is the amount received and no royalties were generated.
        withinDiff(afterTaxAmount, amountReceived, 10 ** 16);
        assertEq(IERC20(address(inuvationToken)).balanceOf(address(inuvationToken)), (1_000_000 * NIN) * 9 / 100);

        // Log
        emit log_named_uint("weth quoted", amountQuoted);
        emit log_named_uint("weth received", amountReceived);
        //emit log_named_uint("quoted tax", taxedAmount);
        emit log_named_uint("actual tax", IERC20(address(inuvationToken)).balanceOf(address(inuvationToken)));
    }

    // verify royalty distributions
    function test_inuvationToken_royalties() public {
        inuvationToken.excludeFromFees(address(this), false);

        // Verify address(this) is NOT excluded from fees and grab pre balance.
        assert(!inuvationToken._isExcludedFromFees(address(this)));

        // Check balance of address(inuvationToken) to see how many tokens have been taxed. Should be 0
        assertEq(IERC20(address(inuvationToken)).balanceOf(address(inuvationToken)), 0);

        // Deposit 10 WETH
        deal(WETH, address(this), 10 ether);

        // Generate a buy - log amount of tokens accrued
        buy_generateFees(10 ether);
        emit log_named_uint("royalty balance post buy", IERC20(address(inuvationToken)).balanceOf(address(inuvationToken))); // 448_772.392470673
        uint256 royaltiesToDistribute = IERC20(address(inuvationToken)).balanceOf(address(inuvationToken));

        // get pre balance of 4 actors
        uint256 preBalJoe = address(joe).balance;
        uint256 preBalJon = address(jon).balance;
        uint256 preBalNik = address(nik).balance;
        uint256 preBalTim = address(tim).balance;

        sell_generateFees(100_000 * NIN);
        emit log_named_uint("royalty balance post sell", IERC20(address(inuvationToken)).balanceOf(address(inuvationToken))); // 9_000.000000000

        // get post balanace of 4 actors
        uint256 postBalJoe = address(joe).balance;
        uint256 postBalJon = address(jon).balance;
        uint256 postBalNik = address(nik).balance;
        uint256 postBalTim = address(tim).balance;

        uint256 amountReceivedJoe = postBalJoe - preBalJoe;
        uint256 amountReceivedJon = postBalJon - preBalJon;
        uint256 amountReceivedNik = postBalNik - preBalNik;
        uint256 amountReceivedTim = postBalTim - preBalTim;

        assertGt(postBalJoe, preBalJoe);
        
        // ensure they all add up to royaltiesToDistribute
        //assertEq(amountReceivedJoe + amountReceivedJon + amountReceivedNik + amountReceivedTim, royaltiesToDistribute);
        // ensure they're all 1/4 of royaltiesToDistribute

    }

}
