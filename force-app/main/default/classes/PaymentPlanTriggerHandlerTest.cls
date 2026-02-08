@isTest
private class PaymentPlanTriggerHandlerTest {

    @TestSetup
    static void setupTestData() {
        Account acc = TestDataFactory.makeAccount('PPTrigger Test Account');
        Opportunity opp1 = TestDataFactory.makeOpp(acc.Id, 'PPTrigger Opp 1');
        Opportunity opp2 = TestDataFactory.makeOpp(acc.Id, 'PPTrigger Opp 2');
    }

    // ==================================================================================
    // preventDuplicateActivePaymentPlans — INSERT scenarios
    // ==================================================================================

    @isTest
    static void insertActivePlan_noExisting_shouldSucceed() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        Test.startTest();
        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Active'
        );
        insert plan;
        Test.stopTest();

        List<PaymentPlan__c> plans = [SELECT Id FROM PaymentPlan__c WHERE Opportunity__c = :opp.Id AND Status__c = 'Active'];
        System.assertEquals(1, plans.size(), 'Should allow first active plan');
    }

    @isTest
    static void insertActivePlan_existingActive_shouldFail() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        // Create existing active plan
        insert new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Active'
        );

        Test.startTest();
        try {
            insert new PaymentPlan__c(
                Opportunity__c = opp.Id,
                Version_Number__c = 2,
                Status__c = 'Active'
            );
            System.assert(false, 'Should have thrown DmlException');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
                'Error should contain duplicate active message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void insertDraftPlan_existingActive_shouldSucceed() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        insert new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Active'
        );

        Test.startTest();
        PaymentPlan__c draftPlan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 2,
            Status__c = 'Draft'
        );
        insert draftPlan;
        Test.stopTest();

        List<PaymentPlan__c> plans = [SELECT Id FROM PaymentPlan__c WHERE Opportunity__c = :opp.Id];
        System.assertEquals(2, plans.size(), 'Should allow inserting a Draft plan alongside an Active one');
    }

    // ==================================================================================
    // preventDuplicateActivePaymentPlans — UPDATE scenarios
    // ==================================================================================

    @isTest
    static void updateToActive_noExisting_shouldSucceed() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Draft'
        );
        insert plan;

        Test.startTest();
        plan.Status__c = 'Active';
        update plan;
        Test.stopTest();

        PaymentPlan__c updated = [SELECT Status__c FROM PaymentPlan__c WHERE Id = :plan.Id];
        System.assertEquals('Active', updated.Status__c, 'Should allow activating when no other active plan exists');
    }

    @isTest
    static void updateToActive_existingActive_shouldFail() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        insert new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Active'
        );

        PaymentPlan__c draftPlan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 2,
            Status__c = 'Draft'
        );
        insert draftPlan;

        Test.startTest();
        try {
            draftPlan.Status__c = 'Active';
            update draftPlan;
            System.assert(false, 'Should have thrown DmlException');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
                'Error should contain duplicate active message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void updateNonStatusField_alreadyActive_shouldSucceed() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Active'
        );
        insert plan;

        Test.startTest();
        plan.Weekly_Payment__c = 200;
        update plan;
        Test.stopTest();

        PaymentPlan__c updated = [SELECT Weekly_Payment__c FROM PaymentPlan__c WHERE Id = :plan.Id];
        System.assertEquals(200, updated.Weekly_Payment__c, 'Should allow updating non-status fields on an active plan');
    }

    // ==================================================================================
    // preventDuplicateActivePaymentPlans — DIFFERENT Opportunities
    // ==================================================================================

    @isTest
    static void insertActivePlans_differentOpps_shouldSucceed() {
        Opportunity opp1 = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];
        Opportunity opp2 = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 2' LIMIT 1];

        Test.startTest();
        List<PaymentPlan__c> plans = new List<PaymentPlan__c>{
            new PaymentPlan__c(Opportunity__c = opp1.Id, Version_Number__c = 1, Status__c = 'Active'),
            new PaymentPlan__c(Opportunity__c = opp2.Id, Version_Number__c = 1, Status__c = 'Active')
        };
        insert plans;
        Test.stopTest();

        List<PaymentPlan__c> activePlans = [SELECT Id FROM PaymentPlan__c WHERE Status__c = 'Active'];
        System.assertEquals(2, activePlans.size(), 'Should allow active plans on different Opportunities');
    }

    // ==================================================================================
    // preventDuplicateActivePaymentPlans — BULK / batch-duplicate scenarios
    // ==================================================================================

    @isTest
    static void bulkInsert_multipleActiveForSameOpp_onlyFirstSucceeds() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        List<PaymentPlan__c> plans = new List<PaymentPlan__c>();
        for (Integer i = 1; i <= 5; i++) {
            plans.add(new PaymentPlan__c(
                Opportunity__c = opp.Id,
                Version_Number__c = i,
                Status__c = 'Active'
            ));
        }

        Test.startTest();
        Database.SaveResult[] results = Database.insert(plans, false);
        Test.stopTest();

        Integer successCount = 0;
        Integer failCount = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                successCount++;
            } else {
                failCount++;
                System.assert(sr.getErrors()[0].getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
                    'Failed record should have duplicate active message');
            }
        }
        System.assertEquals(1, successCount, 'Only the first record should succeed');
        System.assertEquals(4, failCount, 'Remaining 4 records should fail');
    }

    @isTest
    static void bulkUpdate_multipleToActiveForSameOpp_onlyFirstSucceeds() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        List<PaymentPlan__c> plans = new List<PaymentPlan__c>();
        for (Integer i = 1; i <= 3; i++) {
            plans.add(new PaymentPlan__c(
                Opportunity__c = opp.Id,
                Version_Number__c = i,
                Status__c = 'Draft'
            ));
        }
        insert plans;

        Test.startTest();
        for (PaymentPlan__c p : plans) {
            p.Status__c = 'Active';
        }
        Database.SaveResult[] results = Database.update(plans, false);
        Test.stopTest();

        Integer successCount = 0;
        Integer failCount = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                successCount++;
            } else {
                failCount++;
                System.assert(sr.getErrors()[0].getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
                    'Failed record should have duplicate active message');
            }
        }
        System.assertEquals(1, successCount, 'Only the first record should succeed');
        System.assertEquals(2, failCount, 'Remaining 2 records should fail');
    }
}
