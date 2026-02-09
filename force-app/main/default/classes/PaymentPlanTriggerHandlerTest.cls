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
        Assert.areEqual(1, plans.size(), 'Should allow first active plan');
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
            Assert.fail('Should have thrown DmlException');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
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
        Assert.areEqual(2, plans.size(), 'Should allow inserting a Draft plan alongside an Active one');
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
        Assert.areEqual('Active', updated.Status__c, 'Should allow activating when no other active plan exists');
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
            Assert.fail('Should have thrown DmlException');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
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
        Assert.areEqual(200, updated.Weekly_Payment__c, 'Should allow updating non-status fields on an active plan');
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
        Assert.areEqual(2, activePlans.size(), 'Should allow active plans on different Opportunities');
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
                Assert.isTrue(sr.getErrors()[0].getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
                    'Failed record should have duplicate active message');
            }
        }
        Assert.areEqual(1, successCount, 'Only the first record should succeed');
        Assert.areEqual(4, failCount, 'Remaining 4 records should fail');
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
                Assert.isTrue(sr.getErrors()[0].getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
                    'Failed record should have duplicate active message');
            }
        }
        Assert.areEqual(1, successCount, 'Only the first record should succeed');
        Assert.areEqual(2, failCount, 'Remaining 2 records should fail');
    }

    // ==================================================================================
    // blockDMLWhileRelatedOppIsLocked — INSERT scenario
    // ==================================================================================

    @isTest
    static void insertPlan_unlockedOpp_shouldSucceed() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        Test.startTest();
        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Draft'
        );
        insert plan;
        Test.stopTest();

        List<PaymentPlan__c> plans = [SELECT Id FROM PaymentPlan__c WHERE Id = :plan.Id];
        Assert.areEqual(1, plans.size(), 'Should allow insert when Opportunity is not locked');
    }

    @isTest
    static void insertPlan_lockedOpp_shouldFail() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        Approval.lock(opp.Id);

        Test.startTest();
        try {
            insert new PaymentPlan__c(
                Opportunity__c = opp.Id,
                Version_Number__c = 1,
                Status__c = 'Draft'
            );
            Assert.fail('Should have thrown DmlException for locked Opportunity');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains(PaymentPlanTriggerHandler.APPROVAL_BLOCK_MSG),
                'Error should contain approval block message: ' + e.getMessage());
        }
        Test.stopTest();

        Approval.unlock(opp.Id);
    }

    // ==================================================================================
    // blockDMLWhileRelatedOppIsLocked — UPDATE scenario
    // ==================================================================================

    @isTest
    static void updatePlan_lockedOpp_shouldFail() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Draft'
        );
        insert plan;

        Approval.lock(opp.Id);

        Test.startTest();
        try {
            plan.Weekly_Payment__c = 500;
            update plan;
            Assert.fail('Should have thrown DmlException for locked Opportunity');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains(PaymentPlanTriggerHandler.APPROVAL_BLOCK_MSG),
                'Error should contain approval block message: ' + e.getMessage());
        }
        Test.stopTest();

        Approval.unlock(opp.Id);
    }

    // ==================================================================================
    // blockDMLWhileRelatedOppIsLocked — DELETE scenario
    // ==================================================================================

    @isTest
    static void deletePlan_unlockedOpp_shouldSucceed() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Draft'
        );
        insert plan;

        Test.startTest();
        delete plan;
        Test.stopTest();

        List<PaymentPlan__c> plans = [SELECT Id FROM PaymentPlan__c WHERE Id = :plan.Id];
        Assert.areEqual(0, plans.size(), 'Should allow delete when Opportunity is not locked');
    }

    @isTest
    static void deletePlan_lockedOpp_shouldFail() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];

        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Version_Number__c = 1,
            Status__c = 'Draft'
        );
        insert plan;

        Approval.lock(opp.Id);

        Test.startTest();
        try {
            delete plan;
            Assert.fail('Should have thrown DmlException for locked Opportunity');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains(PaymentPlanTriggerHandler.APPROVAL_BLOCK_MSG),
                'Error should contain approval block message: ' + e.getMessage());
        }
        Test.stopTest();

        Approval.unlock(opp.Id);
    }

    // ==================================================================================
    // blockDMLWhileRelatedOppIsLocked — BULK scenario
    // ==================================================================================

    @isTest
    static void bulkInsert_mixedLockedAndUnlocked_partialSuccess() {
        Opportunity opp1 = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 1' LIMIT 1];
        Opportunity opp2 = [SELECT Id FROM Opportunity WHERE Name = 'PPTrigger Opp 2' LIMIT 1];

        Approval.lock(opp1.Id);

        Test.startTest();
        List<PaymentPlan__c> plans = new List<PaymentPlan__c>{
            new PaymentPlan__c(Opportunity__c = opp1.Id, Version_Number__c = 1, Status__c = 'Draft'),
            new PaymentPlan__c(Opportunity__c = opp2.Id, Version_Number__c = 1, Status__c = 'Draft')
        };
        Database.SaveResult[] results = Database.insert(plans, false);
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess(), 'Insert on locked Opportunity should fail');
        Assert.isTrue(results[0].getErrors()[0].getMessage().contains(PaymentPlanTriggerHandler.APPROVAL_BLOCK_MSG),
            'Error should contain approval block message');
        Assert.isTrue(results[1].isSuccess(), 'Insert on unlocked Opportunity should succeed');

        Approval.unlock(opp1.Id);
    }

    // ==================================================================================
    // Edge case — null Opportunity
    // ==================================================================================

    @isTest
    static void insertPlan_nullOpportunity_shouldSkipValidation() {
        Test.startTest();
        try {
            PaymentPlan__c plan = new PaymentPlan__c(
                Version_Number__c = 1,
                Status__c = 'Active'
            );
            insert plan;
        } catch (DmlException e) {
            // If Opportunity__c is required by validation rules, the insert may fail
            // but it should NOT fail due to our trigger handler logic
            Assert.isFalse(e.getMessage().contains(PaymentPlanTriggerHandler.DUPLICATE_ACTIVE_MSG),
                'Null Opportunity should not trigger duplicate active check');
            Assert.isFalse(e.getMessage().contains(PaymentPlanTriggerHandler.APPROVAL_BLOCK_MSG),
                'Null Opportunity should not trigger approval lock check');
        }
        Test.stopTest();
    }
}
