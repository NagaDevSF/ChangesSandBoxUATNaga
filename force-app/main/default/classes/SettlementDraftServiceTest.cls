/**
 * @description Test class for SettlementDraftService, SettlementDraftController,
 *              SettlementDateUtils, and SettlementFeeCalculator.
 *              
 *              Uses the NEW data model (January 2026):
 *              - Settlement_Segment__c records (not JSON)
 *              - Settlement_Plan_Item__c records (not JSON)
 *              - CreditorOpportunity__c field (not Creditors_List__c)
 *
 * @author Settlement Calculator Team
 * @date January 2026
 *
 * NOTE: Tests that use BusinessHours require @IsTest(SeeAllData=true) because
 *       BusinessHours is a setup object that cannot be created in test context.
 */
@IsTest
private class SettlementDraftServiceTest {

    // ==================== CONSTANTS ====================
    private static final Decimal TEST_BALANCE = 20000.00;
    private static final Decimal TEST_SETTLEMENT_OFFER = 10000.00;
    private static final Decimal TEST_ESCROW_START = 15000.00;
    private static final Decimal TEST_PAYMENT_AMOUNT = 2500.00;
    private static final Decimal TEST_COMMISSION_FEE = 35.00;
    private static final Decimal TEST_BANK_FEE = 35.00;
    private static final Decimal TEST_EPPS_TXN_FEE = 12.00;

    private static String getItemStatusValue(String label, String fallbackLabel) {
        Map<String, String> statusMap = new Map<String, String>();
        for (Schema.PicklistEntry entry :
            Schema.SObjectType.Settlement_Plan_Item__c.fields.Status__c.getPicklistValues()
        ) {
            if (entry == null) continue;
            if (String.isNotBlank(entry.getLabel())) {
                statusMap.put(entry.getLabel().toLowerCase(), entry.getValue());
            }
            if (String.isNotBlank(entry.getValue())) {
                statusMap.put(entry.getValue().toLowerCase(), entry.getValue());
            }
        }
        if (String.isNotBlank(label) && statusMap.containsKey(label.toLowerCase())) {
            return statusMap.get(label.toLowerCase());
        }
        if (String.isNotBlank(fallbackLabel) && statusMap.containsKey(fallbackLabel.toLowerCase())) {
            return statusMap.get(fallbackLabel.toLowerCase());
        }
        return String.isNotBlank(label) ? label : fallbackLabel;
    }

    private static String statusScheduled() {
        return getItemStatusValue('Scheduled', null);
    }

    private static String statusCleared() {
        return getItemStatusValue('Cleared', 'Paid');
    }

    private static String statusProcessing() {
        return getItemStatusValue('Processing', null);
    }

    private static String statusSuspended() {
        return getItemStatusValue('Suspended', null);
    }

    private static String statusVoid() {
        return getItemStatusValue('Void', null);
    }

    private static String statusMissed() {
        return getItemStatusValue('Missed', null);
    }

    private static String statusCancelled() {
        return getItemStatusValue('Cancelled', null);
    }

    private static String statusSkipped() {
        return getItemStatusValue('Skipped', null);
    }

    // ==================== TEST DATA FACTORY ====================
    
    /**
     * @description Creates and returns a new CreditorOpportunity for tests.
     *              Note: We don't use @TestSetup because some tests in this class
     *              use @IsTest(SeeAllData=true) for BusinessHours access, and Salesforce
     *              doesn't allow @TestSetup in a class with SeeAllData tests.
     */
    private static CreditorOpportunity__c getTestCreditorOpportunity() {
        Account acc = new Account(Name = 'Test Settlement Account');
        insert acc;
        
        CreditorOpportunity__c credOpp = new CreditorOpportunity__c(
            Name = 'Test Creditor Opportunity',
            CreditorAccount__c = acc.Id,
            Amount__c = TEST_BALANCE,
            Escrow_Start_Balance__c = TEST_ESCROW_START
        );
        insert credOpp;
        return credOpp;
    }

    /**
     * @description Creates a NEW CreditorOpportunity (for SeeAllData tests that can't use TestSetup)
     */
    private static CreditorOpportunity__c createNewCreditorOpportunity() {
        Account acc = new Account(Name = 'Test Settlement Account - SeeAllData');
        insert acc;
        
        CreditorOpportunity__c credOpp = new CreditorOpportunity__c(
            Name = 'Test Creditor Opportunity - SeeAllData',
            CreditorAccount__c = acc.Id,
            Amount__c = TEST_BALANCE,
            Escrow_Start_Balance__c = TEST_ESCROW_START
        );
        insert credOpp;
        return credOpp;
    }

    /**
     * @description Creates a test draft with basic fields (no segments/items)
     */
    private static Settlement_Plan_Draft__c createTestDraft(Id credOppId, String name, String status) {
        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = name,
            CreditorOpportunity__c = credOppId,
            Status__c = status,
            Balance__c = TEST_BALANCE,
            Settlement_Offer_Amount__c = TEST_SETTLEMENT_OFFER,
            Escrow_Start_Balance__c = TEST_ESCROW_START,
            Commission_Fee__c = TEST_COMMISSION_FEE,
            Is_Manually_Modified__c = false
        );
        insert draft;
        return draft;
    }

    /**
     * @description Overload - creates draft with default 'Draft' status
     */
    private static Settlement_Plan_Draft__c createTestDraft(Id credOppId, String name) {
        return createTestDraft(credOppId, name, SettlementDraftService.STATUS_DRAFT);
    }

    /**
     * @description Creates test segments for a draft
     */
    private static List<Settlement_Segment__c> createTestSegments(Id draftId, Integer count) {
        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>();
        
        for (Integer i = 1; i <= count; i++) {
            segments.add(new Settlement_Segment__c(
                Settlement_Plan__c = draftId,
                Segment_Order__c = i,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            ));
        }
        
        insert segments;
        return segments;
    }

    /**
     * @description Creates test payment items for a draft
     */
    private static List<Settlement_Plan_Item__c> createTestPaymentItems(Id draftId, Integer count) {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();

        for (Integer i = 1; i <= count; i++) {
            items.add(new Settlement_Plan_Item__c(
                Settlement_Plan__c = draftId,
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                EPPS_Month_End_Fee__c = 0,
                Payee_Fee__c = 0,
                Status__c = statusScheduled()
            ));
        }

        insert items;
        return items;
    }

    /**
     * @description Creates payment items with specific statuses (for locked row tests)
     */
    private static List<Settlement_Plan_Item__c> createPaymentItemsWithStatuses(
        Id draftId,
        List<String> statuses
    ) {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();

        for (Integer i = 0; i < statuses.size(); i++) {
            items.add(new Settlement_Plan_Item__c(
                Settlement_Plan__c = draftId,
                Payment_Number__c = i + 1,
                Payment_Date__c = Date.today().addMonths(i + 1),
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                EPPS_Month_End_Fee__c = 0,
                Payee_Fee__c = 0,
                Status__c = statuses[i]
            ));
        }

        insert items;
        return items;
    }

    /**
     * @description Creates a mock config for FeeCalculator tests
     */
    private static Settlement_Calc_Config__mdt createMockConfig() {
        // Note: Custom Metadata cannot be inserted in tests, so we create in-memory
        Settlement_Calc_Config__mdt config = new Settlement_Calc_Config__mdt(
            DeveloperName = 'Test_Config',
            Default_Bank_Fee__c = TEST_BANK_FEE,
            EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
            EPPS_Monthly_Minimum__c = 55.00,
            Fully_Funded_Tolerance__c = SettlementDraftService.DEFAULT_BALANCE_CHECK_TOLERANCE
        );
        return config;
    }

    // ==================== SERVICE: CRUD TESTS ====================

    @IsTest
    static void testCreateDraft_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        Test.startTest();
        Settlement_Plan_Draft__c draft = SettlementDraftService.createDraft(credOpp.Id, 'Test Draft');
        Test.stopTest();

        System.assertNotEquals(null, draft.Id, 'Draft should be created');
        System.assertEquals('Test Draft', draft.Name, 'Name should match');
        System.assertEquals(SettlementDraftService.STATUS_DRAFT, draft.Status__c, 'Status should be Draft');
        System.assertEquals(credOpp.Id, draft.CreditorOpportunity__c, 'Should link to CreditorOpportunity');
        System.assertEquals(credOpp.Amount__c, draft.Balance__c, 'Balance should copy from CredOpp');
    }

    @IsTest
    static void testCreateDraft_NullCredOppId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftService.createDraft(null, 'Test Draft');
            System.assert(false, 'Should throw exception for null CredOpp ID');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetDrafts_ReturnsDrafts() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        createTestDraft(credOpp.Id, 'Draft 1');
        createTestDraft(credOpp.Id, 'Draft 2');

        Test.startTest();
        List<Settlement_Plan_Draft__c> drafts = SettlementDraftService.getDrafts(credOpp.Id);
        Test.stopTest();

        System.assertEquals(2, drafts.size(), 'Should return 2 drafts');
    }

    @IsTest
    static void testGetDrafts_NullId_ReturnsEmptyList() {
        Test.startTest();
        List<Settlement_Plan_Draft__c> drafts = SettlementDraftService.getDrafts(null);
        Test.stopTest();

        System.assertEquals(0, drafts.size(), 'Should return empty list for null ID');
    }

    @IsTest
    static void testGetDraftWithDetails_ReturnsSegmentsAndItems() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Detail Test');
        createTestSegments(draft.Id, 1);
        createTestPaymentItems(draft.Id, 4);

        Test.startTest();
        SettlementDraftService.DraftWrapper wrapper = SettlementDraftService.getDraftWithDetails(draft.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper.draft, 'Draft should be returned');
        System.assertEquals(1, wrapper.segments.size(), 'Should have 1 segment');
        System.assertEquals(4, wrapper.paymentItems.size(), 'Should have 4 payment items');
        System.assertNotEquals(null, wrapper.creditorOpportunity, 'Should include CreditorOpportunity');
    }

    @IsTest
    static void testGetDraftWithDetails_NullId_ReturnsEmptyWrapper() {
        Test.startTest();
        SettlementDraftService.DraftWrapper wrapper = SettlementDraftService.getDraftWithDetails(null);
        Test.stopTest();

        System.assertEquals(null, wrapper.draft, 'Draft should be null');
        System.assertEquals(0, wrapper.segments.size(), 'Segments should be empty');
        System.assertEquals(0, wrapper.paymentItems.size(), 'Items should be empty');
    }

    @IsTest
    static void testGetDefaultDraft_ReturnsActive() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        createTestDraft(credOpp.Id, 'Draft Status');
        Settlement_Plan_Draft__c activeDraft = createTestDraft(credOpp.Id, 'Active Draft', SettlementDraftService.STATUS_ACTIVE);

        Test.startTest();
        Settlement_Plan_Draft__c defaultDraft = SettlementDraftService.getDefaultDraft(credOpp.Id);
        Test.stopTest();

        System.assertEquals(activeDraft.Id, defaultDraft.Id, 'Should return Active draft');
    }

    @IsTest
    static void testGetDefaultDraft_NoActive_ReturnsNewestDraft() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        createTestDraft(credOpp.Id, 'Draft 1');
        createTestDraft(credOpp.Id, 'Draft 2');

        Test.startTest();
        Settlement_Plan_Draft__c defaultDraft = SettlementDraftService.getDefaultDraft(credOpp.Id);
        Test.stopTest();

        System.assertNotEquals(null, defaultDraft, 'Should return a draft');
    }

    @IsTest
    static void testGetDefaultDraft_NullId_ReturnsNull() {
        Test.startTest();
        Settlement_Plan_Draft__c result = SettlementDraftService.getDefaultDraft(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null ID');
    }

    @IsTest
    static void testSaveDraftWithRecords_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Save Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 4; i++) {
            items.add(new Settlement_Plan_Item__c(
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ));
        }

        Test.startTest();
        Settlement_Plan_Draft__c savedDraft = SettlementDraftService.saveDraftWithRecords(
            draft.Id, segments, items
        );
        Test.stopTest();

        System.assertNotEquals(null, savedDraft, 'Should return saved draft');
        
        List<Settlement_Segment__c> savedSegments = [
            SELECT Id FROM Settlement_Segment__c WHERE Settlement_Plan__c = :draft.Id
        ];
        System.assertEquals(1, savedSegments.size(), 'Should have 1 segment');

        List<Settlement_Plan_Item__c> savedItems = [
            SELECT Id FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :draft.Id
        ];
        System.assertEquals(4, savedItems.size(), 'Should have 4 items');
    }

    @IsTest
    static void testSaveDraftWithRecords_NonEditableStatus_ThrowsException() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Test Active status
        Settlement_Plan_Draft__c activeDraft = createTestDraft(credOpp.Id, 'Active Draft', SettlementDraftService.STATUS_ACTIVE);
        try {
            SettlementDraftService.saveDraftWithRecords(activeDraft.Id, null, null);
            System.assert(false, 'Should throw exception for Active draft');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Cannot edit'), 'Active: Error should mention cannot edit');
        }

        // Test Archived status
        Settlement_Plan_Draft__c archivedDraft = createTestDraft(credOpp.Id, 'Archived Draft', SettlementDraftService.STATUS_ARCHIVED);
        try {
            SettlementDraftService.saveDraftWithRecords(archivedDraft.Id, null, null);
            System.assert(false, 'Should throw exception for Archived draft');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Cannot edit'), 'Archived: Error should mention cannot edit');
        }
    }

    @IsTest
    static void testSaveDraftWithRecords_DeletesOrphanedSegments() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Orphan Test');

        // Create and save 2 segments
        List<Settlement_Segment__c> twoSegments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 2,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            ),
            new Settlement_Segment__c(
                Segment_Order__c = 2,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 2,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(60)
            )
        };

        SettlementDraftService.saveDraftWithRecords(draft.Id, twoSegments, null);

        // Verify 2 segments exist
        List<Settlement_Segment__c> savedSegments = [
            SELECT Id, Segment_Order__c, Segment_Type__c, Payment_Amount__c,
                   Payment_Count__c, Frequency__c, Start_Date__c
            FROM Settlement_Segment__c
            WHERE Settlement_Plan__c = :draft.Id
            ORDER BY Segment_Order__c
        ];
        System.assertEquals(2, savedSegments.size(), 'Should have 2 segments initially');

        // Now save with only 1 segment (simulating user deleted one in UI)
        List<Settlement_Segment__c> oneSegment = new List<Settlement_Segment__c>{
            savedSegments[0]  // Keep only the first segment with its ID
        };

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(draft.Id, oneSegment, null);
        Test.stopTest();

        // Verify only 1 segment remains (orphan was deleted)
        List<Settlement_Segment__c> remainingSegments = [
            SELECT Id FROM Settlement_Segment__c WHERE Settlement_Plan__c = :draft.Id
        ];
        System.assertEquals(1, remainingSegments.size(), 'Should have 1 segment after orphan deletion');
        System.assertEquals(savedSegments[0].Id, remainingSegments[0].Id, 'Should keep the first segment');
    }

    @IsTest
    static void testSaveDraftWithRecords_NullDraftId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftService.saveDraftWithRecords(null, null, null);
            System.assert(false, 'Should throw exception for null draft ID');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCloneDraft_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c sourceDraft = createTestDraft(credOpp.Id, 'Source Draft');
        createTestSegments(sourceDraft.Id, 1);
        createTestPaymentItems(sourceDraft.Id, 4);

        Test.startTest();
        Settlement_Plan_Draft__c clonedDraft = SettlementDraftService.cloneDraft(sourceDraft.Id, 'Cloned Draft');
        Test.stopTest();

        System.assertNotEquals(sourceDraft.Id, clonedDraft.Id, 'Should be a new record');
        System.assertEquals('Cloned Draft', clonedDraft.Name, 'Name should match');
        System.assertEquals(SettlementDraftService.STATUS_DRAFT, clonedDraft.Status__c, 'Cloned draft should be Draft status');
        System.assertEquals(sourceDraft.Id, clonedDraft.Cloned_From__c, 'Should reference source');
        System.assertEquals(TEST_COMMISSION_FEE, clonedDraft.Commission_Fee__c, 'Commission fee should be cloned');

        List<Settlement_Segment__c> clonedSegments = [
            SELECT Id FROM Settlement_Segment__c WHERE Settlement_Plan__c = :clonedDraft.Id
        ];
        System.assertEquals(1, clonedSegments.size(), 'Should clone segment');

        List<Settlement_Plan_Item__c> clonedItems = [
            SELECT Id, Status__c FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :clonedDraft.Id
        ];
        System.assertEquals(4, clonedItems.size(), 'Should clone items');
        System.assertEquals(statusScheduled(), clonedItems[0].Status__c, 'Cloned items should be Scheduled');
    }

    @IsTest
    static void testCloneDraft_NullSourceId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftService.cloneDraft(null, 'Clone');
            System.assert(false, 'Should throw exception for null source ID');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCloneThenSave_WithoutCalculate_ItemsPersist() {
        // Bug fix test: Clone + Save without Calculate should preserve items
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c sourceDraft = createTestDraft(credOpp.Id, 'Source Draft');
        List<Settlement_Segment__c> sourceSegments = createTestSegments(sourceDraft.Id, 1);
        List<Settlement_Plan_Item__c> sourceItems = createTestPaymentItems(sourceDraft.Id, 4);

        // Clone the draft
        Settlement_Plan_Draft__c clonedDraft = SettlementDraftService.cloneDraft(sourceDraft.Id, 'Cloned Draft');

        // Get cloned items (these have IDs from the clone operation)
        List<Settlement_Plan_Item__c> clonedItems = [
            SELECT Id, Payment_Number__c, Payment_Amount__c, Payment_Date__c, Original_Payment_Date__c, Settlement_Plan__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :clonedDraft.Id
            ORDER BY Payment_Number__c
        ];
        System.assertEquals(4, clonedItems.size(), 'Clone should have 4 items initially');

        // Get cloned segments
        List<Settlement_Segment__c> clonedSegments = [
            SELECT Id FROM Settlement_Segment__c WHERE Settlement_Plan__c = :clonedDraft.Id
        ];

        Test.startTest();
        // Save the cloned draft WITHOUT calculating - pass the existing items back
        Settlement_Plan_Draft__c savedDraft = SettlementDraftService.saveDraftWithRecords(
            clonedDraft.Id,
            clonedSegments,
            clonedItems,
            new Map<String, Object>()
        );
        Test.stopTest();

        // Verify items still exist after save
        List<Settlement_Plan_Item__c> itemsAfterSave = [
            SELECT Id FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :clonedDraft.Id
        ];
        System.assertEquals(4, itemsAfterSave.size(), 'Items should persist after save without calculate');
    }

    @IsTest
    static void testCloneThenModifyAndSave_UpdatesCorrectly() {
        // Test that modifying a cloned item and saving updates it correctly
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c sourceDraft = createTestDraft(credOpp.Id, 'Source Draft');
        createTestSegments(sourceDraft.Id, 1);
        createTestPaymentItems(sourceDraft.Id, 3);

        // Clone the draft
        Settlement_Plan_Draft__c clonedDraft = SettlementDraftService.cloneDraft(sourceDraft.Id, 'Cloned Draft');

        // Get cloned items
        List<Settlement_Plan_Item__c> clonedItems = [
            SELECT Id, Payment_Number__c, Payment_Amount__c, Payment_Date__c, Original_Payment_Date__c, Settlement_Plan__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :clonedDraft.Id
            ORDER BY Payment_Number__c
        ];
        List<Settlement_Segment__c> clonedSegments = [
            SELECT Id FROM Settlement_Segment__c WHERE Settlement_Plan__c = :clonedDraft.Id
        ];

        // Modify one item's amount
        Decimal originalAmount = clonedItems[0].Payment_Amount__c;
        Decimal newAmount = originalAmount + 100;
        clonedItems[0].Payment_Amount__c = newAmount;

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(
            clonedDraft.Id,
            clonedSegments,
            clonedItems,
            new Map<String, Object>()
        );
        Test.stopTest();

        // Verify the modification was saved
        Settlement_Plan_Item__c updatedItem = [
            SELECT Payment_Amount__c FROM Settlement_Plan_Item__c WHERE Id = :clonedItems[0].Id
        ];
        System.assertEquals(newAmount, updatedItem.Payment_Amount__c, 'Modified item should be updated');

        // Verify all items still exist
        Integer itemCount = [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :clonedDraft.Id];
        System.assertEquals(3, itemCount, 'All items should still exist');
    }

    @IsTest
    static void testCloneThenDeleteItemAndSave_RemovesOnlyDeletedItem() {
        // Test that removing an item from the list and saving deletes only that item
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c sourceDraft = createTestDraft(credOpp.Id, 'Source Draft');
        createTestSegments(sourceDraft.Id, 1);
        createTestPaymentItems(sourceDraft.Id, 4);

        // Clone the draft
        Settlement_Plan_Draft__c clonedDraft = SettlementDraftService.cloneDraft(sourceDraft.Id, 'Cloned Draft');

        // Get cloned items
        List<Settlement_Plan_Item__c> clonedItems = [
            SELECT Id, Payment_Number__c, Payment_Amount__c, Payment_Date__c, Original_Payment_Date__c, Settlement_Plan__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :clonedDraft.Id
            ORDER BY Payment_Number__c
        ];
        List<Settlement_Segment__c> clonedSegments = [
            SELECT Id FROM Settlement_Segment__c WHERE Settlement_Plan__c = :clonedDraft.Id
        ];
        System.assertEquals(4, clonedItems.size(), 'Should start with 4 items');

        // Remove one item from the list (simulate user deleting in UI)
        Id removedItemId = clonedItems[0].Id;
        clonedItems.remove(0);
        System.assertEquals(3, clonedItems.size(), 'List should have 3 items after removal');

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(
            clonedDraft.Id,
            clonedSegments,
            clonedItems,
            new Map<String, Object>()
        );
        Test.stopTest();

        // Verify only 3 items remain
        List<Settlement_Plan_Item__c> itemsAfterSave = [
            SELECT Id FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :clonedDraft.Id
        ];
        System.assertEquals(3, itemsAfterSave.size(), 'Should have 3 items after save');

        // Verify the removed item is actually deleted
        Integer deletedItemCount = [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Id = :removedItemId];
        System.assertEquals(0, deletedItemCount, 'Removed item should be deleted from database');
    }

    @IsTest
    static void testDeleteDraft_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Delete Test');
        createTestSegments(draft.Id, 1);
        createTestPaymentItems(draft.Id, 2);

        Test.startTest();
        SettlementDraftService.deleteDraft(draft.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Settlement_Plan_Draft__c WHERE Id = :draft.Id], 
            'Draft should be deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Settlement_Segment__c WHERE Settlement_Plan__c = :draft.Id], 
            'Segments should cascade delete');
        System.assertEquals(0, [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :draft.Id], 
            'Items should cascade delete');
    }

    @IsTest
    static void testDeleteDraft_NonDeletableStatus_ThrowsException() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Test Active status
        Settlement_Plan_Draft__c activeDraft = createTestDraft(credOpp.Id, 'Active Draft', SettlementDraftService.STATUS_ACTIVE);
        try {
            SettlementDraftService.deleteDraft(activeDraft.Id);
            System.assert(false, 'Should throw exception for Active draft');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Cannot delete'), 'Active: Error should mention cannot delete');
        }

        // Test Applied status
        Settlement_Plan_Draft__c appliedDraft = createTestDraft(credOpp.Id, 'Applied Draft', SettlementDraftService.STATUS_APPLIED);
        try {
            SettlementDraftService.deleteDraft(appliedDraft.Id);
            System.assert(false, 'Should throw exception for Applied draft');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Cannot delete'), 'Applied: Error should mention cannot delete');
        }
    }

    @IsTest
    static void testDeleteDraft_NullId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftService.deleteDraft(null);
            System.assert(false, 'Should throw exception for null ID');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    // ==================== SERVICE: CALCULATION TESTS ====================
    // Note: These tests require @IsTest(SeeAllData=true) due to BusinessHours dependency

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_FixedSegment() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Calc Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(4, result.numberOfPayments, 'Should have 4 payments');
        System.assertEquals(TEST_SETTLEMENT_OFFER, result.totalScheduledAmount, 'Total should match settlement offer');
    }

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_RemainderSegment() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Remainder Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Remainder',
                Payment_Amount__c = 2000.00,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(5, result.numberOfPayments, 'Should have 5 payments ($10k / $2k)');
        System.assertEquals(TEST_SETTLEMENT_OFFER, result.totalScheduledAmount, 'Total should match settlement offer');
    }

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_SolveAmountSegment() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'SolveAmount Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'SolveAmount',
                Payment_Count__c = 5,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(5, result.numberOfPayments, 'Should have 5 payments');
        System.assertEquals(TEST_SETTLEMENT_OFFER, result.totalScheduledAmount, 'Total should match settlement offer');
    }

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_MultipleSegments() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Multi Segment Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = 3000.00,
                Payment_Count__c = 2,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            ),
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 2,
                Segment_Type__c = 'Remainder',
                Payment_Amount__c = 2000.00,
                Frequency__c = 'Monthly'
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assertEquals(TEST_SETTLEMENT_OFFER, result.totalScheduledAmount, 'Total should match settlement offer');
    }

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_NoSegments_Fails() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'No Segments Test');

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, new List<Settlement_Segment__c>(), TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with no segments');
        System.assert(result.errorMessage.contains('segment'), 'Error should mention segments');
    }

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_NoStartDate_Fails() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'No Start Date Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly'
                // No Start_Date__c
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail without start date');
        System.assert(result.errorMessage.contains('Start Date'), 'Error should mention Start Date');
    }

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_NoCommissionFee_Fails() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = 'No Commission Test',
            CreditorOpportunity__c = credOpp.Id,
            Status__c = SettlementDraftService.STATUS_DRAFT,
            Balance__c = TEST_BALANCE,
            Settlement_Offer_Amount__c = TEST_SETTLEMENT_OFFER,
            Escrow_Start_Balance__c = TEST_ESCROW_START
            // No Commission_Fee__c
        );
        insert draft;

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        Test.startTest();
        // Pass null for commissionFee to test the validation
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, null, 0
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail without commission fee');
        System.assert(result.errorMessage.contains('Commission Fee'), 'Error should mention Commission Fee');
    }

    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_InvalidSegmentType_Fails() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Invalid Type Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'InvalidType',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with invalid segment type');
        System.assert(result.errorMessage.containsIgnoreCase('invalid'), 'Error should mention invalid type');
    }

    // ==================== SERVICE: RECALCULATION TESTS ====================

    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_Success() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Recalc Test');
        List<Settlement_Plan_Item__c> items = createTestPaymentItems(draft.Id, 4);

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Recalculation should succeed');
        System.assertEquals(4, result.paymentItems.size(), 'Should have 4 items');
        System.assertEquals(TEST_SETTLEMENT_OFFER, result.totalScheduledAmount, 'Total should match settlement offer');
        System.assertEquals(true, result.isBalanced, 'Should be balanced');
    }

    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_WithLockedRows_PreservesValues() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Locked Rows Test');

        // Create items with Paid statuses (Paid and Processing are locked)
        List<Settlement_Plan_Item__c> items = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{statusCleared(), statusCleared(), statusScheduled(), statusScheduled()}
        );

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Recalculation should succeed');
        System.assertEquals(4, result.paymentItems.size(), 'Should have 4 items');

        // Verify locked rows (Cleared) remain unchanged
        Settlement_Plan_Item__c paidItem1 = result.paymentItems[0];
        Settlement_Plan_Item__c paidItem2 = result.paymentItems[1];

        System.assertEquals(statusCleared(), paidItem1.Status__c,
            'Cleared item 1 status should be preserved');
        System.assertEquals(statusCleared(), paidItem2.Status__c,
            'Cleared item 2 status should be preserved');
    }

    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_Underfunded() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Underfunded Test');
        
        // Create items that total less than settlement offer
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 3; i++) {
            items.add(new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = 2000.00, // Only $6000 total vs $10000 offer
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ));
        }
        insert items;

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Recalculation should succeed');
        System.assertEquals(false, result.isBalanced, 'Should NOT be balanced');
        System.assert(result.warningMessage.contains('underfunded'), 'Should show underfunded warning');
        System.assertEquals(6000.00, result.totalScheduledAmount, 'Total should be $6000');
        System.assert(result.fundingDifference < 0, 'Funding difference should be negative');
    }

    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_Overfunded() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Overfunded Test');
        
        // Create items that total more than settlement offer
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 5; i++) {
            items.add(new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = TEST_PAYMENT_AMOUNT, // $12,500 total vs $10000 offer
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ));
        }
        insert items;

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Recalculation should succeed');
        System.assertEquals(false, result.isBalanced, 'Should NOT be balanced');
        System.assert(result.warningMessage.contains('overfunded'), 'Should show overfunded warning');
        System.assertEquals(12500.00, result.totalScheduledAmount, 'Total should be $12,500');
        System.assert(result.fundingDifference > 0, 'Funding difference should be positive');
    }

    @IsTest
    static void testRecalculateBalances_EmptyList_Fails() {
        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            new List<Settlement_Plan_Item__c>(), TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with empty list');
        System.assert(result.errorMessage.contains('No payment items'), 'Should mention no items');
    }

    @IsTest
    static void testRecalculateBalances_NullList_Fails() {
        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            null, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with null list');
    }

    // ==================== SERVICE: ACTIVATION TESTS ====================

    @IsTest(SeeAllData=true)
    static void testActivateDraft_Success() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Activate Test');
        createTestSegments(draft.Id, 1);
        createTestPaymentItems(draft.Id, 4);

        Test.startTest();
        SettlementDraftService.ActivationResult result = SettlementDraftService.activateDraft(draft.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Activation should succeed');
        System.assertEquals(1, result.segmentCount, 'Should have 1 segment');
        System.assertEquals(4, result.paymentItemCount, 'Should have 4 payment items');
        System.assertEquals(draft.Id, result.activatedDraftId, 'Should return draft ID');

        Settlement_Plan_Draft__c updatedDraft = [
            SELECT Status__c, Applied_Date__c
            FROM Settlement_Plan_Draft__c
            WHERE Id = :draft.Id
        ];
        System.assertEquals(SettlementDraftService.STATUS_ACTIVE, updatedDraft.Status__c, 'Draft should be Active');
        System.assertNotEquals(null, updatedDraft.Applied_Date__c, 'Applied date should be set');

        // Verify Active_Plan__c is set on CreditorOpportunity
        CreditorOpportunity__c updatedCredOpp = [
            SELECT Active_Plan__c FROM CreditorOpportunity__c WHERE Id = :credOpp.Id
        ];
        System.assertEquals(draft.Id, updatedCredOpp.Active_Plan__c, 'Active_Plan__c should point to activated draft');
    }

    @IsTest(SeeAllData=true)
    static void testActivateDraft_ArchivesPreviousActive() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        
        // Create first Active draft
        Settlement_Plan_Draft__c firstDraft = createTestDraft(credOpp.Id, 'First Draft', SettlementDraftService.STATUS_ACTIVE);
        createTestPaymentItems(firstDraft.Id, 2);

        // Create second Draft to activate
        Settlement_Plan_Draft__c secondDraft = createTestDraft(credOpp.Id, 'Second Draft');
        createTestSegments(secondDraft.Id, 1);
        createTestPaymentItems(secondDraft.Id, 4);

        Test.startTest();
        SettlementDraftService.ActivationResult result = SettlementDraftService.activateDraft(secondDraft.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Activation should succeed');

        Settlement_Plan_Draft__c updatedFirst = [
            SELECT Status__c FROM Settlement_Plan_Draft__c WHERE Id = :firstDraft.Id
        ];
        System.assertEquals(SettlementDraftService.STATUS_ARCHIVED, updatedFirst.Status__c, 'First draft should be Archived');
    }

    @IsTest(SeeAllData=true)
    static void testActivateDraft_NotDraftStatus_Fails() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Active Draft', SettlementDraftService.STATUS_ACTIVE);

        Test.startTest();
        SettlementDraftService.ActivationResult result = SettlementDraftService.activateDraft(draft.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail for non-Draft status');
        System.assert(result.errorMessage.contains('Draft'), 'Error should mention Draft status');
    }

    @IsTest(SeeAllData=true)
    static void testActivateDraft_NoPaymentItems_Fails() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Empty Draft');

        Test.startTest();
        SettlementDraftService.ActivationResult result = SettlementDraftService.activateDraft(draft.Id);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail without payment items');
        System.assert(result.errorMessage.contains('payment items'), 'Error should mention payment items');
    }

    @IsTest(SeeAllData=true)
    static void testActivateDraft_NullId_Fails() {
        Test.startTest();
        SettlementDraftService.ActivationResult result = SettlementDraftService.activateDraft(null);
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail for null ID');
        System.assert(result.errorMessage.contains('required'), 'Error should mention required');
    }

    // ==================== BULK OPERATION TESTS ====================

    @IsTest
    static void testBulkDraftCreation() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        
        Test.startTest();
        List<Settlement_Plan_Draft__c> drafts = new List<Settlement_Plan_Draft__c>();
        for (Integer i = 0; i < 50; i++) {
            drafts.add(new Settlement_Plan_Draft__c(
                Name = 'Bulk Draft ' + i,
                CreditorOpportunity__c = credOpp.Id,
                Status__c = SettlementDraftService.STATUS_DRAFT,
                Balance__c = TEST_BALANCE,
                Settlement_Offer_Amount__c = TEST_SETTLEMENT_OFFER,
                Escrow_Start_Balance__c = TEST_ESCROW_START,
                Commission_Fee__c = TEST_COMMISSION_FEE
            ));
        }
        insert drafts;
        Test.stopTest();

        System.assertEquals(50, [SELECT COUNT() FROM Settlement_Plan_Draft__c WHERE CreditorOpportunity__c = :credOpp.Id],
            'Should create 50 drafts');
    }

    @IsTest
    static void testBulkPaymentItemCreation() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Bulk Items Test');

        Test.startTest();
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 100; i++) {
            items.add(new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addDays(i * 7),
                Payment_Amount__c = 100.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ));
        }
        insert items;
        Test.stopTest();

        System.assertEquals(100, [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :draft.Id],
            'Should create 100 payment items');
    }

    // ==================== CONTROLLER TESTS ====================

    @IsTest
    static void testController_GetDrafts() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        createTestDraft(credOpp.Id, 'Controller Test Draft');

        Test.startTest();
        List<Settlement_Plan_Draft__c> drafts = SettlementDraftController.getDrafts(credOpp.Id);
        Test.stopTest();

        System.assertEquals(1, drafts.size(), 'Should return 1 draft');
    }

    @IsTest
    static void testController_GetDraftWithDetails() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Detail Draft');
        createTestSegments(draft.Id, 1);
        createTestPaymentItems(draft.Id, 4);

        Test.startTest();
        SettlementDraftService.DraftWrapper wrapper = SettlementDraftController.getDraftWithDetails(draft.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper.draft, 'Draft should be returned');
        System.assertEquals(1, wrapper.segments.size(), 'Should have 1 segment');
        System.assertEquals(4, wrapper.paymentItems.size(), 'Should have 4 items');
    }

    @IsTest
    static void testController_GetDefaultDraft() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c activeDraft = createTestDraft(credOpp.Id, 'Active', SettlementDraftService.STATUS_ACTIVE);

        Test.startTest();
        Settlement_Plan_Draft__c result = SettlementDraftController.getDefaultDraft(credOpp.Id);
        Test.stopTest();

        System.assertEquals(activeDraft.Id, result.Id, 'Should return Active draft');
    }

    @IsTest
    static void testController_GetCreditorOpportunity_WithAndWithoutId() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Test with valid ID
        CreditorOpportunity__c result = SettlementDraftController.getCreditorOpportunity(credOpp.Id);
        System.assertEquals(credOpp.Id, result.Id, 'Valid ID: Should return correct CredOpp');

        // Test with null ID
        CreditorOpportunity__c nullResult = SettlementDraftController.getCreditorOpportunity(null);
        System.assertEquals(null, nullResult, 'Null ID: Should return null');
    }

    @IsTest
    static void testController_SaveDraftWithRecords() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Save Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = 2500,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.newInstance(2026, 3, 1)
            )
        };
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Number__c = 1,
                Payment_Date__c = Date.newInstance(2026, 3, 1),
                Payment_Amount__c = 2500,
                Status__c = statusScheduled()
            )
        };
        Map<String, Object> draftFields = new Map<String, Object>{
            'Commission_Fee__c' => 35
        };

        Test.startTest();
        Settlement_Plan_Draft__c saved = SettlementDraftController.saveDraftWithRecords(
            draft.Id, segments, items, draftFields
        );
        Test.stopTest();

        System.assertNotEquals(null, saved, 'Should return saved draft');
    }

    @IsTest
    static void testController_SaveDraftWithRecords_NullDraftId() {
        Test.startTest();
        try {
            SettlementDraftController.saveDraftWithRecords(
                null,
                new List<Settlement_Segment__c>(),
                new List<Settlement_Plan_Item__c>(),
                null
            );
            System.assert(false, 'Should throw for null draft ID');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testController_CloneDraft() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Original');

        Test.startTest();
        Settlement_Plan_Draft__c cloned = SettlementDraftController.cloneDraft(draft.Id, 'Cloned');
        Test.stopTest();

        System.assertNotEquals(draft.Id, cloned.Id, 'Should be a new record');
    }

    @IsTest
    static void testController_CloneDraft_NullId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftController.cloneDraft(null, 'Clone');
            System.assert(false, 'Should throw for null source ID');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    @IsTest
    static void testController_DeleteDraft() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Delete Test');

        Test.startTest();
        SettlementDraftController.deleteDraft(draft.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Settlement_Plan_Draft__c WHERE Id = :draft.Id],
            'Draft should be deleted');
    }

    @IsTest
    static void testController_DeleteDraft_NullId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftController.deleteDraft(null);
            System.assert(false, 'Should throw for null draft ID');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    @IsTest(SeeAllData=true)
    static void testController_CalculateDraftPlan() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Calc Test');

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = 2500,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.newInstance(2026, 3, 1)
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftController.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
    }

    @IsTest(SeeAllData=true)
    static void testController_RecalculateBalances() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Recalc Test');
        List<Settlement_Plan_Item__c> items = createTestPaymentItems(draft.Id, 4);

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftController.recalculateBalances(
            items, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Recalculation should succeed');
    }

    @IsTest(SeeAllData=true)
    static void testController_RecalculateBalances_EmptyList() {
        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftController.recalculateBalances(
            new List<Settlement_Plan_Item__c>(), TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with empty list');
    }

    @IsTest(SeeAllData=true)
    static void testController_RecalculateBalances_NullList() {
        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftController.recalculateBalances(
            null, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail with null list');
    }

    @IsTest(SeeAllData=true)
    static void testController_ActivateDraft() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Activate Test');
        createTestSegments(draft.Id, 1);
        createTestPaymentItems(draft.Id, 4);

        Test.startTest();
        SettlementDraftService.ActivationResult result = SettlementDraftController.activateDraft(draft.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Activation should succeed');
    }

    @IsTest
    static void testController_InitializeModal() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        createTestDraft(credOpp.Id, 'Init Test Draft');

        Test.startTest();
        SettlementDraftController.ModalInitResult result = SettlementDraftController.initializeModal(credOpp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.creditorOpportunity, 'Should have CredOpp');
        System.assertEquals(1, result.drafts.size(), 'Should have 1 draft');
        System.assertNotEquals(null, result.defaultDraft, 'Should have default draft');
    }

    @IsTest
    static void testController_InitializeModal_NullId() {
        Test.startTest();
        SettlementDraftController.ModalInitResult result = SettlementDraftController.initializeModal(null);
        Test.stopTest();

        System.assertEquals(null, result.creditorOpportunity, 'Should have null CredOpp');
        System.assertEquals(0, result.drafts.size(), 'Should have no drafts');
    }

    @IsTest
    static void testController_InitializeModal_WithActivePlan() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c activeDraft = createTestDraft(credOpp.Id, 'Active Plan', SettlementDraftService.STATUS_ACTIVE);
        createTestPaymentItems(activeDraft.Id, 4);

        Test.startTest();
        SettlementDraftController.ModalInitResult result = SettlementDraftController.initializeModal(credOpp.Id);
        Test.stopTest();

        System.assertEquals(true, result.hasExistingPlan, 'Should have existing plan');
    }

    @IsTest
    static void testController_GetFeeConfig_Success() {
        // getFeeConfig returns fee values from custom metadata config
        Test.startTest();
        Map<String, Decimal> config = SettlementDraftController.getFeeConfig();
        Test.stopTest();

        System.assertNotEquals(null, config, 'Config should not be null');
        System.assert(config.containsKey('bankFee'), 'Should contain bankFee key');
        System.assert(config.containsKey('eppsTransactionFee'), 'Should contain eppsTransactionFee key');
        // Verify values match test constants (from config)
        System.assertEquals(TEST_BANK_FEE, config.get('bankFee'), 'Bank fee should match config');
        System.assertEquals(TEST_EPPS_TXN_FEE, config.get('eppsTransactionFee'), 'EPPS fee should match config');
    }

    /**
     * @description Test saveDraftWithRecords with null parameters to cover null-handling branches
     */
    @IsTest
    static void testController_SaveDraftWithRecords_NullParams() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Null Params Test');

        Test.startTest();
        // Pass nulls for segments, items, and draftFields - should handle gracefully
        Settlement_Plan_Draft__c saved = SettlementDraftController.saveDraftWithRecords(
            draft.Id, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, saved, 'Should return saved draft even with null params');
    }

    /**
     * @description Test createAndSaveDraft with null parameters to cover null-handling branches
     */
    @IsTest
    static void testController_CreateAndSaveDraft_NullParams() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        Test.startTest();
        // Pass nulls for segments, items, and draftFields - should handle gracefully
        Settlement_Plan_Draft__c draft = SettlementDraftController.createAndSaveDraft(
            credOpp.Id, 'Null Params Draft', null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, draft.Id, 'Draft should be created with null params');
    }

    /**
     * @description Test calculateDraftPlan with null segments to cover null-handling branch
     */
    @IsTest(SeeAllData=true)
    static void testController_CalculateDraftPlan_NullSegments() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Null Segments Test');

        Test.startTest();
        // Pass null for segments - should handle gracefully and return error
        SettlementDraftService.DraftCalculationResult result = SettlementDraftController.calculateDraftPlan(
            draft.Id, null, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        // With null segments converted to empty list, calculation should fail validation
        System.assertEquals(false, result.success, 'Should fail with no segments');
    }

    /**
     * @description Test initializeModal returns correctly when no drafts exist
     */
    @IsTest
    static void testController_InitializeModal_NoDrafts() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        // Don't create any drafts

        Test.startTest();
        SettlementDraftController.ModalInitResult result = SettlementDraftController.initializeModal(credOpp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.creditorOpportunity, 'CredOpp should be returned');
        System.assertEquals(null, result.defaultDraft, 'Default draft should be null when no drafts');
        System.assertEquals(null, result.defaultDraftDetails, 'Details should be null when no default draft');
        System.assertEquals(false, result.hasExistingPlan, 'Should not have existing plan');
    }

    /**
     * @description Test getDrafts exception handling
     */
    @IsTest
    static void testController_GetDrafts_InvalidId() {
        Test.startTest();
        // Pass a valid-format but non-existent ID - should return empty list, not throw
        List<Settlement_Plan_Draft__c> drafts = SettlementDraftController.getDrafts(null);
        Test.stopTest();

        System.assertNotEquals(null, drafts, 'Should return empty list, not null');
    }

    /**
     * @description Test getDraftWithDetails with null ID
     */
    @IsTest
    static void testController_GetDraftWithDetails_NullId() {
        Test.startTest();
        SettlementDraftService.DraftWrapper wrapper = SettlementDraftController.getDraftWithDetails(null);
        Test.stopTest();

        // Method handles null gracefully - returns empty wrapper with null draft
        System.assertNotEquals(null, wrapper, 'Should return wrapper object');
        System.assertEquals(null, wrapper.draft, 'Draft should be null');
    }

    /**
     * @description Test getDefaultDraft with null ID
     */
    @IsTest
    static void testController_GetDefaultDraft_NullId() {
        Test.startTest();
        Settlement_Plan_Draft__c draft = SettlementDraftController.getDefaultDraft(null);
        Test.stopTest();

        System.assertEquals(null, draft, 'Should return null for null credOpp ID');
    }

    /**
     * @description Test activateDraft with null ID returns error result
     */
    @IsTest
    static void testController_ActivateDraft_NullId() {
        Test.startTest();
        SettlementDraftService.ActivationResult result = SettlementDraftController.activateDraft(null);
        Test.stopTest();

        // Method handles null gracefully - returns failure result
        System.assertEquals(false, result.success, 'Should return failure for null ID');
    }

    // ==================== DATE UTILS TESTS ====================
    // Note: Most DateUtils methods don't need BusinessHours - only isBusinessDay and applyPreviousBusinessDayRule

    @IsTest
    static void testDateUtils_AdvanceDate_AllBasicFrequencies() {
        Date startDate = Date.newInstance(2026, 1, 15);

        // Test Weekly
        Date weeklyResult = SettlementDateUtils.advanceDate(startDate, 'Weekly');
        System.assertEquals(Date.newInstance(2026, 1, 22), weeklyResult, 'Weekly: Should add 7 days');

        // Test Bi-Weekly
        Date biWeeklyResult = SettlementDateUtils.advanceDate(startDate, 'Bi-Weekly');
        System.assertEquals(Date.newInstance(2026, 1, 29), biWeeklyResult, 'Bi-Weekly: Should add 14 days');

        // Test Monthly
        Date monthlyResult = SettlementDateUtils.advanceDate(startDate, 'Monthly');
        System.assertEquals(Date.newInstance(2026, 2, 15), monthlyResult, 'Monthly: Should add 1 month');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_SemiMonthly_AllCases() {
        // Test Before 15th - should move to 15th
        Date before15th = Date.newInstance(2026, 1, 10);
        Date resultBefore = SettlementDateUtils.advanceDate(before15th, 'Semi-Monthly');
        System.assertEquals(Date.newInstance(2026, 1, 15), resultBefore, 'Before 15th: Should move to 15th');

        // Test After 15th - should move to 1st of next month
        Date after15th = Date.newInstance(2026, 1, 20);
        Date resultAfter = SettlementDateUtils.advanceDate(after15th, 'Semi-Monthly');
        System.assertEquals(Date.newInstance(2026, 2, 1), resultAfter, 'After 15th: Should move to 1st of next month');

        // Test On 15th - should move to 1st of next month
        Date on15th = Date.newInstance(2026, 1, 15);
        Date resultOn = SettlementDateUtils.advanceDate(on15th, 'Semi-Monthly');
        System.assertEquals(Date.newInstance(2026, 2, 1), resultOn, 'On 15th: Should move to 1st of next month');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_UnknownFrequency_DefaultsToMonthly() {
        Date startDate = Date.newInstance(2026, 1, 15);

        Test.startTest();
        Date result = SettlementDateUtils.advanceDate(startDate, 'Unknown');
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 2, 15), result, 'Unknown frequency should default to Monthly');
    }

    @IsTest
    static void testDateUtils_AdvanceDate_NullDate_ThrowsException() {
        Test.startTest();
        try {
            SettlementDateUtils.advanceDate(null, 'Monthly');
            System.assert(false, 'Should throw exception for null date');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().containsIgnoreCase('null'), 'Error should mention null');
        }
        Test.stopTest();
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_IsBusinessDay() {
        Date weekday = Date.newInstance(2026, 1, 15); // Thursday

        Test.startTest();
        Boolean result = SettlementDateUtils.isBusinessDay(weekday);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a boolean');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_IsBusinessDay_NullDate() {
        Test.startTest();
        Boolean result = SettlementDateUtils.isBusinessDay(null);
        Test.stopTest();

        System.assertEquals(false, result, 'Should return false for null date');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule() {
        // Saturday Jan 17, 2026 should go back 2 business days to Thursday Jan 15, 2026
        Date testDate = Date.newInstance(2026, 1, 17); // Saturday

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(testDate);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a date');
        // Saturday -> 2 business days back = Thursday (skips Friday, counts Fri & Thu)
        Date expectedDate = Date.newInstance(2026, 1, 15); // Thursday
        System.assertEquals(expectedDate, result, 'Saturday should adjust to Thursday (2 business days back)');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_NullDate() {
        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null input');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_BusinessDay() {
        // Thursday Jan 15, 2026 is a business day - should return unchanged
        Date testDate = Date.newInstance(2026, 1, 15); // Thursday

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(testDate);
        Test.stopTest();

        System.assertEquals(testDate, result, 'Business day should return unchanged');
    }

    @IsTest(SeeAllData=true)
    static void testDateUtils_ApplyPreviousBusinessDayRule_Sunday() {
        // Sunday Jan 18, 2026 should go back 2 business days to Thursday Jan 15, 2026
        Date testDate = Date.newInstance(2026, 1, 18); // Sunday

        Test.startTest();
        Date result = SettlementDateUtils.applyPreviousBusinessDayRule(testDate);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a date');
        // Sunday -> 2 business days back = Thursday (skips Sat, counts Fri & Thu)
        Date expectedDate = Date.newInstance(2026, 1, 15); // Thursday
        System.assertEquals(expectedDate, result, 'Sunday should adjust to Thursday (2 business days back)');
    }

    @IsTest
    static void testDateUtils_WeeksBetween() {
        Date startDate = Date.newInstance(2026, 1, 1);
        Date endDate = Date.newInstance(2026, 1, 29); // 28 days = 4 weeks

        Test.startTest();
        Integer result = SettlementDateUtils.weeksBetween(startDate, endDate);
        Test.stopTest();

        System.assertEquals(4, result, 'Should be 4 weeks');
    }

    @IsTest
    static void testDateUtils_WeeksBetween_NullDates() {
        Test.startTest();
        Integer result = SettlementDateUtils.weeksBetween(null, null);
        Test.stopTest();

        System.assertEquals(0, result, 'Should return 0 for null dates');
    }

    @IsTest
    static void testDateUtils_GetMonthYearKey() {
        Date testDate = Date.newInstance(2026, 3, 15);

        Test.startTest();
        String result = SettlementDateUtils.getMonthYearKey(testDate);
        Test.stopTest();

        System.assertEquals('2026-03', result, 'Should format as YYYY-MM');
    }

    @IsTest
    static void testDateUtils_GetMonthYearKey_SingleDigitMonth() {
        Date testDate = Date.newInstance(2026, 1, 5);

        Test.startTest();
        String result = SettlementDateUtils.getMonthYearKey(testDate);
        Test.stopTest();

        System.assertEquals('2026-01', result, 'Should pad single digit month with zero');
    }

    @IsTest
    static void testDateUtils_GetMonthYearKey_NullDate() {
        Test.startTest();
        String result = SettlementDateUtils.getMonthYearKey(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null date');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Sort Test');

        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = 3,
                Payment_Date__c = Date.newInstance(2026, 3, 1),
                Payment_Amount__c = 1000,
                Status__c = statusScheduled()
            ),
            new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = 1,
                Payment_Date__c = Date.newInstance(2026, 1, 1),
                Payment_Amount__c = 1000,
                Status__c = statusScheduled()
            ),
            new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = 2,
                Payment_Date__c = Date.newInstance(2026, 2, 1),
                Payment_Amount__c = 1000,
                Status__c = statusScheduled()
            )
        };
        insert items;

        Test.startTest();
        List<Settlement_Plan_Item__c> sorted = SettlementDateUtils.sortByPaymentDate(items);
        Test.stopTest();

        System.assertEquals(1, sorted[0].Payment_Number__c, 'First should be payment 1');
        System.assertEquals(2, sorted[1].Payment_Number__c, 'Second should be payment 2');
        System.assertEquals(3, sorted[2].Payment_Number__c, 'Third should be payment 3');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate_SameDateDifferentPaymentNumber() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Sort Tiebreak Test');

        Date sameDate = Date.newInstance(2026, 1, 15);
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = 3,
                Payment_Date__c = sameDate,
                Payment_Amount__c = 1000,
                Status__c = statusScheduled()
            ),
            new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = 1,
                Payment_Date__c = sameDate,
                Payment_Amount__c = 1000,
                Status__c = statusScheduled()
            )
        };
        insert items;

        Test.startTest();
        List<Settlement_Plan_Item__c> sorted = SettlementDateUtils.sortByPaymentDate(items);
        Test.stopTest();

        System.assertEquals(1, sorted[0].Payment_Number__c, 'Payment number should be tiebreaker');
        System.assertEquals(3, sorted[1].Payment_Number__c, 'Higher payment number should be second');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate_EmptyList() {
        Test.startTest();
        List<Settlement_Plan_Item__c> result = SettlementDateUtils.sortByPaymentDate(
            new List<Settlement_Plan_Item__c>()
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list');
    }

    @IsTest
    static void testDateUtils_SortByPaymentDate_NullList() {
        Test.startTest();
        List<Settlement_Plan_Item__c> result = SettlementDateUtils.sortByPaymentDate(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return empty list, not null');
        System.assertEquals(0, result.size(), 'Should be empty');
    }

    // ==================== FEE CALCULATOR TESTS ====================

    @IsTest
    static void testFeeCalculator_Constructor_Success() {
        Settlement_Calc_Config__mdt config = createMockConfig();

        Test.startTest();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);
        Test.stopTest();

        System.assertEquals(TEST_COMMISSION_FEE, calculator.getCommissionFee(), 'Commission fee should match');
        System.assertEquals(TEST_BANK_FEE, calculator.getBankFee(), 'Bank fee should come from config');
    }

    @IsTest
    static void testFeeCalculator_Constructor_NullConfig_ThrowsException() {
        Test.startTest();
        try {
            new SettlementFeeCalculator(null, TEST_COMMISSION_FEE);
            System.assert(false, 'Should throw exception for null config');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Configuration'), 'Error should mention configuration');
            System.assertEquals(SettlementCalculatorException.ErrorType.FEE_CALCULATION_ERROR, e.getErrorType(),
                'Should be FEE_CALCULATION_ERROR type');
        }
        Test.stopTest();
    }

    @IsTest
    static void testFeeCalculator_Constructor_NullCommissionFee_ThrowsException() {
        Settlement_Calc_Config__mdt config = createMockConfig();

        Test.startTest();
        try {
            new SettlementFeeCalculator(config, null);
            System.assert(false, 'Should throw exception for null commission fee');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Commission Fee'), 'Error should mention commission fee');
        }
        Test.stopTest();
    }

    @IsTest
    static void testFeeCalculator_CalculateFeesForItem() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Payment_Amount__c = TEST_PAYMENT_AMOUNT
        );

        Test.startTest();
        calculator.calculateFeesForItem(item);
        Test.stopTest();

        System.assertEquals(TEST_COMMISSION_FEE, item.Commission_Fee__c, 'Commission fee should be set');
        System.assertEquals(TEST_BANK_FEE, item.Bank_Fee__c, 'Bank fee should be set from config');
        System.assertEquals(TEST_EPPS_TXN_FEE, item.EPPS_Transaction_Fee__c, 'EPPS transaction fee should be set');
        System.assertEquals(0, item.EPPS_Month_End_Fee__c, 'EPPS month end fee should default to 0');
        System.assertEquals(0, item.Payee_Fee__c, 'Payee fee should default to 0');
    }

    @IsTest
    static void testFeeCalculator_CalculateFeesForItem_PreservesExistingPayeeFee() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Payment_Amount__c = TEST_PAYMENT_AMOUNT,
            Payee_Fee__c = 25.00  // Pre-existing payee fee
        );

        Test.startTest();
        calculator.calculateFeesForItem(item);
        Test.stopTest();

        System.assertEquals(25.00, item.Payee_Fee__c, 'Existing payee fee should be preserved');
    }

    // ============================================================================
    // EPPS MONTH-END TRUE-UP TESTS - DISABLED (Jan 2026)
    // Reason: True-up calculation logic disabled - will be populated by backend if needed
    // To re-enable: Uncomment the test methods below when true-up logic is re-enabled
    // ============================================================================
    /*
    @IsTest
    static void testFeeCalculator_CalculateEppsMonthEndFees_SinglePaymentPerMonth() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        // Single payment in January - should get full true-up ($55 - $12 = $43)
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 1, 15),
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            )
        };

        Test.startTest();
        calculator.calculateEppsMonthEndFees(items);
        Test.stopTest();

        System.assertEquals(43.00, items[0].EPPS_Month_End_Fee__c,
            'Single payment should get true-up to reach $55 minimum');
    }

    @IsTest
    static void testFeeCalculator_CalculateEppsMonthEndFees_MultiplePaymentsSameMonth() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        // 3 payments in January = 3 × $12 = $36, true-up = $55 - $36 = $19
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 1, 10),
                Payment_Number__c = 1,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            ),
            new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 1, 20),
                Payment_Number__c = 2,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            ),
            new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 1, 30),
                Payment_Number__c = 3,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            )
        };

        Test.startTest();
        calculator.calculateEppsMonthEndFees(items);
        Test.stopTest();

        // Note: Items that don't get a true-up may have null instead of 0
        Decimal firstFee = items[0].EPPS_Month_End_Fee__c == null ? 0 : items[0].EPPS_Month_End_Fee__c;
        Decimal secondFee = items[1].EPPS_Month_End_Fee__c == null ? 0 : items[1].EPPS_Month_End_Fee__c;
        System.assertEquals(0, firstFee, 'First payment should have no true-up');
        System.assertEquals(0, secondFee, 'Second payment should have no true-up');
        System.assertEquals(19.00, items[2].EPPS_Month_End_Fee__c,
            'Last payment of month should get true-up');
    }

    @IsTest
    static void testFeeCalculator_CalculateEppsMonthEndFees_ExceedsMinimum() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        // 5 payments = 5 × $12 = $60, exceeds $55 minimum, no true-up needed
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 5; i++) {
            items.add(new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 1, i * 5),
                Payment_Number__c = i,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            ));
        }

        Test.startTest();
        calculator.calculateEppsMonthEndFees(items);
        Test.stopTest();

        for (Settlement_Plan_Item__c item : items) {
            // Items that don't get a true-up may have null instead of 0
            Decimal monthEndFee = item.EPPS_Month_End_Fee__c == null ? 0 : item.EPPS_Month_End_Fee__c;
            System.assertEquals(0, monthEndFee,
                'No true-up needed when exceeding minimum');
        }
    }

    @IsTest
    static void testFeeCalculator_CalculateEppsMonthEndFees_MultipleMonths() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        // 1 payment each in Jan, Feb, Mar
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 1, 15),
                Payment_Number__c = 1,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            ),
            new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 2, 15),
                Payment_Number__c = 2,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            ),
            new Settlement_Plan_Item__c(
                Payment_Date__c = Date.newInstance(2026, 3, 15),
                Payment_Number__c = 3,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE
            )
        };

        Test.startTest();
        calculator.calculateEppsMonthEndFees(items);
        Test.stopTest();

        // Each month gets its own true-up
        System.assertEquals(43.00, items[0].EPPS_Month_End_Fee__c, 'January should get true-up');
        System.assertEquals(43.00, items[1].EPPS_Month_End_Fee__c, 'February should get true-up');
        System.assertEquals(43.00, items[2].EPPS_Month_End_Fee__c, 'March should get true-up');
    }

    @IsTest
    static void testFeeCalculator_CalculateEppsMonthEndFees_EmptyList() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Test.startTest();
        calculator.calculateEppsMonthEndFees(new List<Settlement_Plan_Item__c>());
        // Should not throw
        Test.stopTest();

        System.assert(true, 'Should handle empty list without error');
    }

    @IsTest
    static void testFeeCalculator_CalculateEppsMonthEndFees_NullList() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Test.startTest();
        calculator.calculateEppsMonthEndFees(null);
        // Should not throw
        Test.stopTest();

        System.assert(true, 'Should handle null list without error');
    }
    */
    // END DISABLED EPPS TRUE-UP TESTS

    @IsTest
    static void testFeeCalculator_CalculateTotalFees_InstanceAndStatic() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Commission_Fee__c = 35.00,
            Bank_Fee__c = 35.00,
            EPPS_Transaction_Fee__c = 12.00,
            EPPS_Month_End_Fee__c = 43.00,
            Payee_Fee__c = 5.00
        );

        // Test instance method
        Decimal instanceTotal = calculator.calculateTotalFees(item);
        System.assertEquals(82.00, instanceTotal, 'Instance: Total fees should be $82');

        // Test static method
        Decimal staticTotal = SettlementFeeCalculator.calculateTotalFeesStatic(item);
        System.assertEquals(82.00, staticTotal, 'Static: Total fees should be $82');
    }

    @IsTest
    static void testFeeCalculator_CalculateTotalFeesStatic_WithNulls() {
        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Commission_Fee__c = 35.00,
            Bank_Fee__c = null,
            EPPS_Transaction_Fee__c = 12.00
            // Other fields null
        );

        Test.startTest();
        Decimal total = SettlementFeeCalculator.calculateTotalFeesStatic(item);
        Test.stopTest();

        System.assertEquals(47.00, total, 'Should handle nulls as zero');
    }

    @IsTest
    static void testFeeCalculator_CalculateTotalPayment() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Payment_Amount__c = 2500.00,
            Commission_Fee__c = 35.00,
            Bank_Fee__c = 35.00,
            EPPS_Transaction_Fee__c = 12.00,
            EPPS_Month_End_Fee__c = 0,
            Payee_Fee__c = 0
        );

        Test.startTest();
        Decimal totalPayment = calculator.calculateTotalPayment(item);
        Test.stopTest();

        System.assertEquals(2582.00, totalPayment, 'Total payment should be amount + fees');
    }

    @IsTest
    static void testFeeCalculator_CalculateTotalPayment_NullPaymentAmount() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Settlement_Plan_Item__c item = new Settlement_Plan_Item__c(
            Payment_Amount__c = null,
            Commission_Fee__c = 35.00,
            Bank_Fee__c = 35.00,
            EPPS_Transaction_Fee__c = 12.00
        );

        Test.startTest();
        Decimal totalPayment = calculator.calculateTotalPayment(item);
        Test.stopTest();

        System.assertEquals(82.00, totalPayment, 'Should handle null payment amount as zero');
    }

    @IsTest
    static void testFeeCalculator_CalculateFeeTotals() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Commission_Fee__c = 35.00,
                Bank_Fee__c = 35.00,
                EPPS_Transaction_Fee__c = 12.00,
                EPPS_Month_End_Fee__c = 43.00,
                Payee_Fee__c = 5.00
            ),
            new Settlement_Plan_Item__c(
                Commission_Fee__c = 35.00,
                Bank_Fee__c = 35.00,
                EPPS_Transaction_Fee__c = 12.00,
                EPPS_Month_End_Fee__c = 0,
                Payee_Fee__c = 0
            )
        };

        Test.startTest();
        Map<String, Decimal> totals = calculator.calculateFeeTotals(items);
        Test.stopTest();

        System.assertEquals(70.00, totals.get('commissionTotal'), 'Commission total should be $70');
        System.assertEquals(70.00, totals.get('bankTotal'), 'Bank total should be $70');
        System.assertEquals(24.00, totals.get('eppsTransactionTotal'), 'EPPS transaction total should be $24');
        System.assertEquals(0, totals.get('eppsMonthEndTotal'), 'EPPS month-end total should be $0');
        System.assertEquals(0, totals.get('payeeTotal'), 'Payee total should be $0');
        System.assertEquals(164.00, totals.get('grandTotal'), 'Grand total should be $164');
    }

    @IsTest
    static void testFeeCalculator_CalculateFeeTotals_EmptyList() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Test.startTest();
        Map<String, Decimal> totals = calculator.calculateFeeTotals(new List<Settlement_Plan_Item__c>());
        Test.stopTest();

        System.assertEquals(0, totals.get('grandTotal'), 'Grand total should be 0 for empty list');
    }

    @IsTest
    static void testFeeCalculator_CalculateFeeTotals_NullList() {
        Settlement_Calc_Config__mdt config = createMockConfig();
        SettlementFeeCalculator calculator = new SettlementFeeCalculator(config, TEST_COMMISSION_FEE);

        Test.startTest();
        Map<String, Decimal> totals = calculator.calculateFeeTotals(null);
        Test.stopTest();

        System.assertEquals(0, totals.get('grandTotal'), 'Grand total should be 0 for null list');
    }

    // ==================== EXCEPTION CLASS TESTS ====================

    @IsTest
    static void testException_WithErrorType() {
        Test.startTest();
        SettlementCalculatorException ex = new SettlementCalculatorException(
            SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
            'Test error message'
        );
        Test.stopTest();

        System.assertEquals(
            SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
            ex.getErrorType(),
            'Error type should match'
        );
        System.assertEquals('Test error message', ex.getMessage(), 'Message should match');
    }

    @IsTest
    static void testException_WithFieldContext() {
        Test.startTest();
        SettlementCalculatorException ex = new SettlementCalculatorException(
            SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
            'Invalid value',
            'Payment_Amount__c',
            -100
        );
        Test.stopTest();

        System.assertEquals('Payment_Amount__c', ex.getFieldName(), 'Field name should match');
        System.assertEquals(-100, ex.getInvalidValue(), 'Invalid value should match');
    }

    @IsTest
    static void testException_AllErrorTypes() {
        // Test that all error types can be used
        Test.startTest();
        List<SettlementCalculatorException.ErrorType> types = new List<SettlementCalculatorException.ErrorType>{
            SettlementCalculatorException.ErrorType.NO_SEGMENTS,
            SettlementCalculatorException.ErrorType.INVALID_SEGMENT_TYPE,
            SettlementCalculatorException.ErrorType.INVALID_SETTLEMENT_AMOUNT,
            SettlementCalculatorException.ErrorType.INVALID_SEGMENT_CONFIG,
            SettlementCalculatorException.ErrorType.MAX_ITERATIONS_EXCEEDED,
            SettlementCalculatorException.ErrorType.INVALID_CREDITOR_OPPORTUNITY,
            SettlementCalculatorException.ErrorType.CALCULATION_ERROR,
            SettlementCalculatorException.ErrorType.DATE_CALCULATION_ERROR,
            SettlementCalculatorException.ErrorType.FEE_CALCULATION_ERROR
        };

        for (SettlementCalculatorException.ErrorType errType : types) {
            SettlementCalculatorException ex = new SettlementCalculatorException(errType, 'Test');
            System.assertEquals(errType, ex.getErrorType(), 'Error type should match: ' + errType);
        }
        Test.stopTest();
    }

    // ==================== WRAPPER CLASS TESTS ====================

    @IsTest
    static void testDraftWrapper_Constructor() {
        Test.startTest();
        SettlementDraftService.DraftWrapper wrapper = new SettlementDraftService.DraftWrapper();
        Test.stopTest();

        System.assertNotEquals(null, wrapper.segments, 'Segments should be initialized');
        System.assertNotEquals(null, wrapper.paymentItems, 'Payment items should be initialized');
        System.assertEquals(0, wrapper.segments.size(), 'Segments should be empty');
        System.assertEquals(0, wrapper.paymentItems.size(), 'Items should be empty');
    }

    @IsTest
    static void testDraftCalculationResult_Constructor() {
        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = new SettlementDraftService.DraftCalculationResult();
        Test.stopTest();

        System.assertEquals(false, result.success, 'Success should default to false');
        System.assertNotEquals(null, result.paymentItems, 'Items should be initialized');
        System.assertEquals(0, result.totalScheduledAmount, 'Total should be 0');
        System.assertEquals(0, result.numberOfPayments, 'Payment count should be 0');
    }

    @IsTest
    static void testRecalculationResult_Constructor() {
        Test.startTest();
        SettlementDraftService.RecalculationResult result = new SettlementDraftService.RecalculationResult();
        Test.stopTest();

        System.assertEquals(false, result.success, 'Success should default to false');
        System.assertEquals(false, result.isBalanced, 'IsBalanced should default to false');
    }

    @IsTest
    static void testActivationResult_Constructor() {
        Test.startTest();
        SettlementDraftService.ActivationResult result = new SettlementDraftService.ActivationResult();
        Test.stopTest();

        System.assertEquals(false, result.success, 'Success should default to false');
        System.assertEquals(0, result.segmentCount, 'Segment count should be 0');
        System.assertEquals(0, result.paymentItemCount, 'Item count should be 0');
    }

    // ==================== PHASE 10: DUPLICATE ITEMS BUG FIX TESTS ====================

    /**
     * @description Tests that calculateDraftPlan preserves locked (Paid/Processing) items
     *              and generates new items starting after the locked items.
     */
    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_WithLockedItems_PreservesThem() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Locked Items Test');

        // Create 4 items, mark first 2 as Paid
        List<Settlement_Plan_Item__c> items = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{statusCleared(), statusCleared(), statusScheduled(), statusScheduled()}
        );

        // Store the IDs of the locked items
        Id paidItem1Id = items[0].Id;
        Id paidItem2Id = items[1].Id;
        Decimal totalPaidAmount = TEST_PAYMENT_AMOUNT * 2;

        // Create segments for recalculation
        // Start date must be AFTER the last preserved item's date (item 2 is at addMonths(2))
        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addMonths(3)
            )
        };

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, totalPaidAmount
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Calculation should succeed');
        System.assert(result.paymentItems.size() > 0, 'Should have payment items');

        // Verify locked items are included in result with their IDs
        Boolean foundPaid1 = false;
        Boolean foundPaid2 = false;
        Integer newItemsCount = 0;

        for (Settlement_Plan_Item__c item : result.paymentItems) {
            if (item.Id == paidItem1Id) {
                foundPaid1 = true;
                System.assertEquals(statusCleared(), item.Status__c, 'First locked item should have Paid status');
            } else if (item.Id == paidItem2Id) {
                foundPaid2 = true;
                System.assertEquals(statusCleared(), item.Status__c, 'Second locked item should have Paid status');
            } else if (item.Id == null) {
                newItemsCount++;
                // New items should have payment numbers starting after locked items
                System.assert(item.Payment_Number__c >= 3,
                    'New items should have payment number >= 3, got: ' + item.Payment_Number__c);
            }
        }

        System.assertEquals(true, foundPaid1, 'First Paid item should be preserved in result');
        System.assertEquals(true, foundPaid2, 'Second Paid item should be preserved in result');
        System.assert(newItemsCount > 0, 'Should have generated new items');
    }

    /**
     * @description Tests that calculateDraftPlan returns error when ALL items are non-Scheduled
     *              AND no segments are provided to generate new items.
     *              (Phase 33: If segments exist, new items CAN be generated even with all locked items)
     */
    @IsTest(SeeAllData=true)
    static void testCalculateDraftPlan_AllItemsLocked_ReturnsError() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'All Locked Test');

        // Create 4 items, ALL marked as Paid (non-Scheduled)
        createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{statusCleared(), statusCleared(), statusCleared(), statusCleared()}
        );

        // No segments provided - cannot regenerate without segments when all items are locked
        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>();

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result = SettlementDraftService.calculateDraftPlan(
            draft.Id, segments, TEST_BALANCE, TEST_SETTLEMENT_OFFER, TEST_COMMISSION_FEE, 0
        );
        Test.stopTest();

        System.assertEquals(false, result.success, 'Should fail when no Scheduled items to regenerate and no segments');
        System.assert(result.errorMessage.containsIgnoreCase('segment'),
            'Error message should mention segments: ' + result.errorMessage);
    }

    /**
     * @description Tests that saveDraftWithRecords preserves locked items (Paid)
     *              while deleting and replacing non-locked items.
     */
    @IsTest
    static void testSaveDraftWithRecords_PreservesLockedItems() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Preserve Locked Test');

        // Create 4 items: 2 Paid, 2 Scheduled
        List<Settlement_Plan_Item__c> existingItems = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{statusCleared(), statusCleared(), statusScheduled(), statusScheduled()}
        );

        Id paidItem1Id = existingItems[0].Id;
        Id paidItem2Id = existingItems[1].Id;
        Decimal paid1Amount = existingItems[0].Payment_Amount__c;
        Decimal paid2Amount = existingItems[1].Payment_Amount__c;

        // Now save with NEW items (simulating after a recalculate)
        // Include the locked items with IDs, plus new items without IDs
        List<Settlement_Plan_Item__c> itemsToSave = new List<Settlement_Plan_Item__c>{
            // Locked items (already in DB - will be skipped)
            new Settlement_Plan_Item__c(
                Id = paidItem1Id,
                Payment_Number__c = 1,
                Payment_Date__c = Date.today().addMonths(1),
                Payment_Amount__c = paid1Amount,
                Status__c = statusCleared()
            ),
            new Settlement_Plan_Item__c(
                Id = paidItem2Id,
                Payment_Number__c = 2,
                Payment_Date__c = Date.today().addMonths(2),
                Payment_Amount__c = paid2Amount,
                Status__c = statusCleared()
            ),
            // New items (no ID - will be inserted)
            new Settlement_Plan_Item__c(
                Payment_Number__c = 3,
                Payment_Date__c = Date.today().addMonths(3),
                Payment_Amount__c = 1500.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ),
            new Settlement_Plan_Item__c(
                Payment_Number__c = 4,
                Payment_Date__c = Date.today().addMonths(4),
                Payment_Amount__c = 1500.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            )
        };

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(draft.Id, null, itemsToSave);
        Test.stopTest();

        // Query all items for this draft
        List<Settlement_Plan_Item__c> savedItems = [
            SELECT Id, Payment_Number__c, Payment_Amount__c, Status__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draft.Id
            ORDER BY Payment_Number__c
        ];

        System.assertEquals(4, savedItems.size(), 'Should have 4 items total');

        // Verify the Paid items are still there with original IDs
        System.assertEquals(paidItem1Id, savedItems[0].Id, 'First Paid item should be preserved');
        System.assertEquals(statusCleared(), savedItems[0].Status__c, 'First item should still be Paid');
        System.assertEquals(paidItem2Id, savedItems[1].Id, 'Second Paid item should be preserved');
        System.assertEquals(statusCleared(), savedItems[1].Status__c, 'Second item should still be Paid');

        // Verify new items were inserted
        System.assertNotEquals(paidItem1Id, savedItems[2].Id, 'Third item should be new');
        System.assertEquals(statusScheduled(), savedItems[2].Status__c, 'Third item should be Scheduled');
        System.assertEquals(1500.00, savedItems[2].Payment_Amount__c, 'Third item amount should match');
    }

    /**
     * @description Tests that saveDraftWithRecords deletes non-locked items before inserting new ones.
     */
    @IsTest
    static void testSaveDraftWithRecords_DeletesNonLockedItems() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Delete Non-Locked Test');

        // Create 4 items, all Scheduled (non-locked)
        List<Settlement_Plan_Item__c> existingItems = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{statusScheduled(), statusScheduled(), statusScheduled(), statusScheduled()}
        );

        // Store original IDs
        Set<Id> originalIds = new Set<Id>();
        for (Settlement_Plan_Item__c item : existingItems) {
            originalIds.add(item.Id);
        }

        // Now save with completely different items (simulating recalculate)
        List<Settlement_Plan_Item__c> newItems = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Number__c = 1,
                Payment_Date__c = Date.today().addMonths(1),
                Payment_Amount__c = 3000.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ),
            new Settlement_Plan_Item__c(
                Payment_Number__c = 2,
                Payment_Date__c = Date.today().addMonths(2),
                Payment_Amount__c = 3000.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            )
        };

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(draft.Id, null, newItems);
        Test.stopTest();

        // Query all items for this draft
        List<Settlement_Plan_Item__c> savedItems = [
            SELECT Id, Payment_Number__c, Payment_Amount__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draft.Id
            ORDER BY Payment_Number__c
        ];

        // Should have only 2 items now (the new ones)
        System.assertEquals(2, savedItems.size(), 'Should have 2 items after save');

        // Verify old items were deleted
        for (Settlement_Plan_Item__c item : savedItems) {
            System.assertEquals(false, originalIds.contains(item.Id),
                'Old item should have been deleted, found ID: ' + item.Id);
        }

        // Verify new item amounts
        System.assertEquals(3000.00, savedItems[0].Payment_Amount__c, 'First item should have new amount');
        System.assertEquals(3000.00, savedItems[1].Payment_Amount__c, 'Second item should have new amount');
    }

    /**
     * @description Tests that multiple Calculate→Save cycles don't create duplicate items.
     *              This is the core bug fix test for Phase 10.
     */
    @IsTest
    static void testSaveDraftWithRecords_MultipleCalculateSaveCycles_NoDuplicates() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'No Duplicates Test');

        // Simulate first Calculate → Save cycle
        List<Settlement_Plan_Item__c> firstItems = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 4; i++) {
            firstItems.add(new Settlement_Plan_Item__c(
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = 2500.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ));
        }

        Test.startTest();

        // First save
        SettlementDraftService.saveDraftWithRecords(draft.Id, null, firstItems);

        Integer countAfterFirstSave = [
            SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :draft.Id
        ];
        System.assertEquals(4, countAfterFirstSave, 'Should have 4 items after first save');

        // Simulate second Calculate (generates new items with no IDs, just like LWC does)
        List<Settlement_Plan_Item__c> secondItems = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 4; i++) {
            secondItems.add(new Settlement_Plan_Item__c(
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = 2500.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ));
        }

        // Second save (should NOT create duplicates)
        SettlementDraftService.saveDraftWithRecords(draft.Id, null, secondItems);

        Test.stopTest();

        // Query final count
        Integer countAfterSecondSave = [
            SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :draft.Id
        ];

        // CRITICAL: Should still be 4 items, NOT 8
        System.assertEquals(4, countAfterSecondSave,
            'Should still have 4 items after second save - NO DUPLICATES. Actual count: ' + countAfterSecondSave);

        // Verify items have correct values
        List<Settlement_Plan_Item__c> finalItems = [
            SELECT Payment_Number__c, Payment_Amount__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draft.Id
            ORDER BY Payment_Number__c
        ];

        for (Integer i = 0; i < 4; i++) {
            System.assertEquals(i + 1, finalItems[i].Payment_Number__c,
                'Payment number should be sequential');
            System.assertEquals(2500.00, finalItems[i].Payment_Amount__c,
                'Amount should match');
        }
    }

    // ==================== PHASE 11: LAZY DRAFT CREATION TESTS ====================

    /**
     * @description Tests createAndSaveDraft creates draft, segments, and items in one transaction.
     */
    @IsTest
    static void testCreateAndSaveDraft_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Prepare segments
        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        // Prepare items
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 4; i++) {
            items.add(new Settlement_Plan_Item__c(
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = TEST_PAYMENT_AMOUNT,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            ));
        }

        // Prepare draft fields
        Map<String, Object> draftFields = new Map<String, Object>{
            'Settlement_Offer_Amount__c' => TEST_SETTLEMENT_OFFER,
            'Commission_Fee__c' => TEST_COMMISSION_FEE
        };

        Test.startTest();
        Settlement_Plan_Draft__c draft = SettlementDraftService.createAndSaveDraft(
            credOpp.Id, 'Lazy Draft Test', segments, items, draftFields
        );
        Test.stopTest();

        // Verify draft was created
        System.assertNotEquals(null, draft.Id, 'Draft should be created');
        System.assertEquals('Lazy Draft Test', draft.Name, 'Name should match');
        System.assertEquals(SettlementDraftService.STATUS_DRAFT, draft.Status__c, 'Status should be Draft');
        System.assertEquals(TEST_SETTLEMENT_OFFER, draft.Settlement_Offer_Amount__c, 'Settlement offer should be set');
        System.assertEquals(TEST_COMMISSION_FEE, draft.Commission_Fee__c, 'Commission fee should be set');

        // Verify segments were created
        List<Settlement_Segment__c> savedSegments = [
            SELECT Id, Settlement_Plan__c, Segment_Order__c
            FROM Settlement_Segment__c
            WHERE Settlement_Plan__c = :draft.Id
        ];
        System.assertEquals(1, savedSegments.size(), 'Should have 1 segment');
        System.assertEquals(draft.Id, savedSegments[0].Settlement_Plan__c, 'Segment should reference draft');

        // Verify items were created
        List<Settlement_Plan_Item__c> savedItems = [
            SELECT Id, Settlement_Plan__c, Payment_Number__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draft.Id
            ORDER BY Payment_Number__c
        ];
        System.assertEquals(4, savedItems.size(), 'Should have 4 items');
        System.assertEquals(draft.Id, savedItems[0].Settlement_Plan__c, 'Item should reference draft');
    }

    /**
     * @description Tests createAndSaveDraft with null segments and items (valid use case).
     */
    @IsTest
    static void testCreateAndSaveDraft_NoSegmentsOrItems() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        Map<String, Object> draftFields = new Map<String, Object>{
            'Settlement_Offer_Amount__c' => TEST_SETTLEMENT_OFFER
        };

        Test.startTest();
        Settlement_Plan_Draft__c draft = SettlementDraftService.createAndSaveDraft(
            credOpp.Id, 'Empty Draft', null, null, draftFields
        );
        Test.stopTest();

        System.assertNotEquals(null, draft.Id, 'Draft should be created');
        System.assertEquals('Empty Draft', draft.Name, 'Name should match');

        // Verify no segments or items
        Integer segmentCount = [SELECT COUNT() FROM Settlement_Segment__c WHERE Settlement_Plan__c = :draft.Id];
        Integer itemCount = [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :draft.Id];
        System.assertEquals(0, segmentCount, 'Should have 0 segments');
        System.assertEquals(0, itemCount, 'Should have 0 items');
    }

    /**
     * @description Tests createAndSaveDraft throws exception for null CreditorOpportunity ID.
     */
    @IsTest
    static void testCreateAndSaveDraft_NullCredOppId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftService.createAndSaveDraft(null, 'Test', null, null, null);
            System.assert(false, 'Should throw exception for null CreditorOpportunity ID');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required');
        }
        Test.stopTest();
    }

    /**
     * @description Tests createAndSaveDraft applies all supported draft field overrides.
     */
    @IsTest
    static void testCreateAndSaveDraft_AppliesAllDraftFields() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        Map<String, Object> draftFields = new Map<String, Object>{
            'Name' => 'Custom Name Override',
            'Balance__c' => 25000.00,
            'Settlement_Offer_Amount__c' => 12500.00,
            'Escrow_Start_Balance__c' => 20000.00,
            'Commission_Fee__c' => 50.00,
            'Is_Manually_Modified__c' => true,
            'Settlement_Memo__c' => 'Test memo'
        };

        Test.startTest();
        Settlement_Plan_Draft__c draft = SettlementDraftService.createAndSaveDraft(
            credOpp.Id, 'Initial Name', null, null, draftFields
        );
        Test.stopTest();

        // Re-query to verify all fields were saved
        draft = [
            SELECT Name, Balance__c, Settlement_Offer_Amount__c, Escrow_Start_Balance__c,
                   Commission_Fee__c, Is_Manually_Modified__c, Settlement_Memo__c
            FROM Settlement_Plan_Draft__c
            WHERE Id = :draft.Id
        ];

        System.assertEquals('Custom Name Override', draft.Name, 'Name should be overridden');
        System.assertEquals(25000.00, draft.Balance__c, 'Balance should be overridden');
        System.assertEquals(12500.00, draft.Settlement_Offer_Amount__c, 'Settlement offer should be set');
        System.assertEquals(20000.00, draft.Escrow_Start_Balance__c, 'Escrow start should be overridden');
        System.assertEquals(50.00, draft.Commission_Fee__c, 'Commission fee should be set');
        System.assertEquals(true, draft.Is_Manually_Modified__c, 'Is manually modified should be set');
        System.assertEquals('Test memo', draft.Settlement_Memo__c, 'Memo should be set');
    }

    /**
     * @description Tests Controller.createAndSaveDraft wrapper method.
     */
    @IsTest
    static void testController_CreateAndSaveDraft_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = 2500,
                Payment_Count__c = 2,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };

        String scheduledStatus = statusScheduled();
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Number__c = 1,
                Payment_Date__c = Date.today().addMonths(1),
                Payment_Amount__c = 2500,
                Status__c = scheduledStatus
            ),
            new Settlement_Plan_Item__c(
                Payment_Number__c = 2,
                Payment_Date__c = Date.today().addMonths(2),
                Payment_Amount__c = 2500,
                Status__c = scheduledStatus
            )
        };

        Map<String, Object> draftFields = new Map<String, Object>{
            'Settlement_Offer_Amount__c' => 5000,
            'Commission_Fee__c' => 35
        };

        Test.startTest();
        Settlement_Plan_Draft__c draft = SettlementDraftController.createAndSaveDraft(
            credOpp.Id, 'Controller Test', segments, items, draftFields
        );
        Test.stopTest();

        System.assertNotEquals(null, draft.Id, 'Draft should be created');
        System.assertEquals('Controller Test', draft.Name, 'Name should match');

        // Verify segments and items were created
        Integer segmentCount = [SELECT COUNT() FROM Settlement_Segment__c WHERE Settlement_Plan__c = :draft.Id];
        Integer itemCount = [SELECT COUNT() FROM Settlement_Plan_Item__c WHERE Settlement_Plan__c = :draft.Id];
        System.assertEquals(1, segmentCount, 'Should have 1 segment');
        System.assertEquals(2, itemCount, 'Should have 2 items');
    }

    // ==================== SUSPEND FEATURE TESTS ====================

    /**
     * @description Tests suspendPaymentItems successfully suspends only Scheduled items
     *              (preserves Paid, Processing, Missed, Cancelled, Skipped statuses)
     *              and changes draft status to Suspended.
     */
    @IsTest
    static void testSuspendPaymentItems_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Suspend Test', SettlementDraftService.STATUS_ACTIVE);

        // Create items with mixed statuses: 1 Cleared, 1 Processing, 2 Scheduled
        List<Settlement_Plan_Item__c> items = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{statusCleared(), statusProcessing(), statusScheduled(), statusScheduled()}
        );

        Test.startTest();
        Integer suspendedCount = SettlementDraftService.suspendPaymentItems(draft.Id);
        Test.stopTest();

        // Verify count of updated items (Processing + Scheduled)
        System.assertEquals(3, suspendedCount, 'Should update 3 items (Processing + Scheduled)');

        // Verify draft status changed to Suspended
        Settlement_Plan_Draft__c updatedDraft = [
            SELECT Status__c FROM Settlement_Plan_Draft__c WHERE Id = :draft.Id
        ];
        System.assertEquals(SettlementDraftService.STATUS_SUSPENDED, updatedDraft.Status__c, 'Draft status should be Suspended');

        // Verify item statuses
        List<Settlement_Plan_Item__c> updatedItems = [
            SELECT Status__c FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draft.Id
            ORDER BY Payment_Number__c
        ];
        System.assertEquals(statusCleared(), updatedItems[0].Status__c, 'Cleared item should remain Cleared');
        System.assertEquals(statusVoid(), updatedItems[1].Status__c, 'Processing item should be Void');
        System.assertEquals(statusSuspended(), updatedItems[2].Status__c, 'Scheduled item should be Suspended');
        System.assertEquals(statusSuspended(), updatedItems[3].Status__c, 'Scheduled item should be Suspended');
    }

    /**
     * @description Tests suspendPaymentItems throws exception for non-Active draft.
     */
    @IsTest
    static void testSuspendPaymentItems_NotActiveError() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Not Active Test', SettlementDraftService.STATUS_DRAFT);

        createPaymentItemsWithStatuses(draft.Id, new List<String>{statusScheduled(), statusScheduled()});

        Test.startTest();
        try {
            SettlementDraftService.suspendPaymentItems(draft.Id);
            System.assert(false, 'Should throw exception for non-Active draft');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Active'),
                'Error should mention Active status: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * @description Tests suspendPaymentItems throws exception for null draft ID.
     */
    @IsTest
    static void testSuspendPaymentItems_NullDraftId_ThrowsException() {
        Test.startTest();
        try {
            SettlementDraftService.suspendPaymentItems(null);
            System.assert(false, 'Should throw exception for null draft ID');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('required'),
                'Error should mention required: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * @description Tests that cloning a draft with Suspended items converts them to Scheduled.
     */
    @IsTest
    static void testCloneDraft_SuspendedItemsBecomeScheduled() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Clone Suspended Test', SettlementDraftService.STATUS_SUSPENDED);

        // Create items with Paid and Suspended statuses
        List<Settlement_Plan_Item__c> items = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{statusCleared(), statusSuspended(), statusSuspended(), statusSuspended()}
        );

        // Need segments for clone to work properly
        createTestSegments(draft.Id, 1);

        Test.startTest();
        Settlement_Plan_Draft__c clonedDraft = SettlementDraftService.cloneDraft(draft.Id, 'Cloned Draft');
        Test.stopTest();

        // Verify cloned draft is in Draft status
        System.assertEquals(SettlementDraftService.STATUS_DRAFT, clonedDraft.Status__c, 'Cloned draft should be in Draft status');

        // Verify item statuses in cloned draft
        List<Settlement_Plan_Item__c> clonedItems = [
            SELECT Status__c FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :clonedDraft.Id
            ORDER BY Payment_Number__c
        ];
        System.assertEquals(4, clonedItems.size(), 'Should have 4 cloned items');
        System.assertEquals(statusCleared(), clonedItems[0].Status__c, 'Cleared item should stay Cleared');
        System.assertEquals(statusScheduled(), clonedItems[1].Status__c, 'Suspended item should become Scheduled');
        System.assertEquals(statusScheduled(), clonedItems[2].Status__c, 'Suspended item should become Scheduled');
        System.assertEquals(statusScheduled(), clonedItems[3].Status__c, 'Suspended item should become Scheduled');
    }

    /**
     * @description Tests that cloneDraft copies actual payment fields (Actual_Payment_Amount__c,
     *              Actual_Payment_Date__c, Confirmation_Number__c, Skip_Payment__c, Skip_Reason__c).
     */
    @IsTest
    static void testCloneDraft_CopiesActualPaymentFields() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c sourceDraft = createTestDraft(credOpp.Id, 'Source Draft');
        createTestSegments(sourceDraft.Id, 1);
        List<Settlement_Plan_Item__c> sourceItems = createTestPaymentItems(sourceDraft.Id, 2);

        // Set actual payment fields on source items
        sourceItems[0].Actual_Payment_Amount__c = 150.00;
        sourceItems[0].Actual_Payment_Date__c = Date.today().addDays(-5);
        sourceItems[0].Confirmation_Number__c = 'CONF-12345';
        sourceItems[0].Skip_Payment__c = false;
        sourceItems[0].Skip_Reason__c = null;

        sourceItems[1].Actual_Payment_Amount__c = null;
        sourceItems[1].Actual_Payment_Date__c = null;
        sourceItems[1].Confirmation_Number__c = null;
        sourceItems[1].Skip_Payment__c = true;
        sourceItems[1].Skip_Reason__c = 'Customer requested delay';
        update sourceItems;

        Test.startTest();
        Settlement_Plan_Draft__c clonedDraft = SettlementDraftService.cloneDraft(sourceDraft.Id, 'Cloned Draft');
        Test.stopTest();

        // Verify cloned items have the same actual payment field values
        List<Settlement_Plan_Item__c> clonedItems = [
            SELECT Actual_Payment_Amount__c, Actual_Payment_Date__c, Confirmation_Number__c,
                   Skip_Payment__c, Skip_Reason__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :clonedDraft.Id
            ORDER BY Payment_Number__c
        ];

        System.assertEquals(2, clonedItems.size(), 'Should have 2 cloned items');

        // Verify first item fields
        System.assertEquals(150.00, clonedItems[0].Actual_Payment_Amount__c, 'Actual payment amount should be copied');
        System.assertEquals(Date.today().addDays(-5), clonedItems[0].Actual_Payment_Date__c, 'Actual payment date should be copied');
        System.assertEquals('CONF-12345', clonedItems[0].Confirmation_Number__c, 'Confirmation number should be copied');
        System.assertEquals(false, clonedItems[0].Skip_Payment__c, 'Skip payment should be copied');
        System.assertEquals(null, clonedItems[0].Skip_Reason__c, 'Skip reason should be copied');

        // Verify second item fields
        System.assertEquals(null, clonedItems[1].Actual_Payment_Amount__c, 'Null actual payment amount should be preserved');
        System.assertEquals(null, clonedItems[1].Actual_Payment_Date__c, 'Null actual payment date should be preserved');
        System.assertEquals(null, clonedItems[1].Confirmation_Number__c, 'Null confirmation number should be preserved');
        System.assertEquals(true, clonedItems[1].Skip_Payment__c, 'Skip payment true should be copied');
        System.assertEquals('Customer requested delay', clonedItems[1].Skip_Reason__c, 'Skip reason should be copied');
    }

    /**
     * @description Tests Controller.suspendPaymentItems wrapper method.
     */
    @IsTest
    static void testController_SuspendPaymentItems_Success() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Controller Suspend Test', SettlementDraftService.STATUS_ACTIVE);

        createPaymentItemsWithStatuses(draft.Id, new List<String>{statusScheduled(), statusScheduled()});

        Test.startTest();
        Integer count = SettlementDraftController.suspendPaymentItems(draft.Id);
        Test.stopTest();

        System.assertEquals(2, count, 'Should suspend 2 items via controller');
    }

    /**
     * @description Tests Controller.suspendPaymentItems throws AuraHandledException for invalid status.
     */
    @IsTest
    static void testController_SuspendPaymentItems_ThrowsAuraException() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Controller Error Test', SettlementDraftService.STATUS_DRAFT);

        createPaymentItemsWithStatuses(draft.Id, new List<String>{statusScheduled()});

        Test.startTest();
        try {
            SettlementDraftController.suspendPaymentItems(draft.Id);
            System.assert(false, 'Should throw AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Active'),
                'Error should mention Active: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * @description Tests that Suspended drafts cannot be edited (saveDraftWithRecords).
     */
    @IsTest
    static void testSaveDraftWithRecords_SuspendedDraft_ThrowsException() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Edit Suspended Test', SettlementDraftService.STATUS_SUSPENDED);

        List<Settlement_Segment__c> segments = createTestSegments(draft.Id, 1);

        Test.startTest();
        try {
            SettlementDraftService.saveDraftWithRecords(draft.Id, segments, null, null);
            System.assert(false, 'Should throw exception for Suspended draft');
        } catch (SettlementCalculatorException e) {
            System.assert(e.getMessage().contains('Suspended'),
                'Error should mention Suspended: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ==================== HISTORICAL ITEM SAVE TESTS ====================

    /**
     * @description Tests that Missed items are not modified on save.
     */
    @IsTest
    static void testSaveDraft_SkipsMissedItems() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Missed Balance Update Test');

        // Create items: Paid, Missed, Scheduled
        List<Settlement_Plan_Item__c> items = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{
                statusCleared(),
                statusMissed(),
                statusScheduled()
            }
        );

        // Get original values
        Id missedItemId = items[1].Id;
        Decimal originalMissedAmount = items[1].Payment_Amount__c;
        Decimal originalMissedEpps = items[1].EPPS_Month_End_Fee__c;

        // Create segments for save
        List<Settlement_Segment__c> segments = createTestSegments(draft.Id, 1);

        // Modify the Missed item in memory (should be ignored on save)
        items[1].Payment_Amount__c = originalMissedAmount + 500;
        items[1].EPPS_Month_End_Fee__c = 10.00;

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(draft.Id, segments, items, null);
        Test.stopTest();

        // Verify Missed item was NOT modified in DB
        Settlement_Plan_Item__c updatedMissedItem = [
            SELECT Payment_Amount__c, EPPS_Month_End_Fee__c
            FROM Settlement_Plan_Item__c
            WHERE Id = :missedItemId
        ];
        System.assertEquals(originalMissedAmount, updatedMissedItem.Payment_Amount__c,
            'Missed item amount should be unchanged');
        System.assertEquals(originalMissedEpps, updatedMissedItem.EPPS_Month_End_Fee__c,
            'Missed item EPPS fee should be unchanged');
    }

    /**
     * @description Tests that Paid and Processing items are never modified on save.
     */
    @IsTest
    static void testSaveDraft_SkipsPaidAndProcessingItems() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Immutable Items Test');

        // Create items: Paid, Processing, Scheduled
        List<Settlement_Plan_Item__c> items = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{
                statusCleared(),
                statusProcessing(),
                statusScheduled()
            }
        );

        // Store original values
        Id paidItemId = items[0].Id;
        Id processingItemId = items[1].Id;
        Decimal originalPaidAmount = items[0].Payment_Amount__c;
        Decimal originalProcessingAmount = items[1].Payment_Amount__c;

        // Create segments for save
        List<Settlement_Segment__c> segments = createTestSegments(draft.Id, 1);

        // Try to modify Cleared and Processing items (should be ignored)
        items[0].Payment_Amount__c = 99999.99;
        items[1].Payment_Amount__c = 88888.88;

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(draft.Id, segments, items, null);
        Test.stopTest();

        // Verify Paid and Processing items were NOT modified
        List<Settlement_Plan_Item__c> updatedItems = [
            SELECT Id, Payment_Amount__c
            FROM Settlement_Plan_Item__c
            WHERE Id IN (:paidItemId, :processingItemId)
        ];

        for (Settlement_Plan_Item__c item : updatedItems) {
            if (item.Id == paidItemId) {
                System.assertEquals(originalPaidAmount, item.Payment_Amount__c,
                    'Cleared item amount should be unchanged');
            } else {
                System.assertEquals(originalProcessingAmount, item.Payment_Amount__c,
                    'Processing item amount should be unchanged');
            }
        }
    }

    /**
     * @description Tests that recalculateBalances correctly tracks balance through mixed statuses.
     *              Scenario: Paid -> Missed -> Paid -> Scheduled
     */
    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_TracksThroughMixedStatuses() {
        CreditorOpportunity__c credOpp = createNewCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Mixed Status Balance Test');

        // Create items with mixed statuses
        List<Settlement_Plan_Item__c> items = createPaymentItemsWithStatuses(
            draft.Id,
            new List<String>{
                statusCleared(),
                statusMissed(),
                statusCleared(),
                statusScheduled()
            }
        );

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items, TEST_SETTLEMENT_OFFER
        );
        Test.stopTest();

        System.assertEquals(true, result.success, 'Recalculation should succeed');
        System.assertEquals(4, result.paymentItems.size(), 'Should have 4 items');

        // Verify statuses preserved in order
        System.assertEquals(statusCleared(), result.paymentItems[0].Status__c,
            'First item should remain Cleared');
        System.assertEquals(statusMissed(), result.paymentItems[1].Status__c,
            'Second item should remain Missed');
        System.assertEquals(statusCleared(), result.paymentItems[2].Status__c,
            'Third item should remain Cleared');
        System.assertEquals(statusScheduled(), result.paymentItems[3].Status__c,
            'Fourth item should remain Scheduled');
    }

    // ==================== REVISED SETTLEMENT AMOUNT TESTS ====================

    /**
     * @description Tests that getEffectiveSettlementAmount uses Revised when set.
     *              This is tested indirectly via calculateDraftPlan.
     */
    @IsTest
    static void testCalculateDraftPlan_WithRevisedAmount_UsesRevisedForRemainder() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Create draft with Original = 10,000, Revised = 12,000
        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = 'Revised Amount Test',
            CreditorOpportunity__c = credOpp.Id,
            Status__c = SettlementDraftService.STATUS_DRAFT,
            Balance__c = 20000,
            Settlement_Offer_Amount__c = 10000,
            Revised_Settlement_Amount__c = 12000,
            Commission_Fee__c = TEST_COMMISSION_FEE
        );
        insert draft;

        // Create 2 Paid items totaling $2,000 (payment history)
        List<Settlement_Plan_Item__c> paidItems = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = 1,
                Payment_Date__c = Date.today().addMonths(-2),
                Payment_Amount__c = 1000,
                Status__c = statusCleared()
            ),
            new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = 2,
                Payment_Date__c = Date.today().addMonths(-1),
                Payment_Amount__c = 1000,
                Status__c = statusCleared()
            )
        };
        insert paidItems;

        // Create a Remainder segment to pay off the rest
        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Remainder',
                Payment_Amount__c = 1000,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addMonths(1)
            )
        };
        insert segments;

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result =
            SettlementDraftService.calculateDraftPlan(draft.Id, null, null, null, null, null);
        Test.stopTest();

        System.assert(result.success, 'Calculation should succeed: ' + result.errorMessage);

        // The remaining balance should be: Revised (12,000) - Paid (2,000) = 10,000
        // With payments of $1,000 each, we should have 10 NEW payments
        // Plus 2 Paid items = 12 total
        Integer newPaymentCount = result.numberOfPayments - 2; // Subtract Paid items
        System.assertEquals(10, newPaymentCount, 'Should generate 10 new payments to cover $10,000 remaining');

        // Total scheduled should be $12,000 (2 Paid + 10 new)
        System.assertEquals(12000, result.totalScheduledAmount.setScale(0),
            'Total scheduled should equal revised amount ($12,000)');

        // Funding difference should be $0 (balanced)
        System.assertEquals(0, result.fundingDifference.setScale(0),
            'Funding difference should be zero (balanced with revised amount)');
    }

    /**
     * @description Tests that calculation uses original amount when revised is null.
     */
    @IsTest
    static void testCalculateDraftPlan_WithoutRevisedAmount_UsesOriginal() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Create draft with Original = 10,000, Revised = null
        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = 'No Revised Test',
            CreditorOpportunity__c = credOpp.Id,
            Status__c = SettlementDraftService.STATUS_DRAFT,
            Balance__c = 20000,
            Settlement_Offer_Amount__c = 10000,
            Revised_Settlement_Amount__c = null, // No revision
            Commission_Fee__c = TEST_COMMISSION_FEE
        );
        insert draft;

        // Create a Fixed segment for 4 payments of $2,500 each
        List<Settlement_Segment__c> segments = new List<Settlement_Segment__c>{
            new Settlement_Segment__c(
                Settlement_Plan__c = draft.Id,
                Segment_Order__c = 1,
                Segment_Type__c = 'Fixed',
                Payment_Amount__c = 2500,
                Payment_Count__c = 4,
                Frequency__c = 'Monthly',
                Start_Date__c = Date.today().addDays(30)
            )
        };
        insert segments;

        Test.startTest();
        SettlementDraftService.DraftCalculationResult result =
            SettlementDraftService.calculateDraftPlan(draft.Id, null, null, null, null, null);
        Test.stopTest();

        System.assert(result.success, 'Calculation should succeed: ' + result.errorMessage);
        System.assertEquals(4, result.numberOfPayments, 'Should generate 4 payments');
        System.assertEquals(10000, result.totalScheduledAmount.setScale(0),
            'Total should be $10,000 (original amount)');
        System.assertEquals(0, result.fundingDifference.setScale(0),
            'Funding difference should be zero');
    }

    /**
     * @description Tests that cloneDraft copies Revised_Settlement_Amount__c.
     */
    @IsTest
    static void testCloneDraft_CopiesRevisedAmount() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Create source draft with revised amount
        Settlement_Plan_Draft__c sourceDraft = new Settlement_Plan_Draft__c(
            Name = 'Clone Source',
            CreditorOpportunity__c = credOpp.Id,
            Status__c = SettlementDraftService.STATUS_DRAFT,
            Balance__c = 20000,
            Settlement_Offer_Amount__c = 10000,
            Revised_Settlement_Amount__c = 15000,
            Commission_Fee__c = TEST_COMMISSION_FEE
        );
        insert sourceDraft;
        createTestSegments(sourceDraft.Id, 1);

        Test.startTest();
        Settlement_Plan_Draft__c clonedDraft = SettlementDraftService.cloneDraft(sourceDraft.Id, 'Cloned With Revised');
        Test.stopTest();

        // Re-query to get all fields
        clonedDraft = [
            SELECT Settlement_Offer_Amount__c, Revised_Settlement_Amount__c
            FROM Settlement_Plan_Draft__c
            WHERE Id = :clonedDraft.Id
        ];

        System.assertEquals(10000, clonedDraft.Settlement_Offer_Amount__c,
            'Original amount should be copied');
        System.assertEquals(15000, clonedDraft.Revised_Settlement_Amount__c,
            'Revised amount should be copied');
    }

    /**
     * @description Tests applyDraftFields handles Revised_Settlement_Amount__c.
     */
    @IsTest
    static void testApplyDraftFields_HandlesRevisedAmount() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        Map<String, Object> draftFields = new Map<String, Object>{
            'Name' => 'Revised Test',
            'Settlement_Offer_Amount__c' => 10000,
            'Revised_Settlement_Amount__c' => 12500,
            'Commission_Fee__c' => TEST_COMMISSION_FEE
        };

        Test.startTest();
        Settlement_Plan_Draft__c draft = SettlementDraftService.createAndSaveDraft(
            credOpp.Id, 'Initial Name', null, null, draftFields
        );
        Test.stopTest();

        // Re-query to verify field was saved
        draft = [
            SELECT Settlement_Offer_Amount__c, Revised_Settlement_Amount__c
            FROM Settlement_Plan_Draft__c
            WHERE Id = :draft.Id
        ];

        System.assertEquals(10000, draft.Settlement_Offer_Amount__c, 'Original should be set');
        System.assertEquals(12500, draft.Revised_Settlement_Amount__c, 'Revised should be set');
    }

    /**
     * @description Tests updateDraftSummary calculates funding difference against effective amount.
     */
    @IsTest
    static void testUpdateDraftSummary_UsesEffectiveAmount() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        // Create draft with Original = 10,000, Revised = 12,000
        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = 'Summary Test',
            CreditorOpportunity__c = credOpp.Id,
            Status__c = SettlementDraftService.STATUS_DRAFT,
            Balance__c = 20000,
            Settlement_Offer_Amount__c = 10000,
            Revised_Settlement_Amount__c = 12000,
            Commission_Fee__c = TEST_COMMISSION_FEE
        );
        insert draft;

        // Create payment items totaling $12,000 (to match revised amount)
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();
        for (Integer i = 1; i <= 4; i++) {
            items.add(new Settlement_Plan_Item__c(
                Settlement_Plan__c = draft.Id,
                Payment_Number__c = i,
                Payment_Date__c = Date.today().addMonths(i),
                Payment_Amount__c = 3000,
                Status__c = statusScheduled()
            ));
        }
        insert items;

        Test.startTest();
        // Save to trigger updateDraftSummary
        SettlementDraftService.saveDraftWithRecords(draft.Id, null, items, null);
        Test.stopTest();

        // Verify items were saved correctly
        List<Settlement_Plan_Item__c> savedItems = [
            SELECT Id, Payment_Amount__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draft.Id
        ];

        // Verify 4 items were saved with correct total ($12,000 = 4 x $3,000)
        System.assertEquals(4, savedItems.size(), 'Should have 4 items saved');
        Decimal totalAmount = 0;
        for (Settlement_Plan_Item__c item : savedItems) {
            totalAmount += item.Payment_Amount__c;
        }
        System.assertEquals(12000, totalAmount, 'Total scheduled should be $12,000');
    }

    // ============ PHASE 34 TESTS: Item Ordering & Running Balance Fix ============

    /**
     * @description Tests recalculateBalances sorts items by date before calculating balances.
     *              Phase 34: Items may arrive unsorted from LWC; must sort before balance calculation.
     */
    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_SortsItemsByDate() {
        // Create items in WRONG order (by date): Mar, Jan, Feb
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();

        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 3,
            Payment_Date__c = Date.today().addMonths(3), // March
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));
        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 1,
            Payment_Date__c = Date.today().addMonths(1), // January
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));
        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 2,
            Payment_Date__c = Date.today().addMonths(2), // February
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items,
            3000 // Settlement offer = $3,000
        );
        Test.stopTest();

        System.assert(result.success, 'Recalculation should succeed');

        // After sorting, items should be in date order: Jan, Feb, Mar
        // Balances should cascade correctly: 2000, 1000, 0
        System.assertEquals(Date.today().addMonths(1), result.paymentItems[0].Payment_Date__c,
            'First item should be January (earliest date)');
        System.assertEquals(Date.today().addMonths(2), result.paymentItems[1].Payment_Date__c,
            'Second item should be February');
        System.assertEquals(Date.today().addMonths(3), result.paymentItems[2].Payment_Date__c,
            'Third item should be March (latest date)');
    }

    /**
     * @description Tests recalculateBalances uses effectiveOffer - totalPaid as starting balance.
     *              Phase 34: When revised amount is set, new items should start from (Revised - Paid).
     */
    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_UsesEffectiveOfferMinusPaid() {
        // Scenario: Original $42k, Revised $45k, $2k already paid

        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();

        // Paid item (locked) - $2k paid
        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 1,
            Payment_Date__c = Date.today(),
            Payment_Amount__c = 2000,
            Status__c = statusCleared()
        ));

        // New scheduled item - $1k payment
        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 2,
            Payment_Date__c = Date.today().addMonths(1),
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items,
            45000 // Effective (revised) settlement = $45,000
        );
        Test.stopTest();

        System.assert(result.success, 'Recalculation should succeed');
        System.assertEquals(statusCleared(), result.paymentItems[0].Status__c,
            'Cleared item status should be preserved');
        System.assertEquals(statusScheduled(), result.paymentItems[1].Status__c,
            'Scheduled item status should be preserved');
    }

    /**
     * @description Tests recalculateBalances correctly handles Missed items.
     *              Missed items should PRESERVE their historical running balance (not recalculated).
     *              Only Scheduled items get their running balance recalculated.
     */
    @IsTest(SeeAllData=true)
    static void testRecalculateBalances_MissedItemsAreBalanceNeutral() {
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();

        // Paid item - $1k paid, historical balance preserved
        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 1,
            Payment_Date__c = Date.today(),
            Payment_Amount__c = 1000,
            Status__c = statusCleared()
        ));

        // Missed item - should PRESERVE historical balance (not recalculated)
        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 2,
            Payment_Date__c = Date.today().addMonths(1),
            Payment_Amount__c = 1000,
            Status__c = statusMissed()
        ));

        // Scheduled item - should be recalculated based on effective offer minus paid
        items.add(new Settlement_Plan_Item__c(
            Payment_Number__c = 3,
            Payment_Date__c = Date.today().addMonths(2),
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));

        Test.startTest();
        SettlementDraftService.RecalculationResult result = SettlementDraftService.recalculateBalances(
            items,
            10000 // Effective settlement = $10,000
        );
        Test.stopTest();

        System.assert(result.success, 'Recalculation should succeed');
        System.assertEquals(statusCleared(), result.paymentItems[0].Status__c,
            'Cleared item status should be preserved');
        System.assertEquals(statusMissed(), result.paymentItems[1].Status__c,
            'Missed item status should be preserved');
        System.assertEquals(statusScheduled(), result.paymentItems[2].Status__c,
            'Scheduled item status should be preserved');
    }

    /**
     * @description Tests getDraftWithDetails returns items ordered by date, then payment number.
     *              Phase 34: ORDER BY Payment_Date__c ASC, Payment_Number__c ASC
     */
    @IsTest
    static void testGetDraftWithDetails_OrdersByDateThenPaymentNumber() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();

        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = 'Order Test',
            CreditorOpportunity__c = credOpp.Id,
            Status__c = SettlementDraftService.STATUS_DRAFT,
            Balance__c = TEST_BALANCE,
            Settlement_Offer_Amount__c = TEST_SETTLEMENT_OFFER
        );
        insert draft;

        // Create items with same date but different payment numbers
        // and items with different dates to test sorting
        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>();

        // Feb 15 - Payment #3 (should be 3rd)
        items.add(new Settlement_Plan_Item__c(
            Settlement_Plan__c = draft.Id,
            Payment_Number__c = 3,
            Payment_Date__c = Date.newInstance(2026, 2, 15),
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));
        // Jan 15 - Payment #2 (should be 2nd - same date as #1 but higher number)
        items.add(new Settlement_Plan_Item__c(
            Settlement_Plan__c = draft.Id,
            Payment_Number__c = 2,
            Payment_Date__c = Date.newInstance(2026, 1, 15),
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));
        // Jan 15 - Payment #1 (should be 1st)
        items.add(new Settlement_Plan_Item__c(
            Settlement_Plan__c = draft.Id,
            Payment_Number__c = 1,
            Payment_Date__c = Date.newInstance(2026, 1, 15),
            Payment_Amount__c = 1000,
            Status__c = statusScheduled()
        ));
        insert items;

        Test.startTest();
        SettlementDraftService.DraftWrapper wrapper = SettlementDraftService.getDraftWithDetails(draft.Id);
        Test.stopTest();

        System.assertEquals(3, wrapper.paymentItems.size(), 'Should have 3 items');

        // Verify order: Jan15/#1, Jan15/#2, Feb15/#3
        System.assertEquals(Date.newInstance(2026, 1, 15), wrapper.paymentItems[0].Payment_Date__c,
            'First item should be Jan 15');
        System.assertEquals(1, wrapper.paymentItems[0].Payment_Number__c,
            'First item should be Payment #1');

        System.assertEquals(Date.newInstance(2026, 1, 15), wrapper.paymentItems[1].Payment_Date__c,
            'Second item should be Jan 15');
        System.assertEquals(2, wrapper.paymentItems[1].Payment_Number__c,
            'Second item should be Payment #2');

        System.assertEquals(Date.newInstance(2026, 2, 15), wrapper.paymentItems[2].Payment_Date__c,
            'Third item should be Feb 15');
        System.assertEquals(3, wrapper.paymentItems[2].Payment_Number__c,
            'Third item should be Payment #3');
    }

    // ============ BUSINESS DAY ADJUSTMENT ON SAVE ============

    /**
     * @description Tests that saveDraftWithRecords adjusts weekend dates to 2 business days prior.
     *              When a user manually edits a payment date to a weekend, save should auto-correct it.
     */
    @IsTest(SeeAllData=true)
    static void testSaveDraftWithRecords_AdjustsWeekendDatesToBusinessDay() {
        CreditorOpportunity__c credOpp = getTestCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createTestDraft(credOpp.Id, 'Business Day Adjustment Test');

        // Feb 7, 2026 is a Saturday - should be adjusted 2 business days back to Thursday Feb 5, 2026
        Date saturday = Date.newInstance(2026, 2, 7);
        Date expectedThursday = Date.newInstance(2026, 2, 5);

        List<Settlement_Plan_Item__c> items = new List<Settlement_Plan_Item__c>{
            new Settlement_Plan_Item__c(
                Payment_Number__c = 1,
                Payment_Date__c = saturday,
                Payment_Amount__c = 1000.00,
                Commission_Fee__c = TEST_COMMISSION_FEE,
                Bank_Fee__c = TEST_BANK_FEE,
                EPPS_Transaction_Fee__c = TEST_EPPS_TXN_FEE,
                Status__c = statusScheduled()
            )
        };

        Test.startTest();
        SettlementDraftService.saveDraftWithRecords(draft.Id, null, items);
        Test.stopTest();

        // Query saved item
        Settlement_Plan_Item__c savedItem = [
            SELECT Id, Payment_Date__c, Original_Payment_Date__c
            FROM Settlement_Plan_Item__c
            WHERE Settlement_Plan__c = :draft.Id
            LIMIT 1
        ];

        System.assertEquals(expectedThursday, savedItem.Payment_Date__c,
            'Payment date should be adjusted from Saturday to Thursday (2 business days back)');
        System.assertEquals(saturday, savedItem.Original_Payment_Date__c,
            'Original payment date should store the original Saturday date');
    }
}