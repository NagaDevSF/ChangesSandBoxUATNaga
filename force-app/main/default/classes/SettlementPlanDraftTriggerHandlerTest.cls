/**
 * @description Test class for SettlementPlanDraftTrigger and SettlementPlanDraftTriggerHandler.
 *              Tests the "one Active plan per CreditorOpportunity" validation.
 */
@IsTest
private class SettlementPlanDraftTriggerHandlerTest {

    private static final Decimal TEST_BALANCE = 20000.00;
    private static final Decimal TEST_ESCROW_START = 15000.00;

    // ==================== TEST DATA FACTORY ====================

    private static CreditorOpportunity__c createCreditorOpportunity() {
        Account acc = new Account(Name = 'Trigger Test Account');
        insert acc;

        Account_Bank_Information__c bankInfo = new Account_Bank_Information__c(Account__c = acc.Id);
        insert bankInfo;

        CreditorOpportunity__c credOpp = new CreditorOpportunity__c(
            Name = 'Trigger Test Creditor Opp',
            CreditorAccount__c = acc.Id,
            Account_Bank_Information__c = bankInfo.Id,
            Amount__c = TEST_BALANCE,
            Escrow_Start_Balance__c = TEST_ESCROW_START
        );
        insert credOpp;
        return credOpp;
    }

    private static Settlement_Plan_Draft__c createDraft(Id credOppId, String name, String status) {
        Settlement_Plan_Draft__c draft = new Settlement_Plan_Draft__c(
            Name = name,
            CreditorOpportunity__c = credOppId,
            Status__c = status,
            Balance__c = TEST_BALANCE,
            Settlement_Offer_Amount__c = 10000.00,
            Escrow_Start_Balance__c = TEST_ESCROW_START,
            Is_Manually_Modified__c = false
        );
        insert draft;
        return draft;
    }

    // ==================== POSITIVE TESTS ====================

    @IsTest
    static void testAllowsFirstActiveInsert() {
        CreditorOpportunity__c credOpp = createCreditorOpportunity();

        Test.startTest();
        Settlement_Plan_Draft__c draft = createDraft(
            credOpp.Id, 'Only Active', SettlementDraftService.STATUS_ACTIVE
        );
        Test.stopTest();

        Settlement_Plan_Draft__c result = [
            SELECT Status__c FROM Settlement_Plan_Draft__c WHERE Id = :draft.Id
        ];
        System.assertEquals(SettlementDraftService.STATUS_ACTIVE, result.Status__c,
            'First Active draft should be allowed');
    }

    @IsTest
    static void testAllowsResaveOfExistingActive() {
        CreditorOpportunity__c credOpp = createCreditorOpportunity();
        Settlement_Plan_Draft__c draft = createDraft(
            credOpp.Id, 'Active Draft', SettlementDraftService.STATUS_ACTIVE
        );

        Test.startTest();
        draft.Balance__c = 15000;
        update draft;
        Test.stopTest();

        Settlement_Plan_Draft__c result = [
            SELECT Status__c, Balance__c FROM Settlement_Plan_Draft__c WHERE Id = :draft.Id
        ];
        System.assertEquals(SettlementDraftService.STATUS_ACTIVE, result.Status__c,
            'Re-saving existing Active draft should not be blocked');
        System.assertEquals(15000, result.Balance__c, 'Balance should be updated');
    }

    @IsTest
    static void testAllowsNonActiveStatusChanges() {
        CreditorOpportunity__c credOpp = createCreditorOpportunity();
        createDraft(credOpp.Id, 'Active Plan', SettlementDraftService.STATUS_ACTIVE);

        Test.startTest();
        Settlement_Plan_Draft__c draft = createDraft(credOpp.Id, 'Other Draft', SettlementDraftService.STATUS_DRAFT);
        draft.Status__c = SettlementDraftService.STATUS_ARCHIVED;
        update draft;
        Test.stopTest();

        Settlement_Plan_Draft__c result = [
            SELECT Status__c FROM Settlement_Plan_Draft__c WHERE Id = :draft.Id
        ];
        System.assertEquals(SettlementDraftService.STATUS_ARCHIVED, result.Status__c,
            'Non-Active status changes should not be blocked');
    }

    @IsTest
    static void testAllowsActiveOnDifferentCreditorOpps() {
        CreditorOpportunity__c credOpp1 = createCreditorOpportunity();

        Account acc2 = new Account(Name = 'Trigger Test Account 2');
        insert acc2;
        Account_Bank_Information__c bankInfo2 = new Account_Bank_Information__c(Account__c = acc2.Id);
        insert bankInfo2;
        CreditorOpportunity__c credOpp2 = new CreditorOpportunity__c(
            Name = 'Trigger Test Creditor Opp 2',
            CreditorAccount__c = acc2.Id,
            Account_Bank_Information__c = bankInfo2.Id,
            Amount__c = TEST_BALANCE,
            Escrow_Start_Balance__c = TEST_ESCROW_START
        );
        insert credOpp2;

        Test.startTest();
        createDraft(credOpp1.Id, 'Active on CredOpp1', SettlementDraftService.STATUS_ACTIVE);
        createDraft(credOpp2.Id, 'Active on CredOpp2', SettlementDraftService.STATUS_ACTIVE);
        Test.stopTest();

        List<Settlement_Plan_Draft__c> actives = [
            SELECT Id FROM Settlement_Plan_Draft__c WHERE Status__c = :SettlementDraftService.STATUS_ACTIVE
        ];
        System.assertEquals(2, actives.size(), 'Different CreditorOpps should each allow one Active');
    }

    // ==================== NEGATIVE TESTS ====================

    @IsTest
    static void testBlocksSecondActiveInsert() {
        CreditorOpportunity__c credOpp = createCreditorOpportunity();
        createDraft(credOpp.Id, 'First Active', SettlementDraftService.STATUS_ACTIVE);

        Test.startTest();
        try {
            createDraft(credOpp.Id, 'Second Active', SettlementDraftService.STATUS_ACTIVE);
            System.assert(false, 'Should have thrown DmlException for duplicate Active');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Only one Settlement Plan can be Active'),
                'Error should mention one Active per Creditor Opportunity. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testBlocksUpdateToActiveWithExistingSibling() {
        CreditorOpportunity__c credOpp = createCreditorOpportunity();
        createDraft(credOpp.Id, 'Already Active', SettlementDraftService.STATUS_ACTIVE);

        Settlement_Plan_Draft__c secondDraft = createDraft(
            credOpp.Id, 'Will Try Active', SettlementDraftService.STATUS_DRAFT
        );

        Test.startTest();
        try {
            secondDraft.Status__c = SettlementDraftService.STATUS_ACTIVE;
            update secondDraft;
            System.assert(false, 'Should have thrown DmlException for duplicate Active');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Only one Settlement Plan can be Active'),
                'Error should mention one Active per Creditor Opportunity. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testBlocksBatchInsertOfTwoActivesForSameCreditorOpp() {
        CreditorOpportunity__c credOpp = createCreditorOpportunity();

        List<Settlement_Plan_Draft__c> drafts = new List<Settlement_Plan_Draft__c>{
            new Settlement_Plan_Draft__c(
                Name = 'Batch Active 1',
                CreditorOpportunity__c = credOpp.Id,
                Status__c = SettlementDraftService.STATUS_ACTIVE,
                Balance__c = TEST_BALANCE,
                Settlement_Offer_Amount__c = 10000.00,
                Escrow_Start_Balance__c = TEST_ESCROW_START,
                Is_Manually_Modified__c = false
            ),
            new Settlement_Plan_Draft__c(
                Name = 'Batch Active 2',
                CreditorOpportunity__c = credOpp.Id,
                Status__c = SettlementDraftService.STATUS_ACTIVE,
                Balance__c = TEST_BALANCE,
                Settlement_Offer_Amount__c = 10000.00,
                Escrow_Start_Balance__c = TEST_ESCROW_START,
                Is_Manually_Modified__c = false
            )
        };

        Test.startTest();
        try {
            insert drafts;
            System.assert(false, 'Should have thrown DmlException for batch duplicate Active');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Only one Settlement Plan can be Active'),
                'Error should mention one Active per Creditor Opportunity. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }
}