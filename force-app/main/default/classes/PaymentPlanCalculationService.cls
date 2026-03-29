/**
 * @description Base calculation service for Payment Plan operations.
 *
 * This service contains shared helper methods, constants, and core calculation logic
 * that is used by PaymentPlanEditorController and other payment plan services.
 *
 * KEY RESPONSIBILITIES:
 * - Recalculate payment plans from Opportunity data (recalculatePaymentPlan)
 * - Recalculate remaining balance with status-aware redistribution (recalculateRemainingBalance)
 * - Shared utility methods: draft number recalculation, item cloning, fee distribution
 * - Query field list generation for dynamic SOQL
 * - Fee record creation for schedule items
 *
 * RELATED CLASSES:
 * - PaymentPlanEditorController: Thin controller that delegates to this service
 * - PaymentFeeService: Fee record CRUD operations
 * - PaymentCalcConfigSvc: CMDT configuration retrieval
 *
 * @author DCG Development Team
 * @since 2024-01
 */
public with sharing class PaymentPlanCalculationService {

    // ==================================================================================
    // CONSTANTS - PAYMENT SCHEDULE ITEM STATUS VALUES
    // ==================================================================================
    /** Status for future scheduled payments */
    private static final String STATUS_SCHEDULED = 'Scheduled';
    /** Status for successfully processed payments */
    private static final String STATUS_CLEARED = 'Cleared';
    /** Status for payments that failed due to insufficient funds */
    private static final String STATUS_NSF = 'NSF';
    /** Status for cancelled/voided payments */
    private static final String STATUS_CANCELLED = 'Cancelled';

    /** Cached set of valid status picklist values (lazy-loaded) */
    private static Set<String> validStatusValues;

    // ==================================================================================
    // CONSTANTS - PAYMENT PLAN VERSION STATUS VALUES
    // ==================================================================================
    /** Draft version - not yet activated, can be edited */
    private static final String VERSION_STATUS_DRAFT = 'Draft';
    /** Active version - currently in use */
    private static final String VERSION_STATUS_ACTIVE = 'Active';
    /** Archived version - superseded by newer version */
    private static final String VERSION_STATUS_ARCHIVED = 'Archived';

    // ==================================================================================
    // CONSTANTS - SOURCE AND VERSION TYPE VALUES
    // ==================================================================================
    /** Source identifier for UI-created plans */
    private static final String SOURCE_UI = 'UI';
    /** Version type for standard revisions */
    private static final String VERSION_TYPE_REVISION = 'Revision';
    /** Version type for plan suspensions */
    private static final String VERSION_TYPE_SUSPENSION = 'Suspension';
    /** Version type for plan reactivations */
    private static final String VERSION_TYPE_REACTIVATION = 'Reactivation';
    /** Status for suspended plans */
    private static final String STATUS_SUSPENDED = 'Suspended';

    // ==================================================================================
    // CONSTANTS - DEFAULT VALUES FOR CALCULATIONS
    // ==================================================================================
    /** Default banking fee per payment ($15.00) */
    private static final Decimal DEFAULT_BANKING_FEE = 15.00;
    /** Days between payments (weekly = 7) */
    private static final Integer PAYMENT_INTERVAL_DAYS = 7;
    /** Default retainer fee (none) */
    private static final Decimal DEFAULT_RETAINER_FEE = 0.00;
    /** Default program/escrow split ratio (50/50) */
    private static final Decimal DEFAULT_SPLIT_RATIO = 0.50;
    /** Default number of setup fee payments */
    private static final Integer DEFAULT_SETUP_FEE_PAYMENTS = 4;
    /** Default total number of payments (52 weeks) */
    private static final Integer DEFAULT_NUMBER_OF_PAYMENTS = 52;

    // ==================================================================================
    // CONSTANTS - QUERY AND VALIDATION LIMITS
    // ==================================================================================
    /** Maximum records to query in a single SOQL statement */
    private static final Integer MAX_QUERY_LIMIT = 1000;
    /** Maximum allowed currency value for validation */
    private static final Decimal MAX_CURRENCY_VALUE = 99999999.99;
    /** Minimum allowed currency value for validation */
    private static final Decimal MIN_CURRENCY_VALUE = -99999999.99;

    // ==================================================================================
    // CONSTANTS - ERROR MESSAGE SYMBOLS (for user-friendly error display)
    // ==================================================================================
    private static final String ERROR_SYMBOL = '⚠️ ';
    private static final String NOT_FOUND_SYMBOL = '🔍 ';
    private static final String VALIDATION_SYMBOL = '❌ ';
    private static final String CONFIG_SYMBOL = '⚙️ ';

    // ==================================================================================
    // CONSTANTS - DEBUG LOGGING PREFIXES
    // These prefixes enable easy filtering in Salesforce debug logs
    // ==================================================================================
    private static final String CLASS_NAME = 'PaymentPlanCalculationService';
    private static final String LOG_ENTRY = '▶️ ENTRY';
    private static final String LOG_EXIT = '◀️ EXIT';
    private static final String LOG_PARAM = '📋 PARAM';
    private static final String LOG_QUERY = '🔍 QUERY';
    private static final String LOG_DML = '💾 DML';
    private static final String LOG_ERROR = '❌ ERROR';
    private static final String LOG_WARN = '⚠️ WARN';
    private static final String LOG_INFO = 'ℹ️ INFO';
    private static final String LOG_DEBUG = '🔧 DEBUG';
    private static final String LOG_SUCCESS = '✅ SUCCESS';

    // ==================================================================================
    // CONSTANTS - SOQL QUERY FIELD LISTS (for maintainability)
    // ==================================================================================
    /**
     * Standard fields to query for PaymentPlan__c records.
     * Includes all plan configuration, version info, and rollup summary fields.
     */
    private static final String PAYMENT_PLAN_QUERY_FIELDS =
        'Id, Name, Opportunity__c, Contract__c, Program_Type__c, ' +
        'Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c, ' +
        'Total_Program_Cost__c, Weekly_Payment__c, Monthly_Payment__c, ' +
        'Number_of_Payments__c, First_Payment_Date__c, Status__c, ' +
        'Version_Number__c, Is_Active__c, ' +
        'Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c, ' +
        'Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c, ' +
        'Calculation_Timestamp__c, Previous_Version__c, Source__c, ' +
        'Version_Type__c, Version_Notes__c, Schedule_Item_Count__c, ' +
        'Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c, ' +
        'Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c, ' +
        'Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c, ' +
        'Cleared_Payment_Sum__c, Cleared_Setup_Fee_Sum__c, Cleared_Program_Fee_Sum__c, ' +
        'Cleared_Banking_Fee_Sum__c, Cleared_Savings_Sum__c, Cleared_Escrow_Sum__c, ' +
        'NSF_Draft_Amount_Sum__c, NSF_Setup_Fee_Sum__c, NSF_Program_Fee_Sum__c, ' +
        'NSF_Banking_Fee_Sum__c, NSF_Savings_Sum__c';

    // ==================================================================================
    // INNER CLASSES
    // ==================================================================================

    /**
     * @description Wrapper class to hold paid sums from non-scheduled items
     * Used for redistribution calculations when recalculating payment plans
     */
    public class PaidSumsWrapper {
        public Decimal setupFee = 0;
        public Decimal programFee = 0;
        public Decimal escrow = 0;
        public Decimal savingsBalance = 0;
        public Integer nonScheduledCount = 0;
    }

    /**
     * @description Helper wrapper class for sorting Payment_Schedule_Item__c by Payment_Date__c
     * Implements Comparable for custom sorting
     */
    private class DraftNumberSortWrapper implements Comparable {
        public Payment_Schedule_Item__c item;
        public Integer originalIndex;

        public DraftNumberSortWrapper(Payment_Schedule_Item__c item, Integer originalIndex) {
            this.item = item;
            this.originalIndex = originalIndex;
        }

        public Integer compareTo(Object other) {
            DraftNumberSortWrapper otherWrapper = (DraftNumberSortWrapper) other;

            // Sort by Payment_Date__c first (nulls last)
            Date thisDate = this.item.Payment_Date__c;
            Date otherDate = otherWrapper.item.Payment_Date__c;

            if (thisDate == null && otherDate == null) {
                // Both null, sort by Payment_Number__c
                return comparePaymentNumbers(this.item.Payment_Number__c, otherWrapper.item.Payment_Number__c);
            }
            if (thisDate == null) {
                return 1; // Nulls last
            }
            if (otherDate == null) {
                return -1; // Nulls last
            }

            // Compare dates
            if (thisDate < otherDate) {
                return -1;
            }
            if (thisDate > otherDate) {
                return 1;
            }

            // Same date, sort by Payment_Number__c
            return comparePaymentNumbers(this.item.Payment_Number__c, otherWrapper.item.Payment_Number__c);
        }

        private Integer comparePaymentNumbers(Decimal num1, Decimal num2) {
            if (num1 == null && num2 == null) {
                return 0;
            }
            if (num1 == null) {
                return 1;
            }
            if (num2 == null) {
                return -1;
            }
            return num1 < num2 ? -1 : (num1 > num2 ? 1 : 0);
        }
    }

    // ==================================================================================
    // PRIVATE HELPERS - Status Validation
    // ==================================================================================

    /**
     * @description Get valid status picklist values for Payment_Schedule_Item__c.Status__c
     * Uses lazy loading to avoid repeated schema describes
     * @return Set of valid status values (case-sensitive)
     */
    private static Set<String> getValidStatusValues() {
        if (validStatusValues == null) {
            validStatusValues = new Set<String>();
            Schema.DescribeFieldResult fieldResult = Payment_Schedule_Item__c.Status__c.getDescribe();
            for (Schema.PicklistEntry entry : fieldResult.getPicklistValues()) {
                if (entry.isActive()) {
                    validStatusValues.add(entry.getValue());
                }
            }
        }
        return validStatusValues;
    }

    /**
     * @description Validate and normalize a status value
     * Returns the status if valid, otherwise returns 'Scheduled' as default
     * @param status The status value to validate
     * @return Valid status value (original if valid, 'Scheduled' if invalid/blank)
     */
    private static String validateStatus(String status) {
        if (String.isBlank(status)) {
            return STATUS_SCHEDULED;
        }
        if (getValidStatusValues().contains(status)) {
            return status;
        }
        // Invalid status - log warning and default to Scheduled
        System.debug(LoggingLevel.WARN, LOG_WARN + ' | validateStatus | Invalid status value: "' + status + '", defaulting to Scheduled');
        return STATUS_SCHEDULED;
    }

    // ==================================================================================
    // PUBLIC SHARED HELPER METHODS
    // ==================================================================================

    /**
     * @description Dynamically builds the field list for Payment_Schedule_Item__c queries
     * using Schema describe. Includes all accessible fields so new custom fields are
     * automatically picked up without code changes.
     * @return Comma-separated field names for use in SOQL queries
     */
    public static String getScheduleItemQueryFields() {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Payment_Schedule_Item__c.fields.getMap();
        List<String> fieldNames = new List<String>();
        fieldNames.add('Id');
        for (String fieldName : fieldMap.keySet()) {
            if (fieldName == 'id') continue; // Already added
            Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
            if (!fd.isAccessible()) continue; // Skip fields user can't read
            fieldNames.add(fieldName);
        }
        fieldNames.sort();
        return String.join(fieldNames, ', ');
    }

    /**
     * @description Returns a comma-separated list of all accessible PaymentPlan__c fields
     * using Schema.describe so new custom fields are automatically included in queries.
     * This ensures clone() and field reads always have complete data.
     */
    public static String getPaymentPlanQueryFields() {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.PaymentPlan__c.fields.getMap();
        List<String> fieldNames = new List<String>();
        fieldNames.add('Id');
        for (String fieldName : fieldMap.keySet()) {
            if (fieldName == 'id') continue;
            Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
            if (!fd.isAccessible()) continue;
            fieldNames.add(fieldName);
        }
        fieldNames.sort();
        return String.join(fieldNames, ', ');
    }

    /**
     * @description Parse a percentage string to Decimal value
     * Handles values like "35%", "35", "20%" by stripping the % symbol
     * @param value The string value to parse
     * @return Decimal value or null if blank/invalid
     */
    public static Decimal parsePercentageToDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            String cleanValue = value.replace('%', '').trim();
            if (String.isBlank(cleanValue)) {
                return null;
            }
            return Decimal.valueOf(cleanValue);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Recalculate Draft_Number__c for all items, skipping NSF and Cancelled statuses.
     * This ensures Draft_Number__c matches the LWC display logic where NSF/Cancelled rows
     * are excluded from the draft numbering sequence.
     *
     * Items are sorted by Payment_Date__c, then assigned sequential draft numbers.
     * NSF and Cancelled items get null Draft_Number__c.
     *
     * @param items List of Payment_Schedule_Item__c records to update (modified in place)
     */
    public static void recalculateDraftNumbers(List<Payment_Schedule_Item__c> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        // Sort items by Payment_Date__c (nulls last), then by Payment_Number__c
        List<Payment_Schedule_Item__c> sortedItems = new List<Payment_Schedule_Item__c>(items);
        sortedItems.sort();

        // Create a map to track original index for updating the original list
        Map<Id, Payment_Schedule_Item__c> itemMap = new Map<Id, Payment_Schedule_Item__c>();
        for (Payment_Schedule_Item__c item : items) {
            if (item.Id != null) {
                itemMap.put(item.Id, item);
            }
        }

        // Sort by Payment_Date__c using a custom comparator approach
        // Since Apex doesn't have custom comparators, we'll use a wrapper approach
        List<DraftNumberSortWrapper> wrappers = new List<DraftNumberSortWrapper>();
        for (Integer i = 0; i < items.size(); i++) {
            wrappers.add(new DraftNumberSortWrapper(items[i], i));
        }
        wrappers.sort();

        // Calculate draft numbers, skipping NSF and Cancelled
        Integer draftCounter = 0;
        Set<String> skipStatuses = new Set<String>{ STATUS_NSF, STATUS_CANCELLED };

        for (DraftNumberSortWrapper wrapper : wrappers) {
            Payment_Schedule_Item__c item = wrapper.item;
            Boolean shouldSkip = skipStatuses.contains(item.Status__c);

            if (shouldSkip) {
                item.Draft_Number__c = null;
            } else {
                draftCounter++;
                item.Draft_Number__c = String.valueOf(draftCounter);
            }
        }

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | recalculateDraftNumbers | Processed ' + items.size() + ' items, assigned ' + draftCounter + ' draft numbers');
    }

    /**
     * @description Clone a schedule item for a new payment plan using dynamic field discovery.
     * Preserves all createable field values but assigns to new plan.
     * New custom fields added to Payment_Schedule_Item__c are automatically included.
     * @param original Original item to clone
     * @param newPlanId New payment plan ID
     * @return Cloned item with new plan assignment
     */
    public static Payment_Schedule_Item__c cloneItemForNewPlan(
        Payment_Schedule_Item__c original,
        Id newPlanId
    ) {
        Payment_Schedule_Item__c cloned = new Payment_Schedule_Item__c();
        cloned.Payment_Plan__c = newPlanId;
        List<String> fieldNames = getCloneableFieldNames(
            Schema.SObjectType.Payment_Schedule_Item__c,
            new Set<String>{'Id', 'Payment_Plan__c'}
        );
        copyFieldValues(original, cloned, fieldNames);
        return cloned;
    }

    /**
     * @description Carry over wire fees from old schedule items to new schedule items
     * Matches by Payment_Number__c (row number) to link wire fees to correct new items
     * @param oldScheduleItems List of old schedule items (must have Id and Payment_Number__c populated)
     * @param newScheduleItems List of new schedule items (must have Id and Payment_Number__c populated after insert)
     */
    public static void carryOverWireFees(
        List<Payment_Schedule_Item__c> oldScheduleItems,
        List<Payment_Schedule_Item__c> newScheduleItems
    ) {
        String methodName = 'carryOverWireFees';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | oldScheduleItems: ' + (oldScheduleItems != null ? oldScheduleItems.size() : 0) + ' | newScheduleItems: ' + (newScheduleItems != null ? newScheduleItems.size() : 0));

        if (oldScheduleItems == null || oldScheduleItems.isEmpty() ||
            newScheduleItems == null || newScheduleItems.isEmpty()) {
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Empty input lists, skipping wire fee carryover');
            return;
        }

        // Build map of Payment_Number__c -> Old Item ID
        Map<Decimal, Id> paymentNumToOldItemId = new Map<Decimal, Id>();
        Set<Id> oldItemIds = new Set<Id>();

        for (Payment_Schedule_Item__c oldItem : oldScheduleItems) {
            if (oldItem.Payment_Number__c != null) {
                paymentNumToOldItemId.put(oldItem.Payment_Number__c, oldItem.Id);
            }
            oldItemIds.add(oldItem.Id);
        }

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Built map with ' + paymentNumToOldItemId.size() + ' payment numbers');

        // Query all wire fee records for old schedule items
        Map<Id, List<Payment_Fee__c>> oldWireFeeMap = PaymentFeeService.getWireFeesByScheduleItemIds(oldItemIds);

        // Count total wire fees
        Integer totalWireFees = 0;
        for (List<Payment_Fee__c> fees : oldWireFeeMap.values()) {
            totalWireFees += fees.size();
        }

        System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + totalWireFees + ' wire fee(s) to carry over');

        if (totalWireFees == 0) {
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | No wire fees to carry over');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS (no action needed)');
            return;
        }

        // Build map of Payment_Number__c -> New Item ID
        Map<Decimal, Id> paymentNumToNewItemId = new Map<Decimal, Id>();
        for (Payment_Schedule_Item__c newItem : newScheduleItems) {
            if (newItem.Payment_Number__c != null) {
                paymentNumToNewItemId.put(newItem.Payment_Number__c, newItem.Id);
            }
        }

        // Clone wire fees to new schedule items
        List<Payment_Fee__c> newWireFees = new List<Payment_Fee__c>();
        for (Decimal paymentNum : paymentNumToOldItemId.keySet()) {
            Id oldItemId = paymentNumToOldItemId.get(paymentNum);
            Id newItemId = paymentNumToNewItemId.get(paymentNum);

            // Only clone if both old and new items exist for this payment number
            if (newItemId != null && oldWireFeeMap.containsKey(oldItemId)) {
                for (Payment_Fee__c oldFee : oldWireFeeMap.get(oldItemId)) {
                    Payment_Fee__c newFee = oldFee.clone(false, true, false, false);
                    newFee.Payment_Schedule_Item__c = newItemId;
                    newWireFees.add(newFee);
                }
            }
        }

        if (!newWireFees.isEmpty()) {
            insert newWireFees;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newWireFees.size() + ' new wire fee(s)');
        }

        System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Wire fees carried over successfully');
        System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
    }

    /**
     * @description Create Payment_Fee__c records for a list of Payment_Schedule_Item__c records.
     * Uses the fee amounts from the schedule item fields (Setup_Fee_Amount__c, Program_Fee_Amount__c, Banking_Fee_Amount__c).
     * @param items List of Payment_Schedule_Item__c records (must have Ids populated)
     */
    public static void createFeeRecordsForScheduleItems(List<Payment_Schedule_Item__c> items) {
        if (items == null || items.isEmpty()) {
            return;
        }

        // Build wrapper map from schedule items
        Map<Id, PaymentPlanEditorController.ScheduleItemWrapper> wrapperMap = new Map<Id, PaymentPlanEditorController.ScheduleItemWrapper>();
        for (Payment_Schedule_Item__c item : items) {
            if (item.Id == null) {
                continue;
            }
            PaymentPlanEditorController.ScheduleItemWrapper wrapper = new PaymentPlanEditorController.ScheduleItemWrapper();
            wrapper.id = item.Id;
            wrapper.setupFee = item.Setup_Fee_Amount__c != null ? item.Setup_Fee_Amount__c : 0;
            wrapper.programFee = item.Program_Fee_Amount__c != null ? item.Program_Fee_Amount__c : 0;
            wrapper.bankingFee = item.Banking_Fee_Amount__c != null ? item.Banking_Fee_Amount__c : 0;
            wrapperMap.put(item.Id, wrapper);
        }

        // Create and insert fee records
        List<Payment_Fee__c> feeRecords = PaymentFeeService.createFeeRecordsForItems(items, wrapperMap);
        if (!feeRecords.isEmpty()) {
            insert feeRecords;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | createFeeRecordsForScheduleItems | Inserted ' + feeRecords.size() + ' fee record(s)');
        }
    }

    /**
     * @description Separate schedule items by status into scheduled and non-scheduled lists
     * Non-scheduled includes: Cleared, NSF, Cancelled (anything except 'Scheduled')
     * @param allItems All items to separate
     * @param nonScheduledItems Output list for non-scheduled items
     * @param scheduledItems Output list for scheduled items
     */
    public static void separateItemsByStatus(
        List<Payment_Schedule_Item__c> allItems,
        List<Payment_Schedule_Item__c> nonScheduledItems,
        List<Payment_Schedule_Item__c> scheduledItems
    ) {
        for (Payment_Schedule_Item__c item : allItems) {
            if (item.Status__c == STATUS_SCHEDULED) {
                scheduledItems.add(item);
            } else {
                nonScheduledItems.add(item);
            }
        }
    }

    /**
     * @description Calculate sum of amounts from non-scheduled items
     * Only counts CLEARED items as actually paid - NSF and Cancelled items were never collected
     * @param nonScheduledItems List of non-scheduled items
     * @return PaidSumsWrapper containing all summed values
     */
    public static PaidSumsWrapper calculatePaidSums(List<Payment_Schedule_Item__c> nonScheduledItems) {
        PaidSumsWrapper sums = new PaidSumsWrapper();

        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            sums.nonScheduledCount++;
            // Only count CLEARED items as actually paid
            // NSF and Cancelled items were never collected, so don't count their fees as "paid"
            if (item.Status__c == STATUS_CLEARED) {
                sums.setupFee += item.Setup_Fee_Amount__c != null ? item.Setup_Fee_Amount__c : 0;
                sums.programFee += item.Program_Fee_Amount__c != null ? item.Program_Fee_Amount__c : 0;
                sums.escrow += item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
            }
        }

        // Get last savings balance from the highest payment number CLEARED item
        // (NSF/Cancelled items don't contribute to actual savings balance)
        Decimal maxPaymentNumber = 0;
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            if (item.Status__c == STATUS_CLEARED && item.Payment_Number__c != null && item.Payment_Number__c > maxPaymentNumber) {
                maxPaymentNumber = item.Payment_Number__c;
                sums.savingsBalance = item.Savings_Balance__c != null ? item.Savings_Balance__c : 0;
            }
        }

        return sums;
    }

    /**
     * @description Distribute an amount evenly across N payments with proper cents handling
     * First payment receives any remainder from rounding
     * @param totalAmount Total amount to distribute
     * @param count Number of payments to distribute across
     * @return List of distributed amounts
     */
    public static List<Decimal> distributeAmountEvenly(Decimal totalAmount, Integer count) {
        List<Decimal> distributed = new List<Decimal>();

        if (count <= 0 || totalAmount <= 0) {
            for (Integer i = 0; i < count; i++) {
                distributed.add(0);
            }
            return distributed;
        }

        // Calculate base amount per payment (rounded down to 2 decimal places)
        Decimal baseAmount = (totalAmount / count).setScale(2, RoundingMode.DOWN);

        // Calculate remainder (cents that need to go to first payment)
        Decimal remainder = totalAmount - (baseAmount * count);
        remainder = remainder.setScale(2, RoundingMode.HALF_UP);

        for (Integer i = 0; i < count; i++) {
            if (i == 0) {
                // First payment gets base amount plus remainder
                distributed.add(baseAmount + remainder);
            } else {
                distributed.add(baseAmount);
            }
        }

        return distributed;
    }

    // ==================================================================================
    // PRIVATE HELPERS - Field Cloning
    // ==================================================================================

    /**
     * @description Discovers all createable, non-formula fields on an SObject,
     * excluding specified fields. Used for dynamic record-to-record cloning so
     * that new custom fields are automatically picked up without code changes.
     * @param describeResult The SObject describe result
     * @param excludeFields Set of field API names to exclude (case-insensitive)
     * @return Sorted list of field API names eligible for cloning
     */
    private static List<String> getCloneableFieldNames(
        Schema.DescribeSObjectResult describeResult,
        Set<String> excludeFields
    ) {
        Set<String> excludeLower = new Set<String>();
        if (excludeFields != null) {
            for (String f : excludeFields) {
                excludeLower.add(f.toLowerCase());
            }
        }
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        List<String> fieldNames = new List<String>();
        for (String fieldName : fieldMap.keySet()) {
            if (excludeLower.contains(fieldName)) continue;
            Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
            if (fd.isCalculated()) continue;  // Skip formula fields
            if (!fd.isCreateable()) continue; // Skip read-only system fields
            fieldNames.add(fieldName);
        }
        fieldNames.sort();
        return fieldNames;
    }

    /**
     * @description Copies field values from one SObject to another for the given field names.
     * @param source Source SObject to copy from
     * @param target Target SObject to copy to
     * @param fieldNames List of field API names to copy
     */
    private static void copyFieldValues(SObject source, SObject target, List<String> fieldNames) {
        if (source == null || target == null || fieldNames == null) return;
        for (String fieldName : fieldNames) {
            target.put(fieldName, source.get(fieldName));
        }
    }

    // ==================================================================================
    // PRIVATE HELPERS - Schedule Item Calculation
    // ==================================================================================

    /**
     * @description Calculate schedule items with all fee breakdowns
     * Handles status-based recalculation: preserves non-scheduled rows (Cleared/NSF/Cancelled)
     * and recalculates scheduled rows using the same split ratio formula as CalculationService.
     * Program fee cap is reduced by already collected amount from non-scheduled rows.
     * @param plan The Payment Plan to create items for
     * @param opp The Opportunity with source data
     * @param config The CMDT configuration
     * @param existingItems Existing schedule items from the current plan (can be null for fresh calculation)
     * @return List of Payment_Schedule_Item__c records (not yet inserted)
     */
    private static List<Payment_Schedule_Item__c> calculateScheduleItems(
        PaymentPlan__c plan,
        Opportunity opp,
        PaymentCalcConfigSvc.ConfigDTO config,
        List<Payment_Schedule_Item__c> existingItems
    ) {
        List<Payment_Schedule_Item__c> resultItems = new List<Payment_Schedule_Item__c>();

        // Get calculation parameters
        Integer numberOfPayments = plan.Number_of_Payments__c != null ?
            plan.Number_of_Payments__c.intValue() : DEFAULT_NUMBER_OF_PAYMENTS;
        Date firstPaymentDate = plan.First_Payment_Date__c != null ?
            plan.First_Payment_Date__c : Date.today().addDays(PAYMENT_INTERVAL_DAYS);
        Decimal weeklyPayment = plan.Weekly_Payment__c != null ? plan.Weekly_Payment__c : 0;

        // Get fee values
        Decimal totalSetupFee = plan.Setup_Fee__c != null ? plan.Setup_Fee__c : 0;
        Decimal setupFeePayments = plan.Setup_Fee_Payments__c != null ? plan.Setup_Fee_Payments__c : DEFAULT_SETUP_FEE_PAYMENTS;
        Decimal perPaymentSetupFee = setupFeePayments > 0 ? (totalSetupFee / setupFeePayments) : 0;

        // Get fee values from CMDT (flat fees)
        Decimal bankingFee = plan.Banking_Fee__c != null ? plan.Banking_Fee__c : config.bankingFee;
        Decimal bank2Fee = plan.Bank2_Fee__c != null ? plan.Bank2_Fee__c : config.bank2Fee;

        // Get split ratios from CMDT config (matches CalculationService)
        Decimal programSplitRatio = config.programSplitRatio != null ? config.programSplitRatio : DEFAULT_SPLIT_RATIO;

        // No Fee Program override
        Boolean isNoFeeProgram = opp.No_Fee_Program__c != null && opp.No_Fee_Program__c;
        if (isNoFeeProgram) {
            programSplitRatio = 0;
        }

        // Calculate total program fee from debt and percentage (matches CalculationService)
        Decimal totalDebt = plan.Total_Debt__c != null ? plan.Total_Debt__c : 0;
        Decimal programFeePercentage = plan.Program_Fee_Percentage__c != null ?
            plan.Program_Fee_Percentage__c : config.programFeePercent;
        Decimal totalProgramFee = totalDebt * (programFeePercentage / 100);

        // Separate existing items by status and calculate paid sums
        List<Payment_Schedule_Item__c> nonScheduledItems = new List<Payment_Schedule_Item__c>();
        List<Payment_Schedule_Item__c> scheduledItems = new List<Payment_Schedule_Item__c>();
        PaidSumsWrapper paidSums = new PaidSumsWrapper();

        if (existingItems != null && !existingItems.isEmpty()) {
            separateItemsByStatus(existingItems, nonScheduledItems, scheduledItems);
            paidSums = calculatePaidSums(nonScheduledItems);
        }

        // If no existing items or all items are scheduled, do fresh calculation
        if (existingItems == null || existingItems.isEmpty() || nonScheduledItems.isEmpty()) {
            return calculateFreshScheduleItems(plan, opp, config, numberOfPayments, firstPaymentDate);
        }

        // Calculate remaining program fee (cap reduced by already collected from CLEARED items)
        Decimal remainingProgramFee = Math.max(0, totalProgramFee - paidSums.programFee);

        // Calculate remaining setup fee payments — count ALL non-scheduled items with setup fee
        // (Cleared, NSF, Processing, Cancelled). Setup fees were already allocated to these items;
        // do not re-add them in the new schedule regardless of collection status.
        Integer paidSetupFeeCount = 0;
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            if (item.Setup_Fee_Amount__c != null && item.Setup_Fee_Amount__c > 0) {
                paidSetupFeeCount++;
            }
        }
        Integer remainingSetupFeePayments = Math.max(0, setupFeePayments.intValue() - paidSetupFeeCount);

        // Copy non-scheduled items first (preserve original values)
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            resultItems.add(cloneItemForNewPlan(item, plan.Id));
        }

        // Find the last date from non-scheduled items for smart continuation
        Date lastNonScheduledDate = null;
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            if (item.Payment_Date__c != null) {
                if (lastNonScheduledDate == null || item.Payment_Date__c > lastNonScheduledDate) {
                    lastNonScheduledDate = item.Payment_Date__c;
                }
            }
        }

        // Calculate how many scheduled items are needed based on Number_of_Weeks__c
        // Total items = numberOfPayments, so scheduled items = numberOfPayments - nonScheduledItems.size()
        Integer scheduledItemsNeeded = numberOfPayments - nonScheduledItems.size();
        if (scheduledItemsNeeded < 0) {
            scheduledItemsNeeded = 0;
        }
        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | calculateScheduleItems | numberOfPayments: ' + numberOfPayments +
            ' | nonScheduledCount: ' + nonScheduledItems.size() + ' | scheduledItemsNeeded: ' + scheduledItemsNeeded);

        // Determine start date for scheduled items (7 days after last non-scheduled item)
        Date scheduledStartDate = lastNonScheduledDate != null ?
            lastNonScheduledDate.addDays(PAYMENT_INTERVAL_DAYS) : firstPaymentDate;
        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | calculateScheduleItems | lastNonScheduledDate: ' + lastNonScheduledDate +
            ' | scheduledStartDate: ' + scheduledStartDate);

        // Start running escrow balance from last paid row's balance
        Decimal runningEscrowBalance = paidSums.savingsBalance;
        Integer setupFeePaymentsMade = 0;

        // Normalize program type for consistent comparison (space->underscore, uppercase)
        String normalizedProgramType = plan.Program_Type__c != null ? plan.Program_Type__c.replace(' ', '_').toUpperCase() : 'DCG_MOD';

        // Create scheduled items based on Number_of_Weeks__c (smart continuation)
        // This replaces the old logic that only iterated over existing scheduled items
        for (Integer i = 1; i <= scheduledItemsNeeded; i++) {
            // Payment number continues from where non-scheduled items left off
            Integer paymentNumber = nonScheduledItems.size() + i;

            Payment_Schedule_Item__c newItem = new Payment_Schedule_Item__c();
            newItem.Payment_Plan__c = plan.Id;
            newItem.Payment_Number__c = paymentNumber;
            newItem.Draft_Number__c = String.valueOf(paymentNumber);
            newItem.Payment_Date__c = scheduledStartDate.addDays((i - 1) * PAYMENT_INTERVAL_DAYS);

            // Calculate setup fee for this payment (only for remaining setup fee payments)
            Decimal thisSetupFee = 0;
            if (setupFeePaymentsMade < remainingSetupFeePayments) {
                thisSetupFee = perPaymentSetupFee;
                setupFeePaymentsMade++;
            }

            // Banking fees are flat from CMDT
            Decimal thisBankingFee = bankingFee;
            Decimal thisBank2Fee = bank2Fee;

            // Calculate net amount available for program/escrow split (matches CalculationService)
            Decimal netAmount = weeklyPayment - thisBankingFee;

            // Calculate program fee and escrow using split ratios (matches CalculationService)
            Decimal thisProgramFee = 0;
            Decimal toEscrow = 0;

            // For DCG Debt: skip program fee on first payment - all goes to escrow
            Boolean skipFeeThisPayment = (paymentNumber == 1 && normalizedProgramType == 'DCG_DEBT');

            if (remainingProgramFee > 0 && !skipFeeThisPayment) {
                // Desired program amount based on split ratio
                Decimal desiredProgramFee = netAmount * programSplitRatio;
                // Cap at remaining program fee
                thisProgramFee = Math.min(desiredProgramFee, remainingProgramFee);
                // Escrow gets the rest of net amount
                toEscrow = netAmount - thisProgramFee;
                // Reduce remaining program fee
                remainingProgramFee -= thisProgramFee;
            } else {
                // All program fees collected, everything goes to escrow
                toEscrow = netAmount;
            }

            // Update running escrow balance
            runningEscrowBalance += toEscrow;

            // Total Payment = base weekly payment + setup fee (setup fee is ON TOP)
            Decimal totalPayment = weeklyPayment + thisSetupFee;

            // Set all fields
            newItem.Total_Payment__c = totalPayment;
            newItem.Setup_Fee_Amount__c = thisSetupFee;
            newItem.Program_Fee_Amount__c = thisProgramFee;
            newItem.Banking_Fee_Amount__c = thisBankingFee;
            newItem.Bank2_Fee_Amount__c = thisBank2Fee;
            newItem.Retainer_Fee_Amount__c = DEFAULT_RETAINER_FEE;
            newItem.To_Escrow_Amount__c = toEscrow;
            newItem.Savings_Balance__c = runningEscrowBalance;
            newItem.Status__c = STATUS_SCHEDULED;

            resultItems.add(newItem);
        }

        // Sort by payment number to maintain order
        resultItems.sort();

        return resultItems;
    }

    /**
     * @description Overloaded method for backward compatibility (fresh calculation)
     */
    private static List<Payment_Schedule_Item__c> calculateScheduleItems(
        PaymentPlan__c plan,
        Opportunity opp,
        PaymentCalcConfigSvc.ConfigDTO config
    ) {
        return calculateScheduleItems(plan, opp, config, null);
    }

    /**
     * @description Calculate fresh schedule items without existing items
     * Used when there are no non-scheduled items to preserve
     */
    private static List<Payment_Schedule_Item__c> calculateFreshScheduleItems(
        PaymentPlan__c plan,
        Opportunity opp,
        PaymentCalcConfigSvc.ConfigDTO config,
        Integer numberOfPayments,
        Date firstPaymentDate
    ) {
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();

        Decimal weeklyPayment = plan.Weekly_Payment__c != null ? plan.Weekly_Payment__c : 0;
        Decimal totalSetupFee = plan.Setup_Fee__c != null ? plan.Setup_Fee__c : 0;
        Decimal setupFeePayments = plan.Setup_Fee_Payments__c != null ? plan.Setup_Fee_Payments__c : DEFAULT_SETUP_FEE_PAYMENTS;
        Decimal perPaymentSetupFee = setupFeePayments > 0 ? (totalSetupFee / setupFeePayments) : 0;

        Decimal bankingFee = plan.Banking_Fee__c != null ? plan.Banking_Fee__c : config.bankingFee;
        Decimal bank2Fee = plan.Bank2_Fee__c != null ? plan.Bank2_Fee__c : config.bank2Fee;

        Decimal programSplitRatio = config.programSplitRatio != null ? config.programSplitRatio : DEFAULT_SPLIT_RATIO;

        Boolean isNoFeeProgram = opp.No_Fee_Program__c != null && opp.No_Fee_Program__c;
        if (isNoFeeProgram) {
            programSplitRatio = 0;
        }

        Decimal totalDebt = plan.Total_Debt__c != null ? plan.Total_Debt__c : 0;
        Decimal programFeePercentage = plan.Program_Fee_Percentage__c != null ?
            plan.Program_Fee_Percentage__c : config.programFeePercent;
        Decimal totalProgramFee = totalDebt * (programFeePercentage / 100);

        Decimal remainingProgramFee = totalProgramFee;
        Decimal runningEscrowBalance = 0;

        // Normalize program type for consistent comparison (space->underscore, uppercase)
        String normalizedProgramType = plan.Program_Type__c != null ? plan.Program_Type__c.replace(' ', '_').toUpperCase() : 'DCG_MOD';

        for (Integer i = 1; i <= numberOfPayments; i++) {
            Payment_Schedule_Item__c item = new Payment_Schedule_Item__c();
            item.Payment_Plan__c = plan.Id;
            item.Payment_Number__c = i;
            item.Draft_Number__c = String.valueOf(i);
            item.Payment_Date__c = firstPaymentDate.addDays((i - 1) * PAYMENT_INTERVAL_DAYS);

            Decimal thisSetupFee = (i <= setupFeePayments.intValue()) ? perPaymentSetupFee : 0;
            Decimal netAmount = weeklyPayment - bankingFee;

            Decimal thisProgramFee = 0;
            Decimal toEscrow = 0;

            // For DCG Debt: skip program fee on first payment - all goes to escrow
            Boolean skipFeeThisPayment = (i == 1 && normalizedProgramType == 'DCG_DEBT');

            if (remainingProgramFee > 0 && !skipFeeThisPayment) {
                Decimal desiredProgramFee = netAmount * programSplitRatio;
                thisProgramFee = Math.min(desiredProgramFee, remainingProgramFee);
                toEscrow = netAmount - thisProgramFee;
                remainingProgramFee -= thisProgramFee;
            } else {
                toEscrow = netAmount;
            }

            runningEscrowBalance += toEscrow;

            item.Total_Payment__c = weeklyPayment + thisSetupFee;
            item.Setup_Fee_Amount__c = thisSetupFee;
            item.Program_Fee_Amount__c = thisProgramFee;
            item.Banking_Fee_Amount__c = bankingFee;
            item.Bank2_Fee_Amount__c = bank2Fee;
            item.Retainer_Fee_Amount__c = DEFAULT_RETAINER_FEE;
            item.To_Escrow_Amount__c = toEscrow;
            item.Savings_Balance__c = runningEscrowBalance;
            item.Status__c = STATUS_SCHEDULED;

            items.add(item);
        }

        return items;
    }

    // ==================================================================================
    // MAIN SERVICE METHODS
    // ==================================================================================

    /**
     * @description Recalculate payment plan by fetching Opportunity data and creating a new version
     * Creates a new PaymentPlan__c with incremented version number and calculates all fee breakdowns
     * @param planId The current Payment Plan ID to base calculations on
     * @return PaymentPlanWrapper for the new version
     */
    public static PaymentPlanEditorController.PaymentPlanWrapper recalculatePaymentPlan(Id planId) {
        String methodName = 'recalculatePaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get current plan with all fields via describe (ensures clone/copy never misses a field)
            String ppFields = getPaymentPlanQueryFields();
            List<PaymentPlan__c> currentPlans = Database.query(
                'SELECT ' + ppFields + ' FROM PaymentPlan__c WHERE Id = :planId LIMIT 1'
            );

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentPlans.size() + ' current plan(s)');

            if (currentPlans.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Payment Plan not found: ' + planId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c currentPlan = currentPlans[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Current Plan: ' + currentPlan.Name + ' | Version: ' + currentPlan.Version_Number__c);

            if (currentPlan.Opportunity__c == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Plan not linked to Opportunity');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Payment Plan is not linked to an Opportunity.');
            }

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Fetching Opportunity: ' + currentPlan.Opportunity__c);

            // Get Opportunity data with all required fields
            List<Opportunity> opportunities = [
                SELECT Id, Name, ContractId, Program_Type__c,
                       Setup_Fee__c, Setup_Fee_Term__c,
                       Total_Program__c, Program_Fee__c,
                       Est_weekly_payment__c, Estimated_Current_Payment__c,
                       Estimated_Total_Debt__c, Estimated_Settlement_to_Creditors__c,
                       Est_Settlement__c, Number_of_Weeks__c, First_Draft_Date__c,
                       No_Fee_Program__c, Payment_Frequency__c
                FROM Opportunity
                WHERE Id = :currentPlan.Opportunity__c
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + opportunities.size() + ' opportunity(s)');

            if (opportunities.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Opportunity not found: ' + currentPlan.Opportunity__c);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Related Opportunity not found. It may have been deleted.');
            }

            Opportunity opp = opportunities[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Opportunity: ' + opp.Name + ' | Program: ' + opp.Program_Type__c);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Opp Fields - Weekly: ' + opp.Est_weekly_payment__c + ' | Debt: ' + opp.Estimated_Total_Debt__c + ' | Weeks: ' + opp.Number_of_Weeks__c);

            // Validate required Opportunity fields
            List<String> missingFields = new List<String>();
            if (opp.Estimated_Total_Debt__c == null || opp.Estimated_Total_Debt__c <= 0) {
                missingFields.add('Estimated Total Debt');
            }
            if (opp.Number_of_Weeks__c == null || opp.Number_of_Weeks__c <= 0) {
                missingFields.add('Number of Weeks');
            }
            if (opp.Est_weekly_payment__c == null || opp.Est_weekly_payment__c <= 0) {
                missingFields.add('Est Weekly Payment');
            }
            if (!missingFields.isEmpty()) {
                String errorMsg = 'Missing or invalid required Opportunity fields: ' + String.join(missingFields, ', ') + '. Please update the Opportunity before recalculating.';
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | ' + errorMsg);
                throw new AuraHandledException(VALIDATION_SYMBOL + errorMsg);
            }

            // Get config for split ratios (banking fee comes from existing plan, fallback to config)
            // Normalize program type: Opportunity stores "DCG DEBT" (spaces), CMDT expects "DCG_DEBT" (underscores)
            String programType = opp.Program_Type__c != null ? opp.Program_Type__c : currentPlan.Program_Type__c;
            String normalizedProgramType = programType != null ? programType.replace(' ', '_').toUpperCase() : 'DCG_MOD';
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Program Type: ' + programType + ' | Normalized: ' + normalizedProgramType);

            PaymentCalcConfigSvc.ConfigDTO config;
            try {
                config = PaymentCalcConfigSvc.getRequiredConfigForProgram(normalizedProgramType);
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Loaded program-specific config for: ' + normalizedProgramType);
            } catch (Exception configEx) {
                // Fall back to default config if program-specific fails
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Program config not found, using default. Error: ' + configEx.getMessage());
                config = PaymentCalcConfigSvc.getRequiredConfig();
            }

            // Get Banking Fee from EXISTING PLAN first, fallback to CMDT config if not set
            Decimal bankingFee = currentPlan.Banking_Fee__c != null ? currentPlan.Banking_Fee__c : (config.bankingFee != null ? config.bankingFee : 15.00);
            Decimal bank2Fee = currentPlan.Bank2_Fee__c != null ? currentPlan.Bank2_Fee__c : (config.bank2Fee != null ? config.bank2Fee : 0);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | BankingFee: ' + bankingFee + ' (from ' + (currentPlan.Banking_Fee__c != null ? 'existing plan' : 'config') + ') | Bank2Fee: ' + bank2Fee + ' | SplitRatio: ' + config.programSplitRatio);

            // Calculate new version number
            Decimal newVersionNumber = currentPlan.Version_Number__c != null ?
                currentPlan.Version_Number__c + 1 : 2;
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Creating new version: ' + newVersionNumber);

            // Create new Payment Plan with data from Opportunity
            PaymentPlan__c newPlan = new PaymentPlan__c();
            newPlan.Opportunity__c = opp.Id;
            newPlan.Contract__c = opp.ContractId;
            newPlan.Program_Type__c = opp.Program_Type__c != null ? opp.Program_Type__c : currentPlan.Program_Type__c;

            // Map Opportunity fields to Payment Plan
            newPlan.Setup_Fee__c = opp.Setup_Fee__c;
            // Convert String fields to Decimal (strip % symbol if present)
            newPlan.Setup_Fee_Payments__c = parsePercentageToDecimal(opp.Setup_Fee_Term__c);
            newPlan.Program_Fee_Amount__c = opp.Total_Program__c;
            newPlan.Program_Fee_Percentage__c = parsePercentageToDecimal(opp.Program_Fee__c);
            newPlan.Weekly_Payment__c = opp.Est_weekly_payment__c;
            newPlan.Current_Payment__c = opp.Estimated_Current_Payment__c;
            newPlan.Total_Debt__c = opp.Estimated_Total_Debt__c;
            newPlan.Settlement_Amount__c = opp.Estimated_Settlement_to_Creditors__c;
            newPlan.Settlement_Percentage__c = parsePercentageToDecimal(opp.Est_Settlement__c);
            newPlan.Number_of_Payments__c = opp.Number_of_Weeks__c;
            newPlan.First_Payment_Date__c = opp.First_Draft_Date__c;
            newPlan.No_Fee_Program__c = opp.No_Fee_Program__c;

            // Set Banking Fee from CMDT
            newPlan.Banking_Fee__c = bankingFee;
            newPlan.Bank2_Fee__c = bank2Fee;

            // Version metadata
            newPlan.Version_Number__c = newVersionNumber;
            newPlan.Status__c = VERSION_STATUS_DRAFT;
            newPlan.Is_Active__c = false;
            newPlan.Previous_Version__c = currentPlan.Id;
            newPlan.Version_Type__c = VERSION_TYPE_REVISION;
            newPlan.Source__c = SOURCE_UI;
            newPlan.Version_Notes__c = 'Recalculated from Opportunity on ' + DateTime.now().format();
            newPlan.Calculation_Timestamp__c = DateTime.now();

            // Carry forward calculator settings from previous plan
            newPlan.Target_Payment_Percent__c = currentPlan.Target_Payment_Percent__c;
            newPlan.Calculation_Mode__c = currentPlan.Calculation_Mode__c;
            newPlan.Payment_Frequency__c = opp.Payment_Frequency__c != null ? opp.Payment_Frequency__c : currentPlan.Payment_Frequency__c;
            newPlan.Preferred_Day_of_Week__c = currentPlan.Preferred_Day_of_Week__c;
            // Calculate Total Program Cost, Total Savings, and Total Banking Fee
            Decimal totalProgram = (newPlan.Settlement_Amount__c != null ? newPlan.Settlement_Amount__c : 0)
                + (newPlan.Program_Fee_Amount__c != null ? newPlan.Program_Fee_Amount__c : 0)
                + (newPlan.Setup_Fee__c != null ? newPlan.Setup_Fee__c : 0)
                + (bankingFee * (newPlan.Number_of_Payments__c != null ? newPlan.Number_of_Payments__c : 0));
            newPlan.Total_Program_Cost__c = totalProgram;
            newPlan.Total_Savings__c = (newPlan.Total_Debt__c != null ? newPlan.Total_Debt__c : 0) - totalProgram;
            newPlan.Total_Banking_Fee__c = bankingFee * (newPlan.Number_of_Payments__c != null ? newPlan.Number_of_Payments__c : 0);
            newPlan.Monthly_Payment__c = newPlan.Weekly_Payment__c != null ? (newPlan.Weekly_Payment__c * 4.33).setScale(2, RoundingMode.HALF_UP) : null;

            insert newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted new plan: ' + newPlan.Id + ' | Weekly: ' + newPlan.Weekly_Payment__c + ' | Payments: ' + newPlan.Number_of_Payments__c);

            // Query existing schedule items from current plan for status-based redistribution
            String fields = getScheduleItemQueryFields();
            String query = 'SELECT ' + fields +
                ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :planId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
            List<Payment_Schedule_Item__c> existingItems = Database.query(query);
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + existingItems.size() + ' existing schedule items');

            // Count items by status for logging
            Integer clearedCount = 0, nsfCount = 0, cancelledCount = 0, scheduledCount = 0;
            for (Payment_Schedule_Item__c item : existingItems) {
                if (item.Status__c == STATUS_CLEARED) clearedCount++;
                else if (item.Status__c == STATUS_NSF) nsfCount++;
                else if (item.Status__c == STATUS_CANCELLED) cancelledCount++;
                else if (item.Status__c == STATUS_SCHEDULED) scheduledCount++;
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Item Status Breakdown - Cleared: ' + clearedCount + ' | NSF: ' + nsfCount + ' | Cancelled: ' + cancelledCount + ' | Scheduled: ' + scheduledCount);

            // Calculate and create schedule items (preserves non-scheduled, redistributes scheduled)
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Calculating schedule items...');
            List<Payment_Schedule_Item__c> scheduleItems = calculateScheduleItems(newPlan, opp, config, existingItems);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Calculated ' + scheduleItems.size() + ' schedule items');

            if (!scheduleItems.isEmpty()) {
                // Recalculate Draft_Number__c to skip NSF/Cancelled items
                recalculateDraftNumbers(scheduleItems);
                insert scheduleItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + scheduleItems.size() + ' schedule items');

                // Create Payment_Fee__c records for all new schedule items
                createFeeRecordsForScheduleItems(scheduleItems);
            }

            // Carry over wired payments from old plan to new plan
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Carrying over wired payments...');
            carryOverWireFees(existingItems, scheduleItems);

            // Update plan item count
            newPlan.Schedule_Item_Count__c = scheduleItems.size();
            update newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Updated plan item count: ' + scheduleItems.size());

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Recalculation completed successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return PaymentPlanEditorController.getPaymentPlanById(newPlan.Id);

        } catch (PaymentCalcConfigException configEx) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Config Exception: ' + configEx.getMessage());
            throw new AuraHandledException(CONFIG_SYMBOL + 'Configuration error: ' + configEx.getMessage());
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error recalculating payment plan: ' + e.getMessage());
        }
    }

    /**
     * @description Recalculate remaining balance by redistributing unpaid debt evenly across future scheduled payments.
     * Algorithm:
     * 1. Total Program Cost = Estimated_Total_Debt__c x 0.95 (Settlement 60% + Program Fee 35%)
     * 2. Paid To Date = SUM(Cleared payments' Total_Payment__c) + SUM(Wire Fees Amount__c)
     * 3. Remaining Balance = Total Program Cost - Paid To Date
     * 4. If Remaining Balance <= 0 -> Error: "Debt is already paid off"
     * 5. Remaining Count = Number_of_Weeks__c - COUNT(non-Scheduled items)
     * 6. Base Payment = FLOOR(Remaining Balance / Remaining Count, 2 decimals)
     * 7. Remainder = Remaining Balance - (Base Payment x Remaining Count)
     * 8. Last payment = Base Payment + Remainder (cents adjustment)
     * @param planId The current Payment Plan ID
     * @return PaymentPlanWrapper for the new version
     */
    public static PaymentPlanEditorController.PaymentPlanWrapper recalculateRemainingBalance(Id planId) {
        String methodName = 'recalculateRemainingBalance';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get current plan with all fields via describe (ensures clone never misses a field)
            String ppFields = getPaymentPlanQueryFields();
            List<PaymentPlan__c> currentPlans = Database.query(
                'SELECT ' + ppFields + ' FROM PaymentPlan__c WHERE Id = :planId LIMIT 1'
            );

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentPlans.size() + ' current plan(s)');

            if (currentPlans.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Payment Plan not found: ' + planId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c currentPlan = currentPlans[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Current Plan: ' + currentPlan.Name + ' | Version: ' + currentPlan.Version_Number__c);

            if (currentPlan.Opportunity__c == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Plan not linked to Opportunity');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Payment Plan is not linked to an Opportunity.');
            }

            // Get Opportunity with all required fields (same as recalculatePaymentPlan)
            List<Opportunity> opportunities = [
                SELECT Id, Name, Estimated_Total_Debt__c, Number_of_Weeks__c, First_Draft_Date__c,
                       No_Fee_Program__c, Program_Type__c,
                       Setup_Fee__c, Setup_Fee_Term__c,
                       Total_Program__c, Program_Fee__c, Est_Settlement__c,
                       Est_weekly_payment__c, Payment_Frequency__c,
                       Estimated_Current_Payment__c
                FROM Opportunity
                WHERE Id = :currentPlan.Opportunity__c
                LIMIT 1
            ];

            if (opportunities.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Opportunity not found');
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Related Opportunity not found.');
            }

            Opportunity opp = opportunities[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Opportunity: ' + opp.Name + ' | Est Debt: ' + opp.Estimated_Total_Debt__c + ' | Weeks: ' + opp.Number_of_Weeks__c);

            // Validate required Opportunity fields
            List<String> missingFields = new List<String>();
            if (opp.Estimated_Total_Debt__c == null || opp.Estimated_Total_Debt__c <= 0) {
                missingFields.add('Estimated Total Debt');
            }
            if (opp.Number_of_Weeks__c == null || opp.Number_of_Weeks__c <= 0) {
                missingFields.add('Number of Weeks');
            }
            if (!missingFields.isEmpty()) {
                String errorMsg = 'Missing or invalid required Opportunity fields: ' + String.join(missingFields, ', ') + '. Please update the Opportunity before recalculating.';
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | ' + errorMsg);
                throw new AuraHandledException(VALIDATION_SYMBOL + errorMsg);
            }

            // Get CMDT config for program split ratio (same as recalculatePaymentPlan)
            String programType = opp.Program_Type__c != null ? opp.Program_Type__c : currentPlan.Program_Type__c;
            String normalizedProgramType = programType != null ? programType.replace(' ', '_').toUpperCase() : 'DCG_MOD';
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Program Type: ' + programType + ' | Normalized: ' + normalizedProgramType);

            PaymentCalcConfigSvc.ConfigDTO config;
            try {
                config = PaymentCalcConfigSvc.getRequiredConfigForProgram(normalizedProgramType);
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Loaded program-specific config for: ' + normalizedProgramType);
            } catch (Exception configEx) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Program config not found, using default. Error: ' + configEx.getMessage());
                config = PaymentCalcConfigSvc.getRequiredConfig();
            }

            // Get split ratios from CMDT config (matches CalculationService)
            Decimal programSplitRatio = config.programSplitRatio != null ? config.programSplitRatio : DEFAULT_SPLIT_RATIO;

            // No Fee Program override
            Boolean isNoFeeProgram = opp.No_Fee_Program__c != null && opp.No_Fee_Program__c;
            if (isNoFeeProgram) {
                programSplitRatio = 0;
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Program Split Ratio: ' + programSplitRatio + ' | No Fee Program: ' + isNoFeeProgram);

            // Step 1: Calculate Settlement + Program Fee from actual percentages (NOT hardcoded 0.95)
            Decimal estimatedTotalDebt = opp.Estimated_Total_Debt__c != null ? opp.Estimated_Total_Debt__c : 0;
            Decimal totalDebt = estimatedTotalDebt;

            // Settlement percentage from Opportunity, fallback to config, then default 60%
            Decimal settlementPercentage = parsePercentageToDecimal(opp.Est_Settlement__c);
            if (settlementPercentage == null) {
                settlementPercentage = config.settlementPercent != null ? config.settlementPercent : 60;
            }
            Decimal settlementAmount = (totalDebt * (settlementPercentage / 100)).setScale(2, RoundingMode.HALF_UP);

            // Program fee percentage from Opportunity, fallback to config, then default 35%
            Decimal programFeePercentage = parsePercentageToDecimal(opp.Program_Fee__c);
            if (programFeePercentage == null) {
                programFeePercentage = config.programFeePercent != null ? config.programFeePercent : 35;
            }
            Decimal totalProgramFee = (totalDebt * (programFeePercentage / 100)).setScale(2, RoundingMode.HALF_UP);

            // Total Program Cost = Settlement + Program Fee (each from its own percentage)
            Decimal totalProgramCost = settlementAmount + totalProgramFee;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Settlement: ' + settlementAmount + ' (' + settlementPercentage + '%) | ProgramFee: ' + totalProgramFee + ' (' + programFeePercentage + '%) | TotalProgramCost: ' + totalProgramCost);

            // Get setup fee parameters from OPPORTUNITY
            Decimal totalSetupFee = opp.Setup_Fee__c != null ? opp.Setup_Fee__c : 0;
            Decimal setupFeePaymentsTotal = parsePercentageToDecimal(opp.Setup_Fee_Term__c);
            if (setupFeePaymentsTotal == null || setupFeePaymentsTotal <= 0) {
                setupFeePaymentsTotal = DEFAULT_SETUP_FEE_PAYMENTS;
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Setup Fee (from Opp): ' + totalSetupFee + ' over ' + setupFeePaymentsTotal + ' payments');

            // Get existing schedule items
            String fields = getScheduleItemQueryFields();
            String query = 'SELECT ' + fields +
                ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :planId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
            List<Payment_Schedule_Item__c> existingItems = Database.query(query);
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + existingItems.size() + ' existing schedule items');

            // Separate items by status and calculate paid amounts
            List<Payment_Schedule_Item__c> nonScheduledItems = new List<Payment_Schedule_Item__c>();
            List<Payment_Schedule_Item__c> scheduledItems = new List<Payment_Schedule_Item__c>();
            Decimal clearedProgramCostSum = 0;  // Sum of (Program_Fee + To_Escrow) - the actual program cost paid
            Decimal paidProgramFeeSum = 0;
            Decimal paidEscrowSum = 0;
            Integer paidSetupFeeCount = 0;
            Decimal paidSetupFeeAmount = 0;
            // Track lost fees from NSF items for logging/reporting purposes
            // Note: Banking fees are NOT recovered (no cascading) per business requirement
            Decimal lostSetupFeeFromNSF = 0;
            Decimal lostProgramFeeFromNSF = 0;
            Integer nsfItemCount = 0;
            Integer nsfSetupFeeCount = 0; // Count of NSF items that had setup fees

            for (Payment_Schedule_Item__c item : existingItems) {
                if (item.Status__c == STATUS_SCHEDULED) {
                    scheduledItems.add(item);
                } else {
                    nonScheduledItems.add(item);
                    // Sum Program_Fee + To_Escrow from Cleared items (the actual program cost portion)
                    // NOT Total_Payment which includes setup fee and banking fee
                    if (item.Status__c == STATUS_CLEARED) {
                        Decimal programFee = item.Program_Fee_Amount__c != null ? item.Program_Fee_Amount__c : 0;
                        Decimal toEscrow = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
                        clearedProgramCostSum += (programFee + toEscrow);
                        paidEscrowSum += toEscrow;
                    }
                    // Count and sum setup fees from ALL non-scheduled items (Cleared, NSF, Processing, Cancelled)
                    // Setup fees were already allocated -- do not re-add them in the new schedule
                    if (item.Setup_Fee_Amount__c != null && item.Setup_Fee_Amount__c > 0) {
                        paidSetupFeeCount++;
                        paidSetupFeeAmount += item.Setup_Fee_Amount__c;
                    }
                    // Track program fees already collected (from Cleared items only)
                    if (item.Status__c == STATUS_CLEARED && item.Program_Fee_Amount__c != null && item.Program_Fee_Amount__c > 0) {
                        paidProgramFeeSum += item.Program_Fee_Amount__c;
                    }
                    // Track lost fees from NSF items for logging purposes
                    // Note: Banking fees are NOT recovered to prevent cascading fee increase
                    if (item.Status__c == STATUS_NSF) {
                        nsfItemCount++;
                        if (item.Setup_Fee_Amount__c != null && item.Setup_Fee_Amount__c > 0) {
                            lostSetupFeeFromNSF += item.Setup_Fee_Amount__c;
                            nsfSetupFeeCount++; // Count NSF items with setup fees to extend setup fee payments
                        }
                        if (item.Program_Fee_Amount__c != null && item.Program_Fee_Amount__c > 0) {
                            lostProgramFeeFromNSF += item.Program_Fee_Amount__c;
                        }
                    }
                }
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Non-Scheduled: ' + nonScheduledItems.size() + ' | Scheduled: ' + scheduledItems.size());
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Cleared Program Cost (Program+Escrow): ' + clearedProgramCostSum);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Paid Program Fee: ' + paidProgramFeeSum + ' | Paid Escrow: ' + paidEscrowSum + ' | Paid Setup Fee Payments: ' + paidSetupFeeCount);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | NSF Items: ' + nsfItemCount + ' | NSF Setup Fee Count: ' + nsfSetupFeeCount);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Lost Setup Fee: ' + lostSetupFeeFromNSF + ' | Lost Program Fee: ' + lostProgramFeeFromNSF + ' (Banking fees not recovered)');

            // Calculate remaining fees
            // remainingProgramFee = totalProgramFee - paidProgramFeeSum
            // Since paidProgramFeeSum only counts CLEARED items, NSF items' program fees are already
            // included in the remaining (they were never counted as "paid"), so NO additional addition needed
            Decimal remainingProgramFee = Math.max(0, totalProgramFee - paidProgramFeeSum);
            // Calculate remaining setup fee payments
            // paidSetupFeeCount includes ALL non-scheduled items with setup fee (Cleared, NSF, Processing, Cancelled)
            // Setup fees were already allocated to those items -- do not redistribute
            Integer remainingSetupFeePayments = Math.max(0, setupFeePaymentsTotal.intValue() - paidSetupFeeCount);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Remaining Program Fee: ' + remainingProgramFee);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Remaining Setup Fee Payments: ' + remainingSetupFeePayments);

            // Step 2 (cont): Paid To Date = Cleared Program Cost
            // Note: Wire fees are now tracked separately in Payment_Fee__c
            Decimal paidProgramCost = clearedProgramCostSum;
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Paid Program Cost (Cleared Program+Escrow): ' + paidProgramCost);

            // Step 3: Remaining Program Cost = Total Program Cost - Paid Program Cost
            Decimal remainingProgramCost = totalProgramCost - paidProgramCost;
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Remaining Program Cost (before NSF recovery): ' + remainingProgramCost);

            // Note on NSF fee recovery:
            // - Program Fee: Already included in remainingProgramCost because paidProgramCost only counts CLEARED items
            // - Setup Fee: Recovered by extending setup fee payments (nsfSetupFeeCount added to remainingSetupFeePayments)
            // - Banking Fee: NOT recovered - per business requirement to prevent cascading fee increases
            // NO additional addition to remainingProgramCost needed for Program Fee - it's already there
            Decimal totalLostFeesFromNSF = lostSetupFeeFromNSF + lostProgramFeeFromNSF;
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Total lost fees from NSF: $' + totalLostFeesFromNSF + ' (Setup: $' + lostSetupFeeFromNSF + ', Program: $' + lostProgramFeeFromNSF + ') - Banking fees not recovered');

            // Step 4: Validate remaining balance
            if (remainingProgramCost <= 0) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Remaining program cost <= 0');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Debt is already paid off. Remaining balance: ' + remainingProgramCost.setScale(2));
            }

            // Step 5: Remaining Count = Number_of_Weeks__c - COUNT(non-Scheduled items)
            Integer numberOfWeeks = opp.Number_of_Weeks__c != null ? opp.Number_of_Weeks__c.intValue() : DEFAULT_NUMBER_OF_PAYMENTS;
            Integer remainingCount = numberOfWeeks - nonScheduledItems.size();
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Remaining Count: ' + remainingCount + ' (Weeks: ' + numberOfWeeks + ' - Non-Scheduled: ' + nonScheduledItems.size() + ')');

            // Validate remaining count
            if (remainingCount <= 0) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | No remaining payments to schedule');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'No remaining payments to schedule. All payments have been processed.');
            }

            // Get Banking Fee from current plan or config (need this before calculating weekly payment)
            Decimal bankingFee = currentPlan.Banking_Fee__c != null ? currentPlan.Banking_Fee__c : DEFAULT_BANKING_FEE;
            Decimal bank2Fee = currentPlan.Bank2_Fee__c != null ? currentPlan.Bank2_Fee__c : 0;

            // Banking fees are NOT recovered from NSF items to prevent cascading fee increases
            // Each payment uses the flat base banking fee from config
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Banking fee per payment: $' + bankingFee + ' (flat rate, no recovery from NSF)');

            // Step 6: Calculate evenly distributed base program cost per payment
            // Use CEILING rounding so most payments are slightly higher, and last payment is <= others
            // This ensures even distribution with last payment being at most 1 cent less (never more)
            Decimal baseProgramCostPerPayment = (remainingProgramCost / remainingCount).setScale(2, RoundingMode.CEILING);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Base Program Cost per Payment (CEILING): ' + baseProgramCostPerPayment);

            // Weekly Payment = Base Program Cost + Banking Fee
            Decimal weeklyPayment = baseProgramCostPerPayment + bankingFee;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Weekly Payment (Base + Banking): ' + weeklyPayment);

            // Step 7: Calculate last payment's program cost
            // Last payment = Remaining Program Cost - (Base x (Count - 1))
            // This will be <= baseProgramCostPerPayment (at most a few cents less)
            Decimal lastPaymentProgramCost = remainingProgramCost - (baseProgramCostPerPayment * (remainingCount - 1));
            lastPaymentProgramCost = lastPaymentProgramCost.setScale(2, RoundingMode.HALF_UP);
            Decimal lastWeeklyPayment = lastPaymentProgramCost + bankingFee;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Last Payment Program Cost: ' + lastPaymentProgramCost + ' | Last Weekly Payment: ' + lastWeeklyPayment);

            // Create new version of the plan
            Decimal newVersionNumber = currentPlan.Version_Number__c != null ?
                currentPlan.Version_Number__c + 1 : 2;
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Creating new version: ' + newVersionNumber);

            PaymentPlan__c newPlan = currentPlan.clone(false, true, false, false);
            newPlan.Version_Number__c = newVersionNumber;
            newPlan.Status__c = VERSION_STATUS_DRAFT;
            newPlan.Is_Active__c = false;
            newPlan.Previous_Version__c = currentPlan.Id;
            newPlan.Version_Type__c = VERSION_TYPE_REVISION;
            newPlan.Source__c = SOURCE_UI;
            // Build version notes with NSF recovery details if applicable
            String versionNotes = 'Remaining balance recalculated on ' + DateTime.now().format() +
                '. Weekly payment: $' + weeklyPayment + ' × ' + remainingCount + ' payments (Program cost: $' + baseProgramCostPerPayment + ' + Banking: $' + bankingFee + ').';
            if (totalLostFeesFromNSF > 0) {
                versionNotes += ' NSF items: ' + nsfItemCount + ' (Setup Fee $' + lostSetupFeeFromNSF.setScale(2) + ', Program Fee $' + lostProgramFeeFromNSF.setScale(2) + ' - recovered via remaining payments).';
            }
            newPlan.Version_Notes__c = versionNotes;
            newPlan.Calculation_Timestamp__c = DateTime.now();
            newPlan.Weekly_Payment__c = weeklyPayment; // Update weekly payment to new calculated amount

            // Update setup fee and program fee from Opportunity (same as recalculatePaymentPlan)
            newPlan.Setup_Fee__c = totalSetupFee;
            newPlan.Setup_Fee_Payments__c = setupFeePaymentsTotal;
            newPlan.Program_Fee_Percentage__c = programFeePercentage;
            newPlan.Total_Debt__c = totalDebt;

            // Update Program Type, No Fee Program, and Number of Payments from Opportunity
            newPlan.Program_Type__c = opp.Program_Type__c;
            newPlan.No_Fee_Program__c = opp.No_Fee_Program__c;
            newPlan.Number_of_Payments__c = opp.Number_of_Weeks__c;

            // Carry forward calculator settings (clone copies them, but recalculate banking/savings)
            newPlan.Payment_Frequency__c = opp.Payment_Frequency__c != null ? opp.Payment_Frequency__c : currentPlan.Payment_Frequency__c;
            newPlan.Total_Banking_Fee__c = bankingFee * (newPlan.Number_of_Payments__c != null ? newPlan.Number_of_Payments__c : 0);
            Decimal recalcTotalProgram = (remainingProgramCost != null ? remainingProgramCost : 0)
                + (totalSetupFee != null ? totalSetupFee : 0)
                + (bankingFee * (newPlan.Number_of_Payments__c != null ? newPlan.Number_of_Payments__c : 0));
            newPlan.Total_Program_Cost__c = recalcTotalProgram;
            newPlan.Total_Savings__c = (totalDebt != null ? totalDebt : 0) - recalcTotalProgram;

            // Ensure calculated plan fields are populated using the actual percentages calculated above
            newPlan.Settlement_Percentage__c = settlementPercentage;
            newPlan.Settlement_Amount__c = settlementAmount;
            newPlan.Program_Fee_Amount__c = totalProgramFee;
            newPlan.Program_Fee_Percentage__c = programFeePercentage;
            newPlan.Current_Payment__c = opp.Estimated_Current_Payment__c;
            newPlan.Monthly_Payment__c = (weeklyPayment * 4.33).setScale(2, RoundingMode.HALF_UP);

            insert newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted new plan: ' + newPlan.Id);

            // Create schedule items
            List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();

            // Copy non-Scheduled items first (preserve Cleared/NSF/Cancelled)
            for (Payment_Schedule_Item__c item : nonScheduledItems) {
                newItems.add(cloneItemForNewPlan(item, newPlan.Id));
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Copied ' + nonScheduledItems.size() + ' non-scheduled items');

            // Find the last date from non-scheduled items
            Date lastNonScheduledDate = null;
            for (Payment_Schedule_Item__c item : nonScheduledItems) {
                if (item.Payment_Date__c != null) {
                    if (lastNonScheduledDate == null || item.Payment_Date__c > lastNonScheduledDate) {
                        lastNonScheduledDate = item.Payment_Date__c;
                    }
                }
            }

            // Determine start date for new scheduled items
            Date firstDraftDate = opp.First_Draft_Date__c != null ? opp.First_Draft_Date__c : Date.today();
            Date scheduledStartDate = lastNonScheduledDate != null ?
                lastNonScheduledDate.addDays(PAYMENT_INTERVAL_DAYS) : firstDraftDate;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Scheduled start date: ' + scheduledStartDate);

            // Create new Scheduled items with uniform payment amounts and proper fee split
            Decimal runningEscrowBalance = 0;
            // Get the last savings balance from non-scheduled items
            for (Payment_Schedule_Item__c item : nonScheduledItems) {
                if (item.Savings_Balance__c != null && item.Savings_Balance__c > runningEscrowBalance) {
                    runningEscrowBalance = item.Savings_Balance__c;
                }
            }

            // Track setup fee payments made in this loop and remaining program fee for split calculation
            Integer setupFeePaymentsMade = 0;
            Decimal trackingRemainingProgramFee = remainingProgramFee;

            // Setup fee: use FLOOR rounding with last-payment-remainder to ensure exact total
            Decimal remainingSetupFeeAmount = Math.max(0, totalSetupFee - paidSetupFeeAmount);
            Decimal baseSetupFeePerPayment = remainingSetupFeePayments > 0
                ? (remainingSetupFeeAmount / remainingSetupFeePayments).setScale(2, RoundingMode.FLOOR)
                : 0;
            Decimal lastSetupFeePaymentAmt = remainingSetupFeePayments > 0
                ? (remainingSetupFeeAmount - (baseSetupFeePerPayment * (remainingSetupFeePayments - 1))).setScale(2, RoundingMode.HALF_UP)
                : 0;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Setup fee distribution: base=' + baseSetupFeePerPayment + ' x ' + (remainingSetupFeePayments - 1) + ' + last=' + lastSetupFeePaymentAmt + ' = ' + remainingSetupFeeAmount);

            for (Integer i = 1; i <= remainingCount; i++) {
                Integer paymentNumber = nonScheduledItems.size() + i;

                Payment_Schedule_Item__c newItem = new Payment_Schedule_Item__c();
                newItem.Payment_Plan__c = newPlan.Id;
                newItem.Payment_Number__c = paymentNumber;
                newItem.Draft_Number__c = String.valueOf(paymentNumber);
                newItem.Payment_Date__c = scheduledStartDate.addDays((i - 1) * PAYMENT_INTERVAL_DAYS);

                // Step 8: Last payment uses pre-calculated amount (will be <= base weekly payment)
                // All other payments use the base weekly payment
                Decimal thisWeeklyPayment = weeklyPayment;
                if (i == remainingCount) {
                    thisWeeklyPayment = lastWeeklyPayment;
                }

                // Setup fee: last setup fee payment absorbs remainder to keep total exact
                Decimal thisSetupFee = 0;
                if (setupFeePaymentsMade < remainingSetupFeePayments) {
                    Boolean isLastSetupPayment = (setupFeePaymentsMade == remainingSetupFeePayments - 1);
                    thisSetupFee = isLastSetupPayment ? lastSetupFeePaymentAmt : baseSetupFeePerPayment;
                    setupFeePaymentsMade++;
                }

                // Banking fees: flat rate from config (no recovery from NSF items)
                Decimal thisBankingFee = bankingFee;
                Decimal thisBank2Fee = bank2Fee;

                // Calculate net amount available for program/escrow split (matches CalculationService)
                // Note: net amount uses base banking fee only, extra banking fee is separate recovery
                Decimal netAmount = thisWeeklyPayment - bankingFee;

                // Calculate program fee and escrow using split ratios (matches CalculationService)
                Decimal thisProgramFee = 0;
                Decimal toEscrow = 0;

                // For DCG Debt: skip program fee on first payment -- all goes to escrow
                Boolean skipFeeThisPayment = (paymentNumber == 1 && normalizedProgramType == 'DCG_DEBT');

                if (trackingRemainingProgramFee > 0 && !skipFeeThisPayment) {
                    // Desired program amount based on split ratio
                    Decimal desiredProgramFee = netAmount * programSplitRatio;
                    // Cap at remaining program fee
                    thisProgramFee = Math.min(desiredProgramFee, trackingRemainingProgramFee);
                    // Escrow gets the rest of net amount
                    toEscrow = netAmount - thisProgramFee;
                    // Reduce tracking remaining program fee
                    trackingRemainingProgramFee -= thisProgramFee;
                } else {
                    // All program fees collected, everything goes to escrow
                    toEscrow = netAmount;
                }

                // Update running escrow balance
                runningEscrowBalance += toEscrow;

                // Total Payment = base weekly payment + setup fee
                // thisWeeklyPayment already includes base banking fee
                Decimal totalPayment = thisWeeklyPayment + thisSetupFee;

                // Set all fields
                newItem.Total_Payment__c = totalPayment;
                newItem.Setup_Fee_Amount__c = thisSetupFee;
                newItem.Program_Fee_Amount__c = thisProgramFee;
                newItem.Banking_Fee_Amount__c = thisBankingFee;
                newItem.Bank2_Fee_Amount__c = thisBank2Fee;
                newItem.Retainer_Fee_Amount__c = DEFAULT_RETAINER_FEE;
                newItem.To_Escrow_Amount__c = toEscrow;
                newItem.Savings_Balance__c = runningEscrowBalance;
                newItem.Status__c = STATUS_SCHEDULED;

                newItems.add(newItem);
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Created ' + remainingCount + ' new scheduled items with proper fee split');

            if (!newItems.isEmpty()) {
                // Recalculate Draft_Number__c to skip NSF/Cancelled items
                recalculateDraftNumbers(newItems);
                insert newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newItems.size() + ' schedule items total');

                // Create Payment_Fee__c records for all new schedule items
                createFeeRecordsForScheduleItems(newItems);
            }

            // Carry over wired payments
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Carrying over wired payments...');
            carryOverWireFees(existingItems, newItems);

            // Update plan item count
            newPlan.Schedule_Item_Count__c = newItems.size();
            update newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Updated plan item count: ' + newItems.size());

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Remaining balance recalculation completed successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return PaymentPlanEditorController.getPaymentPlanById(newPlan.Id);

        } catch (AuraHandledException ae) {
            Database.rollback(sp);
            throw ae;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error recalculating remaining balance: ' + e.getMessage());
        }
    }
}
