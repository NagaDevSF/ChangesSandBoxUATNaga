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
        'Version_Number__c, Version_Status__c, Is_Active__c, ' +
        'Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c, ' +
        'Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c, ' +
        'Calculation_Timestamp__c, Previous_Version__c, Source__c, ' +
        'Version_Type__c, Version_Notes__c, Schedule_Item_Count__c, ' +
        'Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c, ' +
        'Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c, ' +
        'Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c';

    /**
     * Standard fields to query for Payment_Schedule_Item__c records.
     * Includes all payment amounts, fees, and status information.
     */
    private static final String SCHEDULE_ITEM_QUERY_FIELDS =
        'Id, Payment_Number__c, Draft_Number__c, Payment_Date__c, ' +
        'Total_Payment__c, Net_Draft_Amount__c, Retainer_Fee_Amount__c, ' +
        'Setup_Fee_Amount__c, Program_Fee_Amount__c, Banking_Fee_Amount__c, ' +
        'Bank2_Fee_Amount__c, Additional_Products_Amount__c, Status__c, ' +
        'Savings_Balance__c, To_Escrow_Amount__c';

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
                       Version_Number__c, Version_Status__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Calculation_Timestamp__c, Previous_Version__c, Source__c,
                       Version_Type__c, Version_Notes__c, Schedule_Item_Count__c,
                       Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c,
                       Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c,
                       Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c
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
                       Version_Number__c, Version_Status__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Calculation_Timestamp__c, Previous_Version__c, Source__c,
                       Version_Type__c, Version_Notes__c, Schedule_Item_Count__c,
                       Program_Fee_Amount__c,
                       Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c,
                       Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c,
                       Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c
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
            wrapper.versionStatus = plans[0].Version_Status__c;
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
                SELECT Id, Name, Version_Number__c, Version_Status__c, Is_Active__c,
                       CreatedDate, LastModifiedDate, Status__c
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
                wrapper.versionStatus = plan.Version_Status__c;
                wrapper.isLatestVersion = (plan.Version_Number__c == latestVersion);
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
        String methodName = 'createManualVersion';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | currentPlanId: ' + currentPlanId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (currentPlanId == null) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | currentPlanId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            List<PaymentPlan__c> currentPlans = [
                SELECT Id, Name, Opportunity__c, Contract__c, Program_Type__c,
                       Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Total_Program_Cost__c, Weekly_Payment__c, Monthly_Payment__c,
                       Number_of_Payments__c, First_Payment_Date__c, Status__c,
                       Version_Number__c, Version_Status__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Schedule_Item_Count__c
                FROM PaymentPlan__c
                WHERE Id = :currentPlanId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentPlans.size() + ' plan(s)');

            if (currentPlans.isEmpty()) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Payment Plan not found: ' + currentPlanId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c currentPlan = currentPlans[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Current plan: ' + currentPlan.Name + ' (Version ' + currentPlan.Version_Number__c + ')');

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

            Decimal newVersionNumber = currentPlan.Version_Number__c != null ?
                currentPlan.Version_Number__c + 1 : 2;

            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Creating new version: ' + newVersionNumber);

            // Clone the plan as Draft (user must activate manually)
            PaymentPlan__c newPlan = currentPlan.clone(false, true, false, false);
            newPlan.Version_Number__c = newVersionNumber;
            newPlan.Version_Status__c = VERSION_STATUS_DRAFT;
            newPlan.Status__c = VERSION_STATUS_DRAFT;  // Also set Status__c to Draft
            newPlan.Is_Active__c = false;
            newPlan.Previous_Version__c = currentPlan.Id;
            newPlan.Version_Type__c = VERSION_TYPE_REVISION;
            newPlan.Source__c = SOURCE_UI;
            newPlan.Version_Notes__c = 'Manual version created on ' + DateTime.now().format();
            newPlan.Calculation_Timestamp__c = DateTime.now();

            // Update Program Type, No Fee Program, and Number of Payments from Opportunity
            if (opp != null) {
                newPlan.Program_Type__c = opp.Program_Type__c;
                newPlan.No_Fee_Program__c = opp.No_Fee_Program__c;
                newPlan.Number_of_Payments__c = opp.Number_of_Weeks__c;
            }

            insert newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted new plan: ' + newPlan.Id);

            // Clone schedule items
            List<Payment_Schedule_Item__c> currentItems = [
                SELECT Id, Payment_Number__c, Draft_Number__c, Payment_Date__c,
                       Total_Payment__c, Net_Draft_Amount__c, Retainer_Fee_Amount__c,
                       Setup_Fee_Amount__c, Program_Fee_Amount__c, Banking_Fee_Amount__c,
                       Bank2_Fee_Amount__c, Additional_Products_Amount__c, Status__c,
                       Savings_Balance__c, To_Escrow_Amount__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :currentPlanId
                ORDER BY Payment_Number__c ASC
                LIMIT :MAX_QUERY_LIMIT
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentItems.size() + ' schedule items to clone');

            List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();
            for (Payment_Schedule_Item__c item : currentItems) {
                Payment_Schedule_Item__c newItem = item.clone(false, true, false, false);
                newItem.Payment_Plan__c = newPlan.Id;
                // Keep the original status
                newItems.add(newItem);
            }

            if (!newItems.isEmpty()) {
                // Recalculate Draft_Number__c to skip NSF/Cancelled items
                recalculateDraftNumbers(newItems);
                insert newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newItems.size() + ' schedule items');
            }

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Manual version created successfully: ' + newPlan.Id);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return getPaymentPlanById(newPlan.Id);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Rolling back transaction');
            throw new AuraHandledException(ERROR_SYMBOL + 'Error creating manual version: ' + e.getMessage());
        }
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
                       Version_Number__c, Version_Status__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Calculation_Timestamp__c, Previous_Version__c, Source__c,
                       Version_Type__c, Version_Notes__c, Schedule_Item_Count__c,
                       Total_Draft_Amount__c, Total_Setup_Fee_Rollup__c, Total_Program_Fee_Rollup__c,
                       Total_Banking_Fee_Rollup__c, Total_Savings_Rollup__c, Total_To_Escrow_Rollup__c,
                       Schedule_Item_Count_Rollup__c, Total_Amount_Cleared__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + plans.size() + ' plan(s)');

            if (plans.isEmpty()) {
                System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Payment Plan not found: ' + planId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Plan: ' + plans[0].Name + ' | Version: ' + plans[0].Version_Number__c + ' | Status: ' + plans[0].Version_Status__c);
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
            List<Payment_Schedule_Item__c> previousItems = [
                SELECT Id, Payment_Plan__c, Payment_Number__c, Draft_Number__c,
                       Payment_Date__c, Total_Payment__c, Net_Draft_Amount__c,
                       Setup_Fee_Amount__c, Program_Fee_Amount__c, Banking_Fee_Amount__c,
                       Bank2_Fee_Amount__c, Additional_Products_Amount__c, Status__c,
                       Savings_Balance__c, To_Escrow_Amount__c, Retainer_Fee_Amount__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :previousPlanId
                ORDER BY Payment_Number__c ASC
                LIMIT :MAX_QUERY_LIMIT
            ];

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

            // Get default banking fee from plan
            List<PaymentPlan__c> plans = [
                SELECT Banking_Fee__c
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
            newItem.Bank2_Fee_Amount__c = 0;
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
        String methodName = 'recalculatePaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get current plan to find Opportunity and version number
            List<PaymentPlan__c> currentPlans = [
                SELECT Id, Name, Opportunity__c, Version_Number__c, Program_Type__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

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
                       No_Fee_Program__c
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

            // Get Banking Fee from CMDT config
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

            Decimal bankingFee = config.bankingFee != null ? config.bankingFee : 15.00;
            Decimal bank2Fee = config.bank2Fee != null ? config.bank2Fee : 0;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Config - BankingFee: ' + bankingFee + ' | Bank2Fee: ' + bank2Fee + ' | SplitRatio: ' + config.programSplitRatio);

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
            newPlan.Version_Status__c = VERSION_STATUS_DRAFT;
            newPlan.Is_Active__c = false;
            newPlan.Previous_Version__c = currentPlan.Id;
            newPlan.Version_Type__c = VERSION_TYPE_REVISION;
            newPlan.Source__c = SOURCE_UI;
            newPlan.Version_Notes__c = 'Recalculated from Opportunity on ' + DateTime.now().format();
            newPlan.Calculation_Timestamp__c = DateTime.now();

            insert newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted new plan: ' + newPlan.Id + ' | Weekly: ' + newPlan.Weekly_Payment__c + ' | Payments: ' + newPlan.Number_of_Payments__c);

            // Query existing schedule items from current plan for status-based redistribution
            List<Payment_Schedule_Item__c> existingItems = [
                SELECT Id, Payment_Number__c, Draft_Number__c, Payment_Date__c,
                       Total_Payment__c, Setup_Fee_Amount__c, Program_Fee_Amount__c,
                       Banking_Fee_Amount__c, Bank2_Fee_Amount__c, Additional_Products_Amount__c,
                       Retainer_Fee_Amount__c, To_Escrow_Amount__c, Savings_Balance__c, Status__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :planId
                ORDER BY Payment_Number__c ASC
                LIMIT :MAX_QUERY_LIMIT
            ];
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
            return getPaymentPlanById(newPlan.Id);

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
        String methodName = 'recalculateRemainingBalance';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get current plan with Opportunity reference
            List<PaymentPlan__c> currentPlans = [
                SELECT Id, Name, Opportunity__c, Version_Number__c, Program_Type__c,
                       Number_of_Payments__c, First_Payment_Date__c, Banking_Fee__c, Bank2_Fee__c,
                       Setup_Fee__c, Setup_Fee_Payments__c, Total_Debt__c, Settlement_Percentage__c,
                       Program_Fee_Percentage__c, Total_Program_Cost__c, Weekly_Payment__c,
                       Monthly_Payment__c, Contract__c, Status__c, Version_Status__c, Is_Active__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Schedule_Item_Count__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

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
                       Total_Program__c, Program_Fee__c,
                       Est_weekly_payment__c
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

            // Step 1: Calculate Total Program Cost = Estimated_Total_Debt__c × 0.95
            Decimal estimatedTotalDebt = opp.Estimated_Total_Debt__c != null ? opp.Estimated_Total_Debt__c : 0;
            Decimal totalProgramCost = estimatedTotalDebt * 0.95;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Total Program Cost (Debt × 0.95): ' + totalProgramCost);

            // Get setup fee parameters from OPPORTUNITY (same as recalculatePaymentPlan)
            Decimal totalSetupFee = opp.Setup_Fee__c != null ? opp.Setup_Fee__c : 0;
            Decimal setupFeePaymentsTotal = parsePercentageToDecimal(opp.Setup_Fee_Term__c);
            if (setupFeePaymentsTotal == null || setupFeePaymentsTotal <= 0) {
                setupFeePaymentsTotal = DEFAULT_SETUP_FEE_PAYMENTS;
            }
            Decimal perPaymentSetupFee = setupFeePaymentsTotal > 0 ? (totalSetupFee / setupFeePaymentsTotal) : 0;
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Setup Fee (from Opp): ' + totalSetupFee + ' over ' + setupFeePaymentsTotal + ' payments = ' + perPaymentSetupFee + ' per payment');

            // Get program fee parameters from OPPORTUNITY (same as recalculatePaymentPlan)
            Decimal totalDebt = estimatedTotalDebt;
            Decimal programFeePercentage = parsePercentageToDecimal(opp.Program_Fee__c);
            if (programFeePercentage == null) {
                programFeePercentage = config.programFeePercent != null ? config.programFeePercent : 35;
            }
            Decimal totalProgramFee = totalDebt * (programFeePercentage / 100);
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Total Program Fee (from Opp): ' + totalProgramFee + ' (' + programFeePercentage + '% of ' + totalDebt + ')');

            // Get existing schedule items
            List<Payment_Schedule_Item__c> existingItems = [
                SELECT Id, Payment_Number__c, Draft_Number__c, Payment_Date__c,
                       Total_Payment__c, Setup_Fee_Amount__c, Program_Fee_Amount__c,
                       Banking_Fee_Amount__c, Bank2_Fee_Amount__c, Additional_Products_Amount__c,
                       Retainer_Fee_Amount__c, To_Escrow_Amount__c, Savings_Balance__c, Status__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :planId
                ORDER BY Payment_Number__c ASC
                LIMIT :MAX_QUERY_LIMIT
            ];
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + existingItems.size() + ' existing schedule items');

            // Separate items by status and calculate paid amounts
            List<Payment_Schedule_Item__c> nonScheduledItems = new List<Payment_Schedule_Item__c>();
            List<Payment_Schedule_Item__c> scheduledItems = new List<Payment_Schedule_Item__c>();
            Decimal clearedProgramCostSum = 0;  // Sum of (Program_Fee + To_Escrow) - the actual program cost paid
            Decimal paidProgramFeeSum = 0;
            Decimal paidEscrowSum = 0;
            Integer paidSetupFeeCount = 0;
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
                        // Only count setup fees from CLEARED items as actually paid
                        if (item.Setup_Fee_Amount__c != null && item.Setup_Fee_Amount__c > 0) {
                            paidSetupFeeCount++;
                        }
                    }
                    // Track program fees already collected (from Cleared items only)
                    if (item.Status__c == STATUS_CLEARED && item.Program_Fee_Amount__c != null && item.Program_Fee_Amount__c > 0) {
                        paidProgramFeeSum += item.Program_Fee_Amount__c;
                    }
                    // Track lost fees from NSF items for logging purposes
                    // Note: Banking fees are NOT recovered to prevent cascading fee increases
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
            // Since paidSetupFeeCount only counts CLEARED items, NSF setup fees are already in the "remaining"
            // NO additional extension needed - same logic as Program Fee
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
            // Last payment = Remaining Program Cost - (Base × (Count - 1))
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
            newPlan.Version_Status__c = VERSION_STATUS_DRAFT;
            newPlan.Status__c = VERSION_STATUS_DRAFT;  // Also set Status__c to Draft
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

                // Calculate setup fee for this payment (only for remaining setup fee payments)
                Decimal thisSetupFee = 0;
                if (setupFeePaymentsMade < remainingSetupFeePayments) {
                    thisSetupFee = perPaymentSetupFee;
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

                if (trackingRemainingProgramFee > 0) {
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
            return getPaymentPlanById(newPlan.Id);

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

    /**
     * @description Parse a percentage string to Decimal value
     * Handles values like "35%", "35", "20%" by stripping the % symbol
     * @param value The string value to parse
     * @return Decimal value or null if blank/invalid
     */
    private static Decimal parsePercentageToDecimal(String value) {
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
     * @description Wrapper class to hold paid sums from non-scheduled items
     * Used for redistribution calculations when recalculating payment plans
     */
    private class PaidSumsWrapper {
        public Decimal setupFee = 0;
        public Decimal programFee = 0;
        public Decimal escrow = 0;
        public Decimal savingsBalance = 0;
        public Integer nonScheduledCount = 0;
    }

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

        // Calculate remaining setup fee payments (only count CLEARED items as actually paid)
        // NSF and Cancelled items were never collected, so their setup fees still need to be collected
        Integer paidSetupFeeCount = 0;
        for (Payment_Schedule_Item__c item : nonScheduledItems) {
            if (item.Status__c == STATUS_CLEARED && item.Setup_Fee_Amount__c != null && item.Setup_Fee_Amount__c > 0) {
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

            if (remainingProgramFee > 0) {
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

            if (remainingProgramFee > 0) {
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

    /**
     * @description Separate schedule items by status into scheduled and non-scheduled lists
     * Non-scheduled includes: Cleared, NSF, Cancelled (anything except 'Scheduled')
     * @param allItems All items to separate
     * @param nonScheduledItems Output list for non-scheduled items
     * @param scheduledItems Output list for scheduled items
     */
    private static void separateItemsByStatus(
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
    private static PaidSumsWrapper calculatePaidSums(List<Payment_Schedule_Item__c> nonScheduledItems) {
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
    private static List<Decimal> distributeAmountEvenly(Decimal totalAmount, Integer count) {
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

    /**
     * @description Clone a schedule item for a new payment plan
     * Preserves all field values but assigns to new plan
     * @param original Original item to clone
     * @param newPlanId New payment plan ID
     * @return Cloned item with new plan assignment
     */
    private static Payment_Schedule_Item__c cloneItemForNewPlan(
        Payment_Schedule_Item__c original,
        Id newPlanId
    ) {
        Payment_Schedule_Item__c cloned = new Payment_Schedule_Item__c();
        cloned.Payment_Plan__c = newPlanId;
        cloned.Payment_Number__c = original.Payment_Number__c;
        cloned.Draft_Number__c = original.Draft_Number__c;
        cloned.Payment_Date__c = original.Payment_Date__c;
        cloned.Total_Payment__c = original.Total_Payment__c;
        cloned.Setup_Fee_Amount__c = original.Setup_Fee_Amount__c;
        cloned.Program_Fee_Amount__c = original.Program_Fee_Amount__c;
        cloned.Banking_Fee_Amount__c = original.Banking_Fee_Amount__c;
        cloned.Bank2_Fee_Amount__c = original.Bank2_Fee_Amount__c;
        cloned.Retainer_Fee_Amount__c = original.Retainer_Fee_Amount__c;
        cloned.To_Escrow_Amount__c = original.To_Escrow_Amount__c;
        cloned.Savings_Balance__c = original.Savings_Balance__c;
        cloned.Status__c = original.Status__c;
        return cloned;
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
        String methodName = 'suspendPaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get the current plan with all fields
            List<PaymentPlan__c> currentPlans = [
                SELECT Id, Name, Opportunity__c, Version_Number__c, Version_Status__c,
                       Is_Active__c, Version_Type__c, Source__c, Version_Notes__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Calculation_Timestamp__c, Schedule_Item_Count__c,
                       Weekly_Payment__c, Monthly_Payment__c, Number_of_Payments__c,
                       Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Total_Program_Cost__c, Settlement_Amount__c, Program_Fee_Amount__c,
                       First_Payment_Date__c, Program_Type__c, Contract__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentPlans.size() + ' current plan(s)');

            if (currentPlans.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Payment Plan not found: ' + planId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c currentPlan = currentPlans[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Suspending plan: ' + currentPlan.Name + ' | Version: ' + currentPlan.Version_Number__c);

            // Get the next version number
            Integer maxVersion = 0;
            List<AggregateResult> maxVersionResult = [
                SELECT MAX(Version_Number__c) maxVer
                FROM PaymentPlan__c
                WHERE Opportunity__c = :currentPlan.Opportunity__c
            ];
            if (maxVersionResult.size() > 0 && maxVersionResult[0].get('maxVer') != null) {
                maxVersion = Integer.valueOf(maxVersionResult[0].get('maxVer'));
            }
            System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Max existing version: ' + maxVersion + ' | New version: ' + (maxVersion + 1));

            // Create new plan as a clone with incremented version
            PaymentPlan__c newPlan = currentPlan.clone(false, true, false, false);
            newPlan.Version_Number__c = maxVersion + 1;
            newPlan.Version_Status__c = VERSION_STATUS_ACTIVE;
            newPlan.Status__c = 'Active';  // Set Status__c to Active for suspended plan
            newPlan.Is_Active__c = true;
            newPlan.Version_Type__c = VERSION_TYPE_SUSPENSION;
            newPlan.Source__c = SOURCE_UI;
            newPlan.Version_Notes__c = 'Plan suspended on ' + DateTime.now().format() + '. Scheduled items cancelled.';
            newPlan.Calculation_Timestamp__c = DateTime.now();
            insert newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Created suspension plan: ' + newPlan.Id);

            // Get all schedule items from the current plan
            List<Payment_Schedule_Item__c> currentItems = [
                SELECT Id, Payment_Number__c, Draft_Number__c, Payment_Date__c,
                       Total_Payment__c, Retainer_Fee_Amount__c, Setup_Fee_Amount__c,
                       Program_Fee_Amount__c, Banking_Fee_Amount__c, Bank2_Fee_Amount__c,
                       Additional_Products_Amount__c, Status__c, Savings_Balance__c,
                       To_Escrow_Amount__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :planId
                ORDER BY Payment_Number__c ASC
                LIMIT :MAX_QUERY_LIMIT
            ];
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + currentItems.size() + ' schedule items to process');

            // Clone items to new plan, changing Scheduled to Cancelled
            List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();
            Integer cancelledCount = 0;
            for (Payment_Schedule_Item__c item : currentItems) {
                Payment_Schedule_Item__c newItem = item.clone(false, true, false, false);
                newItem.Payment_Plan__c = newPlan.Id;

                // Change Scheduled status to Cancelled
                if (item.Status__c == STATUS_SCHEDULED) {
                    newItem.Status__c = STATUS_CANCELLED;
                    cancelledCount++;
                }

                newItems.add(newItem);
            }
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Cancelled ' + cancelledCount + ' scheduled items');

            if (!newItems.isEmpty()) {
                // Recalculate Draft_Number__c to skip NSF/Cancelled items
                recalculateDraftNumbers(newItems);
                insert newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newItems.size() + ' schedule items');

                // Carry over wire fees (Wire Fee and Wire Received Fee) from old items to new items
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Carrying over wire fees...');
                carryOverWireFees(currentItems, newItems);
            }

            // Update the new plan's item count
            newPlan.Schedule_Item_Count__c = newItems.size();
            update newPlan;

            // Archive all other plans for this Opportunity (including the original)
            List<PaymentPlan__c> otherPlans = [
                SELECT Id, Version_Status__c, Is_Active__c, Status__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :currentPlan.Opportunity__c
                AND Id != :newPlan.Id
                LIMIT :MAX_QUERY_LIMIT
            ];
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + otherPlans.size() + ' other plan(s) to archive');

            for (PaymentPlan__c otherPlan : otherPlans) {
                otherPlan.Version_Status__c = VERSION_STATUS_ARCHIVED;
                otherPlan.Status__c = 'Draft';  // Set Status__c to Draft for archived plans
                otherPlan.Is_Active__c = false;
            }

            if (!otherPlans.isEmpty()) {
                update otherPlans;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Archived ' + otherPlans.size() + ' plan(s) and set Status to Draft');
            }

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Plan suspended successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            // Return the new plan with schedule items
            return buildPaymentPlanWrapper(newPlan, true);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error suspending payment plan: ' + e.getMessage());
        }
    }

    /**
     * @description Activate a draft payment plan
     * Archives all previous versions and sets the selected plan as Active
     * @param planId The Payment Plan ID
     * @return Updated PaymentPlanWrapper
     */
    @AuraEnabled
    public static PaymentPlanWrapper activatePaymentPlan(Id planId) {
        String methodName = 'activatePaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get the plan to activate and its Opportunity ID
            List<PaymentPlan__c> plansToActivate = [
                SELECT Id, Opportunity__c, Version_Number__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + plansToActivate.size() + ' plan(s)');

            if (plansToActivate.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Payment Plan not found: ' + planId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c planToActivate = plansToActivate[0];
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Activating plan version: ' + planToActivate.Version_Number__c);

            // Archive all other versions for this Opportunity and set their Status to Draft
            List<PaymentPlan__c> otherPlans = [
                SELECT Id, Version_Status__c, Is_Active__c, Status__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :planToActivate.Opportunity__c
                  AND Id != :planId
                  AND Version_Status__c != :VERSION_STATUS_ARCHIVED
                LIMIT :MAX_QUERY_LIMIT
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + otherPlans.size() + ' other plan(s) to archive');

            for (PaymentPlan__c otherPlan : otherPlans) {
                otherPlan.Version_Status__c = VERSION_STATUS_ARCHIVED;
                otherPlan.Status__c = 'Draft';  // Set Status__c to Draft for other plans
                otherPlan.Is_Active__c = false;
            }

            if (!otherPlans.isEmpty()) {
                update otherPlans;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Archived ' + otherPlans.size() + ' plan(s) and set Status to Draft');
            }

            // Activate the selected plan - set both Version_Status__c and Status__c to Active
            PaymentPlan__c plan = new PaymentPlan__c(Id = planId);
            plan.Version_Status__c = VERSION_STATUS_ACTIVE;
            plan.Status__c = 'Active';  // Set Status__c to Active for current plan
            plan.Is_Active__c = true;
            plan.Calculation_Timestamp__c = DateTime.now();
            update plan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Activated plan: ' + planId + ' (both Version_Status__c and Status__c set to Active)');

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Plan activated successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return getPaymentPlanById(planId);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error activating payment plan: ' + e.getMessage());
        }
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
                       Version_Number__c, Version_Status__c, Is_Active__c,
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
            newPlan.Version_Status__c = VERSION_STATUS_DRAFT;
            newPlan.Status__c = VERSION_STATUS_DRAFT;  // Also set Status__c to Draft
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

            // Create all schedule items for the new plan
            List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();
            List<ScheduleItemWrapper> itemWrappers = new List<ScheduleItemWrapper>();

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

                Payment_Schedule_Item__c newItem = new Payment_Schedule_Item__c();
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

                // Preserve valid statuses from LWC (like 'Failed to EPPS', 'Sent to EPPS', 'Processing', etc.)
                // Invalid or blank statuses default to 'Scheduled'
                newItem.Status__c = validateStatus(item.status);

                // Preserve Savings Balance and To Escrow Amount
                newItem.Savings_Balance__c = item.savingsBalance != null ? item.savingsBalance : 0;
                newItem.To_Escrow_Amount__c = item.toEscrowAmount != null ? item.toEscrowAmount : 0;

                newItems.add(newItem);
                itemWrappers.add(item);
            }

            if (!newItems.isEmpty()) {
                // Recalculate Draft_Number__c to skip NSF/Cancelled items
                recalculateDraftNumbers(newItems);
                insert newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newItems.size() + ' schedule items');

                // Create Payment_Fee__c records for all new schedule items
                Map<Id, ScheduleItemWrapper> wrapperMap = new Map<Id, ScheduleItemWrapper>();
                for (Integer i = 0; i < newItems.size(); i++) {
                    wrapperMap.put(newItems[i].Id, itemWrappers[i]);
                }
                List<Payment_Fee__c> feeRecords = PaymentFeeService.createFeeRecordsForItems(newItems, wrapperMap);
                if (!feeRecords.isEmpty()) {
                    insert feeRecords;
                    System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + feeRecords.size() + ' fee record(s)');
                }
            }

            // Get old schedule items for wired payments carryover
            List<Payment_Schedule_Item__c> oldScheduleItems = [
                SELECT Id, Payment_Number__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :currentPlanId
                LIMIT :MAX_QUERY_LIMIT
            ];
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + oldScheduleItems.size() + ' old schedule items for wired payment carryover');

            // Carry over wired payments from old plan to new plan
            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Carrying over wired payments...');
            carryOverWireFees(oldScheduleItems, newItems);

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
     * @description Carry over wire fees from old schedule items to new schedule items
     * Matches by Payment_Number__c (row number) to link wire fees to correct new items
     * @param oldScheduleItems List of old schedule items (must have Id and Payment_Number__c populated)
     * @param newScheduleItems List of new schedule items (must have Id and Payment_Number__c populated after insert)
     */
    private static void carryOverWireFees(
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
     * @description Build PaymentPlanWrapper from PaymentPlan__c record
     */
    private static PaymentPlanWrapper buildPaymentPlanWrapper(PaymentPlan__c plan, Boolean includeItems) {
        String methodName = 'buildPaymentPlanWrapper';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + plan.Id + ' | includeItems: ' + includeItems);

        PaymentPlanWrapper wrapper = new PaymentPlanWrapper();
        wrapper.paymentPlan = plan;
        wrapper.versionNumber = plan.Version_Number__c != null ? plan.Version_Number__c.intValue() : 1;
        wrapper.versionStatus = plan.Version_Status__c;
        wrapper.isLatestVersion = true;

        System.debug(LoggingLevel.DEBUG, LOG_DEBUG + ' | ' + methodName + ' | Building wrapper for version ' + wrapper.versionNumber + ' (' + wrapper.versionStatus + ')');

        if (includeItems) {
            List<Payment_Schedule_Item__c> items = [
                SELECT Id, Name, Payment_Number__c, Draft_Number__c, Payment_Date__c,
                       Total_Payment__c, Net_Draft_Amount__c, Retainer_Fee_Amount__c,
                       Setup_Fee_Amount__c, Program_Fee_Amount__c, Banking_Fee_Amount__c,
                       Bank2_Fee_Amount__c, Additional_Products_Amount__c, Status__c,
                       Savings_Balance__c, To_Escrow_Amount__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :plan.Id
                ORDER BY Payment_Number__c ASC
                LIMIT :MAX_QUERY_LIMIT
            ];

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

            // Program Fee
            Payment_Fee__c programFeeRecord = fees.get(PaymentFeeService.FEE_TYPE_PROGRAM);
            wrapper.programFee = (programFeeRecord != null && programFeeRecord.Amount__c != null)
                ? programFeeRecord.Amount__c : (item.Program_Fee_Amount__c != null ? item.Program_Fee_Amount__c : 0);

            // Setup Fee
            Payment_Fee__c setupFeeRecord = fees.get(PaymentFeeService.FEE_TYPE_SETUP);
            wrapper.setupFee = (setupFeeRecord != null && setupFeeRecord.Amount__c != null)
                ? setupFeeRecord.Amount__c : (item.Setup_Fee_Amount__c != null ? item.Setup_Fee_Amount__c : 0);

            // Payee Fee (Savings/Escrow)
            Payment_Fee__c payeeFeeRecord = fees.get(PaymentFeeService.FEE_TYPE_PAYEE);
            Decimal payeeFeeAmount = (payeeFeeRecord != null && payeeFeeRecord.Amount__c != null)
                ? payeeFeeRecord.Amount__c : (item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0);
            wrapper.savingsBalance = payeeFeeAmount;
            wrapper.toEscrowAmount = payeeFeeAmount;
        } else {
            // Fall back to flat fields on Payment_Schedule_Item__c (backwards compatibility)
            wrapper.bankingFee = item.Banking_Fee_Amount__c;
            wrapper.programFee = item.Program_Fee_Amount__c;
            wrapper.setupFee = item.Setup_Fee_Amount__c;
            wrapper.savingsBalance = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
            wrapper.toEscrowAmount = item.To_Escrow_Amount__c != null ? item.To_Escrow_Amount__c : 0;
        }

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
    private static void recalculateDraftNumbers(List<Payment_Schedule_Item__c> items) {
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
        try {
            String sObjectType = recordId.getSObjectType().getDescribe().getName();

            // Only update Opportunity records
            if (sObjectType != 'Opportunity') {
                throw new AuraHandledException('Record must be an Opportunity');
            }

            // ============ VALIDATION: Number of Weeks and Weekly Payment Ranges ============
            // Get config for validation - if config fails, skip validation but allow save
            PaymentCalcConfigSvc.ConfigDTO cfg = null;
            try {
                cfg = PaymentCalcConfigSvc.getRequiredConfig();
            } catch (Exception configEx) {
                System.debug(LoggingLevel.WARN, '[updateOpportunityOnly] Config not available, skipping range validation: ' + configEx.getMessage());
            }

            // Validate Number of Weeks (only if config loaded successfully)
            if (cfg != null && numberOfWeeks != null) {
                Integer minWeeks = cfg.minProgramWeeks != null ? cfg.minProgramWeeks.intValue() : 24;
                Integer maxWeeks = cfg.maxProgramWeeks != null ? cfg.maxProgramWeeks.intValue() : 260;

                if (numberOfWeeks < minWeeks || numberOfWeeks > maxWeeks) {
                    throw new AuraHandledException(
                        VALIDATION_SYMBOL + 'Number of weeks must be between ' + minWeeks + ' and ' + maxWeeks + '.'
                    );
                }
            }

            // Validate Weekly Payment (Desired Payment)
            // Only validate if current payment is set and config loaded (validation bounds depend on current payment)
            if (cfg != null && weeklyPayment != null) {
                // Query Opportunity to get Estimated_Current_Payment__c for range calculation
                List<Opportunity> opps = [
                    SELECT Id, Estimated_Current_Payment__c
                    FROM Opportunity
                    WHERE Id = :recordId
                    LIMIT 1
                ];

                Decimal currentPayment = 0;
                if (!opps.isEmpty() && opps[0].Estimated_Current_Payment__c != null) {
                    currentPayment = opps[0].Estimated_Current_Payment__c;
                }

                // Only apply payment range validation if current payment is set
                // (The UI shows validation bounds based on current payment)
                if (currentPayment > 0) {
                    // Determine program type for validation
                    String normalizedProgramType = programType != null ? programType.replace(' ', '_').toUpperCase() : 'DCG_MOD';
                    Boolean isDcgDebt = normalizedProgramType == 'DCG_DEBT';

                    // Get minimum payment floor based on program type
                    Decimal minPaymentFloor = isDcgDebt
                        ? (cfg.minWeeklyTargetPaymentDcgDebt != null ? cfg.minWeeklyTargetPaymentDcgDebt : 0)
                        : (cfg.minWeeklyTargetPayment != null ? cfg.minWeeklyTargetPayment : 35);

                    // Calculate percentage-based floor
                    Decimal minTargetPercent = isDcgDebt
                        ? (cfg.minTargetPercentDcgDebt != null ? cfg.minTargetPercentDcgDebt : 15)
                        : (cfg.minTargetPercentDcgMod != null ? cfg.minTargetPercentDcgMod : 40);
                    Decimal percentageFloor = currentPayment * (minTargetPercent / 100);

                    // Use the higher of absolute floor or percentage floor
                    Decimal minPayment = Math.max(minPaymentFloor, percentageFloor);

                    // Calculate maximum payment based on maxTargetPercent
                    Decimal maxTargetPercent = cfg.maxTargetPercent != null ? cfg.maxTargetPercent : 100;
                    Decimal maxPayment = currentPayment * (maxTargetPercent / 100);

                    // Validate payment is within range
                    if (weeklyPayment < minPayment) {
                        throw new AuraHandledException(
                            VALIDATION_SYMBOL + 'Desired payment must be at or above $' + minPayment.setScale(2) + '.'
                        );
                    }
                    if (weeklyPayment > maxPayment) {
                        throw new AuraHandledException(
                            VALIDATION_SYMBOL + 'Desired payment must be at or below $' + maxPayment.setScale(2) + '.'
                        );
                    }
                }
            }
            // ============ END VALIDATION ============

            Opportunity opp = new Opportunity(Id = recordId);
            Boolean hasUpdates = false;

            // Number of weeks
            if (numberOfWeeks != null) {
                opp.Number_of_Weeks__c = numberOfWeeks;
                hasUpdates = true;
            }

            // Weekly payment
            if (weeklyPayment != null) {
                opp.Est_weekly_payment__c = weeklyPayment;
                hasUpdates = true;
            }

            // First draft date
            if (String.isNotBlank(firstDraftDate)) {
                opp.First_Draft_Date__c = parseOpportunityDate(firstDraftDate);
                hasUpdates = true;
            }

            // Banking fee
            if (bankingFee != null) {
                opp.Banking_Fee__c = bankingFee;
                hasUpdates = true;
            }

            // Setup fee term
            if (setupFeeTerm != null) {
                opp.Setup_Fee_Term__c = String.valueOf(setupFeeTerm);
                hasUpdates = true;
            }

            // No-Fee Program
            opp.No_Fee_Program__c = noFeeProgram == true;
            hasUpdates = true;

            // Program Type - convert underscores to spaces and save exactly what user selected
            if (String.isNotBlank(programType)) {
                String programTypeUpper = programType.toUpperCase();
                // Convert underscores to spaces for picklist value
                String picklistValue = programTypeUpper.replace('_', ' ');
                opp.Program_Type__c = picklistValue;
                hasUpdates = true;
            }

            // Settlement percentage picklist - reuses cfg from validation section above
            try {
                // Est_Settlement__c picklist
                if (cfg.settlementPercent != null) {
                    Integer settlementInt = cfg.settlementPercent.intValue();
                    Set<Integer> validSettlementValues = new Set<Integer>();
                    if (String.isNotBlank(cfg.validSettlementValues)) {
                        for (String valStr : cfg.validSettlementValues.split(',')) {
                            validSettlementValues.add(Integer.valueOf(valStr.trim()));
                        }
                    }
                    if (validSettlementValues.contains(settlementInt)) {
                        opp.Est_Settlement__c = String.valueOf(settlementInt) + '%';
                        hasUpdates = true;
                    }
                }

                // Program_Fee__c picklist
                Decimal programFeePct = noFeeProgram ? cfg.baselineNoFeeProgramFee : cfg.programFeePercent;
                if (programFeePct != null) {
                    Decimal minProgramFeePercent = cfg.minProgramFeePercent;
                    Decimal maxProgramFeePercent = cfg.maxProgramFeePercent;
                    if (programFeePct >= minProgramFeePercent && programFeePct <= maxProgramFeePercent) {
                        opp.Program_Fee__c = String.valueOf(programFeePct.intValue()) + '%';
                        hasUpdates = true;
                    }
                }
            } catch (PaymentCalcConfigException e) {
                System.debug('[updateOpportunityOnly] Skipping config-validated fields: ' + e.getMessage());
            }

            if (hasUpdates) {
                Database.update(opp, AccessLevel.SYSTEM_MODE);
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update Opportunity: ' + e.getMessage());
        }
    }

    /**
     * @description Parses a date string in ISO format (YYYY-MM-DD) to a Salesforce Date object.
     * @param dateString The date string to parse (expected format: YYYY-MM-DD)
     * @return The parsed Date object, or null if parsing fails or input is blank
     */
    private static Date parseOpportunityDate(String dateString) {
        if (String.isBlank(dateString)) {
            return null;
        }
        try {
            // Handle ISO format: YYYY-MM-DD
            if (dateString.contains('-')) {
                List<String> parts = dateString.split('-');
                if (parts.size() == 3) {
                    return Date.newInstance(
                        Integer.valueOf(parts[0]),
                        Integer.valueOf(parts[1]),
                        Integer.valueOf(parts[2])
                    );
                }
            }
            // Fallback to valueOf
            return Date.valueOf(dateString);
        } catch (Exception e) {
            System.debug('[parseOpportunityDate] Error parsing date: ' + e.getMessage());
            return null;
        }
    }
}
