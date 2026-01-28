/**
 * @description Service class for Payment_Fee__c CRUD operations.
 * Handles creation, retrieval, update, and deletion of fee records
 * associated with Payment_Schedule_Item__c records.
 *
 * Each Payment_Schedule_Item__c can have 3 fee types:
 * - Banking Fee
 * - Program Fee
 * - Setup Fee
 *
 * Note: Savings/Escrow amounts are stored directly on Payment_Schedule_Item__c.To_Escrow_Amount__c
 */
public with sharing class PaymentFeeService {

    // ==================================================================================
    // DEBUG LOGGING CONSTANTS
    // ==================================================================================
    private static final String LOG_PREFIX = '[PaymentFeeService]';
    private static final String LOG_ENTRY = '▶️';
    private static final String LOG_EXIT = '◀️';
    private static final String LOG_ERROR = '❌';
    private static final String LOG_SUCCESS = '✅';
    private static final String LOG_DEBUG = '🔧';

    // Fee Type Constants
    public static final String FEE_TYPE_BANKING = 'Banking Fee';
    public static final String FEE_TYPE_PROGRAM = 'Program Fee';
    public static final String FEE_TYPE_SETUP = 'Setup Fee';
    public static final String FEE_TYPE_WIRE = 'Wire Fee';
    public static final String FEE_TYPE_WIRE_RECEIVED = 'Wire Received Fee';

    // All supported fee types for schedule items (standard fees)
    public static final Set<String> SCHEDULE_ITEM_FEE_TYPES = new Set<String>{
        FEE_TYPE_BANKING,
        FEE_TYPE_PROGRAM,
        FEE_TYPE_SETUP
    };

    // Wire fee types
    public static final Set<String> WIRE_FEE_TYPES = new Set<String>{
        FEE_TYPE_WIRE,
        FEE_TYPE_WIRE_RECEIVED
    };

    /**
     * @description Create Payment_Fee__c records for a single Payment_Schedule_Item__c.
     * Creates 3 fee records (Banking, Program, Setup) linked to the schedule item.
     * Note: Savings/Escrow is stored directly on Payment_Schedule_Item__c.To_Escrow_Amount__c
     *
     * @param psi The Payment_Schedule_Item__c record (must have Id populated)
     * @param bankingFee Banking fee amount
     * @param programFee Program fee amount
     * @param setupFee Setup fee amount
     * @return List of Payment_Fee__c records (not yet inserted)
     */
    public static List<Payment_Fee__c> createFeeRecordsForItem(
        Payment_Schedule_Item__c psi,
        Decimal bankingFee,
        Decimal programFee,
        Decimal setupFee
    ) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' createFeeRecordsForItem | psiId=' + (psi != null ? psi.Id : 'null'));
        List<Payment_Fee__c> feeRecords = new List<Payment_Fee__c>();

        if (psi == null || psi.Id == null) {
            System.debug(LOG_PREFIX + ' ' + LOG_DEBUG + ' createFeeRecordsForItem | Skipping - null PSI');
            return feeRecords;
        }

        // Create Banking Fee record
        feeRecords.add(createFeeRecord(psi.Id, FEE_TYPE_BANKING, bankingFee));

        // Create Program Fee record
        feeRecords.add(createFeeRecord(psi.Id, FEE_TYPE_PROGRAM, programFee));

        // Create Setup Fee record
        feeRecords.add(createFeeRecord(psi.Id, FEE_TYPE_SETUP, setupFee));

        return feeRecords;
    }

    /**
     * @description Bulk create Payment_Fee__c records for multiple Payment_Schedule_Item__c records.
     * Creates Banking, Program, and Setup fees only. Savings/Escrow is stored on the schedule item.
     *
     * @param items List of Payment_Schedule_Item__c records (must have Id populated)
     * @param wrapperMap Map of PSI Id to wrapper containing fee amounts
     * @return List of Payment_Fee__c records (not yet inserted)
     */
    public static List<Payment_Fee__c> createFeeRecordsForItems(
        List<Payment_Schedule_Item__c> items,
        Map<Id, PaymentPlanEditorController.ScheduleItemWrapper> wrapperMap
    ) {
        List<Payment_Fee__c> allFeeRecords = new List<Payment_Fee__c>();

        if (items == null || items.isEmpty() || wrapperMap == null) {
            return allFeeRecords;
        }

        for (Payment_Schedule_Item__c psi : items) {
            if (psi.Id == null || !wrapperMap.containsKey(psi.Id)) {
                continue;
            }

            PaymentPlanEditorController.ScheduleItemWrapper wrapper = wrapperMap.get(psi.Id);
            allFeeRecords.addAll(createFeeRecordsForItem(
                psi,
                wrapper.bankingFee,
                wrapper.programFee,
                wrapper.setupFee
            ));
        }

        return allFeeRecords;
    }

    /**
     * @description Retrieve Payment_Fee__c records grouped by Payment_Schedule_Item__c Id and Type.
     * Returns a nested map structure: PSI Id -> Fee Type -> Payment_Fee__c record.
     *
     * @param scheduleItemIds Set of Payment_Schedule_Item__c Ids to query fees for
     * @return Map<Id, Map<String, Payment_Fee__c>> - Outer map keyed by PSI Id, inner map keyed by Type__c
     */
    public static Map<Id, Map<String, Payment_Fee__c>> getFeesByScheduleItemIds(Set<Id> scheduleItemIds) {
        Map<Id, Map<String, Payment_Fee__c>> resultMap = new Map<Id, Map<String, Payment_Fee__c>>();

        if (scheduleItemIds == null || scheduleItemIds.isEmpty()) {
            return resultMap;
        }

        // Initialize empty maps for each schedule item
        for (Id psiId : scheduleItemIds) {
            resultMap.put(psiId, new Map<String, Payment_Fee__c>());
        }

        // Query fee records
        List<Payment_Fee__c> fees = [
            SELECT Id, Payment_Schedule_Item__c, Type__c, Amount__c,
                   Fee_Id__c, Status_Code__c, Status__c, Transaction_Id__c
            FROM Payment_Fee__c
            WHERE Payment_Schedule_Item__c IN :scheduleItemIds
            AND Type__c IN :SCHEDULE_ITEM_FEE_TYPES
        ];

        // Group by PSI Id and Type
        for (Payment_Fee__c fee : fees) {
            if (fee.Payment_Schedule_Item__c != null && resultMap.containsKey(fee.Payment_Schedule_Item__c)) {
                resultMap.get(fee.Payment_Schedule_Item__c).put(fee.Type__c, fee);
            }
        }

        return resultMap;
    }

    /**
     * @description Create or update Payment_Fee__c records for a single Payment_Schedule_Item__c.
     * If fee records exist, they are updated; otherwise new records are created.
     * Note: Savings/Escrow is stored directly on Payment_Schedule_Item__c.To_Escrow_Amount__c
     *
     * @param scheduleItemId The Payment_Schedule_Item__c Id
     * @param bankingFee Banking fee amount
     * @param programFee Program fee amount
     * @param setupFee Setup fee amount
     */
    public static void upsertFeeRecords(
        Id scheduleItemId,
        Decimal bankingFee,
        Decimal programFee,
        Decimal setupFee
    ) {
        if (scheduleItemId == null) {
            return;
        }

        // Get existing fee records for this schedule item
        Map<Id, Map<String, Payment_Fee__c>> existingFees =
            getFeesByScheduleItemIds(new Set<Id>{ scheduleItemId });

        Map<String, Payment_Fee__c> feesByType = existingFees.get(scheduleItemId);
        if (feesByType == null) {
            feesByType = new Map<String, Payment_Fee__c>();
        }

        List<Payment_Fee__c> toUpsert = new List<Payment_Fee__c>();

        // Banking Fee
        toUpsert.add(upsertSingleFee(scheduleItemId, FEE_TYPE_BANKING, bankingFee, feesByType));

        // Program Fee
        toUpsert.add(upsertSingleFee(scheduleItemId, FEE_TYPE_PROGRAM, programFee, feesByType));

        // Setup Fee
        toUpsert.add(upsertSingleFee(scheduleItemId, FEE_TYPE_SETUP, setupFee, feesByType));

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }

    /**
     * @description Bulk upsert Payment_Fee__c records for multiple schedule items.
     * More efficient than calling upsertFeeRecords for each item individually.
     * Note: Savings/Escrow is stored directly on Payment_Schedule_Item__c.To_Escrow_Amount__c
     *
     * @param scheduleItemIds Set of schedule item Ids to process
     * @param wrapperMap Map of PSI Id to wrapper containing fee amounts
     */
    public static void bulkUpsertFeeRecords(
        Set<Id> scheduleItemIds,
        Map<Id, PaymentPlanEditorController.ScheduleItemWrapper> wrapperMap
    ) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' bulkUpsertFeeRecords | itemCount=' + (scheduleItemIds != null ? scheduleItemIds.size() : 0));
        if (scheduleItemIds == null || scheduleItemIds.isEmpty() || wrapperMap == null) {
            System.debug(LOG_PREFIX + ' ' + LOG_DEBUG + ' bulkUpsertFeeRecords | Skipping - empty input');
            return;
        }

        // Get existing fee records for all schedule items
        Map<Id, Map<String, Payment_Fee__c>> existingFees = getFeesByScheduleItemIds(scheduleItemIds);

        List<Payment_Fee__c> toUpsert = new List<Payment_Fee__c>();

        for (Id psiId : scheduleItemIds) {
            if (!wrapperMap.containsKey(psiId)) {
                continue;
            }

            PaymentPlanEditorController.ScheduleItemWrapper wrapper = wrapperMap.get(psiId);
            Map<String, Payment_Fee__c> feesByType = existingFees.get(psiId);
            if (feesByType == null) {
                feesByType = new Map<String, Payment_Fee__c>();
            }

            toUpsert.add(upsertSingleFee(psiId, FEE_TYPE_BANKING, wrapper.bankingFee, feesByType));
            toUpsert.add(upsertSingleFee(psiId, FEE_TYPE_PROGRAM, wrapper.programFee, feesByType));
            toUpsert.add(upsertSingleFee(psiId, FEE_TYPE_SETUP, wrapper.setupFee, feesByType));
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
            System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' bulkUpsertFeeRecords | ' + LOG_SUCCESS + ' upserted=' + toUpsert.size());
        }
    }

    /**
     * @description Delete all Payment_Fee__c records for given Payment_Schedule_Item__c Ids.
     * Used when switching versions or deleting schedule items.
     *
     * @param scheduleItemIds Set of Payment_Schedule_Item__c Ids
     */
    public static void deleteFeeRecords(Set<Id> scheduleItemIds) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' deleteFeeRecords | itemCount=' + (scheduleItemIds != null ? scheduleItemIds.size() : 0));
        if (scheduleItemIds == null || scheduleItemIds.isEmpty()) {
            return;
        }

        List<Payment_Fee__c> toDelete = [
            SELECT Id
            FROM Payment_Fee__c
            WHERE Payment_Schedule_Item__c IN :scheduleItemIds
            AND Type__c IN :SCHEDULE_ITEM_FEE_TYPES
        ];

        if (!toDelete.isEmpty()) {
            delete toDelete;
            System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' deleteFeeRecords | ' + LOG_SUCCESS + ' deleted=' + toDelete.size());
        }
    }

    // ============ PRIVATE HELPER METHODS ============

    /**
     * @description Create a single Payment_Fee__c record.
     *
     * @param scheduleItemId The parent Payment_Schedule_Item__c Id
     * @param feeType The fee type (Banking Fee, Program Fee, Setup Fee)
     * @param amount The fee amount
     * @return Payment_Fee__c record (not yet inserted)
     */
    private static Payment_Fee__c createFeeRecord(Id scheduleItemId, String feeType, Decimal amount) {
        Payment_Fee__c fee = new Payment_Fee__c();
        fee.Payment_Schedule_Item__c = scheduleItemId;
        fee.Type__c = feeType;
        fee.Amount__c = amount != null ? amount : 0;
        return fee;
    }

    /**
     * @description Helper to update existing fee or create new one.
     *
     * @param scheduleItemId The parent Payment_Schedule_Item__c Id
     * @param feeType The fee type
     * @param amount The fee amount
     * @param existingFees Map of existing fees by type
     * @return Payment_Fee__c record to upsert
     */
    private static Payment_Fee__c upsertSingleFee(
        Id scheduleItemId,
        String feeType,
        Decimal amount,
        Map<String, Payment_Fee__c> existingFees
    ) {
        Payment_Fee__c fee;

        if (existingFees.containsKey(feeType)) {
            // Update existing fee
            fee = existingFees.get(feeType);
            fee.Amount__c = amount != null ? amount : 0;
        } else {
            // Create new fee
            fee = createFeeRecord(scheduleItemId, feeType, amount);
        }

        return fee;
    }

    // ============ WIRE FEE METHODS ============

    /**
     * @description Create a wire fee record for a schedule item.
     *
     * @param scheduleItemId The parent Payment_Schedule_Item__c Id
     * @param wireType The wire fee type ('Wire Fee' or 'Wire Received Fee')
     * @param amount The wire fee amount (optional)
     * @return The created Payment_Fee__c record Id
     */
    public static Id createWireFeeRecord(Id scheduleItemId, String wireType, Decimal amount) {
        if (scheduleItemId == null) {
            throw new AuraHandledException('Schedule Item ID is required');
        }

        if (String.isBlank(wireType) || !WIRE_FEE_TYPES.contains(wireType)) {
            throw new AuraHandledException('Invalid wire fee type. Must be "Wire Fee" or "Wire Received Fee"');
        }

        Payment_Fee__c fee = new Payment_Fee__c();
        fee.Payment_Schedule_Item__c = scheduleItemId;
        fee.Type__c = wireType;
        fee.Amount__c = amount != null ? amount : 0;

        insert fee;
        return fee.Id;
    }

    /**
     * @description Retrieve wire fee records grouped by Payment_Schedule_Item__c Id.
     * Returns a map structure: PSI Id -> List of Payment_Fee__c records.
     *
     * @param scheduleItemIds Set of Payment_Schedule_Item__c Ids to query wire fees for
     * @return Map<Id, List<Payment_Fee__c>> - Map keyed by PSI Id containing list of wire fees
     */
    public static Map<Id, List<Payment_Fee__c>> getWireFeesByScheduleItemIds(Set<Id> scheduleItemIds) {
        Map<Id, List<Payment_Fee__c>> resultMap = new Map<Id, List<Payment_Fee__c>>();

        if (scheduleItemIds == null || scheduleItemIds.isEmpty()) {
            return resultMap;
        }

        // Initialize empty lists for each schedule item
        for (Id psiId : scheduleItemIds) {
            resultMap.put(psiId, new List<Payment_Fee__c>());
        }

        // Query wire fee records
        List<Payment_Fee__c> wireFees = [
            SELECT Id, Payment_Schedule_Item__c, Type__c, Amount__c
            FROM Payment_Fee__c
            WHERE Payment_Schedule_Item__c IN :scheduleItemIds
            AND Type__c IN :WIRE_FEE_TYPES
            ORDER BY CreatedDate ASC
        ];

        // Group by PSI Id
        for (Payment_Fee__c fee : wireFees) {
            if (fee.Payment_Schedule_Item__c != null && resultMap.containsKey(fee.Payment_Schedule_Item__c)) {
                resultMap.get(fee.Payment_Schedule_Item__c).add(fee);
            }
        }

        return resultMap;
    }

    /**
     * @description Delete wire fee records for given Payment_Schedule_Item__c Ids.
     *
     * @param scheduleItemIds Set of Payment_Schedule_Item__c Ids
     */
    public static void deleteWireFeeRecords(Set<Id> scheduleItemIds) {
        if (scheduleItemIds == null || scheduleItemIds.isEmpty()) {
            return;
        }

        List<Payment_Fee__c> toDelete = [
            SELECT Id
            FROM Payment_Fee__c
            WHERE Payment_Schedule_Item__c IN :scheduleItemIds
            AND Type__c IN :WIRE_FEE_TYPES
        ];

        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    /**
     * @description Delete a single wire fee record by Id.
     *
     * @param feeId The Payment_Fee__c record Id to delete
     */
    public static void deleteWireFeeById(Id feeId) {
        if (feeId == null) {
            throw new AuraHandledException('Fee ID is required');
        }

        Payment_Fee__c fee = [
            SELECT Id, Type__c
            FROM Payment_Fee__c
            WHERE Id = :feeId
            LIMIT 1
        ];

        if (!WIRE_FEE_TYPES.contains(fee.Type__c)) {
            throw new AuraHandledException('Cannot delete non-wire fee records using this method');
        }

        delete fee;
    }
}