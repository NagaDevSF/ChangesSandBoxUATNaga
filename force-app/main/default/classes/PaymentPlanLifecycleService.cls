/**
 * @description Service class handling Payment Plan lifecycle operations.
 *
 * This service manages plan state transitions: suspend, activate, deactivate,
 * reactivate, and manual version creation. It delegates shared calculation
 * helpers to PaymentPlanCalculationService and wrapper construction to
 * PaymentPlanEditorController.
 *
 * LIFECYCLE TRANSITIONS:
 * - Draft → Active (activatePaymentPlan)
 * - Active → Deactivated (deactivatePaymentPlan)
 * - Active → Suspended (suspendPaymentPlan)
 * - Suspended → Active (reactivatePaymentPlan)
 * - Any → Draft clone (createManualVersion)
 *
 * @author DCG Development Team
 * @since 2024-01
 * @see PaymentPlanEditorController
 * @see PaymentPlanCalculationService
 */
public with sharing class PaymentPlanLifecycleService {

    // ==================================================================================
    // CONSTANTS - DEBUG LOGGING PREFIXES
    // ==================================================================================
    private static final String CLASS_NAME = 'PaymentPlanLifecycleService';
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
    // CONSTANTS - PAYMENT SCHEDULE ITEM STATUS VALUES
    // ==================================================================================
    private static final String STATUS_SCHEDULED = 'Scheduled';
    private static final String STATUS_CLEARED = 'Cleared';
    private static final String STATUS_NSF = 'NSF';
    private static final String STATUS_CANCELLED = 'Cancelled';

    // ==================================================================================
    // CONSTANTS - PAYMENT PLAN VERSION STATUS VALUES
    // ==================================================================================
    private static final String VERSION_STATUS_DRAFT = 'Draft';
    private static final String VERSION_STATUS_ACTIVE = 'Active';
    private static final String VERSION_STATUS_ARCHIVED = 'Archived';

    // ==================================================================================
    // CONSTANTS - SOURCE AND VERSION TYPE VALUES
    // ==================================================================================
    private static final String SOURCE_UI = 'UI';
    private static final String VERSION_TYPE_REVISION = 'Revision';
    private static final String VERSION_TYPE_SUSPENSION = 'Suspension';
    private static final String VERSION_TYPE_REACTIVATION = 'Reactivation';
    private static final String STATUS_SUSPENDED = 'Suspended';

    // ==================================================================================
    // CONSTANTS - QUERY AND VALIDATION LIMITS
    // ==================================================================================
    private static final Integer MAX_QUERY_LIMIT = 1000;

    // ==================================================================================
    // CONSTANTS - ERROR MESSAGE SYMBOLS
    // ==================================================================================
    private static final String ERROR_SYMBOL = '⚠️ ';
    private static final String NOT_FOUND_SYMBOL = '🔍 ';
    private static final String VALIDATION_SYMBOL = '❌ ';

    // ==================================================================================
    // PUBLIC SERVICE METHODS - Plan Lifecycle Operations
    // ==================================================================================

    /**
     * @description Suspend a payment plan
     * Creates a new version with Scheduled items changed to Cancelled,
     * activates the new version, and archives the previous plan
     * @param planId The Payment Plan ID
     * @return PaymentPlanWrapper for the new suspended version
     */
    public static PaymentPlanEditorController.PaymentPlanWrapper suspendPaymentPlan(Id planId) {
        String methodName = 'suspendPaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get the current plan with all fields via describe (ensures clone never misses a field)
            String ppFields = PaymentPlanCalculationService.getPaymentPlanQueryFields();
            List<PaymentPlan__c> currentPlans = Database.query(
                'SELECT ' + ppFields + ' FROM PaymentPlan__c WHERE Id = :planId LIMIT 1'
            );

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

            // Archive all other plans for this Opportunity BEFORE inserting the new active plan
            // to avoid the duplicate active Payment Plan trigger validation
            List<PaymentPlan__c> otherPlans = [
                SELECT Id, Status__c, Is_Active__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :currentPlan.Opportunity__c
                LIMIT :MAX_QUERY_LIMIT
            ];
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + otherPlans.size() + ' other plan(s) to archive');

            for (PaymentPlan__c otherPlan : otherPlans) {
                otherPlan.Status__c = VERSION_STATUS_ARCHIVED;
                otherPlan.Is_Active__c = false;
            }

            if (!otherPlans.isEmpty()) {
                update otherPlans;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Archived ' + otherPlans.size() + ' plan(s) and set Status to Draft');
            }

            // Create new plan as a clone with incremented version
            PaymentPlan__c newPlan = currentPlan.clone(false, true, false, false);
            newPlan.Version_Number__c = maxVersion + 1;
            newPlan.Status__c = STATUS_SUSPENDED;
            newPlan.Is_Active__c = true;
            newPlan.Version_Type__c = VERSION_TYPE_SUSPENSION;
            newPlan.Source__c = SOURCE_UI;
            newPlan.Version_Notes__c = 'Plan suspended on ' + DateTime.now().format() + '. Scheduled items cancelled.';
            newPlan.Calculation_Timestamp__c = DateTime.now();
            insert newPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Created suspension plan: ' + newPlan.Id);

            // Get all schedule items from the current plan
            String fields = PaymentPlanCalculationService.getScheduleItemQueryFields();
            String query = 'SELECT ' + fields +
                ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :planId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
            List<Payment_Schedule_Item__c> currentItems = Database.query(query);
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
                PaymentPlanCalculationService.recalculateDraftNumbers(newItems);
                insert newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newItems.size() + ' schedule items');

                // Create Payment_Fee__c records for all new schedule items
                PaymentPlanCalculationService.createFeeRecordsForScheduleItems(newItems);

                // Carry over wire fees (Wire Fee and Wire Received Fee) from old items to new items
                System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Carrying over wire fees...');
                PaymentPlanCalculationService.carryOverWireFees(currentItems, newItems);
            }

            // Update the new plan's item count
            newPlan.Schedule_Item_Count__c = newItems.size();
            update newPlan;

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Plan suspended successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            // Return the new plan with schedule items
            return PaymentPlanEditorController.getPaymentPlanById(newPlan.Id);

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
    public static PaymentPlanEditorController.PaymentPlanWrapper activatePaymentPlan(Id planId) {
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
                SELECT Id, Status__c, Is_Active__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :planToActivate.Opportunity__c
                  AND Id != :planId
                  AND Status__c != :VERSION_STATUS_ARCHIVED
                LIMIT :MAX_QUERY_LIMIT
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + otherPlans.size() + ' other plan(s) to archive');

            for (PaymentPlan__c otherPlan : otherPlans) {
                otherPlan.Status__c = VERSION_STATUS_ARCHIVED;
                otherPlan.Is_Active__c = false;
            }

            if (!otherPlans.isEmpty()) {
                update otherPlans;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Archived ' + otherPlans.size() + ' plan(s) and set Status to Draft');
            }

            // Activate the selected plan
            PaymentPlan__c plan = new PaymentPlan__c(Id = planId);
            plan.Status__c = VERSION_STATUS_ACTIVE;
            plan.Is_Active__c = true;
            plan.Calculation_Timestamp__c = DateTime.now();
            update plan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Activated plan: ' + planId + ' (Status__c set to Active)');

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Plan activated successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return PaymentPlanEditorController.getPaymentPlanById(planId);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error activating payment plan: ' + e.getMessage());
        }
    }

    /**
     * @description Deactivate an active payment plan
     * Sets the plan back to Draft status without creating a new version
     * @param planId The Payment Plan ID
     * @return Updated PaymentPlanWrapper
     */
    public static PaymentPlanEditorController.PaymentPlanWrapper deactivatePaymentPlan(Id planId) {
        String methodName = 'deactivatePaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | planId: ' + planId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (planId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | planId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get the plan to deactivate
            List<PaymentPlan__c> plansToDeactivate = [
                SELECT Id, Opportunity__c, Version_Number__c, Status__c
                FROM PaymentPlan__c
                WHERE Id = :planId
                LIMIT 1
            ];

            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + plansToDeactivate.size() + ' plan(s)');

            if (plansToDeactivate.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Payment Plan not found: ' + planId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c planToDeactivate = plansToDeactivate[0];

            if (planToDeactivate.Status__c != VERSION_STATUS_ACTIVE) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Plan is not active: ' + planId);
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Only active plans can be deactivated.');
            }

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Deactivating plan version: ' + planToDeactivate.Version_Number__c);

            // Set the plan to Deactivated
            PaymentPlan__c plan = new PaymentPlan__c(Id = planId);
            plan.Status__c = 'Deactivated';
            plan.Is_Active__c = false;
            plan.Calculation_Timestamp__c = DateTime.now();
            update plan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Deactivated plan: ' + planId + ' (Status__c set to Deactivated)');

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Plan deactivated successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return PaymentPlanEditorController.getPaymentPlanById(planId);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error deactivating payment plan: ' + e.getMessage());
        }
    }

    /**
     * @description Reactivate a suspended payment plan
     * Sets the plan back to Active and restores future Cancelled items to Scheduled.
     * @param suspendedPlanId The suspended Payment Plan ID
     * @return Updated PaymentPlanWrapper
     */
    public static PaymentPlanEditorController.PaymentPlanWrapper reactivatePaymentPlan(Id suspendedPlanId) {
        String methodName = 'reactivatePaymentPlan';
        System.debug(LoggingLevel.DEBUG, LOG_ENTRY + ' | ' + CLASS_NAME + '.' + methodName);
        System.debug(LoggingLevel.DEBUG, LOG_PARAM + ' | suspendedPlanId: ' + suspendedPlanId);

        Savepoint sp = Database.setSavepoint();
        try {
            if (suspendedPlanId == null) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | suspendedPlanId is null');
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Plan ID is required.');
            }

            // Get the suspended plan
            List<PaymentPlan__c> suspendedPlans = [
                SELECT Id, Name, Opportunity__c, Version_Number__c, Status__c,
                       Is_Active__c, Version_Type__c, Source__c, Version_Notes__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Calculation_Timestamp__c, Schedule_Item_Count__c,
                       Weekly_Payment__c, Monthly_Payment__c, Number_of_Payments__c,
                       Total_Debt__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Total_Program_Cost__c, Settlement_Amount__c, Program_Fee_Amount__c,
                       First_Payment_Date__c, Program_Type__c, Contract__c
                FROM PaymentPlan__c
                WHERE Id = :suspendedPlanId
                LIMIT 1
            ];

            if (suspendedPlans.isEmpty()) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Payment Plan not found: ' + suspendedPlanId);
                throw new AuraHandledException(NOT_FOUND_SYMBOL + 'Payment Plan not found. It may have been deleted.');
            }

            PaymentPlan__c suspendedPlan = suspendedPlans[0];

            // Validate the plan is actually suspended
            if (!STATUS_SUSPENDED.equalsIgnoreCase(suspendedPlan.Status__c)) {
                System.debug(LoggingLevel.WARN, LOG_WARN + ' | ' + methodName + ' | Plan is not suspended: ' + suspendedPlan.Status__c);
                throw new AuraHandledException(VALIDATION_SYMBOL + 'Only suspended plans can be reactivated.');
            }

            System.debug(LoggingLevel.DEBUG, LOG_INFO + ' | ' + methodName + ' | Reactivating plan: ' + suspendedPlan.Name + ' | Version: ' + suspendedPlan.Version_Number__c);

            // Simply set the plan back to Active
            suspendedPlan.Status__c = VERSION_STATUS_ACTIVE;
            suspendedPlan.Is_Active__c = true;
            suspendedPlan.Version_Notes__c = 'Plan reactivated on ' + DateTime.now().format() + '.';
            update suspendedPlan;
            System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Plan status set to Active');

            // Restore future Cancelled items back to Scheduled
            Date today = Date.today();
            List<Payment_Schedule_Item__c> cancelledItems = [
                SELECT Id, Status__c, Payment_Date__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :suspendedPlanId
                  AND Status__c = :STATUS_CANCELLED
                  AND Payment_Date__c > :today
                LIMIT :MAX_QUERY_LIMIT
            ];
            System.debug(LoggingLevel.DEBUG, LOG_QUERY + ' | ' + methodName + ' | Found ' + cancelledItems.size() + ' future cancelled items to restore');

            for (Payment_Schedule_Item__c item : cancelledItems) {
                item.Status__c = STATUS_SCHEDULED;
            }

            if (!cancelledItems.isEmpty()) {
                update cancelledItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Restored ' + cancelledItems.size() + ' items to Scheduled');
            }

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Plan reactivated successfully');
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return PaymentPlanEditorController.getPaymentPlanById(suspendedPlanId);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(ERROR_SYMBOL + 'Error reactivating payment plan: ' + e.getMessage());
        }
    }

    /**
     * @description Create a new manual version of the Payment Plan
     * Clones the current plan and its schedule items
     * @param currentPlanId The current Payment Plan ID to clone
     * @return PaymentPlanWrapper for the new version
     */
    public static PaymentPlanEditorController.PaymentPlanWrapper createManualVersion(Id currentPlanId) {
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
                       Version_Number__c, Is_Active__c,
                       Banking_Fee__c, Bank2_Fee__c, Setup_Fee__c, Setup_Fee_Payments__c,
                       Current_Payment__c, No_Fee_Program__c, Preferred_Day_of_Week__c,
                       Schedule_Item_Count__c,
                       Target_Payment_Percent__c, Calculation_Mode__c, Payment_Frequency__c,
                       Total_Savings__c, Total_Banking_Fee__c
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
            newPlan.Status__c = VERSION_STATUS_DRAFT;
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
            String fields = PaymentPlanCalculationService.getScheduleItemQueryFields();
            String query = 'SELECT ' + fields +
                ' FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :currentPlanId ORDER BY Payment_Number__c ASC LIMIT ' + MAX_QUERY_LIMIT;
            List<Payment_Schedule_Item__c> currentItems = Database.query(query);

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
                PaymentPlanCalculationService.recalculateDraftNumbers(newItems);
                insert newItems;
                System.debug(LoggingLevel.DEBUG, LOG_DML + ' | ' + methodName + ' | Inserted ' + newItems.size() + ' schedule items');
            }

            System.debug(LoggingLevel.DEBUG, LOG_SUCCESS + ' | ' + methodName + ' | Manual version created successfully: ' + newPlan.Id);
            System.debug(LoggingLevel.DEBUG, LOG_EXIT + ' | ' + CLASS_NAME + '.' + methodName + ' | SUCCESS');
            return PaymentPlanEditorController.getPaymentPlanById(newPlan.Id);

        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Exception: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Stack Trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, LOG_ERROR + ' | ' + methodName + ' | Rolling back transaction');
            throw new AuraHandledException(ERROR_SYMBOL + 'Error creating manual version: ' + e.getMessage());
        }
    }
}