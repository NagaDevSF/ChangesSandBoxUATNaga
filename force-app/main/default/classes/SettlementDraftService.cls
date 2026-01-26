/**
 * @description Service class for Settlement Plan Draft operations.
 *              Handles CRUD operations, calculation preview, balance recalculation,
 *              and activation of drafts.
 *
 *              REFACTORED: January 2026 - Data Model Refactor
 *              - Removed JSON storage (Segments_JSON__c, Payment_Items_JSON__c)
 *              - Now uses real Settlement_Segment__c and Settlement_Plan_Item__c records
 *
 *              DATA MODEL:
 *              CreditorOpportunity__c
 *              └── Settlement_Plan_Draft__c (Master-Detail)
 *                  ├── Settlement_Segment__c (Master-Detail to Draft)
 *                  └── Settlement_Plan_Item__c (Master-Detail to Draft, Lookup to Segment)
 *
 * @author Settlement Calculator Team
 * @date January 2026
 *
 * ============================================================================
 * KEY FEATURES:
 * ============================================================================
 * - Draft management (create, save, clone, delete)
 * - Preview calculation without saving to real records
 * - Manual edit support with balance recalculation
 * - Activation to set draft as Active
 * - Only one Active draft per CreditorOpportunity
 * ============================================================================
 */
public with sharing class SettlementDraftService {

    // Status constants
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_ACTIVE = 'Active';
    public static final String STATUS_SUSPENDED = 'Suspended';
    public static final String STATUS_APPLIED = 'Applied';
    public static final String STATUS_ARCHIVED = 'Archived';

    // Item status resolution (picklist-driven)
    @TestVisible private static Map<String, String> itemStatusValueByLabelLower;

    private static Map<String, String> getItemStatusMap() {
        if (itemStatusValueByLabelLower != null) {
            return itemStatusValueByLabelLower;
        }
        itemStatusValueByLabelLower = new Map<String, String>();
        for (Schema.PicklistEntry entry :
            Schema.SObjectType.Settlement_Plan_Item__c.fields.Status__c.getPicklistValues()
        ) {
            if (entry == null) continue;
            if (String.isNotBlank(entry.getLabel())) {
                itemStatusValueByLabelLower.put(entry.getLabel().toLowerCase(), entry.getValue());
            }
            if (String.isNotBlank(entry.getValue())) {
                itemStatusValueByLabelLower.put(entry.getValue().toLowerCase(), entry.getValue());
            }
        }
        return itemStatusValueByLabelLower;
    }

    @TestVisible
    private static String resolveItemStatusValue(String labelOrValue, String fallbackLabelOrValue) {
        if (String.isBlank(labelOrValue) && String.isBlank(fallbackLabelOrValue)) {
            return null;
        }
        Map<String, String> statusMap = getItemStatusMap();
        if (String.isNotBlank(labelOrValue)) {
            String key = labelOrValue.toLowerCase();
            if (statusMap.containsKey(key)) {
                return statusMap.get(key);
            }
        }
        if (String.isNotBlank(fallbackLabelOrValue)) {
            String key = fallbackLabelOrValue.toLowerCase();
            if (statusMap.containsKey(key)) {
                return statusMap.get(key);
            }
        }
        return String.isNotBlank(labelOrValue) ? labelOrValue : fallbackLabelOrValue;
    }

    private static String getScheduledStatus() {
        return resolveItemStatusValue('Scheduled', null);
    }

    private static String getClearedStatus() {
        return resolveItemStatusValue('Cleared', 'Paid');
    }

    private static String getProcessingStatus() {
        return resolveItemStatusValue('Processing', null);
    }

    private static String getSuspendedStatus() {
        return resolveItemStatusValue('Suspended', null);
    }

    private static String getVoidStatus() {
        return resolveItemStatusValue('Void', null);
    }

    private static Boolean isScheduledStatus(String status) {
        String scheduled = getScheduledStatus();
        if (String.isBlank(status) || String.isBlank(scheduled)) {
            return false;
        }
        return status.equalsIgnoreCase(scheduled);
    }

    private static Boolean isPaidStatus(String status) {
        if (String.isBlank(status)) {
            return false;
        }
        String cleared = getClearedStatus();
        String processing = getProcessingStatus();
        if (String.isNotBlank(cleared) && status.equalsIgnoreCase(cleared)) {
            return true;
        }
        if (String.isNotBlank(processing) && status.equalsIgnoreCase(processing)) {
            return true;
        }
        return false;
    }

    // Tolerance constants (fallback when config is null)
    public static final Decimal DEFAULT_FULLY_FUNDED_TOLERANCE = 0.01;
    public static final Decimal DEFAULT_BALANCE_CHECK_TOLERANCE = 0.10;

    // Valid segment types
    private static final Set<String> VALID_SEGMENT_TYPES = new Set<String>{'Fixed', 'Remainder', 'SolveAmount'};

    /**
     * @description Get the effective settlement amount (revised if set, otherwise original)
     * @param draft The settlement plan draft
     * @return The effective settlement amount to use for calculations
     */
    private static Decimal getEffectiveSettlementAmount(Settlement_Plan_Draft__c draft) {
        if (draft.Revised_Settlement_Amount__c != null) {
            return draft.Revised_Settlement_Amount__c;
        }
        return draft.Settlement_Offer_Amount__c != null ? draft.Settlement_Offer_Amount__c : 0;
    }

    // Configuration from Custom Metadata (loaded once, cached)
    private static Settlement_Calc_Config__mdt configCache;

    // ============ WRAPPER CLASSES ============

    /**
     * @description Wrapper containing draft record with related segment and item records
     */
    public class DraftWrapper {
        @AuraEnabled public Settlement_Plan_Draft__c draft;
        @AuraEnabled public List<Settlement_Segment__c> segments;
        @AuraEnabled public List<Settlement_Plan_Item__c> paymentItems;
        @AuraEnabled public CreditorOpportunity__c creditorOpportunity;

        public DraftWrapper() {
            this.segments = new List<Settlement_Segment__c>();
            this.paymentItems = new List<Settlement_Plan_Item__c>();
        }
    }

    /**
     * @description Result wrapper for draft calculation
     */
    public class DraftCalculationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public List<Settlement_Plan_Item__c> paymentItems;
        @AuraEnabled public Decimal totalScheduledAmount;
        @AuraEnabled public Decimal fundingDifference;
        @AuraEnabled public Integer numberOfPayments;
        @AuraEnabled public Integer escrowShortageCount;
        @AuraEnabled public Date firstPaymentDate;
        @AuraEnabled public Date finalPaymentDate;
        @AuraEnabled public Integer settlementTermWeeks;

        public DraftCalculationResult() {
            this.success = false;
            this.paymentItems = new List<Settlement_Plan_Item__c>();
            this.totalScheduledAmount = 0;
            this.fundingDifference = 0;
            this.numberOfPayments = 0;
            this.escrowShortageCount = 0;
        }
    }

    /**
     * @description Result wrapper for balance recalculation after manual edit
     */
    public class RecalculationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public List<Settlement_Plan_Item__c> paymentItems;
        @AuraEnabled public Decimal totalScheduledAmount;
        @AuraEnabled public Decimal fundingDifference;
        @AuraEnabled public Boolean isBalanced;
        @AuraEnabled public String warningMessage;

        public RecalculationResult() {
            this.success = false;
            this.paymentItems = new List<Settlement_Plan_Item__c>();
            this.totalScheduledAmount = 0;
            this.fundingDifference = 0;
            this.isBalanced = false;
        }
    }

    /**
     * @description Result wrapper for draft activation
     */
    public class ActivationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Integer segmentCount;
        @AuraEnabled public Integer paymentItemCount;
        @AuraEnabled public Id activatedDraftId;

        public ActivationResult() {
            this.success = false;
            this.segmentCount = 0;
            this.paymentItemCount = 0;
        }
    }

    // ============ CONFIGURATION METHODS ============

    /**
     * @description Load configuration from Custom Metadata (cached)
     *              Public to allow controller to access fee values for Add Row
     */
    public static Settlement_Calc_Config__mdt getConfig() {
        if (configCache == null) {
            List<Settlement_Calc_Config__mdt> configs = [
                SELECT
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
            configCache = configs[0];
        }
        return configCache;
    }

    // ============ DRAFT VALIDATION HELPERS ============

    /**
     * @description Get draft by ID with validation that it exists.
     *              Centralizes draft lookup to reduce code duplication.
     *              Callers should add their own status validation with operation-specific messages.
     * @param draftId The draft record ID
     * @param operationName Name of operation for error message (e.g., "save operation", "deletion", "suspension")
     * @return The draft record
     * @throws SettlementCalculatorException if draftId is null or draft not found
     */
    private static Settlement_Plan_Draft__c getDraftById(Id draftId, String operationName) {
        if (draftId == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Draft ID is required for ' + operationName + '.'
            );
        }

        List<Settlement_Plan_Draft__c> drafts = [
            SELECT Id, Name, CreditorOpportunity__c, Status__c, Balance__c,
                   Settlement_Offer_Amount__c, Revised_Settlement_Amount__c, Escrow_Start_Balance__c, Commission_Fee__c,
                   Number_of_Payments__c, Is_Manually_Modified__c, Applied_Date__c, Cloned_From__c
            FROM Settlement_Plan_Draft__c
            WHERE Id = :draftId
            LIMIT 1
        ];

        if (drafts.isEmpty()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Draft not found.'
            );
        }

        return drafts[0];
    }

    /**
     * @description Check if draft status allows editing.
     *              Only Draft status can be edited.
     * @param draft The draft to check
     * @throws SettlementCalculatorException if draft cannot be edited
     */
    private static void requireEditableStatus(Settlement_Plan_Draft__c draft) {
        if (draft.Status__c != STATUS_DRAFT) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Cannot edit an ' + draft.Status__c + ' draft. Update it to make changes.'
            );
        }
    }

    /**
     * @description Lightweight draft lookup for calculations - only draft + segments.
     *              Avoids querying payment items and CreditorOpportunity when not needed.
     *              Use this for calculateDraftPlan where we only need draft fields and segments.
     * @param draftId The draft record ID
     * @return DraftWrapper with draft and segments only (paymentItems will be empty)
     */
    private static DraftWrapper getDraftWithSegments(Id draftId) {
        DraftWrapper wrapper = new DraftWrapper();

        if (draftId == null) {
            return wrapper;
        }

        List<Settlement_Plan_Draft__c> drafts = [
            SELECT Id, Name, CreditorOpportunity__c, Status__c, Balance__c,
                   Settlement_Offer_Amount__c, Revised_Settlement_Amount__c, Escrow_Start_Balance__c, Commission_Fee__c,
                   Number_of_Payments__c, Is_Manually_Modified__c, Applied_Date__c, Cloned_From__c,
                   CreatedDate, LastModifiedDate
            FROM Settlement_Plan_Draft__c
            WHERE Id = :draftId
            LIMIT 1
        ];

        if (drafts.isEmpty()) {
            return wrapper;
        }

        wrapper.draft = drafts[0];

        // Query related segments only (no items, no CreditorOpportunity)
        wrapper.segments = [
            SELECT Id, Name, Settlement_Plan__c, Segment_Order__c, Segment_Type__c,
                   Payment_Amount__c, Payment_Count__c, Frequency__c, Start_Date__c,
                   End_Date__c, Calculated_Count__c, Calculated_Amount__c, Segment_Note__c,
                   Is_First_Segment__c, Continues_From_Previous__c, Segment_Total__c
            FROM Settlement_Segment__c
            WHERE Settlement_Plan__c = :draftId
            ORDER BY Segment_Order__c ASC
        ];

        return wrapper;
    }

    /**
     * @description Build a list of cloneable field API names (createable + non-formula).
     *              Excludes Id and any fields in the exclude set.
     */
    private static List<String> getCloneableFieldNames(
        Schema.DescribeSObjectResult describeResult,
        Set<String> excludeFields
    ) {
        // Normalize exclude set to lowercase (field API names from describe are lowercase)
        Set<String> excludeLower = new Set<String>();
        if (excludeFields != null) {
            for (String f : excludeFields) {
                excludeLower.add(f.toLowerCase());
            }
        }
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        List<String> fieldNames = new List<String>();
        for (String fieldName : fieldMap.keySet()) {
            if (excludeLower.contains(fieldName)) {
                continue;
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            if (fieldDescribe.isCalculated()) {
                continue;
            }
            if (!fieldDescribe.isCreateable()) {
                continue;
            }
            fieldNames.add(fieldName);
        }
        fieldNames.sort();
        return fieldNames;
    }

    /**
     * @description Copy fields from source to target using a provided field list.
     */
    private static void copyFieldValues(SObject source, SObject target, List<String> fieldNames) {
        if (source == null || target == null || fieldNames == null) {
            return;
        }
        for (String fieldName : fieldNames) {
            target.put(fieldName, source.get(fieldName));
        }
    }

    // ============ CRUD METHODS ============

    /**
     * @description Get all drafts for a CreditorOpportunity
     * @param creditorOpportunityId The parent CreditorOpp ID
     * @return List of drafts ordered by Status (Active first), then LastModifiedDate
     */
    public static List<Settlement_Plan_Draft__c> getDrafts(Id creditorOpportunityId) {
        if (creditorOpportunityId == null) {
            return new List<Settlement_Plan_Draft__c>();
        }

        return [
            SELECT Id,
                   Name,
                   CreditorOpportunity__c,
                   Status__c,
                   Balance__c,
                   Settlement_Offer_Amount__c,
                   Revised_Settlement_Amount__c,
                   Escrow_Start_Balance__c,
                   Number_of_Payments__c,
                   Is_Manually_Modified__c,
                   Applied_Date__c,
                   Cloned_From__c,
                   CreatedBy.Name,
                   CreatedDate,
                   LastModifiedDate
            FROM Settlement_Plan_Draft__c
            WHERE CreditorOpportunity__c = :creditorOpportunityId
            ORDER BY Status__c ASC, LastModifiedDate DESC
        ];
    }

    /**
     * @description Get a single draft with related segment and item records
     * @param draftId The draft record ID
     * @return DraftWrapper containing draft record + related segments/items
     */
    public static DraftWrapper getDraftWithDetails(Id draftId) {
        DraftWrapper wrapper = new DraftWrapper();

        if (draftId == null) {
            return wrapper;
        }

        List<Settlement_Plan_Draft__c> drafts = [
            SELECT Id,
                   Name,
                   CreditorOpportunity__c,
                   Status__c,
                   Balance__c,
                   Settlement_Offer_Amount__c,
                   Revised_Settlement_Amount__c,
                   Escrow_Start_Balance__c,
                   Commission_Fee__c,
                   Number_of_Payments__c,
                   Is_Manually_Modified__c,
                   Applied_Date__c,
                   Cloned_From__c,
                   Settlement_Memo__c,
                   Contract_File_ID__c,
                   CreatedBy.Name,
                   CreatedDate,
                   LastModifiedDate
            FROM Settlement_Plan_Draft__c
            WHERE Id = :draftId
            LIMIT 1
        ];

        if (drafts.isEmpty()) {
            return wrapper;
        }

        wrapper.draft = drafts[0];

        // Query related segments
        wrapper.segments = [
            SELECT Id,
                   Name,
                   Settlement_Plan__c,
                   Segment_Order__c,
                   Segment_Type__c,
                   Payment_Amount__c,
                   Payment_Count__c,
                   Frequency__c,
                   Start_Date__c,
                   End_Date__c,
                   Calculated_Count__c,
                   Calculated_Amount__c,
                   Segment_Note__c,
                   Is_First_Segment__c,
                   Continues_From_Previous__c,
                   Segment_Total__c
            FROM Settlement_Segment__c
            WHERE Settlement_Plan__c = :draftId
            ORDER BY Segment_Order__c ASC
        ];

        // Query related payment items
        wrapper.paymentItems = [
            SELECT Id,
                   Name,
                   Settlement_Plan__c,
                   Settlement_Segment__c,
                   Payment_Number__c,
                   Payment_Date__c,
                   Original_Payment_Date__c,
                   Payment_Amount__c,
                   Actual_Payment_Date__c,
                   Actual_Payment_Amount__c,
                   Commission_Fee__c,
                   Bank_Fee__c,
                   Payee_Fee__c,
                   EPPS_Transaction_Fee__c,
                   EPPS_Month_End_Fee__c,
                   Total_EPPS_Fee__c,
                   Escrow_Balance__c,
                   Status__c,
                   Payment_Method__c,
                   Confirmation_Number__c,
                   Skip_Payment__c,
                   Skip_Reason__c,
                   Has_Override__c,
                   Notes__c,
                   Is_Escrow_Shortage__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draftId
            ORDER BY Payment_Date__c ASC, Payment_Number__c ASC
        ];

        // Load CreditorOpportunity
        if (wrapper.draft.CreditorOpportunity__c != null) {
            List<CreditorOpportunity__c> credOpps = [
                SELECT Id,
                       Name,
                       Amount__c
                FROM CreditorOpportunity__c
                WHERE Id = :wrapper.draft.CreditorOpportunity__c
                LIMIT 1
            ];
            if (!credOpps.isEmpty()) {
                wrapper.creditorOpportunity = credOpps[0];
            }
        }

        return wrapper;
    }

    /**
     * @description Get the default draft to display for a CreditorOpportunity
     *              Returns Active draft if exists, otherwise newest Draft status
     * @param creditorOpportunityId The parent CreditorOpp ID
     * @return The default draft or null if none exist
     */
    public static Settlement_Plan_Draft__c getDefaultDraft(Id creditorOpportunityId) {
        if (creditorOpportunityId == null) {
            return null;
        }

        // First, look for Active draft
        List<Settlement_Plan_Draft__c> activeDrafts = [
            SELECT Id, Name, Status__c
            FROM Settlement_Plan_Draft__c
            WHERE CreditorOpportunity__c = :creditorOpportunityId
            AND Status__c = :STATUS_ACTIVE
            LIMIT 1
        ];

        if (!activeDrafts.isEmpty()) {
            return activeDrafts[0];
        }

        // If no Active, return newest Draft
        List<Settlement_Plan_Draft__c> drafts = [
            SELECT Id, Name, Status__c
            FROM Settlement_Plan_Draft__c
            WHERE CreditorOpportunity__c = :creditorOpportunityId
            AND Status__c = :STATUS_DRAFT
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        return drafts.isEmpty() ? null : drafts[0];
    }

    /**
     * @description Create a new blank draft for a CreditorOpportunity
     * @param creditorOpportunityId The parent CreditorOpp ID
     * @param draftName User-provided name
     * @return The created draft record
     */
    public static Settlement_Plan_Draft__c createDraft(
        Id creditorOpportunityId,
        String draftName
    ) {
        if (creditorOpportunityId == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Creditor Opportunity ID is required to create a draft.'
            );
        }

        // Load CreditorOpportunity to get default values
        List<CreditorOpportunity__c> credOpps = [
            SELECT Id,
                   Name,
                   Amount__c,
                   Escrow_Start_Balance__c
            FROM CreditorOpportunity__c
            WHERE Id = :creditorOpportunityId
            LIMIT 1
        ];

        if (credOpps.isEmpty()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.INVALID_CREDITOR_OPPORTUNITY,
                'Creditor Opportunity not found.'
            );
        }

        CreditorOpportunity__c credOpp = credOpps[0];

        // Generate default name if not provided
        String name = String.isNotBlank(draftName) ? draftName :
            'Draft ' + Datetime.now().format('yyyy-MM-dd HH:mm');

        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = name,
            CreditorOpportunity__c = creditorOpportunityId,
            Status__c = STATUS_DRAFT,
            Balance__c = credOpp.Amount__c,
            // Settlement_Offer_Amount__c intentionally NULL - user must enter
            Escrow_Start_Balance__c = credOpp.Escrow_Start_Balance__c,
            Is_Manually_Modified__c = false
        );

        // Check create permission
        if (!Schema.sObjectType.Settlement_Plan_Draft__c.isCreateable()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Insufficient permissions to create Settlement Plan Draft.'
            );
        }

        insert draft;
        return draft;
    }

    /**
     * @description Save draft segments and items
     * @param draftId The draft record ID
     * @param segments List of segment records to save
     * @param items List of payment item records to save (optional)
     * @param draftFields Map of draft field names to values to update (optional)
     * @return Updated draft record
     */
    public static Settlement_Plan_Draft__c saveDraftWithRecords(
        Id draftId,
        List<Settlement_Segment__c> segments,
        List<Settlement_Plan_Item__c> items,
        Map<String, Object> draftFields
    ) {
        // Validate draft exists and can be edited
        Settlement_Plan_Draft__c draft = getDraftById(draftId, 'save operation');
        requireEditableStatus(draft);

        Savepoint sp = Database.setSavepoint();

        try {
            // Update draft fields if provided (uses shared helper method)
            if (draftFields != null && !draftFields.isEmpty()) {
                applyDraftFields(draft, draftFields);
                update draft;
            }

            // Upsert segments - update existing or insert new
            if (segments != null && !segments.isEmpty()) {
                // Delete segments that are no longer in the list (handles UI deletion)
                Set<Id> segmentIdsToKeep = new Set<Id>();
                for (Settlement_Segment__c seg : segments) {
                    if (seg.Id != null) {
                        segmentIdsToKeep.add(seg.Id);
                    }
                }

                List<Settlement_Segment__c> segmentsToDelete = [
                    SELECT Id FROM Settlement_Segment__c
                    WHERE Settlement_Plan__c = :draftId
                    AND Id NOT IN :segmentIdsToKeep
                ];
                if (!segmentsToDelete.isEmpty()) {
                    delete segmentsToDelete;
                }

                // Set parent for new segments only (Master-Detail fields are immutable after insert)
                for (Settlement_Segment__c seg : segments) {
                    if (seg.Id == null) {
                        seg.Settlement_Plan__c = draftId;
                    }
                }
                upsert segments;
            }

            // ============ PAYMENT ITEMS: SMART SAVE ============
            // - Any non-Scheduled item already in DB is historical and never modified
            // - Scheduled items are upserted
            // - New items are inserted as provided

            // 1. Query existing items for this draft
            List<Settlement_Plan_Item__c> existingItems = [
                SELECT Id, Status__c
                FROM Settlement_Plan_Item__c
                WHERE Settlement_Plan__c = :draftId
            ];

            // 2. Build maps for comparison
            Map<Id, String> existingItemStatuses = new Map<Id, String>();
            Set<Id> historicalItemIds = new Set<Id>();  // Non-Scheduled - never touch

            for (Settlement_Plan_Item__c existing : existingItems) {
                existingItemStatuses.put(existing.Id, existing.Status__c);
                if (!isScheduledStatus(existing.Status__c)) {
                    historicalItemIds.add(existing.Id);
                }
            }

            // 3. Build set of incoming item IDs
            Set<Id> incomingItemIds = new Set<Id>();
            if (items != null) {
                for (Settlement_Plan_Item__c item : items) {
                    if (item.Id != null) {
                        incomingItemIds.add(item.Id);
                    }
                }
            }

            // 4. Find orphans: Scheduled items in DB but NOT in incoming list
            // (Non-Scheduled items are protected from deletion)
            Set<Id> orphanIds = new Set<Id>();
            for (Id existingId : existingItemStatuses.keySet()) {
                String dbStatus = existingItemStatuses.get(existingId);
                if (!incomingItemIds.contains(existingId) && isScheduledStatus(dbStatus)) {
                    orphanIds.add(existingId);
                }
            }

            // 5. Delete orphan Scheduled items
            if (!orphanIds.isEmpty()) {
                delete [SELECT Id FROM Settlement_Plan_Item__c WHERE Id IN :orphanIds];
            }

            // 6. Prepare items for save
            List<Settlement_Plan_Item__c> itemsToUpsert = new List<Settlement_Plan_Item__c>();

            if (items != null && !items.isEmpty()) {
                for (Settlement_Plan_Item__c item : items) {
                    // Skip historical items entirely (any non-Scheduled item already in DB)
                    if (item.Id != null && historicalItemIds.contains(item.Id)) {
                        continue;
                    }

                    // Full upsert for Scheduled and new items
                    if (item.Id == null) {
                        item.Settlement_Plan__c = draftId;
                    }
                    itemsToUpsert.add(item);
                }
            }

            // 7. Execute DML
            if (!itemsToUpsert.isEmpty()) {
                upsert itemsToUpsert;
            }

            // Update draft summary fields
            updateDraftSummary(draftId);

            // Re-query and return updated draft
            return [
                SELECT Id, Name, Status__c, Settlement_Offer_Amount__c, Revised_Settlement_Amount__c, Balance__c,
                       Escrow_Start_Balance__c, Commission_Fee__c, Number_of_Payments__c,
                       Is_Manually_Modified__c, CreatedBy.Name
                FROM Settlement_Plan_Draft__c
                WHERE Id = :draftId
                LIMIT 1
            ];

        } catch (Exception e) {
            Database.rollback(sp);
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Error saving draft: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Overloaded version without draftFields for backward compatibility
     */
    public static Settlement_Plan_Draft__c saveDraftWithRecords(
        Id draftId,
        List<Settlement_Segment__c> segments,
        List<Settlement_Plan_Item__c> items
    ) {
        return saveDraftWithRecords(draftId, segments, items, null);
    }

    /**
     * @description Update draft summary fields from related items.
     *              Note: Most summary fields (First_Payment_Date__c, Final_Payment_Date__c,
     *              Settlement_Term_Weeks__c, Funding_Difference__c, Total_Scheduled_Amount__c)
     *              are formula or rollup summary fields that auto-calculate.
     *              This method only updates editable fields like Next_Payment_Date__c.
     */
    private static void updateDraftSummary(Id draftId) {
        // Query draft
        List<Settlement_Plan_Draft__c> drafts = [
            SELECT Id, Settlement_Offer_Amount__c, Revised_Settlement_Amount__c
            FROM Settlement_Plan_Draft__c
            WHERE Id = :draftId
            LIMIT 1
        ];

        if (drafts.isEmpty()) return;

        Settlement_Plan_Draft__c draft = drafts[0];

        // Get items for next payment calculation (ordered by date)
        List<Settlement_Plan_Item__c> items = [
            SELECT Payment_Date__c, Payment_Amount__c, Status__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draftId
            ORDER BY Payment_Date__c ASC
        ];

        // Find next scheduled payment (first Scheduled item with date >= today)
        Settlement_Plan_Item__c nextPayment = null;
        Date today = Date.today();

        for (Settlement_Plan_Item__c item : items) {
            if (item.Payment_Date__c != null &&
                nextPayment == null &&
                isScheduledStatus(item.Status__c) &&
                item.Payment_Date__c >= today) {
                nextPayment = item;
                break;
            }
        }

        // Only update editable fields - formula/rollup fields auto-calculate
        // Use dynamic field access to avoid compile errors if fields are formula/rollup
        Boolean hasUpdates = false;
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Settlement_Plan_Draft__c.fields.getMap();

        // Dynamically check and update Next_Payment_Date__c if it's editable
        if (fieldMap.containsKey('next_payment_date__c')) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get('next_payment_date__c').getDescribe();
            if (fieldDescribe.isUpdateable() && !fieldDescribe.isCalculated()) {
                draft.put('Next_Payment_Date__c', nextPayment?.Payment_Date__c);
                hasUpdates = true;
            }
        }

        // Dynamically check and update Next_Payment_Amount__c if it's editable
        if (fieldMap.containsKey('next_payment_amount__c')) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get('next_payment_amount__c').getDescribe();
            if (fieldDescribe.isUpdateable() && !fieldDescribe.isCalculated()) {
                draft.put('Next_Payment_Amount__c', nextPayment?.Payment_Amount__c);
                hasUpdates = true;
            }
        }

        if (hasUpdates) {
            update draft;
        }
    }

    /**
     * @description Clone an existing draft with its segments and items
     * @param sourceDraftId The draft to clone
     * @param newName Name for the cloned draft
     * @return The new cloned draft record
     */
    public static Settlement_Plan_Draft__c cloneDraft(Id sourceDraftId, String newName) {
        if (sourceDraftId == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Source draft ID is required for cloning.'
            );
        }

        // Query source draft with all cloneable fields
        List<String> draftFields = getCloneableFieldNames(
            Schema.SObjectType.Settlement_Plan_Draft__c,
            new Set<String>{'Id'}
        );
        String draftSelect = 'Id';
        if (!draftFields.isEmpty()) {
            draftSelect += ', ' + String.join(draftFields, ', ');
        }

        List<Settlement_Plan_Draft__c> sourceDrafts = Database.query(
            'SELECT ' + draftSelect +
            ' FROM Settlement_Plan_Draft__c WHERE Id = :sourceDraftId LIMIT 1'
        );

        if (sourceDrafts.isEmpty()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Source draft not found.'
            );
        }

        Settlement_Plan_Draft__c source = sourceDrafts[0];

        // Create new draft with copied fields
        Settlement_Plan_Draft__c clone = new Settlement_Plan_Draft__c();
        copyFieldValues(source, clone, draftFields);

        // Generate/override name
        if (String.isNotBlank(newName)) {
            clone.Name = newName;
        } else if (String.isNotBlank(source.Name)) {
            clone.Name = source.Name + ' (Copy)';
        }

        // Always create as Draft
        clone.Status__c = STATUS_DRAFT;
        clone.Cloned_From__c = sourceDraftId;

        // Check create permission
        if (!Schema.sObjectType.Settlement_Plan_Draft__c.isCreateable()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Insufficient permissions to create Settlement Plan Draft.'
            );
        }

        insert clone;

        // Clone segments
        List<String> segmentFields = getCloneableFieldNames(
            Schema.SObjectType.Settlement_Segment__c,
            new Set<String>{'Id', 'Settlement_Plan__c'}
        );
        String segmentSelect = 'Id';
        if (!segmentFields.isEmpty()) {
            segmentSelect += ', ' + String.join(segmentFields, ', ');
        }

        List<Settlement_Segment__c> sourceSegments = Database.query(
            'SELECT ' + segmentSelect +
            ' FROM Settlement_Segment__c WHERE Settlement_Plan__c = :sourceDraftId ORDER BY Segment_Order__c ASC'
        );

        Map<Id, Integer> oldSegmentIdToIndex = new Map<Id, Integer>();
        List<Settlement_Segment__c> clonedSegments = new List<Settlement_Segment__c>();
        for (Settlement_Segment__c seg : sourceSegments) {
            Settlement_Segment__c clonedSeg = new Settlement_Segment__c();
            copyFieldValues(seg, clonedSeg, segmentFields);
            clonedSeg.Settlement_Plan__c = clone.Id;
            clonedSegments.add(clonedSeg);
            oldSegmentIdToIndex.put(seg.Id, clonedSegments.size() - 1);
        }
        if (!clonedSegments.isEmpty()) {
            insert clonedSegments;
        }

        Map<Id, Id> oldSegmentIdToNewId = new Map<Id, Id>();
        for (Id oldId : oldSegmentIdToIndex.keySet()) {
            Integer idx = oldSegmentIdToIndex.get(oldId);
            oldSegmentIdToNewId.put(oldId, clonedSegments[idx].Id);
        }

        // Clone items
        List<String> itemFields = getCloneableFieldNames(
            Schema.SObjectType.Settlement_Plan_Item__c,
            new Set<String>{'Id', 'Settlement_Plan__c', 'Settlement_Segment__c'}
        );
        String itemSelect = 'Id, Settlement_Segment__c';
        if (!itemFields.isEmpty()) {
            itemSelect += ', ' + String.join(itemFields, ', ');
        }

        List<Settlement_Plan_Item__c> sourceItems = Database.query(
            'SELECT ' + itemSelect +
            ' FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :sourceDraftId ORDER BY Payment_Number__c ASC'
        );

        if (!sourceItems.isEmpty()) {
            List<Settlement_Plan_Item__c> clonedItems = new List<Settlement_Plan_Item__c>();
            String suspendedStatus = getSuspendedStatus();
            String scheduledStatus = getScheduledStatus();

            for (Settlement_Plan_Item__c item : sourceItems) {
                Settlement_Plan_Item__c clonedItem = new Settlement_Plan_Item__c();
                copyFieldValues(item, clonedItem, itemFields);
                clonedItem.Settlement_Plan__c = clone.Id;

                if (item.Settlement_Segment__c != null && oldSegmentIdToNewId.containsKey(item.Settlement_Segment__c)) {
                    clonedItem.Settlement_Segment__c = oldSegmentIdToNewId.get(item.Settlement_Segment__c);
                }

                String statusToCopy = item.Status__c;
                if (String.isNotBlank(suspendedStatus) && String.isNotBlank(statusToCopy) &&
                    statusToCopy.equalsIgnoreCase(suspendedStatus)) {
                    statusToCopy = scheduledStatus;
                }
                clonedItem.Status__c = statusToCopy;

                clonedItems.add(clonedItem);
            }
            insert clonedItems;
        }

        // Update summary fields
        updateDraftSummary(clone.Id);

        return clone;
    }

    /**
     * @description Delete a draft (only if status = Draft or Archived)
     *              Master-Detail relationships will cascade delete:
     *              - Settlement_Segment__c (Master-Detail to Draft)
     *              - Settlement_Plan_Item__c (Master-Detail to Draft)
     * @param draftId The draft to delete
     */
    public static void deleteDraft(Id draftId) {
        // Validate draft exists
        Settlement_Plan_Draft__c draft = getDraftById(draftId, 'deletion');

        // Cannot delete Active or Applied drafts (custom messages for each)
        if (draft.Status__c == STATUS_ACTIVE) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Cannot delete an Active draft. Archive it first or activate a different draft.'
            );
        }

        if (draft.Status__c == STATUS_APPLIED) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Cannot delete an Applied draft. It represents historical data.'
            );
        }

        // Check delete permission
        if (!Schema.sObjectType.Settlement_Plan_Draft__c.isDeletable()) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Insufficient permissions to delete Settlement Plan Draft.'
            );
        }

        // Master-Detail relationships automatically cascade delete child Segments and Items
        delete draft;
    }

    // ============ CALCULATION METHODS ============

    /**
     * @description Calculate payment items from segments (preview only)
     *              Returns calculated items that can be saved or displayed.
     *              Preserves historical items (non-Scheduled) and generates
     *              new items starting after the last locked item.
     * @param draftId The draft ID (optional if segments provided directly)
     * @param segments List of segment records to calculate from
     * @param balance The balance amount
     * @param settlementOffer The settlement offer amount
     * @param commissionFee Commission fee per payment (passed from UI)
     * @param totalPaidAmount Total paid amount from UI (Cleared + Processing)
     * @return DraftCalculationResult with calculated items
     */
    public static DraftCalculationResult calculateDraftPlan(
        Id draftId,
        List<Settlement_Segment__c> segments,
        Decimal balance,
        Decimal settlementOffer,
        Decimal commissionFee,
        Decimal totalPaidAmount
    ) {
        DraftCalculationResult result = new DraftCalculationResult();

        try {
            // Load configuration
            Settlement_Calc_Config__mdt config = getConfig();
            Decimal tolerance = config.Fully_Funded_Tolerance__c != null ?
                config.Fully_Funded_Tolerance__c : DEFAULT_FULLY_FUNDED_TOLERANCE;

            Id credOppId = null;
            // Use commission fee passed from UI (takes precedence)
            Decimal commissionOverride = commissionFee;

            // If draftId provided, load draft + segments only (lightweight query)
            // Payment items are queried separately for locked items handling below
            DraftWrapper wrapper = null;
            if (draftId != null) {
                wrapper = getDraftWithSegments(draftId);
                if (wrapper.draft != null) {
                    if (segments == null || segments.isEmpty()) {
                        segments = wrapper.segments;
                    }
                    if (settlementOffer == null) settlementOffer = getEffectiveSettlementAmount(wrapper.draft);
                    credOppId = wrapper.draft.CreditorOpportunity__c;

                    // Only use DB commission fee if not passed from UI
                    if (commissionOverride == null) {
                        commissionOverride = wrapper.draft.Commission_Fee__c;
                    }
                }
            }

            if (segments == null || segments.isEmpty()) {
                result.errorMessage = 'No segments configured. Please add at least one segment.';
                return result;
            }

            // Validate settlement offer
            if (settlementOffer == null || settlementOffer <= 0) {
                result.errorMessage = 'Settlement Offer must be greater than zero.';
                return result;
            }

            // Validate commission fee
            if (commissionOverride == null) {
                result.errorMessage = 'Commission Fee is required. Please enter a value on the Settlement Plan.';
                return result;
            }

            // Note: Segments are already queried with ORDER BY Segment_Order__c ASC
            // No additional sorting needed - SObjects don't implement Comparable

            // Validate first segment has start date
            if (segments[0].Start_Date__c == null) {
                result.errorMessage = 'First segment must have a Start Date.';
                return result;
            }

            String scheduledStatus = getScheduledStatus();

            // ============ PRESERVED ITEMS HANDLING ============
            // Query ALL non-Scheduled items (they will be preserved during recalculation)
            List<Settlement_Plan_Item__c> preservedItems = new List<Settlement_Plan_Item__c>();
            Integer existingItemCount = 0;

            if (draftId != null) {
                // Count all existing items
                existingItemCount = [
                    SELECT COUNT()
                    FROM Settlement_Plan_Item__c
                    WHERE Settlement_Plan__c = :draftId
                ];

                // Preserve all non-Scheduled items
                preservedItems = [
                    SELECT Id, Name, Settlement_Plan__c, Settlement_Segment__c,
                           Payment_Number__c, Payment_Date__c, Original_Payment_Date__c,
                           Payment_Amount__c, Commission_Fee__c, Bank_Fee__c, Payee_Fee__c,
                           EPPS_Transaction_Fee__c, EPPS_Month_End_Fee__c, Total_EPPS_Fee__c,
                           Escrow_Balance__c,
                           Status__c, Payment_Method__c, Has_Override__c, Notes__c, Is_Escrow_Shortage__c
                    FROM Settlement_Plan_Item__c
                    WHERE Settlement_Plan__c = :draftId
                    AND Status__c != :scheduledStatus
                    ORDER BY Payment_Number__c ASC
                ];

                // If ALL existing items are non-Scheduled AND no segments to generate new items, cannot recalculate
                // But if segments exist, we can generate new items from them (Phase 33: revised amount scenario)
                if (existingItemCount > 0 && preservedItems.size() == existingItemCount && (segments == null || segments.isEmpty())) {
                    result.errorMessage = 'Cannot recalculate - no Scheduled items to regenerate. Add segments or manually edit existing items.';
                    return result;
                }
            }

            // Determine starting point based on paid items (Cleared/Processing)
            // Get effective settlement amount - use passed parameter if provided,
            // fall back to DB value only if null (allows UI changes before save)
            Decimal effectiveOffer = settlementOffer != null ?
                settlementOffer :
                (wrapper != null && wrapper.draft != null ? getEffectiveSettlementAmount(wrapper.draft) : 0);

            Integer paymentNumber = 1;
            Date currentDate = null;

            // Calculate remaining based on effective offer minus local/DB paid amounts
            Decimal paidAmount = totalPaidAmount != null ? totalPaidAmount : 0;
            if (totalPaidAmount == null) {
                for (Settlement_Plan_Item__c item : preservedItems) {
                    if (isPaidStatus(item.Status__c)) {
                        paidAmount += item.Payment_Amount__c != null ? item.Payment_Amount__c : 0;
                    }
                }
            }
            Decimal remainingBalance = effectiveOffer - paidAmount;

            if (!preservedItems.isEmpty()) {
                Settlement_Plan_Item__c lastPreserved = preservedItems[preservedItems.size() - 1];
                if (lastPreserved.Payment_Number__c != null) {
                    paymentNumber = Integer.valueOf(lastPreserved.Payment_Number__c) + 1;
                }
            }

            // Validate segment start date is after last preserved item
            if (!preservedItems.isEmpty()) {
                Settlement_Plan_Item__c lastPreserved = preservedItems[preservedItems.size() - 1];
                Date lastPreservedDate = lastPreserved.Payment_Date__c;

                // Check first segment's start date
                if (segments[0].Start_Date__c != null && lastPreservedDate != null && segments[0].Start_Date__c <= lastPreservedDate) {
                    result.errorMessage = 'Segment start date (' + segments[0].Start_Date__c.format() +
                        ') must be after the last preserved payment (' + lastPreservedDate.format() +
                        '). Please update the segment start date.';
                    return result;
                }
            }

            // Generate payment items from segments
            List<Settlement_Plan_Item__c> paymentItems = new List<Settlement_Plan_Item__c>();
            Integer maxPayments = Integer.valueOf(config.Max_Payments__c);

            // Initialize fee calculator with commission fee from Settlement Plan (user-entered)
            SettlementFeeCalculator feeCalc = new SettlementFeeCalculator(config, commissionOverride);

            for (Settlement_Segment__c segment : segments) {
                // Determine start date
                if (segment.Start_Date__c != null) {
                    currentDate = segment.Start_Date__c;
                } else if (currentDate == null) {
                    result.errorMessage = 'Cannot determine start date for segment ' + segment.Segment_Order__c;
                    return result;
                }

                // Validate segment configuration
                String validationError = validateSegmentConfig(segment);
                if (validationError != null) {
                    result.errorMessage = validationError;
                    return result;
                }

                // Generate items based on segment type
                List<Settlement_Plan_Item__c> segmentItems = generateItemsForSegment(
                    segment, currentDate, paymentNumber, remainingBalance, config, feeCalc, draftId
                );

                for (Settlement_Plan_Item__c item : segmentItems) {
                    paymentItems.add(item);
                    remainingBalance -= item.Payment_Amount__c;
                    paymentNumber++;

                    // Update current date for next segment
                    Date itemDate = item.Original_Payment_Date__c != null ?
                        item.Original_Payment_Date__c : item.Payment_Date__c;
                    currentDate = SettlementDateUtils.advanceDate(itemDate, segment.Frequency__c);

                    // Check max payments
                    if (paymentItems.size() > maxPayments) {
                        result.errorMessage = 'Exceeded maximum allowed payments (' + maxPayments + ').';
                        return result;
                    }
                }

                // Stop if balance paid
                if (remainingBalance <= tolerance) {
                    break;
                }
            }

            // EPPS month-end fees no longer calculated - disabled
            // SettlementFeeCalculator.calculateEppsMonthEndFeesStatic(paymentItems, config);

            // ============ MERGE PRESERVED + NEW ITEMS ============
            // Combine preserved items (from DB) with newly calculated items
            List<Settlement_Plan_Item__c> allItems = new List<Settlement_Plan_Item__c>();

            // Add preserved items first (they keep their IDs for upsert/skip on save)
            allItems.addAll(preservedItems);

            // Add newly generated items (they have no IDs, will be inserted on save)
            allItems.addAll(paymentItems);

            // Build result with all items (preserved + new)
            // Using helper method for consistent null-handling
            Decimal totalScheduled = calculateTotalScheduled(allItems);

            result.success = true;
            result.paymentItems = allItems;
            result.totalScheduledAmount = totalScheduled.setScale(2, System.RoundingMode.HALF_UP);
            result.fundingDifference = (totalScheduled - effectiveOffer).setScale(2, System.RoundingMode.HALF_UP);
            result.numberOfPayments = allItems.size();
            result.escrowShortageCount = 0; // Escrow shortage tracking removed

            if (!allItems.isEmpty()) {
                result.firstPaymentDate = allItems[0].Payment_Date__c;
                result.finalPaymentDate = allItems[allItems.size() - 1].Payment_Date__c;
                result.settlementTermWeeks = SettlementDateUtils.weeksBetween(
                    result.firstPaymentDate, result.finalPaymentDate
                );
            }

        } catch (SettlementCalculatorException e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Calculation error: ' + e.getMessage();
        }

        return result;
    }

    /**
     * @description Validate segment configuration
     */
    private static String validateSegmentConfig(Settlement_Segment__c segment) {
        if (String.isBlank(segment.Segment_Type__c)) {
            return 'Segment ' + segment.Segment_Order__c + ' is missing Segment Type.';
        }

        // Validate segment type is one of the allowed values
        if (!VALID_SEGMENT_TYPES.contains(segment.Segment_Type__c)) {
            return 'Segment ' + segment.Segment_Order__c + ' has invalid Segment Type: ' + segment.Segment_Type__c + '. Valid types are: Fixed, Remainder, SolveAmount.';
        }

        if (String.isBlank(segment.Frequency__c)) {
            return 'Segment ' + segment.Segment_Order__c + ' is missing Frequency.';
        }

        if (segment.Segment_Type__c == 'Fixed' || segment.Segment_Type__c == 'Remainder') {
            if (segment.Payment_Amount__c == null || segment.Payment_Amount__c <= 0) {
                return segment.Segment_Type__c + ' segment requires Payment Amount > 0.';
            }
        }

        if (segment.Segment_Type__c == 'Fixed' || segment.Segment_Type__c == 'SolveAmount') {
            if (segment.Payment_Count__c == null || segment.Payment_Count__c <= 0) {
                return segment.Segment_Type__c + ' segment requires Payment Count > 0.';
            }
        }

        return null; // Valid
    }

    /**
     * @description Generate payment items for a single segment
     */
    private static List<Settlement_Plan_Item__c> generateItemsForSegment(
        Settlement_Segment__c segment,
        Date startDate,
        Integer startPaymentNumber,
        Decimal remainingBalance,
        Settlement_Calc_Config__mdt config,
        SettlementFeeCalculator feeCalc,
        Id planId
    ) {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        Date currentDate = startDate;
        Integer paymentNumber = startPaymentNumber;
        Decimal runningBalance = remainingBalance;
        Decimal tolerance = config.Fully_Funded_Tolerance__c != null ?
            config.Fully_Funded_Tolerance__c : DEFAULT_FULLY_FUNDED_TOLERANCE;

        switch on segment.Segment_Type__c {
            when 'Fixed' {
                Integer count = Integer.valueOf(segment.Payment_Count__c);
                Decimal amount = segment.Payment_Amount__c;

                for (Integer i = 0; i < count; i++) {
                    if (runningBalance <= tolerance) break;

                    Decimal paymentAmount = Math.min(amount, runningBalance);
                    if (paymentAmount <= 0) break;

                    Settlement_Plan_Item__c item = createPaymentItem(
                        segment.Id, paymentNumber, currentDate, paymentAmount,
                        runningBalance, feeCalc, planId
                    );

                    items.add(item);
                    runningBalance -= paymentAmount;
                    paymentNumber++;

                    if (i < count - 1) {
                        currentDate = SettlementDateUtils.advanceDate(currentDate, segment.Frequency__c);
                    }
                }
            }
            when 'Remainder' {
                Decimal amount = segment.Payment_Amount__c;
                Integer maxIterations = Integer.valueOf(config.Remainder_Max_Iterations__c);
                Integer iterations = 0;

                while (runningBalance > tolerance && iterations < maxIterations) {
                    Decimal paymentAmount = Math.min(amount, runningBalance);
                    if (paymentAmount <= 0) break;

                    Settlement_Plan_Item__c item = createPaymentItem(
                        segment.Id, paymentNumber, currentDate, paymentAmount,
                        runningBalance, feeCalc, planId
                    );

                    items.add(item);
                    runningBalance -= paymentAmount;
                    paymentNumber++;
                    iterations++;

                    currentDate = SettlementDateUtils.advanceDate(currentDate, segment.Frequency__c);
                }

                if (iterations >= maxIterations && runningBalance > tolerance) {
                    throw new SettlementCalculatorException(
                        SettlementCalculatorException.ErrorType.MAX_ITERATIONS_EXCEEDED,
                        'Remainder segment exceeded maximum iterations.'
                    );
                }
            }
            when 'SolveAmount' {
                Integer count = Integer.valueOf(segment.Payment_Count__c);
                if (count <= 0 || runningBalance <= 0) {
                    return items;
                }

                Decimal calculatedAmount = (runningBalance / count).setScale(2, System.RoundingMode.HALF_UP);

                for (Integer i = 0; i < count; i++) {
                    Decimal paymentAmount;
                    if (i == count - 1) {
                        paymentAmount = runningBalance;
                    } else {
                        paymentAmount = Math.min(calculatedAmount, runningBalance);
                    }

                    if (paymentAmount <= 0) break;

                    Settlement_Plan_Item__c item = createPaymentItem(
                        segment.Id, paymentNumber, currentDate, paymentAmount,
                        runningBalance, feeCalc, planId
                    );

                    items.add(item);
                    runningBalance -= paymentAmount;
                    paymentNumber++;

                    if (i < count - 1) {
                        currentDate = SettlementDateUtils.advanceDate(currentDate, segment.Frequency__c);
                    }
                }
            }
        }

        return items;
    }

    /**
     * @description Create a single payment item with fees calculated by the fee calculator
     */
    private static Settlement_Plan_Item__c createPaymentItem(
        Id segmentId,
        Integer paymentNumber,
        Date originalDate,
        Decimal paymentAmount,
        Decimal balanceBefore,
        SettlementFeeCalculator feeCalc,
        Id planId
    ) {
        Date adjustedDate = SettlementDateUtils.applyPreviousBusinessDayRule(originalDate);

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Settlement_Plan__c = planId,
            Settlement_Segment__c = segmentId,
            Payment_Number__c = paymentNumber,
            Payment_Date__c = adjustedDate,
            Original_Payment_Date__c = originalDate != adjustedDate ? originalDate : null,
            Payment_Amount__c = paymentAmount.setScale(2, System.RoundingMode.HALF_UP),
            Status__c = getScheduledStatus()
        );

        // Calculate fees using centralized fee calculator
        // This ensures consistent fee defaults and preserves any existing Payee_Fee
        feeCalc.calculateFeesForItem(item);

        return item;
    }

    /**
     * @description Running balance recalculation has been retired (save & fetch architecture).
     * @param items List of payment items
     * @param effectiveOffer The effective settlement amount (unused)
     */
    private static void recalculateRunningBalances(
        List<Settlement_Plan_Item__c> items,
        Decimal effectiveOffer
    ) {
        if (items == null || items.isEmpty()) {
            return;
        }
        // Running balance calculation has been retired (save & fetch architecture).
        // We still sort items by date for consistent ordering.
        sortItemsByDate(items);
        return;
    }

    /**
     * @description Sort payment items by Payment_Date__c ASC, then Payment_Number__c ASC
     *              Simple bubble sort since Apex SObjects don't implement Comparable
     * @param items List to sort in place
     */
    private static void sortItemsByDate(List<Settlement_Plan_Item__c> items) {
        Integer n = items.size();
        for (Integer i = 0; i < n - 1; i++) {
            for (Integer j = 0; j < n - i - 1; j++) {
                Settlement_Plan_Item__c a = items[j];
                Settlement_Plan_Item__c b = items[j + 1];

                Boolean shouldSwap = false;

                // Handle nulls - null dates sort to end
                if (a.Payment_Date__c == null && b.Payment_Date__c != null) {
                    shouldSwap = true;
                } else if (a.Payment_Date__c != null && b.Payment_Date__c != null) {
                    if (a.Payment_Date__c > b.Payment_Date__c) {
                        shouldSwap = true;
                    } else if (a.Payment_Date__c == b.Payment_Date__c) {
                        // Same date - sort by Payment_Number__c
                        Decimal numA = a.Payment_Number__c != null ? a.Payment_Number__c : 999999;
                        Decimal numB = b.Payment_Number__c != null ? b.Payment_Number__c : 999999;
                        if (numA > numB) {
                            shouldSwap = true;
                        }
                    }
                }

                if (shouldSwap) {
                    items[j] = b;
                    items[j + 1] = a;
                }
            }
        }
    }

    /**
     * @description Calculate total scheduled amount across all items
     * @param items List of payment items
     * @return Total scheduled amount
     */
    private static Decimal calculateTotalScheduled(List<Settlement_Plan_Item__c> items) {
        Decimal total = 0;
        for (Settlement_Plan_Item__c item : items) {
            total += item.Payment_Amount__c != null ? item.Payment_Amount__c : 0;
        }
        return total;
    }

    /**
     * @description Refresh items after manual edit without recalculating running balances.
     *              Returns summary values based on provided items and offer.
     * @param items Current list of payment items
     * @param settlementOffer The effective settlement amount (revised if set, otherwise original)
     * @return RecalculationResult with updated items + summary
     */
    public static RecalculationResult recalculateBalances(
        List<Settlement_Plan_Item__c> items,
        Decimal settlementOffer
    ) {
        RecalculationResult result = new RecalculationResult();

        try {
            if (items == null || items.isEmpty()) {
                result.errorMessage = 'No payment items to recalculate.';
                return result;
            }

            // Load config for EPPS recalculation
            Settlement_Calc_Config__mdt config = getConfig();

            // Recalculate running balances (handles locked rows internally)
            recalculateRunningBalances(items, settlementOffer);

            // EPPS month-end fees no longer calculated - disabled
            // List<Settlement_Plan_Item__c> itemsForEpps = new List<Settlement_Plan_Item__c>();
            // for (Settlement_Plan_Item__c item : items) {
            //     if (!UI_LOCKED_STATUSES.contains(item.Status__c)) {
            //         itemsForEpps.add(item);
            //     }
            // }
            // if (!itemsForEpps.isEmpty()) {
            //     SettlementFeeCalculator.calculateEppsMonthEndFeesStatic(itemsForEpps, config);
            // }

            // Build result
            Decimal totalScheduled = calculateTotalScheduled(items);
            Decimal fundingDiff = totalScheduled - (settlementOffer != null ? settlementOffer : 0);
            Decimal tolerance = config.Fully_Funded_Tolerance__c != null ? config.Fully_Funded_Tolerance__c : DEFAULT_BALANCE_CHECK_TOLERANCE;

            result.success = true;
            result.paymentItems = items;
            result.totalScheduledAmount = totalScheduled.setScale(2, System.RoundingMode.HALF_UP);
            result.fundingDifference = fundingDiff.setScale(2, System.RoundingMode.HALF_UP);
            result.isBalanced = Math.abs(fundingDiff) <= tolerance;

            if (!result.isBalanced) {
                if (fundingDiff < 0) {
                    result.warningMessage = 'Plan is underfunded by $' + Math.abs(fundingDiff).setScale(2) + '.';
                } else {
                    result.warningMessage = 'Plan is overfunded by $' + fundingDiff.setScale(2) + '.';
                }
            }

        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Recalculation error: ' + e.getMessage();
        }

        return result;
    }

    // ============ LAZY DRAFT CREATION ============

    /**
     * @description Creates a new draft AND saves segments/items in one atomic transaction.
     *              Used for lazy draft creation - draft only created when user clicks Save.
     *              This prevents orphan drafts when user previews but never saves.
     * @param creditorOpportunityId The parent CreditorOpportunity
     * @param draftName Name for the new draft
     * @param segments List of segments to save
     * @param items List of payment items to save
     * @param draftFields Map of draft field values (Settlement_Offer_Amount__c, Commission_Fee__c, etc.)
     * @return The created draft with all data
     */
    public static Settlement_Plan_Draft__c createAndSaveDraft(
        Id creditorOpportunityId,
        String draftName,
        List<Settlement_Segment__c> segments,
        List<Settlement_Plan_Item__c> items,
        Map<String, Object> draftFields
    ) {
        if (creditorOpportunityId == null) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Creditor Opportunity ID is required to create a draft.'
            );
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Create the draft record
            Settlement_Plan_Draft__c draft = createDraft(creditorOpportunityId, draftName);

            // 2. Delegate to saveDraftWithRecords for segments, items, and field updates
            // This ensures consistent save logic and avoids code duplication
            return saveDraftWithRecords(draft.Id, segments, items, draftFields);

        } catch (SettlementCalculatorException e) {
            Database.rollback(sp);
            throw e; // Re-throw as-is to preserve the original message
        } catch (Exception e) {
            Database.rollback(sp);
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Failed to create and save draft: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Apply field values from a map to a draft record.
     *              Extracted as helper for reuse in saveDraftWithRecords and createAndSaveDraft.
     * @param draft The draft record to update
     * @param draftFields Map of field API names to values
     */
    private static void applyDraftFields(Settlement_Plan_Draft__c draft, Map<String, Object> draftFields) {
        if (draftFields.containsKey('Name')) {
            draft.Name = String.valueOf(draftFields.get('Name'));
        }
        if (draftFields.containsKey('Balance__c')) {
            draft.Balance__c = draftFields.get('Balance__c') != null ?
                Decimal.valueOf(String.valueOf(draftFields.get('Balance__c'))) : null;
        }
        if (draftFields.containsKey('Settlement_Offer_Amount__c')) {
            draft.Settlement_Offer_Amount__c = draftFields.get('Settlement_Offer_Amount__c') != null ?
                Decimal.valueOf(String.valueOf(draftFields.get('Settlement_Offer_Amount__c'))) : null;
        }
        if (draftFields.containsKey('Revised_Settlement_Amount__c')) {
            draft.Revised_Settlement_Amount__c = draftFields.get('Revised_Settlement_Amount__c') != null ?
                Decimal.valueOf(String.valueOf(draftFields.get('Revised_Settlement_Amount__c'))) : null;
        }
        if (draftFields.containsKey('Escrow_Start_Balance__c')) {
            draft.Escrow_Start_Balance__c = draftFields.get('Escrow_Start_Balance__c') != null ?
                Decimal.valueOf(String.valueOf(draftFields.get('Escrow_Start_Balance__c'))) : null;
        }
        if (draftFields.containsKey('Commission_Fee__c')) {
            draft.Commission_Fee__c = draftFields.get('Commission_Fee__c') != null ?
                Decimal.valueOf(String.valueOf(draftFields.get('Commission_Fee__c'))) : null;
        }
        if (draftFields.containsKey('Is_Manually_Modified__c')) {
            draft.Is_Manually_Modified__c = Boolean.valueOf(draftFields.get('Is_Manually_Modified__c'));
        }
        if (draftFields.containsKey('Settlement_Memo__c')) {
            draft.Settlement_Memo__c = String.valueOf(draftFields.get('Settlement_Memo__c'));
        }
        if (draftFields.containsKey('Contract_File_ID__c')) {
            draft.Contract_File_ID__c = String.valueOf(draftFields.get('Contract_File_ID__c'));
        }
    }

    // ============ ACTIVATION METHODS ============

    /**
     * @description Activate a draft - sets status to Active
     *              Records are already stored in Settlement_Segment__c and Settlement_Plan_Item__c
     * @param draftId The draft to activate
     * @return ActivationResult with success/error and record counts
     */
    public static ActivationResult activateDraft(Id draftId) {
        ActivationResult result = new ActivationResult();

        if (draftId == null) {
            result.errorMessage = 'Draft ID is required for activation.';
            return result;
        }

        Savepoint sp = Database.setSavepoint();

        try {
            // Load draft with all details
            DraftWrapper wrapper = getDraftWithDetails(draftId);

            if (wrapper.draft == null) {
                result.errorMessage = 'Draft not found.';
                return result;
            }

            // Verify draft is in Draft status
            if (wrapper.draft.Status__c != STATUS_DRAFT) {
                result.errorMessage = 'Only drafts in "Draft" status can be activated. Current status: ' + wrapper.draft.Status__c;
                return result;
            }

            // Verify there are payment items
            if (wrapper.paymentItems.isEmpty()) {
                result.errorMessage = 'No payment items to create. Please calculate the plan first.';
                return result;
            }

            Id credOppId = wrapper.draft.CreditorOpportunity__c;

            // Archive any existing Active draft for this CreditorOpportunity
            List<Settlement_Plan_Draft__c> activeDrafts = [
                SELECT Id, Status__c
                FROM Settlement_Plan_Draft__c
                WHERE CreditorOpportunity__c = :credOppId
                AND Status__c = :STATUS_ACTIVE
                AND Id != :draftId
            ];
            for (Settlement_Plan_Draft__c activeDraft : activeDrafts) {
                activeDraft.Status__c = STATUS_ARCHIVED;
            }
            if (!activeDrafts.isEmpty()) {
                update activeDrafts;
            }

            // Update this draft to Active status
            wrapper.draft.Status__c = STATUS_ACTIVE;
            wrapper.draft.Applied_Date__c = Datetime.now();
            update wrapper.draft;

            // Set Active_Plan__c on CreditorOpportunity to point to this draft
            CreditorOpportunity__c credOpp = new CreditorOpportunity__c(
                Id = credOppId,
                Active_Plan__c = draftId
            );
            update credOpp;

            result.success = true;
            result.activatedDraftId = draftId;
            result.segmentCount = wrapper.segments.size();
            result.paymentItemCount = wrapper.paymentItems.size();

        } catch (Exception e) {
            Database.rollback(sp);
            result.success = false;
            result.errorMessage = 'Activation failed: ' + e.getMessage();
        }

        return result;
    }

    // ============ SUSPEND METHODS ============

    /**
     * @description Suspend Scheduled items and void Processing items for an active draft
     *              Also updates draft status to Suspended
     * @param draftId The draft to suspend
     * @return Number of items suspended
     */
    public static Integer suspendPaymentItems(Id draftId) {
        // Validate draft exists
        Settlement_Plan_Draft__c draft = getDraftById(draftId, 'suspension');

        // Only Active plans can be suspended
        if (draft.Status__c != STATUS_ACTIVE) {
            throw new SettlementCalculatorException(
                SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
                'Only Active plans can be suspended.'
            );
        }

        String scheduledStatus = getScheduledStatus();
        String processingStatus = getProcessingStatus();
        String suspendedStatus = getSuspendedStatus();
        String voidStatus = getVoidStatus();

        List<String> statusesToUpdate = new List<String>();
        if (String.isNotBlank(scheduledStatus)) {
            statusesToUpdate.add(scheduledStatus);
        }
        if (String.isNotBlank(processingStatus)) {
            statusesToUpdate.add(processingStatus);
        }
        if (statusesToUpdate.isEmpty()) {
            return 0;
        }

        // Suspend Scheduled items and convert Processing items to Void
        List<Settlement_Plan_Item__c> items = [
            SELECT Id, Status__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draftId
            AND Status__c IN :statusesToUpdate
        ];

        for (Settlement_Plan_Item__c item : items) {
            if (isScheduledStatus(item.Status__c)) {
                item.Status__c = suspendedStatus;
            } else if (String.isNotBlank(processingStatus) && item.Status__c != null &&
                item.Status__c.equalsIgnoreCase(processingStatus)) {
                item.Status__c = voidStatus;
            }
        }

        if (!items.isEmpty()) {
            update items;
        }

        // Update draft status to Suspended
        draft.Status__c = STATUS_SUSPENDED;
        update draft;

        return items.size();
    }
}