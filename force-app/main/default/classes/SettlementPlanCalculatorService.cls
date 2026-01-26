/**
 * @description Core service class for Settlement Plan calculation.
 *              Generates Settlement_Plan_Item__c records from Settlement_Segment__c rules.
 *
 *              ALGORITHM OVERVIEW:
 *              1. Load segments ordered by Segment_Order__c
 *              2. For each segment, generate payment items based on type:
 *                 - Fixed: Create [count] items at [amount] each
 *                 - Remainder: Create items at [amount] until balance = 0
 *                 - SolveAmount: Create [count] items with calculated amount
 *              3. Apply date advancement based on frequency
 *              4. Apply date rule (Previous Business Day)
 *              5. Calculate fees for each item
 *              6. Calculate EPPS Month-End true-up fees
 *              7. Simulate escrow balance
 *              8. Validate and return results
 *
 * @author Settlement Calculator Team
 * @date December 2025
 *
 * ============================================================================
 * ASSUMPTIONS DOCUMENTED IN THIS FILE:
 * ============================================================================
 * PAYMENT AMOUNTS:
 * P1: Rounding uses HALF_UP (standard banker's rounding)
 * P2: Final payment is exact remainder (may differ slightly from others)
 * P3: Overpayment prevented silently (adjusts to remaining balance)
 * P4: Minimum payment amount from config (only enforced in Remainder segments)
 * P5: "Fully Funded" tolerance from config
 * P6: Balance considered paid at $0.01 threshold
 *
 * SEGMENT PROCESSING:
 * S1: Segments process in Segment_Order__c ASC sequence
 * S2: Next segment continues from previous end date if no Start_Date__c
 * S3: Balance paid ($0.01) = stop processing remaining segments
 * S4: No limit on number of segments
 * S5: Max total payments from config (Max_Payments__c)
 * S6: Max Remainder iterations from config (Remainder_Max_Iterations__c)
 *
 * ESCROW:
 * E1: Escrow can go negative (informational, doesn't block)
 * E2: Escrow shortage is informational only (allows save)
 * E3: Starting escrow defaults to $0 if not set
 *
 * SAVE/DELETE:
 * V1: Save deletes ALL existing items first (if deleteExisting=true)
 * V2: All-or-nothing transaction (Savepoint rollback on error)
 * V3: Save updates 3 fields on CreditorOpportunity
 *
 * DATE HANDLING:
 * D3: Date spacing uses ORIGINAL date (not adjusted) to prevent drift
 * ============================================================================
 */
public with sharing class SettlementPlanCalculatorService {

    // Segment type constants
    private static final String SEGMENT_TYPE_FIXED = 'Fixed';
    private static final String SEGMENT_TYPE_REMAINDER = 'Remainder';
    private static final String SEGMENT_TYPE_SOLVEAMOUNT = 'SolveAmount';

    // Configuration from Custom Metadata
    private Settlement_Calc_Config__mdt config;

    // Fee calculator
    private SettlementFeeCalculator feeCalculator;

    // Results
    private List<Settlement_Plan_Item__c> generatedItems;
    private CalculationResult result;

    /**
     * @description Wrapper class for calculation results
     */
    public class CalculationResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public List<Settlement_Plan_Item__c> planItems { get; set; }
        @AuraEnabled public Decimal totalScheduledAmount { get; set; }
        @AuraEnabled public Decimal settlementOfferAmount { get; set; }
        @AuraEnabled public Boolean isFullyFunded { get; set; }
        @AuraEnabled public Decimal fundingDifference { get; set; }
        @AuraEnabled public Integer numberOfPayments { get; set; }
        @AuraEnabled public Date firstPaymentDate { get; set; }
        @AuraEnabled public Date finalPaymentDate { get; set; }
        @AuraEnabled public Integer settlementTermWeeks { get; set; }
        @AuraEnabled public Decimal totalFees { get; set; }
        @AuraEnabled public Integer escrowShortageCount { get; set; }
        @AuraEnabled public Boolean hasEscrowShortage { get; set; }
        @AuraEnabled public Map<String, Decimal> feeBreakdown { get; set; }

        public CalculationResult() {
            this.success = false;
            this.planItems = new List<Settlement_Plan_Item__c>();
            this.totalScheduledAmount = 0;
            this.numberOfPayments = 0;
            this.totalFees = 0;
            this.escrowShortageCount = 0;
            this.hasEscrowShortage = false;
            this.feeBreakdown = new Map<String, Decimal>();
        }
    }

    /**
     * @description Constructor
     */
    public SettlementPlanCalculatorService() {
        this.generatedItems = new List<Settlement_Plan_Item__c>();
        this.result = new CalculationResult();
        loadConfig();
    }

    /**
     * @description Load configuration from Settlement_Calc_Config__mdt custom metadata.
     *              Throws exception if config record not found or required fields are null.
     */
    private void loadConfig() {
        // Note: Custom Metadata is readable by all users, no security enforcement needed
        List<Settlement_Calc_Config__mdt> configs = [
            SELECT
                Default_Commission_Fee__c,
                Default_Bank_Fee__c,
                EPPS_Transaction_Fee__c,
                EPPS_Monthly_Minimum__c,
                Min_Payment_Amount__c,
                Max_Payments__c,
                Remainder_Max_Iterations__c,
                Default_Date_Rule__c,
                Default_Frequency__c,
                Escrow_Warning_Threshold__c,
                Fully_Funded_Tolerance__c
            FROM Settlement_Calc_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Settlement Calculator configuration not found. Please create a Settlement_Calc_Config__mdt record with DeveloperName = "Default".'
            );
        }

        this.config = configs[0];
        validateConfig();
    }

    /**
     * @description Validate that all required config fields are not null.
     *              Throws exception with specific field name if null.
     */
    private void validateConfig() {
        if (config.Default_Commission_Fee__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: Default_Commission_Fee__c is required.',
                'Default_Commission_Fee__c',
                null
            );
        }
        if (config.Default_Bank_Fee__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: Default_Bank_Fee__c is required.',
                'Default_Bank_Fee__c',
                null
            );
        }
        if (config.EPPS_Transaction_Fee__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: EPPS_Transaction_Fee__c is required.',
                'EPPS_Transaction_Fee__c',
                null
            );
        }
        if (config.EPPS_Monthly_Minimum__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: EPPS_Monthly_Minimum__c is required.',
                'EPPS_Monthly_Minimum__c',
                null
            );
        }
        if (config.Min_Payment_Amount__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: Min_Payment_Amount__c is required.',
                'Min_Payment_Amount__c',
                null
            );
        }
        if (config.Max_Payments__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: Max_Payments__c is required.',
                'Max_Payments__c',
                null
            );
        }
        if (config.Remainder_Max_Iterations__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: Remainder_Max_Iterations__c is required.',
                'Remainder_Max_Iterations__c',
                null
            );
        }
        if (config.Fully_Funded_Tolerance__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Configuration error: Fully_Funded_Tolerance__c is required.',
                'Fully_Funded_Tolerance__c',
                null
            );
        }
    }

    /**
     * @description Main entry point - Calculate settlement plan for a CreditorOpportunity
     * @param creditorOpportunityId The CreditorOpportunity__c record ID
     * @return CalculationResult containing generated items and summary
     */
    public CalculationResult calculatePlan(Id creditorOpportunityId) {
        try {
            // 1. Load and validate CreditorOpportunity
            CreditorOpportunity__c credOpp = loadCreditorOpportunity(creditorOpportunityId);

            // 2. Load segments
            List<Settlement_Segment__c> segments = loadSegments(creditorOpportunityId);

            // 3. Validate inputs
            validateInputs(credOpp, segments);

            // 4. Initialize fee calculator with config and commission override (if any)
            // ASSUMPTION F1: Only Commission Fee can be overridden per-CreditorOpportunity
            // ASSUMPTION F2: Bank Fee always comes from config (no override)
            this.feeCalculator = new SettlementFeeCalculator(
                config,
                credOpp.Commission_Fee__c  // Commission override (null uses config default)
            );

            // 5. Generate payment items from segments
            generatePaymentItems(credOpp, segments);

            // 6. Calculate EPPS Month-End fees
            feeCalculator.calculateEppsMonthEndFees(generatedItems);

            // 7. Simulate escrow balance
            simulateEscrowBalance(credOpp.Escrow_Start_Balance__c);

            // 8. Build result
            buildResult(credOpp);

            result.success = true;

        } catch (SettlementCalculatorException e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Unexpected error: ' + e.getMessage() + ' at line ' + e.getLineNumber();
        }

        return result;
    }

    /**
     * @description Load CreditorOpportunity with required fields
     * @param creditorOpportunityId The record ID
     * @return CreditorOpportunity__c record
     */
    private CreditorOpportunity__c loadCreditorOpportunity(Id creditorOpportunityId) {
        List<CreditorOpportunity__c> credOpps = [
            SELECT Id,
                   Name,
                   Settlement_Offer_Amount__c,
                   Amount__c,
                   Escrow_Start_Balance__c,
                   Commission_Fee__c,
                   Bank_Fee__c,
                   First_Payment_Date__c,
                   Settlement_Status__c
            FROM CreditorOpportunity__c
            WHERE Id = :creditorOpportunityId
            LIMIT 1
        ];

        if (credOpps.isEmpty()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.INVALID_CREDITOR_OPPORTUNITY,
                'CreditorOpportunity not found with ID: ' + creditorOpportunityId
            );
        }

        return credOpps[0];
    }

    /**
     * @description Load segments ordered by Segment_Order__c
     * @param creditorOpportunityId The parent CreditorOpportunity ID
     * @return List of Settlement_Segment__c records
     */
    private List<Settlement_Segment__c> loadSegments(Id creditorOpportunityId) {
        return [
            SELECT Id,
                   Name,
                   Segment_Order__c,
                   Segment_Type__c,
                   Payment_Amount__c,
                   Payment_Count__c,
                   Frequency__c,
                   Start_Date__c,
                   Is_First_Segment__c,
                   Continues_From_Previous__c,
                   Creditors_List__c
            FROM Settlement_Segment__c
            WHERE Creditors_List__c = :creditorOpportunityId
            ORDER BY Segment_Order__c ASC
        ];
    }

    /**
     * @description Validate inputs before calculation
     * @param credOpp The CreditorOpportunity record
     * @param segments The list of segments
     */
    private void validateInputs(CreditorOpportunity__c credOpp, List<Settlement_Segment__c> segments) {
        // Check for segments
        if (segments.isEmpty()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.NO_SEGMENTS,
                'No settlement segments found. Please create at least one segment before calculating.'
            );
        }

        // Check settlement offer amount
        if (credOpp.Settlement_Offer_Amount__c == null || credOpp.Settlement_Offer_Amount__c <= 0) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.INVALID_SETTLEMENT_AMOUNT,
                'Settlement Offer Amount must be greater than zero.',
                'Settlement_Offer_Amount__c',
                credOpp.Settlement_Offer_Amount__c
            );
        }

        // Validate each segment
        for (Settlement_Segment__c segment : segments) {
            validateSegment(segment);
        }

        // Ensure first segment has a start date
        if (segments[0].Start_Date__c == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
                'First segment must have a Start Date.',
                'Start_Date__c',
                null
            );
        }
    }

    /**
     * @description Validate individual segment configuration
     * @param segment The segment to validate
     */
    private void validateSegment(Settlement_Segment__c segment) {
        String segmentType = segment.Segment_Type__c;

        // Check segment type
        if (String.isBlank(segmentType)) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.INVALID_SEGMENT_TYPE,
                'Segment Type is required for segment: ' + segment.Name
            );
        }

        // Validate based on segment type
        switch on segmentType {
            when 'Fixed' {
                if (segment.Payment_Amount__c == null || segment.Payment_Amount__c <= 0) {
                    throw new SettlementCalculatorException(
                        SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
                        'Fixed segment requires a Payment Amount greater than zero.',
                        'Payment_Amount__c',
                        segment.Payment_Amount__c
                    );
                }
                if (segment.Payment_Count__c == null || segment.Payment_Count__c <= 0) {
                    throw new SettlementCalculatorException(
                        SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
                        'Fixed segment requires a Payment Count greater than zero.',
                        'Payment_Count__c',
                        segment.Payment_Count__c
                    );
                }
            }
            when 'Remainder' {
                if (segment.Payment_Amount__c == null || segment.Payment_Amount__c <= 0) {
                    throw new SettlementCalculatorException(
                        SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
                        'Remainder segment requires a Payment Amount greater than zero.',
                        'Payment_Amount__c',
                        segment.Payment_Amount__c
                    );
                }
            }
            when 'SolveAmount' {
                if (segment.Payment_Count__c == null || segment.Payment_Count__c <= 0) {
                    throw new SettlementCalculatorException(
                        SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
                        'SolveAmount segment requires a Payment Count greater than zero.',
                        'Payment_Count__c',
                        segment.Payment_Count__c
                    );
                }
            }
            when else {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.INVALID_SEGMENT_TYPE,
                    'Unknown Segment Type: ' + segmentType
                );
            }
        }

        // Check frequency
        if (String.isBlank(segment.Frequency__c)) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
                'Frequency is required for segment: ' + segment.Name
            );
        }
    }

    /**
     * @description Generate payment items from all segments
     *
     * ASSUMPTION S1: Segments process in Segment_Order__c ASC sequence
     * ASSUMPTION S5: Max total payments from config (Max_Payments__c)
     *
     * @param credOpp The CreditorOpportunity record
     * @param segments The list of segments
     */
    private void generatePaymentItems(CreditorOpportunity__c credOpp, List<Settlement_Segment__c> segments) {
        Decimal remainingBalance = credOpp.Settlement_Offer_Amount__c;
        Date currentDate = null;
        Integer paymentNumber = 1;
        Integer totalPaymentsGenerated = 0;
        // ASSUMPTION S5: Max payments limit from config
        Integer maxPayments = Integer.valueOf(config.Max_Payments__c);

        for (Settlement_Segment__c segment : segments) {
            // ASSUMPTION S2: Next segment continues from previous end date if no Start_Date__c
            // Determine start date for this segment
            if (segment.Start_Date__c != null) {
                currentDate = segment.Start_Date__c;
            } else if (currentDate == null) {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
                    'Cannot determine start date for segment: ' + segment.Name
                );
            }
            // If no start date and currentDate exists, continue from previous segment (ASSUMPTION S2)

            // Generate items based on segment type
            List<Settlement_Plan_Item__c> segmentItems;

            switch on segment.Segment_Type__c {
                when 'Fixed' {
                    segmentItems = generateFixedItems(
                        credOpp.Id,
                        segment,
                        currentDate,
                        paymentNumber,
                        remainingBalance
                    );
                }
                when 'Remainder' {
                    segmentItems = generateRemainderItems(
                        credOpp.Id,
                        segment,
                        currentDate,
                        paymentNumber,
                        remainingBalance
                    );
                }
                when 'SolveAmount' {
                    segmentItems = generateSolveAmountItems(
                        credOpp.Id,
                        segment,
                        currentDate,
                        paymentNumber,
                        remainingBalance
                    );
                }
            }

            // Update counters and state
            for (Settlement_Plan_Item__c item : segmentItems) {
                generatedItems.add(item);
                remainingBalance -= item.Payment_Amount__c;
                paymentNumber++;
                totalPaymentsGenerated++;

                // ASSUMPTION D3: Date spacing uses ORIGINAL date (not adjusted) to prevent drift
                // Use ORIGINAL scheduled date (not business-day adjusted) to maintain consistent spacing
                // This ensures weekly payments stay 7 days apart even if some shift for weekends
                Date nextBaseDate = item.Original_Payment_Date__c != null 
                    ? item.Original_Payment_Date__c 
                    : item.Payment_Date__c;
                currentDate = SettlementDateUtils.advanceDate(
                    nextBaseDate,
                    segment.Frequency__c,
                    paymentNumber
                );
            }

            // Check total payments limit
            if (totalPaymentsGenerated > maxPayments) {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                    'Exceeded maximum allowed payments (' + maxPayments + '). Please adjust segment configuration.'
                );
            }

            // ASSUMPTION S3 & P6: Balance paid ($0.01 threshold) = stop processing
            // If balance is paid off, skip remaining segments
            if (remainingBalance <= 0.01) {
                break;
            }
        }
    }

    /**
     * @description Generate items for a Fixed segment
     *
     * ASSUMPTION P3: Overpayment prevented silently
     * - If payment would exceed remaining balance, adjusts to remaining
     * - No warning/error, just adjusts automatically
     *
     * @param credOppId The CreditorOpportunity ID
     * @param segment The segment record
     * @param startDate Starting date for this segment
     * @param startingPaymentNumber The starting payment number
     * @param currentBalance The current remaining balance
     * @return List of generated Settlement_Plan_Item__c records
     */
    private List<Settlement_Plan_Item__c> generateFixedItems(
        Id credOppId,
        Settlement_Segment__c segment,
        Date startDate,
        Integer startingPaymentNumber,
        Decimal currentBalance
    ) {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        Date currentDate = startDate;
        Integer paymentNumber = startingPaymentNumber;
        Integer count = Integer.valueOf(segment.Payment_Count__c);
        Decimal amount = segment.Payment_Amount__c;
        Decimal runningBalance = currentBalance;

        for (Integer i = 0; i < count; i++) {
            // ASSUMPTION P3: Overpayment prevented silently
            // Stop if balance is already paid
            if (runningBalance <= 0.01) {
                break;
            }
            
            // Adjust payment if it would overpay
            Decimal paymentAmount = amount;
            if (paymentAmount > runningBalance) {
                paymentAmount = runningBalance;
            }

            if (paymentAmount <= 0) {
                break;
            }

            Settlement_Plan_Item__c item = createPaymentItem(
                credOppId,
                segment.Id,
                paymentNumber,
                currentDate,
                paymentAmount,
                runningBalance
            );

            items.add(item);
            runningBalance -= paymentAmount;
            paymentNumber++;

            // Advance date for next payment
            if (i < count - 1) {
                currentDate = SettlementDateUtils.advanceDate(currentDate, segment.Frequency__c, paymentNumber);
            }
        }

        return items;
    }

    /**
     * @description Generate items for a Remainder segment
     *
     * ASSUMPTION S6: Max Remainder iterations from config (Remainder_Max_Iterations__c)
     * - Prevents infinite loops if payment amount is very small
     *
     * ASSUMPTION P4: Minimum payment amount from config
     * - Only enforced in Remainder segments
     * - Final payment can be below minimum if it's the last bit of balance
     *
     * @param credOppId The CreditorOpportunity ID
     * @param segment The segment record
     * @param startDate Starting date for this segment
     * @param startingPaymentNumber The starting payment number
     * @param currentBalance The current remaining balance
     * @return List of generated Settlement_Plan_Item__c records
     */
    private List<Settlement_Plan_Item__c> generateRemainderItems(
        Id credOppId,
        Settlement_Segment__c segment,
        Date startDate,
        Integer startingPaymentNumber,
        Decimal currentBalance
    ) {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        Date currentDate = startDate;
        Integer paymentNumber = startingPaymentNumber;
        Decimal amount = segment.Payment_Amount__c;
        Decimal runningBalance = currentBalance;
        Integer iterations = 0;
        // ASSUMPTION S6: Max iterations from config to prevent infinite loops
        Integer maxIterations = Integer.valueOf(config.Remainder_Max_Iterations__c);
        // ASSUMPTION P4: Minimum payment from config
        Decimal minPaymentAmount = config.Min_Payment_Amount__c;

        while (runningBalance > 0.01 && iterations < maxIterations) {
            // Adjust final payment if it would overpay
            Decimal paymentAmount = Math.min(amount, runningBalance);

            // Check minimum payment amount
            if (paymentAmount < minPaymentAmount && paymentAmount < runningBalance) {
                // If remaining is less than min but equals balance, allow it
                if (runningBalance < minPaymentAmount) {
                    paymentAmount = runningBalance;
                }
            }

            if (paymentAmount <= 0) {
                break;
            }

            Settlement_Plan_Item__c item = createPaymentItem(
                credOppId,
                segment.Id,
                paymentNumber,
                currentDate,
                paymentAmount,
                runningBalance
            );

            items.add(item);
            runningBalance -= paymentAmount;
            paymentNumber++;
            iterations++;

            // Advance date for next payment
            currentDate = SettlementDateUtils.advanceDate(currentDate, segment.Frequency__c, paymentNumber);
        }

        if (iterations >= maxIterations && runningBalance > 0.01) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.MAX_ITERATIONS_EXCEEDED,
                'Remainder calculation exceeded maximum iterations (' + maxIterations +
                '). Remaining balance: $' + runningBalance.setScale(2) +
                '. Consider increasing payment amount or using SolveAmount segment.'
            );
        }

        return items;
    }

    /**
     * @description Generate items for a SolveAmount segment
     *
     * ASSUMPTION P1: Rounding uses HALF_UP (standard banker's rounding)
     * - $333.335 → $333.34, $333.334 → $333.33
     * - Distributes rounding errors fairly
     *
     * ASSUMPTION P2: Final payment is exact remainder
     * - May differ slightly from calculated amount due to rounding
     * - Example: $1000 ÷ 3 = $333.33, $333.33, $333.34
     *
     * @param credOppId The CreditorOpportunity ID
     * @param segment The segment record
     * @param startDate Starting date for this segment
     * @param startingPaymentNumber The starting payment number
     * @param currentBalance The current remaining balance
     * @return List of generated Settlement_Plan_Item__c records
     */
    private List<Settlement_Plan_Item__c> generateSolveAmountItems(
        Id credOppId,
        Settlement_Segment__c segment,
        Date startDate,
        Integer startingPaymentNumber,
        Decimal currentBalance
    ) {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        Date currentDate = startDate;
        Integer paymentNumber = startingPaymentNumber;
        Integer count = Integer.valueOf(segment.Payment_Count__c);
        Decimal runningBalance = currentBalance;

        if (count <= 0 || runningBalance <= 0) {
            return items;
        }

        // ASSUMPTION P1: HALF_UP rounding (standard banker's rounding)
        // Calculate payment amount: divide remaining balance by count
        Decimal calculatedAmount = (runningBalance / count).setScale(2, System.RoundingMode.HALF_UP);

        for (Integer i = 0; i < count; i++) {
            Decimal paymentAmount;
            
            // ASSUMPTION P2: Final payment is exact remainder
            if (i == count - 1) {
                // Last payment - use exact remaining balance to handle any rounding difference
                paymentAmount = runningBalance;
            } else {
                // Regular payment - use calculated amount but don't exceed remaining balance
                paymentAmount = Math.min(calculatedAmount, runningBalance);
            }

            if (paymentAmount <= 0) {
                break;
            }

            Settlement_Plan_Item__c item = createPaymentItem(
                credOppId,
                segment.Id,
                paymentNumber,
                currentDate,
                paymentAmount,
                runningBalance
            );

            items.add(item);
            runningBalance -= paymentAmount;
            paymentNumber++;

            // Advance date for next payment
            if (i < count - 1) {
                currentDate = SettlementDateUtils.advanceDate(currentDate, segment.Frequency__c, paymentNumber);
            }
        }

        return items;
    }

    /**
     * @description Create a single payment item with fees calculated
     * @param credOppId The CreditorOpportunity ID
     * @param segmentId The Settlement_Segment__c ID
     * @param paymentNumber The payment number
     * @param originalDate The original payment date
     * @param paymentAmount The payment amount
     * @param balanceBefore The balance before this payment
     * @return Settlement_Plan_Item__c record
     */
    private Settlement_Plan_Item__c createPaymentItem(
        Id credOppId,
        Id segmentId,
        Integer paymentNumber,
        Date originalDate,
        Decimal paymentAmount,
        Decimal balanceBefore
    ) {
        // Apply date rule (Previous Business Day)
        Date adjustedDate = SettlementDateUtils.applyPreviousBusinessDayRule(originalDate);

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Creditors_List__c = credOppId,
            Settlement_Segment__c = segmentId,
            Payment_Number__c = paymentNumber,
            Payment_Date__c = adjustedDate,
            Original_Payment_Date__c = originalDate != adjustedDate ? originalDate : null,
            Payment_Amount__c = paymentAmount.setScale(2, System.RoundingMode.HALF_UP),
            Running_Balance__c = (balanceBefore - paymentAmount).setScale(2, System.RoundingMode.HALF_UP),
            Status__c = 'Scheduled'
        );

        // Calculate fees
        feeCalculator.calculateFeesForItem(item);

        return item;
    }

    /**
     * @description Simulate escrow balance across all payments
     *
     * ASSUMPTION E1: Escrow can go negative (informational, doesn't block)
     * ASSUMPTION E2: Escrow shortage is informational only (allows save)
     * ASSUMPTION E3: Starting escrow defaults to $0 if not set
     *
     * @param startingEscrow The starting escrow balance
     */
    private void simulateEscrowBalance(Decimal startingEscrow) {
        // ASSUMPTION E3: Default to $0 if not set
        Decimal escrowBalance = startingEscrow != null ? startingEscrow : 0;

        // Sort items by date for chronological processing
        generatedItems = SettlementDateUtils.sortByPaymentDate(generatedItems);

        for (Settlement_Plan_Item__c item : generatedItems) {
            // Calculate total payment (amount + fees)
            Decimal totalPayment = feeCalculator.calculateTotalPayment(item);

            // Deduct from escrow
            escrowBalance -= totalPayment;

            // Set escrow balance on item
            item.Escrow_Balance__c = escrowBalance.setScale(2, System.RoundingMode.HALF_UP);

            // ASSUMPTION E1 & E2: Escrow can go negative, just flag it (informational)
            // Check for shortage - doesn't block, just counts occurrences
            if (escrowBalance < 0) {
                result.escrowShortageCount++;
                result.hasEscrowShortage = true;
            }
        }
    }

    /**
     * @description Build the final result object
     * @param credOpp The CreditorOpportunity record
     */
    private void buildResult(CreditorOpportunity__c credOpp) {
        result.planItems = generatedItems;
        result.numberOfPayments = generatedItems.size();
        result.settlementOfferAmount = credOpp.Settlement_Offer_Amount__c;

        // Calculate totals
        Decimal totalScheduled = 0;
        for (Settlement_Plan_Item__c item : generatedItems) {
            totalScheduled += item.Payment_Amount__c;
        }
        result.totalScheduledAmount = totalScheduled.setScale(2, System.RoundingMode.HALF_UP);

        // ASSUMPTION P5: "Fully Funded" tolerance from config
        // Check fully funded using config tolerance
        result.fundingDifference = Math.abs(result.totalScheduledAmount - result.settlementOfferAmount);
        result.isFullyFunded = result.fundingDifference <= config.Fully_Funded_Tolerance__c;

        // Dates
        if (!generatedItems.isEmpty()) {
            result.firstPaymentDate = generatedItems[0].Payment_Date__c;
            result.finalPaymentDate = generatedItems[generatedItems.size() - 1].Payment_Date__c;
            result.settlementTermWeeks = SettlementDateUtils.weeksBetween(
                result.firstPaymentDate,
                result.finalPaymentDate
            );
        }

        // Fee breakdown
        result.feeBreakdown = feeCalculator.calculateFeeTotals(generatedItems);
        result.totalFees = result.feeBreakdown.get('grandTotal');
    }

    /**
     * @description Save generated items to database and update CreditorOpportunity
     *
     * ASSUMPTION V1: Save deletes ALL existing items first (if deleteExisting=true)
     * - No history kept, no archiving - complete replacement
     *
     * ASSUMPTION V2: All-or-nothing transaction
     * - Uses Savepoint, rolls back entirely on any error
     *
     * ASSUMPTION V3: Save updates 3 fields on CreditorOpportunity
     * - First_Payment_Date__c
     * - Final_Payment_Date__c
     * - Settlement_Term_Weeks__c
     *
     * @param creditorOpportunityId The CreditorOpportunity ID
     * @param deleteExisting Whether to delete existing items first
     * @return CalculationResult with saved items
     */
    public CalculationResult saveCalculation(Id creditorOpportunityId, Boolean deleteExisting) {
        // First calculate if not already done
        if (result == null || !result.success || result.planItems.isEmpty()) {
            calculatePlan(creditorOpportunityId);
        }

        if (!result.success) {
            return result;
        }

        // ASSUMPTION V2: All-or-nothing transaction with Savepoint
        Savepoint sp = Database.setSavepoint();

        try {
            // ASSUMPTION V1: Delete ALL existing items if requested (complete replacement)
            if (deleteExisting) {
                List<Settlement_Plan_Item__c> existingItems = [
                    SELECT Id FROM Settlement_Plan_Item__c
                    WHERE Creditors_List__c = :creditorOpportunityId
                    WITH SECURITY_ENFORCED
                ];
                if (!existingItems.isEmpty()) {
                    // Check delete permission
                    if (!Schema.sObjectType.Settlement_Plan_Item__c.isDeletable()) {
                        throw new SettlementCalculatorException(
                            SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                            'Insufficient permissions to delete existing Settlement Plan Items.'
                        );
                    }
                    delete existingItems;
                }
            }

            // Check insert permission
            if (!Schema.sObjectType.Settlement_Plan_Item__c.isCreateable()) {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                    'Insufficient permissions to create Settlement Plan Items.'
                );
            }

            // Insert new items
            insert result.planItems;

            // Check update permission
            if (!Schema.sObjectType.CreditorOpportunity__c.isUpdateable()) {
                throw new SettlementCalculatorException(
                    SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                    'Insufficient permissions to update Creditor Opportunity.'
                );
            }

            // ASSUMPTION V3: Update these 3 fields on CreditorOpportunity
            CreditorOpportunity__c credOpp = new CreditorOpportunity__c(
                Id = creditorOpportunityId,
                First_Payment_Date__c = result.firstPaymentDate,
                Final_Payment_Date__c = result.finalPaymentDate,
                Settlement_Term_Weeks__c = result.settlementTermWeeks
            );
            update credOpp;

        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.errorMessage = 'Failed to save calculation: ' + e.getMessage();
        }

        return result;
    }
}