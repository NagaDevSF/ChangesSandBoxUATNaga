/**
 * @description Controller for Payment Plan Editor LWC component.
 *
 * This controller provides comprehensive CRUD operations for Payment Plans and their
 * associated Payment Schedule Items with full version management support.
 *
 * KEY FEATURES:
 * - Version-controlled payment plans with draft/active/archived states
 * - Bulk operations support for schedule items (create, update, delete)
 * - Recalculation of payment schedules based on Opportunity data
 * - Wire fee tracking and carryover between versions
 * - Plan suspension with automatic item status updates
 *
 * RELATED OBJECTS:
 * - PaymentPlan__c: Master record containing plan configuration
 * - Payment_Schedule_Item__c: Individual payment line items
 * - Payment_Fee__c: Fee records including wire fees linked to schedule items
 * - Opportunity: Source of debt and program configuration
 *
 * USAGE:
 * This controller is designed to be used exclusively by the paymentPlanEditor LWC.
 * All methods are @AuraEnabled and return wrapper objects for optimal LWC integration.
 *
 * ERROR HANDLING:
 * All methods use try-catch blocks with transaction savepoints for data integrity.
 * Errors are logged with correlation IDs and returned as AuraHandledException.
 *
 * @author DCG Development Team
 * @since 2024-01
 * @see PaymentPlanEditorControllerTest
 * @see paymentPlanEditor LWC
 */
public with sharing class PaymentPlanEditorController {

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
    private static final String CLASS_NAME = 'PaymentPlanEditorController';
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

    /**
     * @description Dynamically builds the field list for Payment_Schedule_Item__c queries
     * using Schema describe. Includes all accessible fields so new custom fields are
     * automatically picked up without code changes.
     * @return Comma-separated field names for use in SOQL queries
     */
    private static String getScheduleItemQueryFields() {
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
    private static String getPaymentPlanQueryFields() {
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

    // ==================================================================================
    // WRAPPER CLASSES - Data Transfer Objects for LWC Communication
    // ==================================================================================

    /**
     * @description Wrapper class containing a Payment Plan with its associated Schedule Items.
     *
     * This is the primary data structure returned to the LWC component, providing
     * all necessary data for displaying and editing a payment plan.
     *
     * @example
     * PaymentPlanWrapper wrapper = PaymentPlanEditorController.getPaymentPlanById(planId);
     * System.debug('Plan has ' + wrapper.scheduleItems.size() + ' items');
     */
    public class PaymentPlanWrapper {
        /** The PaymentPlan__c record with all configuration and rollup fields */
        @AuraEnabled public PaymentPlan__c paymentPlan { get; set; }
        /** List of schedule items belonging to this plan */
        @AuraEnabled public List<ScheduleItemWrapper> scheduleItems { get; set; }
        /** Version number for display (extracted from paymentPlan for convenience) */
        @AuraEnabled public Integer versionNumber { get; set; }
        /** Version status: Draft, Active, or Archived */
        @AuraEnabled public String versionStatus { get; set; }
        /** True if this is the most recent version for the Opportunity */
        @AuraEnabled public Boolean isLatestVersion { get; set; }
        /** Full name of the user who created this plan */
        @AuraEnabled public String createdByName { get; set; }
        /** Full name of the user who last modified (activated) this plan */
        @AuraEnabled public String lastModifiedByName { get; set; }

        /**
         * @description Default constructor initializing empty schedule items list
         */
        public PaymentPlanWrapper() {
            this.scheduleItems = new List<ScheduleItemWrapper>();
        }
    }

    /**
     * @description Wrapper class for individual Payment Schedule Item records.
     *
     * Contains all payment details plus metadata flags for tracking changes
     * in the LWC (isModified, isNew, isDeleted).
     *
     * FIELD MAPPING:
     * - draftAmount -> Total_Payment__c (total payment including all fees)
     * - setupFee -> Setup_Fee_Amount__c
     * - programFee -> Program_Fee_Amount__c
     * - bankingFee -> Banking_Fee_Amount__c
     * - savingsBalance -> Savings_Balance__c (running escrow balance)
     */
    public class ScheduleItemWrapper {
        /** Salesforce record ID (null for new items) */
        @AuraEnabled public String id { get; set; }
        /** Display row number (1-based) */
        @AuraEnabled public Integer rowNumber { get; set; }
        /** Draft/check number for reference */
        @AuraEnabled public String draftNumber { get; set; }
        /** Scheduled payment date */
        @AuraEnabled public Date paymentDate { get; set; }
        /** Total payment amount (maps to Total_Payment__c) */
        @AuraEnabled public Decimal draftAmount { get; set; }
        /** Retainer fee portion */
        @AuraEnabled public Decimal retainerFee { get; set; }
        /** Setup fee portion (first N payments only) */
        @AuraEnabled public Decimal setupFee { get; set; }
        /** Program fee portion */
        @AuraEnabled public Decimal programFee { get; set; }
        /** Primary banking fee */
        @AuraEnabled public Decimal bankingFee { get; set; }
        /** Secondary banking fee (if applicable) */
        @AuraEnabled public Decimal banking2Fee { get; set; }
        /** Running escrow/savings balance after this payment */
        @AuraEnabled public Decimal savingsBalance { get; set; }
        /** Amount going to escrow for settlements */
        @AuraEnabled public Decimal toEscrowAmount { get; set; }
        /** Payment status: Scheduled, Cleared, NSF, or Cancelled */
        @AuraEnabled public String status { get; set; }
        /** Total wire fees for this item (calculated from Payment_Fee__c records) */
        @AuraEnabled public Decimal wiresReceived { get; set; }
        /** Flag indicating item was modified in the UI */
        @AuraEnabled public Boolean isModified { get; set; }
        /** Flag indicating item is newly created (not yet saved) */
        @AuraEnabled public Boolean isNew { get; set; }
        /** Flag indicating item should be deleted on save */
        @AuraEnabled public Boolean isDeleted { get; set; }
        /** Flag indicating item is frozen (non-Scheduled status) and should not be modified */
        @AuraEnabled public Boolean isFrozen { get; set; }
        /** EPPS EFT Status for this payment */
        @AuraEnabled public String eppsEftStatus { get; set; }
        /** EPPS EFT Transaction Id for this payment */
        @AuraEnabled public String eppsEftTransactionId { get; set; }
        /** EPPS NSF Return Code for this payment */
        @AuraEnabled public String eppsNsfReturnCode { get; set; }
        /** EPPS Returned Date for this payment */
        @AuraEnabled public DateTime eppsReturnedDate { get; set; }
        /** EPPS Settlement Date for this payment */
        @AuraEnabled public DateTime eppsSettlementDate { get; set; }
        /** EPPS Status Date for this payment */
        @AuraEnabled public DateTime eppsStatusDate { get; set; }
        /** Status of the Setup Fee from Payment_Fee__c.Status_Code__c */
        @AuraEnabled public String setupFeeStatus { get; set; }
        /** Status of the Program Fee from Payment_Fee__c.Status_Code__c */
        @AuraEnabled public String programFeeStatus { get; set; }
        /** Status of the Banking Fee from Payment_Fee__c.Status_Code__c */
        @AuraEnabled public String bankingFeeStatus { get; set; }

        /**
         * @description Default constructor initializing change tracking flags to false
         */
        public ScheduleItemWrapper() {
            this.isModified = false;
            this.isFrozen = false;
            this.isNew = false;
            this.isDeleted = false;
        }
    }

    /**
     * @description Wrapper class for Wire Fee records.
     *
     * Wire fees are stored in Payment_Fee__c with Type__c = 'Wire Fee' or 'Wire Received Fee'.
     * They are linked to specific schedule items.
     */
    public class WireFeeWrapper {
        /** Salesforce record ID */
        @AuraEnabled public String id { get; set; }
        /** Parent Payment_Schedule_Item__c ID */
        @AuraEnabled public String scheduleItemId { get; set; }
        /** Fee type: 'Wire Fee' or 'Wire Received Fee' */
        @AuraEnabled public String feeType { get; set; }
        /** Wire fee amount (optional) */
        @AuraEnabled public Decimal amount { get; set; }

        /**
         * @description Default constructor
         */
        public WireFeeWrapper() {}
    }

    /**
     * @description Wrapper class for plan modification preview results.
     * Contains calculated summary metrics and the projected schedule items.
     * Used by previewPlanModification to return a live preview without DML.
     */
    public class PlanModificationPreview {
        @AuraEnabled public Integer numberOfPayments { get; set; }
        @AuraEnabled public Decimal totalProgramCost { get; set; }
        @AuraEnabled public Decimal weeklyPayment { get; set; }
        @AuraEnabled public Decimal totalProgramFee { get; set; }
        @AuraEnabled public Decimal estimatedTotalDebt { get; set; }
        @AuraEnabled public Decimal settlementAmount { get; set; }
        @AuraEnabled public Decimal programFeeAmount { get; set; }
        @AuraEnabled public Decimal totalSavings { get; set; }
        @AuraEnabled public Decimal totalBankingFee { get; set; }
        @AuraEnabled public String paymentFrequency { get; set; }
        @AuraEnabled public Decimal targetPaymentPercent { get; set; }
        @AuraEnabled public List<ScheduleItemWrapper> scheduleItems { get; set; }

        public PlanModificationPreview() {
            this.scheduleItems = new List<ScheduleItemWrapper>();
        }
    }

    /**
     * @description Get picklist values for Payment_Schedule_Item__c.Status__c field
     * Returns dynamic picklist values from the org's schema
     * @return List of picklist option maps with label and value
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getStatusPicklistValues() {
        String methodName = 'getStatusPicklistValues';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);

        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldResult = Payment_Schedule_Item__c.Status__c.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Found ' + picklistEntries.size() + ' picklist entries');

        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                Map<String, String> option = new Map<String, String>();
                option.put('label', entry.getLabel());
                option.put('value', entry.getValue());
                options.add(option);
            }
        }

        System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Returning ' + options.size() + ' active status options');
        System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
        return options;
    }

    /**
     * @description Get picklist values for PaymentPlan__c.Status__c dynamically
     * This ensures the LWC always reflects the latest picklist values from the database
     * @return List of Maps with 'label' and 'value' keys
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPlanStatusPicklistValues() {
        String methodName = 'getPlanStatusPicklistValues';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);

        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldResult = PaymentPlan__c.Status__c.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldResult.getPicklistValues();

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Found ' + picklistEntries.size() + ' picklist entries');

        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                Map<String, String> option = new Map<String, String>();
                option.put('label', entry.getLabel());
                option.put('value', entry.getValue());
                options.add(option);
            }
        }

        System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Returning ' + options.size() + ' active plan status options');
        System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
        return options;
    }

    /**
     * @description Get the latest active Payment Plan for an Opportunity
     * @param opportunityId The Opportunity ID
     * @return PaymentPlanWrapper containing plan and schedule items
     */
    @AuraEnabled(cacheable=true)
    public static PaymentPlanWrapper getLatestPaymentPlan(Id opportunityId) {
        String methodName = 'getLatestPaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | opportunityId: ' + opportunityId);

        try {
            if (opportunityId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | opportunityId is null, returning null');
                return null;
            }

            List<PaymentPlan__c> plans = [
                SELECT Id, Name, Opportunity__c, Contract__c, Program_Type__c,
                       Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Total_Program_Cost__c, Weekly_Payment__c, Monthly_Payment__c,
                       Number_of_Payments__c, First_Payment_Date__c, Status__c,
                       Version_Number__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Calculation_Timestamp__c, Previous_Version__c, Source__c,
                       Version_Type__c, Version_Notes__c, Schedule_Item_Count__c,
                       Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c,
                       Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c,
                       Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c,
                       Cleared_Payment_Sum__c, Cleared_Setup_Fee_Sum__c, Cleared_Program_Fee_Sum__c,
                       Cleared_Banking_Fee_Sum__c, Cleared_Savings_Sum__c, Cleared_Escrow_Sum__c,
                       NSF_Draft_Amount_Sum__c, NSF_Setup_Fee_Sum__c, NSF_Program_Fee_Sum__c,
                       NSF_Banking_Fee_Sum__c, NSF_Savings_Sum__c,
                       CreatedBy.Name, LastModifiedBy.Name
                FROM PaymentPlan__c
                WHERE Opportunity__c = :opportunityId
                  AND Is_Active__c = true
                ORDER BY Version_Number__c DESC, CreatedDate DESC
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + plans.size() + ' active payment plan(s)');

            if (plans.isEmpty()) {
                System.debug(LoggingLevel.INFO, LOG_INFO + ' | ' + methodName + ' | No active payment plan found for Opportunity: ' + opportunityId);
                return null;
            }

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Returning plan: ' + plans[0].Id + ' (Version ' + plans[0].Version_Number__c + ')');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return buildPaymentPlanWrapper(plans[0], true);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error fetching payment plan: ' + e.getMessage());
        }
    }

    /**
     * @description Get all active Payment Plans for an Opportunity
     * Returns a single wrapper with all active plans displayed as rows (using PaymentPlan__c fields directly)
     * @param opportunityId The Opportunity ID
     * @return List of PaymentPlanWrapper containing consolidated plan data
     */
    @AuraEnabled(cacheable=true)
    public static List<PaymentPlanWrapper> getActivePaymentPlans(Id opportunityId) {
        String methodName = 'getActivePaymentPlans';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | opportunityId: ' + opportunityId);

        try {
            if (opportunityId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | opportunityId is null, returning empty list');
                return new List<PaymentPlanWrapper>();
            }

            // Get all active plans ordered by First Payment Date
            List<PaymentPlan__c> plans = [
                SELECT Id, Name, Opportunity__c, Contract__c, Program_Type__c,
                       Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Total_Program_Cost__c, Weekly_Payment__c, Monthly_Payment__c,
                       Number_of_Payments__c, First_Payment_Date__c, Status__c,
                       Version_Number__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Calculation_Timestamp__c, Previous_Version__c, Source__c,
                       Version_Type__c, Version_Notes__c, Schedule_Item_Count__c,
                       Program_Fee_Amount__c,
                       Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c,
                       Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c,
                       Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c,
                       Cleared_Payment_Sum__c, Cleared_Setup_Fee_Sum__c, Cleared_Program_Fee_Sum__c,
                       Cleared_Banking_Fee_Sum__c, Cleared_Savings_Sum__c, Cleared_Escrow_Sum__c,
                       NSF_Draft_Amount_Sum__c, NSF_Setup_Fee_Sum__c, NSF_Program_Fee_Sum__c,
                       NSF_Banking_Fee_Sum__c, NSF_Savings_Sum__c,
                       CreatedBy.Name, LastModifiedBy.Name
                FROM PaymentPlan__c
                WHERE Opportunity__c = :opportunityId
                  AND Is_Active__c = true
                ORDER BY First_Payment_Date__c ASC, Name ASC
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + plans.size() + ' active payment plan(s)');

            if (plans.isEmpty()) {
                System.debug(LoggingLevel.INFO, LOG_INFO + ' | ' + methodName + ' | No active payment plans found for Opportunity: ' + opportunityId);
                return new List<PaymentPlanWrapper>();
            }

            // Create a single consolidated wrapper using the first plan as the header
            PaymentPlanWrapper wrapper = new PaymentPlanWrapper();
            wrapper.paymentPlan = plans[0];
            wrapper.versionNumber = plans[0].Version_Number__c != null ? plans[0].Version_Number__c.intValue() : 1;
            wrapper.versionStatus = plans[0].Status__c;
            wrapper.isLatestVersion = true;

            // Build schedule items directly from PaymentPlan__c records
            Integer rowNum = 1;
            for (PaymentPlan__c plan : plans) {
                wrapper.scheduleItems.add(buildScheduleItemFromPlan(plan, rowNum++));
            }

            // Return as single-element list so LWC doesn't show plan selector
            List<PaymentPlanWrapper> wrappers = new List<PaymentPlanWrapper>();
            wrappers.add(wrapper);

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Returning ' + wrappers.size() + ' wrapper(s) with ' + wrapper.scheduleItems.size() + ' schedule items');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return wrappers;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error fetching active payment plans: ' + e.getMessage());
        }
    }

    /**
     * @description Build ScheduleItemWrapper directly from PaymentPlan__c record
     * Maps PaymentPlan__c fields to the schedule item display format
     */
    private static ScheduleItemWrapper buildScheduleItemFromPlan(PaymentPlan__c plan, Integer rowNum) {
        ScheduleItemWrapper wrapper = new ScheduleItemWrapper();
        wrapper.id = plan.Id;
        wrapper.rowNumber = rowNum;
        wrapper.draftNumber = plan.Name; // Draft # = Plan Name (PP-00052, etc.)
        wrapper.paymentDate = plan.First_Payment_Date__c; // Date
        wrapper.draftAmount = plan.Weekly_Payment__c != null ? plan.Weekly_Payment__c : 0; // Draft
        wrapper.retainerFee = 0; // Retainer = 0.00 (hardcoded)
        wrapper.setupFee = plan.Setup_Fee__c != null ? plan.Setup_Fee__c : 0; // Setup
        wrapper.programFee = plan.Program_Fee_Amount__c != null ? plan.Program_Fee_Amount__c : 0; // Program
        wrapper.bankingFee = plan.Banking_Fee__c != null ? plan.Banking_Fee__c : 0; // Banking
        wrapper.banking2Fee = plan.Bank2_Fee__c != null ? plan.Bank2_Fee__c : 0; // Banking2

        // No calculation - Savings_Balance__c only exists on Payment_Schedule_Item__c, not PaymentPlan__c
        wrapper.savingsBalance = 0;
        wrapper.toEscrowAmount = 0;
        // All active payment plans should show Status as 'Active'
        wrapper.status = 'Active';
        return wrapper;
    }

    /**
     * @description Get all versions of Payment Plans for an Opportunity
     * @param opportunityId The Opportunity ID
     * @return List of PaymentPlanWrapper for version history
     */
    @AuraEnabled
    public static List<PaymentPlanWrapper> getPaymentPlanVersions(Id opportunityId) {
        String methodName = 'getPaymentPlanVersions';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | opportunityId: ' + opportunityId);

        try {
            if (opportunityId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | opportunityId is null, returning empty list');
                return new List<PaymentPlanWrapper>();
            }

            List<PaymentPlan__c> plans = [
                SELECT Id, Name, Version_Number__c, Status__c, Is_Active__c,
                       CreatedDate, LastModifiedDate,
                       CreatedBy.Name, LastModifiedBy.Name
                FROM PaymentPlan__c
                WHERE Opportunity__c = :opportunityId
                ORDER BY Version_Number__c DESC
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + plans.size() + ' version(s)');

            List<PaymentPlanWrapper> wrappers = new List<PaymentPlanWrapper>();
            Decimal latestVersion = plans.isEmpty() ? 0 :
                (plans[0].Version_Number__c != null ? plans[0].Version_Number__c : 1);

            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Latest version number: ' + latestVersion);

            for (PaymentPlan__c plan : plans) {
                PaymentPlanWrapper wrapper = new PaymentPlanWrapper();
                wrapper.paymentPlan = plan;
                wrapper.versionNumber = plan.Version_Number__c != null ? plan.Version_Number__c.intValue() : 1;
                wrapper.versionStatus = plan.Status__c;
                wrapper.isLatestVersion = (plan.Version_Number__c == latestVersion);
                wrapper.createdByName = plan.CreatedBy?.Name;
                wrapper.lastModifiedByName = plan.LastModifiedBy?.Name;
                wrappers.add(wrapper);
                System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Version ' + wrapper.versionNumber + ' (' + wrapper.versionStatus + ') - IsLatest: ' + wrapper.isLatestVersion);
            }

            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS - Returning ' + wrappers.size() + ' version(s)');
            return wrappers;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error fetching payment plan versions: ' + e.getMessage());
        }
    }

    /**
     * @description Create a new manual version of the Payment Plan
     * Clones the current plan and its schedule items
     * @param currentPlanId The current Payment Plan ID to clone
     * @return PaymentPlanWrapper for the new version
     */
    @AuraEnabled
    public static PaymentPlanWrapper createManualVersion(Id currentPlanId) {
        return PaymentPlanLifecycleService.createManualVersion(currentPlanId);
    }

    /**
     * @description Get Payment Plan by ID with schedule items
     * @param planId The Payment Plan ID
     * @return PaymentPlanWrapper
     */
    @AuraEnabled
    public static PaymentPlanWrapper getPaymentPlanById(Id planId) {
        String methodName = 'getPaymentPlanById';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        try {
            if (planId == null) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            List<PaymentPlan__c> plans = [
                SELECT Id, Name, Opportunity__c, Contract__c, Program_Type__c,
                       Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Total_Program_Cost__c, Weekly_Payment__c, Monthly_Payment__c,
                       Number_of_Payments__c, First_Payment_Date__c, Status__c,
                       Version_Number__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Target_Payment_Percent__c, Calculation_Mode__c, Payment_Frequency__c,
                       Total_Savings__c, Total_Banking_Fee__c,
                       Calculation_Timestamp__c, Previous_Version__c, Source__c,
                       Version_Type__c, Version_Notes__c, Schedule_Item_Count__c,
                       Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c,
                       Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c,
                       Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c,
                       Cleared_Payment_Sum__c, Cleared_Setup_Fee_Sum__c, Cleared_Program_Fee_Sum__c,
                       Cleared_Banking_Fee_Sum__c, Cleared_Savings_Sum__c, Cleared_Escrow_Sum__c,
                       NSF_Draft_Amount_Sum__c, NSF_Setup_Fee_Sum__c, NSF_Program_Fee_Sum__c,
                       NSF_Banking_Fee_Sum__c, NSF_Savings_Sum__c,
                       CreatedBy.Name, LastModifiedBy.Name,
                       Opportunity__r.Estimated_Current_Payment__c,
                       Opportunity__r.Estimated_Total_Debt__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + plans.size() + ' plan(s)');

            if (plans.isEmpty()) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Payment Plan not found: ' + planId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Plan: ' + plans[0].Name + ' | Version: ' + plans[0].Version_Number__c + ' | Status: ' + plans[0].Status__c);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return buildPaymentPlanWrapper(plans[0], true);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error fetching payment plan: ' + e.getMessage());
        }
    }

    /**
     * @description Get schedule items from the previous version of a Payment Plan
     * Used to compare and detect modified items (show star indicator)
     * @param planId The current Payment Plan ID
     * @return List of ScheduleItemWrapper from previous version, empty list if no previous version
     */
    @AuraEnabled(cacheable=true)
    public static List<ScheduleItemWrapper> getPreviousVersionItems(Id planId) {
        String methodName = 'getPreviousVersionItems';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        try {
            if (planId == null) {
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | planId is null, returning empty list');
                return new List<ScheduleItemWrapper>();
            }

            // Get current plan's Opportunity and Version Number
            List<PaymentPlan__c> currentPlans = [
                SELECT Id, Opportunity__c, Version_Number__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentPlans.size() + ' current plan(s)');

            if (currentPlans.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Current plan not found, returning empty list');
                return new List<ScheduleItemWrapper>();
            }

            PaymentPlan__c currentPlan = currentPlans[0];
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Current Version: ' + currentPlan.Version_Number__c);

            // If this is version 1, there's no previous version
            if (currentPlan.Version_Number__c == null || currentPlan.Version_Number__c <= 1) {
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Version 1 or null - no previous version exists');
                return new List<ScheduleItemWrapper>();
            }

            // Find the previous version (Version_Number__c - 1) for the same Opportunity
            Decimal previousVersionNumber = currentPlan.Version_Number__c - 1;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Looking for previous version: ' + previousVersionNumber);

            List<PaymentPlan__c> previousPlans = [
                SELECT Id, Name, Version_Number__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :currentPlan.Opportunity__c
                  AND Version_Number__c = :previousVersionNumber
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + previousPlans.size() + ' previous plan(s)');

            if (previousPlans.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Previous version not found, returning empty list');
                return new List<ScheduleItemWrapper>();
            }

            Id previousPlanId = previousPlans[0].Id;
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Previous plan: ' + previousPlans[0].Name + ' (Id: ' + previousPlanId + ')');

            // Get schedule items from previous version
            String fields = getScheduleItemQueryFields();
            String query = 'SELECT ' + fields +
                ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :previousPlanId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
            List<Payment_Schedule_Item__c> previousItems = Database.query(query);

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + previousItems.size() + ' schedule items from previous version');

            // Query Payment_Fee__c records for all schedule items
            Set<Id> scheduleItemIds = new Set<Id>();
            for (Payment_Schedule_Item__c item : previousItems) {
                scheduleItemIds.add(item.Id);
            }
            Map<Id, Map<String, Payment_Fee__c>> feeRecordsMap =
                PaymentFeeService.getFeesByScheduleItemIds(scheduleItemIds);

            // Build wrapper list
            List<ScheduleItemWrapper> result = new List<ScheduleItemWrapper>();
            for (Integer i = 0; i < previousItems.size(); i++) {
                result.add(buildScheduleItemWrapper(previousItems[i], i + 1, feeRecordsMap));
            }

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Returning ' + result.size() + ' items');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return result;

        } catch (Exception e) {
            // Return empty list on error - don't break the main functionality
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Returning empty list due to error (graceful degradation)');
            return new List<ScheduleItemWrapper>();
        }
    }

    /**
     * @description Get all Wire Fees for a Payment Plan's schedule items
     * @param planId The Payment Plan ID
     * @return Map of Schedule Item ID to List of WireFeeWrapper
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<WireFeeWrapper>> getWireFeesByPlanId(Id planId) {
        String methodName = 'getWireFeesByPlanId';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        try {
            if (planId == null) {
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | planId is null, returning empty map');
                return new Map<String, List<WireFeeWrapper>>();
            }

            // Get all Schedule Item IDs for this plan
            List<Payment_Schedule_Item__c> scheduleItems = [
                SELECT Id
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :planId
                LIMIT :MAX_QUERY_LIMIT
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + scheduleItems.size() + ' schedule items');

            if (scheduleItems.isEmpty()) {
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | No schedule items found, returning empty map');
                return new Map<String, List<WireFeeWrapper>>();
            }

            Set<Id> scheduleItemIds = new Set<Id>();
            for (Payment_Schedule_Item__c item : scheduleItems) {
                scheduleItemIds.add(item.Id);
            }

            // Query all Wire Fee records for these Schedule Items using PaymentFeeService
            Map<Id, List<Payment_Fee__c>> wireFeeMap = PaymentFeeService.getWireFeesByScheduleItemIds(scheduleItemIds);

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found wire fees for ' + wireFeeMap.size() + ' schedule item(s)');

            // Build the map with String keys for LWC compatibility
            Map<String, List<WireFeeWrapper>> resultMap = new Map<String, List<WireFeeWrapper>>();

            for (Id psiId : wireFeeMap.keySet()) {
                String scheduleItemId = String.valueOf(psiId);
                List<WireFeeWrapper> wrappers = new List<WireFeeWrapper>();

                for (Payment_Fee__c fee : wireFeeMap.get(psiId)) {
                    WireFeeWrapper wrapper = new WireFeeWrapper();
                    wrapper.id = fee.Id;
                    wrapper.scheduleItemId = scheduleItemId;
                    wrapper.feeType = fee.Type__c;
                    wrapper.amount = fee.Amount__c;
                    wrappers.add(wrapper);
                }

                if (!wrappers.isEmpty()) {
                    resultMap.put(scheduleItemId, wrappers);
                }
            }

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Built map with ' + resultMap.size() + ' schedule item(s) having wire fees');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return resultMap;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error fetching wire fees: ' + e.getMessage());
        }
    }

    /**
     * @description Save a wire fee record for a schedule item
     * @param scheduleItemId The Payment Schedule Item ID
     * @param feeType The wire fee type ('Wire Fee' or 'Wire Received Fee')
     * @param amount The optional amount
     * @return The created Payment_Fee__c record ID
     */
    @AuraEnabled
    public static String saveWireFee(String scheduleItemId, String feeType, Decimal amount) {
        String methodName = 'saveWireFee';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | scheduleItemId: ' + scheduleItemId + ' | feeType: ' + feeType + ' | amount: ' + amount);

        try {
            if (String.isBlank(scheduleItemId)) {
                throw new AuraHandledException('Schedule Item ID is required');
            }

            Id feeId = PaymentFeeService.createWireFeeRecord(Id.valueOf(scheduleItemId), feeType, amount);

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Created wire fee: ' + feeId);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return String.valueOf(feeId);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error saving wire fee: ' + e.getMessage());
        }
    }

    /**
     * @description Delete a wire fee record
     * @param feeId The Payment_Fee__c record ID to delete
     */
    @AuraEnabled
    public static void deleteWireFee(String feeId) {
        String methodName = 'deleteWireFee';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | feeId: ' + feeId);

        try {
            if (String.isBlank(feeId)) {
                throw new AuraHandledException('Fee ID is required');
            }

            PaymentFeeService.deleteWireFeeById(Id.valueOf(feeId));

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Deleted wire fee: ' + feeId);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error deleting wire fee: ' + e.getMessage());
        }
    }

    /**
     * @description Update a wire fee record's amount
     * @param feeId The Payment_Fee__c record ID to update
     * @param amount The new amount
     */
    @AuraEnabled
    public static void updateWireFee(String feeId, Decimal amount) {
        String methodName = 'updateWireFee';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | feeId: ' + feeId + ' | amount: ' + amount);

        try {
            if (String.isBlank(feeId)) {
                throw new AuraHandledException('Fee ID is required');
            }

            Payment_Fee__c fee = [SELECT Id, Amount__c FROM Payment_Fee__c WHERE Id = :feeId LIMIT 1];
            fee.Amount__c = amount;
            update fee;

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Updated wire fee: ' + feeId + ' with amount: ' + amount);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error updating wire fee: ' + e.getMessage());
        }
    }

    /**
     * @description Update a boolean flag on a Payment Schedule Item.
     * Supports Void_Requested__c and Immediate_Processing_Requested__c fields.
     * @param scheduleItemId The Payment Schedule Item ID
     * @param fieldName The API name of the checkbox field to update
     * @param value The boolean value to set
     */
    @AuraEnabled
    public static void updateScheduleItemFlag(String scheduleItemId, String fieldName, Boolean value) {
        String methodName = 'updateScheduleItemFlag';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | scheduleItemId: ' + scheduleItemId + ' | fieldName: ' + fieldName + ' | value: ' + value);

        try {
            if (String.isBlank(scheduleItemId)) {
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Schedule Item ID is required.');
            }

            // Whitelist allowed fields for security
            Set<String> allowedFields = new Set<String>{
                'Void_Requested__c',
                'Immediate_Processing_Requested__c'
            };

            if (!allowedFields.contains(fieldName)) {
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Invalid field name: ' + fieldName);
            }

            Payment_Schedule_Item__c item = new Payment_Schedule_Item__c(Id = scheduleItemId);
            item.put(fieldName, value);
            update item;

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Updated ' + fieldName + ' to ' + value + ' on ' + scheduleItemId);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');

        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error updating schedule item flag: ' + e.getMessage());
        }
    }

    /**
     * @description Save changes to schedule items (updates, inserts, deletes)
     * @param planId The Payment Plan ID
     * @param items List of ScheduleItemWrapper objects from LWC
     * @return Updated PaymentPlanWrapper
     */
    @AuraEnabled
    public static PaymentPlanWrapper saveScheduleItems(Id planId, List<ScheduleItemWrapper> items) {
        String methodName = 'saveScheduleItems';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId + ' | items count: ' + (items != null ? items.size() : 0));

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null || items == null || items.isEmpty()) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Invalid parameters - planId: ' + planId + ', items: ' + (items != null ? String.valueOf(items.size()) : 'null'));
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID and items are required.');
            }

            List<Payment_Schedule_Item__c> toUpdate = new List<Payment_Schedule_Item__c>();
            List<Payment_Schedule_Item__c> toInsert = new List<Payment_Schedule_Item__c>();
            List<Id> toDelete = new List<Id>();

            // Track wrappers for fee record creation
            List<ScheduleItemWrapper> insertWrappers = new List<ScheduleItemWrapper>();
            Map<Id, ScheduleItemWrapper> updateWrapperMap = new Map<Id, ScheduleItemWrapper>();

            for (ScheduleItemWrapper item : items) {
                if (item.isDeleted && String.isNotBlank(item.id)) {
                    toDelete.add(item.id);
                } else if (item.isNew && String.isBlank(item.id)) {
                    Payment_Schedule_Item__c newItem = new Payment_Schedule_Item__c();
                    newItem.Payment_Plan__c = planId;
                    mapWrapperToRecord(item, newItem);
                    toInsert.add(newItem);
                    insertWrappers.add(item);
                } else if (item.isModified && String.isNotBlank(item.id)) {
                    Payment_Schedule_Item__c updateItem = new Payment_Schedule_Item__c(Id = item.id);
                    mapWrapperToRecord(item, updateItem);
                    toUpdate.add(updateItem);
                    updateWrapperMap.put(item.id, item);
                }
            }

            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | DML Summary - Delete: ' + toDelete.size() + ', Update: ' + toUpdate.size() + ', Insert: ' + toInsert.size());

            // Perform DML in order: delete, update, insert
            // Note: Payment_Fee__c cascade deletes automatically via master-detail
            if (!toDelete.isEmpty()) {
                delete [SELECT Id FROM Payment_Schedule_Item__c WHERE Id IN :toDelete];
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Deleted ' + toDelete.size() + ' item(s)');
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Updated ' + toUpdate.size() + ' item(s)');

                // Update Payment_Fee__c records for modified items
                PaymentFeeService.bulkUpsertFeeRecords(updateWrapperMap.keySet(), updateWrapperMap);
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Upserted fee records for ' + updateWrapperMap.size() + ' updated item(s)');
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + toInsert.size() + ' item(s)');

                // Create Payment_Fee__c records for inserted items
                Map<Id, ScheduleItemWrapper> insertWrapperMap = new Map<Id, ScheduleItemWrapper>();
                for (Integer i = 0; i < toInsert.size(); i++) {
                    insertWrapperMap.put(toInsert[i].Id, insertWrappers[i]);
                }
                List<Payment_Fee__c> feeRecords = PaymentFeeService.createFeeRecordsForItems(toInsert, insertWrapperMap);
                if (!feeRecords.isEmpty()) {
                    insert feeRecords;
                    System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + feeRecords.size() + ' fee record(s)');
                }
            }

            // Update plan timestamp (item count now comes from Schedule_Item_Count_Rollup__c rollup field)
            PaymentPlan__c plan = new PaymentPlan__c(Id = planId);
            plan.Calculation_Timestamp__c = DateTime.now();
            update plan;

            // Get the updated item count from rollup field
            PaymentPlan__c updatedPlan = [SELECT Schedule_Item_Count_Rollup__c FROM PaymentPlan__c WHERE Id = :planId LIMIT 1];
            Integer itemCount = updatedPlan.Schedule_Item_Count_Rollup__c != null ? updatedPlan.Schedule_Item_Count_Rollup__c.intValue() : 0;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Updated plan, rollup item count: ' + itemCount);

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Schedule items saved successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return getPaymentPlanById(planId);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Rolling back transaction');
            throw new AuraHandledException(ERROR_SYMBOL + 'Error saving schedule items: ' + e.getMessage());
        }
    }

    /**
     * @description Add a new blank payment row
     * @param planId The Payment Plan ID
     * @param afterRowNumber Insert after this row number
     * @return The new ScheduleItemWrapper
     */
    @AuraEnabled
    public static ScheduleItemWrapper addPaymentRow(Id planId, Integer afterRowNumber) {
        String methodName = 'addPaymentRow';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId + ' | afterRowNumber: ' + afterRowNumber);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get the last payment to calculate next date and number
            List<Payment_Schedule_Item__c> lastItems = [
                SELECT Payment_Date__c, Payment_Number__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :planId
                ORDER BY Payment_Number__c DESC
                LIMIT 1
            ];

            // Get default banking fees from plan
            List<PaymentPlan__c> plans = [
                SELECT Banking_Fee__c, Bank2_Fee__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

            if (plans.isEmpty()) {
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c plan = plans[0];

            Date nextDate = Date.today().addDays(PAYMENT_INTERVAL_DAYS);
            Decimal nextNumber = 1;

            if (!lastItems.isEmpty()) {
                if (lastItems[0].Payment_Date__c != null) {
                    nextDate = lastItems[0].Payment_Date__c.addDays(PAYMENT_INTERVAL_DAYS);
                }
                nextNumber = lastItems[0].Payment_Number__c != null ?
                    lastItems[0].Payment_Number__c + 1 : (afterRowNumber != null ? afterRowNumber + 1 : 1);
            }

            Decimal defaultBankingFee = plan.Banking_Fee__c != null ? plan.Banking_Fee__c : DEFAULT_BANKING_FEE;
            Decimal defaultBank2Fee = plan.Bank2_Fee__c != null ? plan.Bank2_Fee__c : 0;

            // Calculate the correct Draft_Number__c by counting existing non-NSF/Cancelled items
            // Draft numbers skip NSF and Cancelled statuses to match LWC display logic
            Integer existingDraftCount = [
                SELECT COUNT()
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :planId
                AND Status__c NOT IN (:STATUS_NSF, :STATUS_CANCELLED)
            ];
            String nextDraftNumber = String.valueOf(existingDraftCount + 1);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Existing draft count: ' + existingDraftCount + ', new draft number: ' + nextDraftNumber);

            // Create new item
            Payment_Schedule_Item__c newItem = new Payment_Schedule_Item__c();
            newItem.Payment_Plan__c = planId;
            newItem.Payment_Number__c = nextNumber;
            newItem.Draft_Number__c = nextDraftNumber;
            newItem.Payment_Date__c = nextDate;
            newItem.Total_Payment__c = 0;
            newItem.Retainer_Fee_Amount__c = DEFAULT_RETAINER_FEE;
            newItem.Setup_Fee_Amount__c = 0;
            newItem.Program_Fee_Amount__c = 0;
            newItem.Banking_Fee_Amount__c = defaultBankingFee;
            newItem.Bank2_Fee_Amount__c = defaultBank2Fee;
            newItem.Status__c = STATUS_SCHEDULED;
            insert newItem;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted new item: ' + newItem.Id + ' | Row: ' + nextNumber + ' | Date: ' + nextDate);

            // Build wrapper
            ScheduleItemWrapper wrapper = new ScheduleItemWrapper();
            wrapper.id = newItem.Id;
            wrapper.rowNumber = nextNumber.intValue();
            wrapper.draftNumber = newItem.Draft_Number__c;
            wrapper.paymentDate = newItem.Payment_Date__c;
            wrapper.draftAmount = newItem.Total_Payment__c;
            wrapper.retainerFee = newItem.Retainer_Fee_Amount__c;
            wrapper.setupFee = newItem.Setup_Fee_Amount__c;
            wrapper.programFee = newItem.Program_Fee_Amount__c;
            wrapper.bankingFee = newItem.Banking_Fee_Amount__c;
            wrapper.banking2Fee = newItem.Bank2_Fee_Amount__c;
            wrapper.savingsBalance = 0;
            wrapper.toEscrowAmount = 0;
            wrapper.status = newItem.Status__c;
            wrapper.isNew = true;

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Payment row added successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return wrapper;

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Rolling back transaction');
            throw new AuraHandledException(ERROR_SYMBOL + 'Error adding payment row: ' + e.getMessage());
        }
    }

    /**
     * @description Delete multiple payment rows
     * @param itemIds List of Payment_Schedule_Item__c IDs to delete
     */
    @AuraEnabled
    public static void deletePaymentRows(List<Id> itemIds) {
        String methodName = 'deletePaymentRows';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | itemIds count: ' + (itemIds != null ? itemIds.size() : 0));

        Savepoint sp = Database.setSavepoint();
        try {
            if (itemIds == null || itemIds.isEmpty()) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | No items provided for deletion');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'No items selected for deletion.');
            }

            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Items to delete: ' + itemIds);

            List<Payment_Schedule_Item__c> itemsToDelete = [
                SELECT Id
                FROM Payment_Schedule_Item__c
                WHERE Id IN :itemIds
                LIMIT :MAX_QUERY_LIMIT
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + itemsToDelete.size() + ' item(s) to delete');

            if (itemsToDelete.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | No items found for deletion - may already be deleted');
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment rows not found. They may have been deleted.');
            }

            delete itemsToDelete;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Deleted ' + itemsToDelete.size() + ' item(s)');
            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Payment rows deleted successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Rolling back transaction');
            throw new AuraHandledException(ERROR_SYMBOL + 'Error deleting payment rows: ' + e.getMessage());
        }
    }

    /**
     * @description Recalculate payment plan by fetching Opportunity data and creating a new version
     * Creates a new PaymentPlan__c with incremented version number and calculates all fee breakdowns
     * @param planId The current Payment Plan ID to base calculations on
     * @return PaymentPlanWrapper for the new version
     */
    @AuraEnabled
    public static PaymentPlanWrapper recalculatePaymentPlan(Id planId) {
        return PaymentPlanCalculationService.recalculatePaymentPlan(planId);
    }

    /**
     * @description Recalculate remaining balance by redistributing unpaid debt evenly across future scheduled payments.
     * Algorithm:
     * 1. Total Program Cost = Estimated_Total_Debt__c × 0.95 (Settlement 60% + Program Fee 35%)
     * 2. Paid To Date = SUM(Cleared payments' Total_Payment__c) + SUM(Wire Fees Amount__c)
     * 3. Remaining Balance = Total Program Cost - Paid To Date
     * 4. If Remaining Balance <= 0 → Error: "Debt is already paid off"
     * 5. Remaining Count = Number_of_Weeks__c - COUNT(non-Scheduled items)
     * 6. Base Payment = FLOOR(Remaining Balance / Remaining Count, 2 decimals)
     * 7. Remainder = Remaining Balance - (Base Payment × Remaining Count)
     * 8. Last payment = Base Payment + Remainder (cents adjustment)
     * @param planId The current Payment Plan ID
     * @return PaymentPlanWrapper for the new version
     */
    @AuraEnabled
    public static PaymentPlanWrapper recalculateRemainingBalance(Id planId) {
        return PaymentPlanCalculationService.recalculateRemainingBalance(planId);
    }

    /**
     * @description Suspend a payment plan
     * Creates a new version with Scheduled items changed to Cancelled,
     * activates the new version, and archives the previous plan
     * @param planId The Payment Plan ID
     * @return PaymentPlanWrapper for the new suspended version
     */
    @AuraEnabled
    public static PaymentPlanWrapper suspendPaymentPlan(Id planId) {
        return PaymentPlanLifecycleService.suspendPaymentPlan(planId);
    }

    /**
     * @description Activate a draft payment plan
     * Archives all previous versions and sets the selected plan as Active
     * @param planId The Payment Plan ID
     * @return Updated PaymentPlanWrapper
     */
    @AuraEnabled
    public static PaymentPlanWrapper activatePaymentPlan(Id planId) {
        return PaymentPlanLifecycleService.activatePaymentPlan(planId);
    }

    /**
     * @description Deactivate an active payment plan
     * Sets the plan back to Draft status without creating a new version
     * @param planId The Payment Plan ID
     * @return Updated PaymentPlanWrapper
     */
    @AuraEnabled
    public static PaymentPlanWrapper deactivatePaymentPlan(Id planId) {
        return PaymentPlanLifecycleService.deactivatePaymentPlan(planId);
    }

    /**
     * @description Reactivate a suspended payment plan
     * Sets the plan back to Active and restores future Cancelled items to Scheduled.
     * @param suspendedPlanId The suspended Payment Plan ID
     * @return Updated PaymentPlanWrapper
     */
    @AuraEnabled
    public static PaymentPlanWrapper reactivatePaymentPlan(Id suspendedPlanId) {
        return PaymentPlanLifecycleService.reactivatePaymentPlan(suspendedPlanId);
    }

    /**
     * @description Save pending items as a new version
     * Creates a new PaymentPlan__c and all Payment_Schedule_Item__c records
     * Archives the old plan and sets new plan as active
     * @param currentPlanId The current Payment Plan ID to clone from
     * @param items List of ScheduleItemWrapper objects from LWC
     * @return PaymentPlanWrapper for the new version
     */
    @AuraEnabled
    public static PaymentPlanWrapper saveAsNewVersion(Id currentPlanId, List<ScheduleItemWrapper> items) {
        String methodName = 'saveAsNewVersion';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | currentPlanId: ' + currentPlanId + ' | items count: ' + (items != null ? items.size() : 0));

        Savepoint sp = Database.setSavepoint();
        try {
            if (currentPlanId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | currentPlanId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }
            if (items == null || items.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | items is null or empty');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Items are required.');
            }

            // Get current plan
            List<PaymentPlan__c> currentPlans = [
                SELECT Id, Name, Opportunity__c, Contract__c, Program_Type__c,
                       Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Total_Program_Cost__c, Weekly_Payment__c, Monthly_Payment__c,
                       Number_of_Payments__c, First_Payment_Date__c, Status__c,
                       Version_Number__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Schedule_Item_Count__c
                FROM PaymentPlan__c
                WHERE Id = :currentPlanId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentPlans.size() + ' current plan(s)');

            if (currentPlans.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Payment Plan not found: ' + currentPlanId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c currentPlan = currentPlans[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Current plan: ' + currentPlan.Name + ' | Version: ' + currentPlan.Version_Number__c);

            // Query Opportunity to get latest Program Type, No Fee Program, and Number of Weeks
            Opportunity opp = null;
            if (currentPlan.Opportunity__c != null) {
                List<Opportunity> opportunities = [
                    SELECT Id, Program_Type__c, No_Fee_Program__c, Number_of_Weeks__c
                    FROM Opportunity
                    WHERE Id = :currentPlan.Opportunity__c
                    LIMIT 1
                ];
                if (!opportunities.isEmpty()) {
                    opp = opportunities[0];
                    System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Fetched Opportunity: ' + opp.Id + ' | Program Type: ' + opp.Program_Type__c + ' | No Fee: ' + opp.No_Fee_Program__c + ' | Weeks: ' + opp.Number_of_Weeks__c);
                }
            }

            // Calculate new version number
            Decimal newVersionNumber = currentPlan.Version_Number__c != null ?
                currentPlan.Version_Number__c + 1 : 2;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Creating new version: ' + newVersionNumber);

            // Keep current plan as-is, just update version status (no longer using Status__c for PaymentPlan)
            // Don't change the current plan - just create the new version as Draft

            // Clone the plan as new version (save as Draft - user must activate manually)
            PaymentPlan__c newPlan = currentPlan.clone(false, true, false, false);
            newPlan.Version_Number__c = newVersionNumber;
            newPlan.Status__c = VERSION_STATUS_DRAFT;
            newPlan.Is_Active__c = false;
            newPlan.Previous_Version__c = currentPlan.Id;
            newPlan.Version_Type__c = VERSION_TYPE_REVISION;
            newPlan.Source__c = SOURCE_UI;
            newPlan.Version_Notes__c = 'Manual version created on ' + DateTime.now().format();
            newPlan.Calculation_Timestamp__c = DateTime.now();
            newPlan.Schedule_Item_Count__c = items.size();

            // Update Program Type, No Fee Program, and Number of Payments from Opportunity
            if (opp != null) {
                newPlan.Program_Type__c = opp.Program_Type__c;
                newPlan.No_Fee_Program__c = opp.No_Fee_Program__c;
                newPlan.Number_of_Payments__c = opp.Number_of_Weeks__c;
            }

            insert newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted new plan: ' + newPlan.Id);

            // Validate all items before processing
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Validating ' + items.size() + ' items...');
            Integer rowIndex = 1;
            for (ScheduleItemWrapper item : items) {
                if (!item.isDeleted) {
                    validateScheduleItemWrapper(item, rowIndex);
                }
                rowIndex++;
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Validation passed');

            // Query ALL fields from old schedule items using dynamic describe (gets all 48+ fields)
            String fields = getScheduleItemQueryFields();
            String query = 'SELECT ' + fields +
                ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :currentPlanId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
            List<Payment_Schedule_Item__c> oldItems = Database.query(query);
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + oldItems.size() + ' old schedule items');

            // Build map: Payment_Number__c -> old Payment_Schedule_Item__c
            Map<Decimal, Payment_Schedule_Item__c> paymentNumToOldItem = new Map<Decimal, Payment_Schedule_Item__c>();
            Set<Id> oldItemIds = new Set<Id>();
            for (Payment_Schedule_Item__c oldItem : oldItems) {
                if (oldItem.Payment_Number__c != null) {
                    paymentNumToOldItem.put(oldItem.Payment_Number__c, oldItem);
                }
                oldItemIds.add(oldItem.Id);
            }

            // Query ALL fees from old schedule items (all types: standard + wire + any other)
            Map<Id, List<Payment_Fee__c>> oldFeeMap = PaymentFeeService.getAllFeesByScheduleItemIds(oldItemIds);

            // Create all schedule items for the new plan using clone
            List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();
            List<ScheduleItemWrapper> itemWrappers = new List<ScheduleItemWrapper>();
            // Track which new items are truly new (no old item match) for fresh fee creation
            List<Boolean> isNewItemList = new List<Boolean>();

            // Count items by status for logging
            Integer newCount = 0, modifiedCount = 0, deletedCount = 0, frozenCount = 0;
            for (ScheduleItemWrapper item : items) {
                if (item.isDeleted) deletedCount++;
                else if (item.isFrozen) frozenCount++;
                else if (item.isNew) newCount++;
                else if (item.isModified) modifiedCount++;
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Item changes - New: ' + newCount + ' | Modified: ' + modifiedCount + ' | Deleted: ' + deletedCount + ' | Frozen: ' + frozenCount);

            for (ScheduleItemWrapper item : items) {
                if (item.isDeleted) continue; // Skip deleted items

                Payment_Schedule_Item__c oldItem = paymentNumToOldItem.get(Decimal.valueOf(item.rowNumber));
                Payment_Schedule_Item__c newItem;

                if (oldItem != null) {
                    // Clone the old record to preserve ALL fields (48+ fields)
                    newItem = oldItem.clone(false, true, false, false);
                    newItem.Payment_Plan__c = newPlan.Id;
                    newItem.Payment_Number__c = item.rowNumber;

                    // For frozen items (non-Scheduled), clone exactly as-is
                    // For editable items, apply user edits on top of the clone
                    if (!item.isFrozen) {
                        newItem.Payment_Date__c = item.paymentDate;
                        newItem.Total_Payment__c = item.draftAmount != null ? item.draftAmount : 0;
                        newItem.Retainer_Fee_Amount__c = item.retainerFee != null ? item.retainerFee : 0;
                        newItem.Setup_Fee_Amount__c = item.setupFee != null ? item.setupFee : 0;
                        newItem.Program_Fee_Amount__c = item.programFee != null ? item.programFee : 0;
                        newItem.Banking_Fee_Amount__c = item.bankingFee != null ? item.bankingFee : 0;
                        newItem.Bank2_Fee_Amount__c = item.banking2Fee != null ? item.banking2Fee : 0;
                        newItem.Status__c = validateStatus(item.status);
                        newItem.Savings_Balance__c = item.savingsBalance != null ? item.savingsBalance : 0;
                        newItem.To_Escrow_Amount__c = item.toEscrowAmount != null ? item.toEscrowAmount : 0;
                        newItem.Draft_Number__c = item.draftNumber;
                    }

                    isNewItemList.add(false);
                } else {
                    // Truly new row added during edit - create fresh record
                    newItem = new Payment_Schedule_Item__c();
                    newItem.Payment_Plan__c = newPlan.Id;
                    newItem.Payment_Number__c = item.rowNumber;
                    newItem.Draft_Number__c = item.draftNumber;
                    newItem.Payment_Date__c = item.paymentDate;
                    newItem.Total_Payment__c = item.draftAmount != null ? item.draftAmount : 0;
                    newItem.Retainer_Fee_Amount__c = item.retainerFee != null ? item.retainerFee : 0;
                    newItem.Setup_Fee_Amount__c = item.setupFee != null ? item.setupFee : 0;
                    newItem.Program_Fee_Amount__c = item.programFee != null ? item.programFee : 0;
                    newItem.Banking_Fee_Amount__c = item.bankingFee != null ? item.bankingFee : 0;
                    newItem.Bank2_Fee_Amount__c = item.banking2Fee != null ? item.banking2Fee : 0;
                    newItem.Status__c = validateStatus(item.status);
                    newItem.Savings_Balance__c = item.savingsBalance != null ? item.savingsBalance : 0;
                    newItem.To_Escrow_Amount__c = item.toEscrowAmount != null ? item.toEscrowAmount : 0;
                    newItem.EPPS_EFT_Status__c = item.eppsEftStatus;
                    newItem.EPPS_EFT_Transaction_Id__c = item.eppsEftTransactionId;
                    newItem.EPPS_NSF_Return_Code__c = item.eppsNsfReturnCode;
                    newItem.EPPS_Returned_Date__c = item.eppsReturnedDate;
                    newItem.EPPS_Settlement_Date__c = item.eppsSettlementDate;
                    newItem.EPPS_Status_Date__c = item.eppsStatusDate;

                    isNewItemList.add(true);
                }

                newItems.add(newItem);
                itemWrappers.add(item);
            }

            if (!newItems.isEmpty()) {
                // Recalculate Draft_Number__c to skip NSF/Cancelled items
                PaymentPlanCalculationService.recalculateDraftNumbers(newItems);
                insert newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newItems.size() + ' schedule items');

                // Clone ALL fees from old items and re-parent to new items;
                // For truly new rows, create fresh fee records
                List<Payment_Fee__c> allNewFees = new List<Payment_Fee__c>();
                List<Payment_Schedule_Item__c> trulyNewItems = new List<Payment_Schedule_Item__c>();
                List<ScheduleItemWrapper> trulyNewWrappers = new List<ScheduleItemWrapper>();

                for (Integer i = 0; i < newItems.size(); i++) {
                    ScheduleItemWrapper wrapper = itemWrappers[i];
                    Boolean isTrulyNew = isNewItemList[i];

                    if (!isTrulyNew) {
                        // Find old item to get its fees
                        Payment_Schedule_Item__c matchedOldItem = paymentNumToOldItem.get(Decimal.valueOf(wrapper.rowNumber));
                        if (matchedOldItem != null && oldFeeMap.containsKey(matchedOldItem.Id)) {
                            List<Payment_Fee__c> oldFees = oldFeeMap.get(matchedOldItem.Id);
                            for (Payment_Fee__c oldFee : oldFees) {
                                Payment_Fee__c clonedFee = oldFee.clone(false, true, false, false);
                                clonedFee.Payment_Schedule_Item__c = newItems[i].Id;

                                // For non-frozen items, update standard fee amounts if user changed them
                                if (!wrapper.isFrozen) {
                                    if (oldFee.Type__c == PaymentFeeService.FEE_TYPE_BANKING) {
                                        clonedFee.Amount__c = wrapper.bankingFee != null ? wrapper.bankingFee : 0;
                                    } else if (oldFee.Type__c == PaymentFeeService.FEE_TYPE_PROGRAM) {
                                        clonedFee.Amount__c = wrapper.programFee != null ? wrapper.programFee : 0;
                                    } else if (oldFee.Type__c == PaymentFeeService.FEE_TYPE_SETUP) {
                                        clonedFee.Amount__c = wrapper.setupFee != null ? wrapper.setupFee : 0;
                                    }
                                    // Wire fees and other types keep their original Amount__c
                                }

                                allNewFees.add(clonedFee);
                            }
                        }
                    } else {
                        // Truly new row - collect for fresh fee creation
                        trulyNewItems.add(newItems[i]);
                        trulyNewWrappers.add(wrapper);
                    }
                }

                // Create fresh fee records for truly new items
                if (!trulyNewItems.isEmpty()) {
                    Map<Id, ScheduleItemWrapper> newWrapperMap = new Map<Id, ScheduleItemWrapper>();
                    for (Integer i = 0; i < trulyNewItems.size(); i++) {
                        newWrapperMap.put(trulyNewItems[i].Id, trulyNewWrappers[i]);
                    }
                    allNewFees.addAll(PaymentFeeService.createFeeRecordsForItems(trulyNewItems, newWrapperMap));
                }

                if (!allNewFees.isEmpty()) {
                    insert allNewFees;
                    System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + allNewFees.size() + ' fee record(s) (cloned + new)');
                }
            }

            // Update plan item count
            newPlan.Schedule_Item_Count__c = newItems.size();
            update newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Updated plan item count: ' + newItems.size());

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | New version saved successfully: ' + newPlan.Id);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return getPaymentPlanById(newPlan.Id);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error saving new version: ' + e.getMessage());
        }
    }

    // ============ PRIVATE HELPER METHODS ============


    /**
     * @description Build PaymentPlanWrapper from PaymentPlan__c record
     */
    private static PaymentPlanWrapper buildPaymentPlanWrapper(PaymentPlan__c plan, Boolean includeItems) {
        String methodName = 'buildPaymentPlanWrapper';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + plan.Id + ' | includeItems: ' + includeItems);

        PaymentPlanWrapper wrapper = new PaymentPlanWrapper();
        wrapper.paymentPlan = plan;
        wrapper.versionNumber = plan.Version_Number__c != null ? plan.Version_Number__c.intValue() : 1;
        wrapper.versionStatus = plan.Status__c;
        wrapper.isLatestVersion = true;
        wrapper.createdByName = plan.CreatedBy?.Name;
        wrapper.lastModifiedByName = plan.LastModifiedBy?.Name;

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Building wrapper for version ' + wrapper.versionNumber + ' (' + wrapper.versionStatus + ')');

        if (includeItems) {
            Id planId = plan.Id;
            String fields = getScheduleItemQueryFields();
            String query = 'SELECT ' + fields +
                ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :planId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
            List<Payment_Schedule_Item__c> items = Database.query(query);

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + items.size() + ' schedule items');

            // Query Payment_Fee__c records for all schedule items (including wire fees)
            Set<Id> scheduleItemIds = new Set<Id>();
            for (Payment_Schedule_Item__c item : items) {
                scheduleItemIds.add(item.Id);
            }
            Map<Id, Map<String, Payment_Fee__c>> feeRecordsMap =
                PaymentFeeService.getFeesByScheduleItemIds(scheduleItemIds);

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Fetched fee records for ' + scheduleItemIds.size() + ' items');

            // Build wrappers with fee data
            Integer rowNum = 1;
            for (Payment_Schedule_Item__c item : items) {
                wrapper.scheduleItems.add(buildScheduleItemWrapper(item, rowNum++, feeRecordsMap));
            }
        }

        System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS - ' + wrapper.scheduleItems.size() + ' items');
        return wrapper;
    }

    /**
     * @description Build ScheduleItemWrapper from Payment_Schedule_Item__c record.
     * Reads fee amounts from Payment_Fee__c child records when available,
     * falling back to flat fields on Payment_Schedule_Item__c for backwards compatibility.
     *
     * @param item The Payment_Schedule_Item__c record
     * @param rowNum The row number for display
     * @param feeRecordsMap Map of PSI Id to Map of Fee Type to Payment_Fee__c record (can be null)
     * @return ScheduleItemWrapper populated with fee data
     */
    private static ScheduleItemWrapper buildScheduleItemWrapper(
        Payment_Schedule_Item__c item,
        Integer rowNum,
        Map<Id, Map<String, Payment_Fee__c>> feeRecordsMap
    ) {
        ScheduleItemWrapper wrapper = new ScheduleItemWrapper();
        wrapper.id = item.Id;
        wrapper.rowNumber = rowNum;
        wrapper.draftNumber = item.Draft_Number__c != null ? item.Draft_Number__c : String.valueOf(rowNum);
        wrapper.paymentDate = item.Payment_Date__c;
        wrapper.draftAmount = item.Total_Payment__c != null ? item.Total_Payment__c : item.Net_Draft_Amount__c;
        wrapper.retainerFee = item.Retainer_Fee_Amount__c;
        wrapper.banking2Fee = item.Bank2_Fee_Amount__c;
        wrapper.status = item.Status__c;
        wrapper.wiresReceived = 0; // Wire fees are now tracked separately in Payment_Fee__c

        // Read fees from Payment_Fee__c records if available, otherwise fall back to flat fields
        if (feeRecordsMap != null && feeRecordsMap.containsKey(item.Id)) {
            Map<String, Payment_Fee__c> fees = feeRecordsMap.get(item.Id);

            // Banking Fee
            Payment_Fee__c bankingFeeRecord = fees.get(PaymentFeeService.FEE_TYPE_BANKING);
            wrapper.bankingFee = (bankingFeeRecord != null && bankingFeeRecord.Amount__c != null)
                ? bankingFeeRecord.Amount__c : (item.Banking_Fee_Amount__c != null ? item.Banking_Fee_Amount__c : 0);
            wrapper.bankingFeeStatus = (bankingFeeRecord != null) ? bankingFeeRecord.Status__c : null;

            // Program Fee
            Payment_Fee__c programFeeRecord = fees.get(PaymentFeeService.FEE_TYPE_PROGRAM);
            wrapper.programFee = (programFeeRecord != null && programFeeRecord.Amount__c != null)
                ? programFeeRecord.Amount__c : (item.Program_Fee_Amount__c != null ? item.Program_Fee_Amount__c : 0);
            wrapper.programFeeStatus = (programFeeRecord != null) ? programFeeRecord.Status__c : null;

            // Setup Fee
            Payment_Fee__c setupFeeRecord = fees.get(PaymentFeeService.FEE_TYPE_SETUP);
            wrapper.setupFee = (setupFeeRecord != null && setupFeeRecord.Amount__c != null)
                ? setupFeeRecord.Amount__c : (item.Setup_Fee_Amount__c != null ? item.Setup_Fee_Amount__c : 0);
            wrapper.setupFeeStatus = (setupFeeRecord != null) ? setupFeeRecord.Status__c : null;

            // Savings/Escrow - read directly from To_Escrow_Amount__c field
            wrapper.savingsBalance = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
            wrapper.toEscrowAmount = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
        } else {
            // Fall back to flat fields on Payment_Schedule_Item__c (backwards compatibility)
            wrapper.bankingFee = item.Banking_Fee_Amount__c;
            wrapper.programFee = item.Program_Fee_Amount__c;
            wrapper.setupFee = item.Setup_Fee_Amount__c;
            wrapper.savingsBalance = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
            wrapper.toEscrowAmount = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
            // No fee status available when falling back to flat fields
            wrapper.bankingFeeStatus = null;
            wrapper.programFeeStatus = null;
            wrapper.setupFeeStatus = null;
        }

        // EPPS fields - always map from the schedule item record
        wrapper.eppsEftStatus = item.EPPS_EFT_Status__c;
        wrapper.eppsEftTransactionId = item.EPPS_EFT_Transaction_Id__c;
        wrapper.eppsNsfReturnCode = item.EPPS_NSF_Return_Code__c;
        wrapper.eppsReturnedDate = item.EPPS_Returned_Date__c;
        wrapper.eppsSettlementDate = item.EPPS_Settlement_Date__c;
        wrapper.eppsStatusDate = item.EPPS_Status_Date__c;

        return wrapper;
    }

    /**
     * @description Map wrapper fields to Payment_Schedule_Item__c record
     */
    private static void mapWrapperToRecord(ScheduleItemWrapper wrapper, Payment_Schedule_Item__c record) {
        record.Payment_Number__c = wrapper.rowNumber;
        record.Draft_Number__c = wrapper.draftNumber;
        record.Payment_Date__c = wrapper.paymentDate;
        record.Total_Payment__c = wrapper.draftAmount;
        record.Retainer_Fee_Amount__c = wrapper.retainerFee;
        record.Setup_Fee_Amount__c = wrapper.setupFee;
        record.Program_Fee_Amount__c = wrapper.programFee;
        record.Banking_Fee_Amount__c = wrapper.bankingFee;
        record.Bank2_Fee_Amount__c = wrapper.banking2Fee;
        record.Savings_Balance__c = wrapper.savingsBalance;
        record.To_Escrow_Amount__c = wrapper.toEscrowAmount;
        record.Status__c = wrapper.status;
        // EPPS fields
        record.EPPS_EFT_Status__c = wrapper.eppsEftStatus;
        record.EPPS_EFT_Transaction_Id__c = wrapper.eppsEftTransactionId;
        record.EPPS_NSF_Return_Code__c = wrapper.eppsNsfReturnCode;
        record.EPPS_Returned_Date__c = wrapper.eppsReturnedDate;
        record.EPPS_Settlement_Date__c = wrapper.eppsSettlementDate;
        record.EPPS_Status_Date__c = wrapper.eppsStatusDate;
    }

    /**
     * @description Validate a currency value is within acceptable range
     * @param value The value to validate
     * @param fieldName Name of the field for error messages
     * @throws AuraHandledException if value is out of range
     */
    private static void validateCurrencyValue(Decimal value, String fieldName) {
        if (value != null) {
            if (value > MAX_CURRENCY_VALUE) {
                throw new AuraHandledException(
                    VALIDATION_SYMBOL + fieldName + ' value exceeds maximum allowed (' + MAX_CURRENCY_VALUE + ').'
                );
            }
            if (value < MIN_CURRENCY_VALUE) {
                throw new AuraHandledException(
                    VALIDATION_SYMBOL + fieldName + ' value is below minimum allowed (' + MIN_CURRENCY_VALUE + ').'
                );
            }
        }
    }

    /**
     * @description Validate schedule item wrapper values before saving
     * Checks currency values are within acceptable ranges
     * @param item The schedule item wrapper to validate
     * @param rowIndex Row number for error messages
     */
    private static void validateScheduleItemWrapper(ScheduleItemWrapper item, Integer rowIndex) {
        String rowPrefix = 'Row ' + rowIndex + ': ';

        validateCurrencyValue(item.draftAmount, rowPrefix + 'Draft Amount');
        validateCurrencyValue(item.setupFee, rowPrefix + 'Setup Fee');
        validateCurrencyValue(item.programFee, rowPrefix + 'Program Fee');
        validateCurrencyValue(item.bankingFee, rowPrefix + 'Banking Fee');
        validateCurrencyValue(item.banking2Fee, rowPrefix + 'Banking2 Fee');
        validateCurrencyValue(item.savingsBalance, rowPrefix + 'Savings Balance');

        // Validate date is not too far in past or future
        if (item.paymentDate != null) {
            Date minDate = Date.today().addYears(-10);
            Date maxDate = Date.today().addYears(10);
            if (item.paymentDate < minDate || item.paymentDate > maxDate) {
                throw new AuraHandledException(
                    VALIDATION_SYMBOL + rowPrefix + 'Payment Date must be within 10 years of today.'
                );
            }
        }
    }

    // ============ V2 METHODS (Merged from PaymentPlanEditorV2Controller) ============

    /**
     * @description Updates Opportunity fields directly from LWC calculator parameters.
     * This is a lightweight method for quick program configuration without creating Payment Plan records.
     *
     * @param recordId The Opportunity ID to update
     * @param numberOfWeeks Program duration in weeks
     * @param weeklyPayment Calculated weekly payment amount
     * @param firstDraftDate First draft date as ISO string YYYY-MM-DD
     * @param bankingFee Weekly banking fee amount
     * @param setupFeeTerm Number of payments for setup fee collection
     * @param noFeeProgram True if this is a no-fee program
     * @param programType Program type identifier: DCG_MOD, DCG_DEBT, or DCG_MOD_CA
     * @param settlementAmount Total settlement amount (used for validation)
     * @param programFee Total program fee amount (used for validation)
     * @throws AuraHandledException if recordId is not an Opportunity or update fails
     */
    @AuraEnabled
    public static void updateOpportunityOnly(
        Id recordId,
        Integer numberOfWeeks,
        Decimal weeklyPayment,
        String firstDraftDate,
        Decimal bankingFee,
        Integer setupFeeTerm,
        Boolean noFeeProgram,
        String programType,
        Decimal settlementAmount,
        Decimal programFee
    ) {
        PaymentPlanModificationService.updateOpportunityOnly(
            recordId, numberOfWeeks, weeklyPayment, firstDraftDate,
            bankingFee, setupFeeTerm, noFeeProgram, programType,
            settlementAmount, programFee
        );
    }

    // ==================================================================================
    // PLAN MODIFICATION METHODS (Modify Weekly Payment / Modify Est Total Debt)
    // Delegated to PaymentPlanModificationService
    // ==================================================================================

    /**
     * @description Preview a plan modification without saving.
     * Calculates the new schedule items based on the modified field value
     * using the same formula as recalculateRemainingBalance.
     * @param planId The current Payment Plan ID
     * @param modificationType 'EST_CURRENT_PAYMENT' or 'EST_TOTAL_DEBT'
     * @param newValue The new value for the modified field
     * @return PlanModificationPreview with summary metrics and projected schedule items
     */
    @AuraEnabled
    public static PlanModificationPreview previewPlanModification(Id planId, String modificationType, Decimal newValue) {
        return PaymentPlanModificationService.previewPlanModification(planId, modificationType, newValue);
    }

    /**
     * @description Save a plan modification as a new Draft version.
     * Creates a new plan version with recalculated schedule items and updates the Opportunity field.
     * Uses the same formula as recalculateRemainingBalance but with the user-provided value override.
     * @param planId The current Payment Plan ID
     * @param modificationType 'EST_CURRENT_PAYMENT' or 'EST_TOTAL_DEBT'
     * @param newValue The new value for the modified field
     * @return PaymentPlanWrapper for the newly created plan version
     */
    @AuraEnabled
    public static PaymentPlanWrapper savePlanModification(Id planId, String modificationType, Decimal newValue) {
        return PaymentPlanModificationService.savePlanModification(planId, modificationType, newValue);
    }

}