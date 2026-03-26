/**
 * @description Controller for bulk Payment File Upload feature.
 *
 * Parses payment wire data uploaded from an Excel file, validates each row
 * against Salesforce Opportunities (via EPPS_ID__c), and creates
 * Payment_Schedule_Item__c and Payment_Fee__c records on the active
 * PaymentPlan__c for each matched Opportunity.
 *
 * KEY FEATURES:
 * - Two-phase workflow: validate first, then create records
 * - Bulk-safe: single SOQL queries for all rows, Database.insert with partial success
 * - Capped at 2000 rows per upload to stay within governor limits
 * - Uses PaymentFeeService for fee record creation
 *
 * RELATED OBJECTS:
 * - Opportunity: matched by EPPS_ID__c
 * - PaymentPlan__c: active plan for each matched Opportunity
 * - Payment_Schedule_Item__c: created for each valid upload row
 * - Payment_Fee__c: Banking, Program, and Setup fees per schedule item
 *
 * @author DCG Development Team
 * @since 2026-03
 * @see PaymentFeeService
 */
public with sharing class PaymentFileUploadController {

    // ==================================================================================
    // CONSTANTS
    // ==================================================================================
    private static final String LOG_PREFIX = '[PaymentFileUploadController]';
    private static final Integer MAX_UPLOAD_ROWS = 2000;
    private static final String DEFAULT_ITEM_STATUS = 'Wire';
    private static final Decimal DEFAULT_BANKING_FEE = 15.00;

    // ==================================================================================
    // WRAPPER CLASSES
    // ==================================================================================

    /**
     * @description Wrapper class representing a single row from the uploaded file.
     * Deserialized from JSON sent by the LWC front-end.
     */
    public class UploadRow {
        @AuraEnabled public String eppsId;
        @AuraEnabled public String clientName;
        @AuraEnabled public String bankName;
        @AuraEnabled public String paymentDate; // ISO date string (yyyy-MM-dd)
        @AuraEnabled public Decimal wireAmount;
        @AuraEnabled public Decimal eppsAmount;
        @AuraEnabled public Decimal commissionAmount;
        @AuraEnabled public Decimal setupFee;
        @AuraEnabled public String notes;
    }

    /**
     * @description Validation result for a single uploaded row.
     * Returned by validateUploadedRecords so the UI can display
     * match status before the user confirms creation.
     */
    public class ValidationResult {
        @AuraEnabled public Integer rowIndex;
        @AuraEnabled public String eppsId;
        @AuraEnabled public String clientName;
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public Id paymentPlanId;
        @AuraEnabled public String paymentPlanName;
    }

    /**
     * @description Creation result for a single uploaded row.
     * Indicates whether the Payment_Schedule_Item__c was created successfully.
     */
    public class CreationResult {
        @AuraEnabled public Integer rowIndex;
        @AuraEnabled public String eppsId;
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Id scheduleItemId;
    }

    /**
     * @description Overall processing result returned by createScheduleItemsFromUpload.
     * Provides summary counts and per-row detail.
     */
    public class ProcessingResult {
        @AuraEnabled public Integer totalRows;
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public List<CreationResult> results;
    }

    // ==================================================================================
    // PUBLIC METHODS
    // ==================================================================================

    /**
     * @description Validate uploaded rows against Salesforce data without creating records.
     * For each row, checks that:
     *   1. The EPPS ID is not blank
     *   2. An Opportunity with that EPPS_ID__c exists
     *   3. The matched Opportunity has an active PaymentPlan__c
     *
     * @param jsonPayload JSON string representing List<UploadRow>
     * @return List<ValidationResult> one result per input row
     */
    @AuraEnabled
    public static List<ValidationResult> validateUploadedRecords(String jsonPayload) {
        List<ValidationResult> validationResults = new List<ValidationResult>();

        // Deserialize
        List<UploadRow> rows = deserializeRows(jsonPayload);
        if (rows.isEmpty()) {
            return validationResults;
        }

        // Enforce row cap
        if (rows.size() > MAX_UPLOAD_ROWS) {
            throw new AuraHandledException(
                'Upload exceeds the maximum of ' + MAX_UPLOAD_ROWS + ' rows. ' +
                'Please reduce the file size and try again.'
            );
        }

        // Collect unique EPPS IDs (skip blanks)
        Set<String> eppsIds = collectEppsIds(rows);

        // Query Opportunities by EPPS_ID__c
        Map<String, Opportunity> oppByEppsId = queryOpportunitiesByEppsId(eppsIds);

        // Collect matched Opportunity Ids to query active plans
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : oppByEppsId.values()) {
            oppIds.add(opp.Id);
        }

        // Query active PaymentPlan__c records for matched Opportunities
        Map<Id, PaymentPlan__c> planByOppId = queryActivePlansByOpportunityIds(oppIds);

        // Build validation results
        for (Integer i = 0; i < rows.size(); i++) {
            UploadRow row = rows[i];
            ValidationResult vr = new ValidationResult();
            vr.rowIndex = i;
            vr.eppsId = row.eppsId;
            vr.clientName = row.clientName;

            if (String.isBlank(row.eppsId)) {
                vr.isValid = false;
                vr.errorMessage = 'EPPS ID is blank.';
                validationResults.add(vr);
                continue;
            }

            String normalizedId = row.eppsId.trim();

            // Check Opportunity match
            Opportunity opp = oppByEppsId.get(normalizedId);
            if (opp == null) {
                vr.isValid = false;
                vr.errorMessage = 'No Opportunity found with EPPS ID "' + normalizedId + '".';
                validationResults.add(vr);
                continue;
            }

            vr.opportunityId = opp.Id;
            vr.opportunityName = opp.Name;

            // Check active Payment Plan
            PaymentPlan__c plan = planByOppId.get(opp.Id);
            if (plan == null) {
                vr.isValid = false;
                vr.errorMessage = 'No active Payment Plan found for Opportunity "' + opp.Name + '".';
                validationResults.add(vr);
                continue;
            }

            vr.paymentPlanId = plan.Id;
            vr.paymentPlanName = plan.Name;
            vr.isValid = true;
            validationResults.add(vr);
        }

        return validationResults;
    }

    /**
     * @description Create Payment_Schedule_Item__c and Payment_Fee__c records for valid rows.
     * Re-validates server-side (never trust client validation alone), then bulk-inserts
     * schedule items with partial success, followed by fee records for successfully
     * inserted items.
     *
     * @param jsonPayload JSON string representing List<UploadRow>
     * @return ProcessingResult with per-row status and summary counts
     */
    @AuraEnabled
    public static ProcessingResult createScheduleItemsFromUpload(String jsonPayload) {
        ProcessingResult processingResult = new ProcessingResult();
        processingResult.results = new List<CreationResult>();

        // Deserialize
        List<UploadRow> rows = deserializeRows(jsonPayload);

        processingResult.totalRows = rows.size();
        processingResult.successCount = 0;
        processingResult.failureCount = 0;

        if (rows.isEmpty()) {
            return processingResult;
        }

        // Enforce row cap
        if (rows.size() > MAX_UPLOAD_ROWS) {
            throw new AuraHandledException(
                'Upload exceeds the maximum of ' + MAX_UPLOAD_ROWS + ' rows. ' +
                'Please reduce the file size and try again.'
            );
        }

        // Collect EPPS IDs
        Set<String> eppsIds = collectEppsIds(rows);

        // Query Opportunities
        Map<String, Opportunity> oppByEppsId = queryOpportunitiesByEppsId(eppsIds);

        // Collect Opportunity Ids
        Set<Id> oppIds = new Set<Id>();
        for (Opportunity opp : oppByEppsId.values()) {
            oppIds.add(opp.Id);
        }

        // Query active Payment Plans (include Banking_Fee__c for fee creation)
        Map<Id, PaymentPlan__c> planByOppId = queryActivePlansByOpportunityIds(oppIds);

        // Collect plan Ids for max Payment_Number__c query
        Set<Id> planIds = new Set<Id>();
        for (PaymentPlan__c plan : planByOppId.values()) {
            planIds.add(plan.Id);
        }

        // Query max Payment_Number__c per plan in bulk
        Map<Id, Decimal> maxPaymentNumByPlanId = queryMaxPaymentNumbers(planIds);

        // Track next payment number per plan (handles multiple rows for same plan)
        Map<Id, Decimal> nextPaymentNumByPlanId = new Map<Id, Decimal>();
        for (Id planId : planIds) {
            Decimal maxNum = maxPaymentNumByPlanId.get(planId);
            nextPaymentNumByPlanId.put(planId, maxNum != null ? maxNum + 1 : 1);
        }

        // Build schedule items and track row-to-item mapping
        List<Payment_Schedule_Item__c> itemsToInsert = new List<Payment_Schedule_Item__c>();
        // Parallel list: index in itemsToInsert -> index in rows
        List<Integer> itemRowIndices = new List<Integer>();
        // Parallel list: index in itemsToInsert -> the UploadRow (for fee amounts)
        List<UploadRow> itemUploadRows = new List<UploadRow>();
        // Parallel list: index in itemsToInsert -> active plan (for banking fee)
        List<PaymentPlan__c> itemPlans = new List<PaymentPlan__c>();

        // Pre-populate creation results for all rows; mark invalid ones immediately
        List<CreationResult> allResults = new List<CreationResult>();
        for (Integer i = 0; i < rows.size(); i++) {
            allResults.add(null); // placeholder
        }

        for (Integer i = 0; i < rows.size(); i++) {
            UploadRow row = rows[i];
            CreationResult cr = new CreationResult();
            cr.rowIndex = i;
            cr.eppsId = row.eppsId;

            // Validate EPPS ID
            if (String.isBlank(row.eppsId)) {
                cr.isSuccess = false;
                cr.errorMessage = 'EPPS ID is blank.';
                allResults[i] = cr;
                processingResult.failureCount++;
                continue;
            }

            String normalizedId = row.eppsId.trim();

            // Find Opportunity
            Opportunity opp = oppByEppsId.get(normalizedId);
            if (opp == null) {
                cr.isSuccess = false;
                cr.errorMessage = 'No Opportunity found with EPPS ID "' + normalizedId + '".';
                allResults[i] = cr;
                processingResult.failureCount++;
                continue;
            }

            // Find active plan
            PaymentPlan__c plan = planByOppId.get(opp.Id);
            if (plan == null) {
                cr.isSuccess = false;
                cr.errorMessage = 'No active Payment Plan found for Opportunity "' + opp.Name + '".';
                allResults[i] = cr;
                processingResult.failureCount++;
                continue;
            }

            // Parse payment date
            Date paymentDate;
            try {
                paymentDate = parseDate(row.paymentDate);
            } catch (Exception e) {
                cr.isSuccess = false;
                cr.errorMessage = 'Invalid payment date: "' + row.paymentDate + '". Expected format: yyyy-MM-dd.';
                allResults[i] = cr;
                processingResult.failureCount++;
                continue;
            }

            // Get next payment number for this plan
            Decimal nextNum = nextPaymentNumByPlanId.get(plan.Id);
            nextPaymentNumByPlanId.put(plan.Id, nextNum + 1);

            // Build Payment_Schedule_Item__c
            Payment_Schedule_Item__c psi = new Payment_Schedule_Item__c();
            psi.Payment_Plan__c = plan.Id;
            psi.Payment_Date__c = paymentDate;
            psi.Total_Payment__c = row.wireAmount != null ? row.wireAmount : 0;
            psi.To_Escrow_Amount__c = row.eppsAmount != null ? row.eppsAmount : 0;
            psi.Program_Fee_Amount__c = row.commissionAmount != null ? row.commissionAmount : 0;
            psi.Setup_Fee_Amount__c = row.setupFee != null ? row.setupFee : 0;
            psi.Banking_Fee_Amount__c = plan.Banking_Fee__c != null ? plan.Banking_Fee__c : DEFAULT_BANKING_FEE;
            psi.Status__c = DEFAULT_ITEM_STATUS;
            psi.Payment_Number__c = nextNum;

            itemsToInsert.add(psi);
            itemRowIndices.add(i);
            itemUploadRows.add(row);
            itemPlans.add(plan);

            // Placeholder result — will be updated after insert
            allResults[i] = cr;
        }

        // Bulk insert with partial success
        if (!itemsToInsert.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.insert(itemsToInsert, false);

            // Collect successfully inserted items for fee creation
            List<Payment_Schedule_Item__c> successItems = new List<Payment_Schedule_Item__c>();
            List<UploadRow> successRows = new List<UploadRow>();
            List<PaymentPlan__c> successPlans = new List<PaymentPlan__c>();

            for (Integer j = 0; j < saveResults.size(); j++) {
                Database.SaveResult sr = saveResults[j];
                Integer rowIdx = itemRowIndices[j];
                CreationResult cr = allResults[rowIdx];

                if (sr.isSuccess()) {
                    cr.isSuccess = true;
                    cr.scheduleItemId = sr.getId();
                    processingResult.successCount++;

                    successItems.add(itemsToInsert[j]);
                    successRows.add(itemUploadRows[j]);
                    successPlans.add(itemPlans[j]);
                } else {
                    cr.isSuccess = false;
                    cr.errorMessage = buildErrorMessage(sr.getErrors());
                    processingResult.failureCount++;
                }
            }

            // Create fee records for successfully inserted items
            if (!successItems.isEmpty()) {
                createFeeRecords(successItems, successRows, successPlans);
            }
        }

        processingResult.results = allResults;
        return processingResult;
    }

    // ==================================================================================
    // PRIVATE HELPER METHODS
    // ==================================================================================

    /**
     * @description Deserialize JSON payload into a list of UploadRow.
     * @param jsonPayload JSON string
     * @return List<UploadRow>
     */
    private static List<UploadRow> deserializeRows(String jsonPayload) {
        if (String.isBlank(jsonPayload)) {
            return new List<UploadRow>();
        }
        try {
            return (List<UploadRow>) JSON.deserialize(jsonPayload, List<UploadRow>.class);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Failed to parse upload data: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Collect unique, non-blank EPPS IDs from a list of rows.
     * @param rows List of UploadRow
     * @return Set<String> of trimmed EPPS IDs
     */
    private static Set<String> collectEppsIds(List<UploadRow> rows) {
        Set<String> eppsIds = new Set<String>();
        for (UploadRow row : rows) {
            if (String.isNotBlank(row.eppsId)) {
                eppsIds.add(row.eppsId.trim());
            }
        }
        return eppsIds;
    }

    /**
     * @description Query Opportunities by EPPS_ID__c and return a map keyed by EPPS_ID__c.
     * @param eppsIds Set of EPPS ID strings
     * @return Map<String, Opportunity> keyed by EPPS_ID__c
     */
    private static Map<String, Opportunity> queryOpportunitiesByEppsId(Set<String> eppsIds) {
        Map<String, Opportunity> oppMap = new Map<String, Opportunity>();
        if (eppsIds.isEmpty()) {
            return oppMap;
        }

        List<Opportunity> opps = [
            SELECT Id, Name, EPPS_ID__c
            FROM Opportunity
            WHERE EPPS_ID__c IN :eppsIds
        ];

        for (Opportunity opp : opps) {
            // If duplicate EPPS IDs exist across Opportunities, first match wins
            if (!oppMap.containsKey(opp.EPPS_ID__c)) {
                oppMap.put(opp.EPPS_ID__c, opp);
            }
        }

        return oppMap;
    }

    /**
     * @description Query active PaymentPlan__c records for a set of Opportunity Ids.
     * Returns one plan per Opportunity (the active one). Includes Banking_Fee__c
     * for fee record creation.
     *
     * @param oppIds Set of Opportunity Ids
     * @return Map<Id, PaymentPlan__c> keyed by Opportunity__c
     */
    private static Map<Id, PaymentPlan__c> queryActivePlansByOpportunityIds(Set<Id> oppIds) {
        Map<Id, PaymentPlan__c> planMap = new Map<Id, PaymentPlan__c>();
        if (oppIds.isEmpty()) {
            return planMap;
        }

        List<PaymentPlan__c> plans = [
            SELECT Id, Name, Opportunity__c, Banking_Fee__c
            FROM PaymentPlan__c
            WHERE Opportunity__c IN :oppIds
              AND Status__c = 'Active'
        ];

        for (PaymentPlan__c plan : plans) {
            // One active plan per Opportunity; first match wins if data is inconsistent
            if (!planMap.containsKey(plan.Opportunity__c)) {
                planMap.put(plan.Opportunity__c, plan);
            }
        }

        return planMap;
    }

    /**
     * @description Query the maximum Payment_Number__c per PaymentPlan__c in bulk.
     * @param planIds Set of PaymentPlan__c Ids
     * @return Map<Id, Decimal> keyed by Payment_Plan__c Id, value is max Payment_Number__c
     */
    private static Map<Id, Decimal> queryMaxPaymentNumbers(Set<Id> planIds) {
        Map<Id, Decimal> maxNumMap = new Map<Id, Decimal>();
        if (planIds.isEmpty()) {
            return maxNumMap;
        }

        for (AggregateResult ar : [
            SELECT Payment_Plan__c planId, MAX(Payment_Number__c) maxNum
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c IN :planIds
            GROUP BY Payment_Plan__c
        ]) {
            Id planId = (Id) ar.get('planId');
            Decimal maxNum = (Decimal) ar.get('maxNum');
            maxNumMap.put(planId, maxNum);
        }

        return maxNumMap;
    }

    /**
     * @description Parse an ISO date string (yyyy-MM-dd) into a Date.
     * @param dateStr The date string to parse
     * @return Date
     */
    private static Date parseDate(String dateStr) {
        if (String.isBlank(dateStr)) {
            throw new IllegalArgumentException('Date string is blank.');
        }
        return Date.valueOf(dateStr.trim());
    }

    /**
     * @description Create Payment_Fee__c records (Banking, Program, Setup) for successfully
     * inserted Payment_Schedule_Item__c records using PaymentFeeService.
     *
     * @param items Successfully inserted Payment_Schedule_Item__c records (with Ids)
     * @param uploadRows Corresponding UploadRow data (for commission/setup fee amounts)
     * @param plans Corresponding active PaymentPlan__c records (for banking fee)
     */
    private static void createFeeRecords(
        List<Payment_Schedule_Item__c> items,
        List<UploadRow> uploadRows,
        List<PaymentPlan__c> plans
    ) {
        List<Payment_Fee__c> allFees = new List<Payment_Fee__c>();

        for (Integer i = 0; i < items.size(); i++) {
            Payment_Schedule_Item__c psi = items[i];
            UploadRow row = uploadRows[i];
            PaymentPlan__c plan = plans[i];

            Decimal bankingFee = plan.Banking_Fee__c != null ? plan.Banking_Fee__c : DEFAULT_BANKING_FEE;
            Decimal programFee = row.commissionAmount != null ? row.commissionAmount : 0;
            Decimal setupFeeAmt = row.setupFee != null ? row.setupFee : 0;

            List<Payment_Fee__c> fees = PaymentFeeService.createFeeRecordsForItem(
                psi, bankingFee, programFee, setupFeeAmt
            );
            allFees.addAll(fees);
        }

        if (!allFees.isEmpty()) {
            Database.SaveResult[] feeResults = Database.insert(allFees, false);
            Integer feeSuccessCount = 0;
            Integer feeFailCount = 0;
            for (Database.SaveResult sr : feeResults) {
                if (sr.isSuccess()) {
                    feeSuccessCount++;
                } else {
                    feeFailCount++;
                    System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ❌ Fee insert failed: ' + buildErrorMessage(sr.getErrors()));
                }
            }
            System.debug(LOG_PREFIX + ' Fee records — Success: ' + feeSuccessCount + ' | Failed: ' + feeFailCount + ' / Total: ' + allFees.size());
            if (feeFailCount > 0) {
                System.debug(LoggingLevel.WARN, LOG_PREFIX + ' ⚠️ ' + feeFailCount + ' fee record(s) failed to insert. Schedule items were created but associated fees are missing.');
            }
        }
    }

    /**
     * @description Build a user-friendly error message from Database.Error list.
     * @param errors List of Database.Error from a failed SaveResult
     * @return Concatenated error message string
     */
    private static String buildErrorMessage(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error err : errors) {
            messages.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(messages, '; ');
    }
}
