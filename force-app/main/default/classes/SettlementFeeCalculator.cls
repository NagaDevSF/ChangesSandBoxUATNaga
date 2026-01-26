/**
 * @description Handles fee calculations for Settlement Plan Items.
 *              Calculates Commission Fee, Bank Fee, EPPS Transaction Fee,
 *              and EPPS Month-End True-up Fee.
 * @author Settlement Calculator Team
 * @date December 2025
 *
 * ============================================================================
 * ASSUMPTIONS DOCUMENTED IN THIS FILE:
 * ============================================================================
 * F1: Commission Fee = CreditorOpp override OR config default
 * F2: Bank Fee = config only (Default_Bank_Fee__c) - NO override
 * F3: EPPS Transaction Fee = config only (EPPS_Transaction_Fee__c)
 * F4: EPPS Monthly Minimum from config (true-up if month total < minimum)
 * F5: EPPS true-up applied to LAST payment of each calendar month
 * F6: All fees deducted from Escrow (Payment Amount + All Fees)
 * F7: Payee Fee defaults to $0 if not specified
 *
 * NOTE: Only Commission Fee can be overridden per-CreditorOpportunity.
 *       All other fees come strictly from Custom Metadata.
 * ============================================================================
 */
public with sharing class SettlementFeeCalculator {

    // Configuration from Custom Metadata
    private Settlement_Calc_Config__mdt config;

    // Commission fee override from CreditorOpportunity (only fee that can be overridden)
    private Decimal commissionFeeOverride;

    /**
     * @description Constructor with config passed from Service class
     * @param config The Settlement_Calc_Config__mdt record containing all fee values
     * @param commissionFeeOverride Override for commission fee from CreditorOpp (null to use config default)
     */
    public SettlementFeeCalculator(Settlement_Calc_Config__mdt config, Decimal commissionFeeOverride) {
        if (config == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.FEE_CALCULATION_ERROR,
                'Configuration is required for fee calculations.'
            );
        }
        this.config = config;
        this.commissionFeeOverride = commissionFeeOverride;
    }

    /**
     * @description Calculate all fees for a single payment item
     * @param item The Settlement_Plan_Item__c record to update with fees
     *
     * ASSUMPTION F1: Commission Fee = CreditorOpp override OR config default
     * ASSUMPTION F2: Bank Fee = config only (no override allowed)
     * ASSUMPTION F3: EPPS Transaction Fee = config only
     * ASSUMPTION F7: Payee Fee defaults to $0 if not specified
     */
    public void calculateFeesForItem(Settlement_Plan_Item__c item) {
        // ASSUMPTION F1: Commission fee from CreditorOpp override or config default
        item.Commission_Fee__c = getCommissionFee();

        // ASSUMPTION F2: Bank fee ALWAYS from config (no override)
        item.Bank_Fee__c = config.Default_Bank_Fee__c;

        // ASSUMPTION F3: EPPS Transaction Fee from config
        item.EPPS_Transaction_Fee__c = config.EPPS_Transaction_Fee__c;

        // EPPS Month End Fee will be calculated after all items are generated
        // (needs to know total EPPS for the month - see calculateEppsMonthEndFees)
        item.EPPS_Month_End_Fee__c = 0;

        // ASSUMPTION F7: Payee Fee defaults to $0 unless specified
        if (item.Payee_Fee__c == null) {
            item.Payee_Fee__c = 0;
        }
    }

    /**
     * @description Calculate EPPS Month-End True-up fees for all items
     *              Applied to the LAST payment of each calendar month
     *
     * ASSUMPTION F4: EPPS Monthly Minimum from config
     * - If total EPPS transaction fees for a month < minimum, add true-up
     * - Example: 2 payments × $12 = $24, minimum $55, true-up = $31
     *
     * ASSUMPTION F5: EPPS true-up applied to LAST payment of each calendar month
     * - Not first payment, not split across payments
     * - Grouped by calendar month (YYYY-MM)
     *
     * @param items List of Settlement_Plan_Item__c records
     */
    public void calculateEppsMonthEndFees(List<Settlement_Plan_Item__c> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        // Group items by month-year
        Map<String, List<Settlement_Plan_Item__c>> itemsByMonth = new Map<String, List<Settlement_Plan_Item__c>>();

        for (Settlement_Plan_Item__c item : items) {
            String monthKey = SettlementDateUtils.getMonthYearKey(item.Payment_Date__c);
            if (!itemsByMonth.containsKey(monthKey)) {
                itemsByMonth.put(monthKey, new List<Settlement_Plan_Item__c>());
            }
            itemsByMonth.get(monthKey).add(item);
        }

        Decimal eppsTransactionFee = config.EPPS_Transaction_Fee__c;
        Decimal eppsMonthlyMinimum = config.EPPS_Monthly_Minimum__c;

        // For each month, calculate true-up and apply to last payment
        for (String monthKey : itemsByMonth.keySet()) {
            List<Settlement_Plan_Item__c> monthItems = itemsByMonth.get(monthKey);

            // Sort by payment date to find last payment of month
            monthItems = SettlementDateUtils.sortByPaymentDate(monthItems);

            // Calculate total EPPS transaction fees for the month
            Decimal monthlyEppsTotal = monthItems.size() * eppsTransactionFee;

            // Calculate true-up amount (minimum $55/month)
            Decimal trueUpAmount = Math.max(0, eppsMonthlyMinimum - monthlyEppsTotal);

            // Apply true-up to the last payment of the month
            if (!monthItems.isEmpty() && trueUpAmount > 0) {
                Settlement_Plan_Item__c lastItem = monthItems[monthItems.size() - 1];
                lastItem.EPPS_Month_End_Fee__c = trueUpAmount;
            }
        }
    }

    /**
     * @description Calculate total fees for an item (after all individual fees are set)
     * @param item The Settlement_Plan_Item__c record
     * @return Total fees amount
     */
    public Decimal calculateTotalFees(Settlement_Plan_Item__c item) {
        Decimal total = 0;

        total += item.Payee_Fee__c != null ? item.Payee_Fee__c : 0;
        total += item.Commission_Fee__c != null ? item.Commission_Fee__c : 0;
        total += item.Bank_Fee__c != null ? item.Bank_Fee__c : 0;
        total += item.EPPS_Transaction_Fee__c != null ? item.EPPS_Transaction_Fee__c : 0;
        total += item.EPPS_Month_End_Fee__c != null ? item.EPPS_Month_End_Fee__c : 0;

        return total;
    }

    /**
     * @description Calculate total payment (amount + fees)
     *
     * ASSUMPTION F6: All fees deducted from Escrow
     * - Total deducted = Payment Amount + Commission + Bank + EPPS Txn + EPPS Month-End + Payee
     * - Fees are NOT separate from settlement payment
     *
     * @param item The Settlement_Plan_Item__c record
     * @return Total payment amount (to be deducted from escrow)
     */
    public Decimal calculateTotalPayment(Settlement_Plan_Item__c item) {
        Decimal paymentAmount = item.Payment_Amount__c != null ? item.Payment_Amount__c : 0;
        return paymentAmount + calculateTotalFees(item);
    }

    /**
     * @description Get commission fee (override from CreditorOpp or config default)
     * @return Commission fee amount
     */
    public Decimal getCommissionFee() {
        return commissionFeeOverride != null ? commissionFeeOverride : config.Default_Commission_Fee__c;
    }

    /**
     * @description Get bank fee (always from config, no override)
     * @return Bank fee amount
     */
    public Decimal getBankFee() {
        return config.Default_Bank_Fee__c;
    }

    /**
     * @description Calculate sum of all fees across multiple items
     * @param items List of Settlement_Plan_Item__c records
     * @return Map with fee totals (commissionTotal, bankTotal, eppsTotal, grandTotal)
     */
    public Map<String, Decimal> calculateFeeTotals(List<Settlement_Plan_Item__c> items) {
        Map<String, Decimal> totals = new Map<String, Decimal>{
            'commissionTotal' => 0,
            'bankTotal' => 0,
            'eppsTransactionTotal' => 0,
            'eppsMonthEndTotal' => 0,
            'payeeTotal' => 0,
            'grandTotal' => 0
        };

        if (items == null || items.isEmpty()) {
            return totals;
        }

        for (Settlement_Plan_Item__c item : items) {
            totals.put('commissionTotal', totals.get('commissionTotal') +
                (item.Commission_Fee__c != null ? item.Commission_Fee__c : 0));
            totals.put('bankTotal', totals.get('bankTotal') +
                (item.Bank_Fee__c != null ? item.Bank_Fee__c : 0));
            totals.put('eppsTransactionTotal', totals.get('eppsTransactionTotal') +
                (item.EPPS_Transaction_Fee__c != null ? item.EPPS_Transaction_Fee__c : 0));
            totals.put('eppsMonthEndTotal', totals.get('eppsMonthEndTotal') +
                (item.EPPS_Month_End_Fee__c != null ? item.EPPS_Month_End_Fee__c : 0));
            totals.put('payeeTotal', totals.get('payeeTotal') +
                (item.Payee_Fee__c != null ? item.Payee_Fee__c : 0));
        }

        // Calculate grand total
        Decimal grandTotal = 0;
        for (String key : totals.keySet()) {
            if (key != 'grandTotal') {
                grandTotal += totals.get(key);
            }
        }
        totals.put('grandTotal', grandTotal);

        return totals;
    }
}