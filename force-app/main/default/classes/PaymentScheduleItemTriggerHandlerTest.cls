@isTest
private class PaymentScheduleItemTriggerHandlerTest {

    @TestSetup
    static void setupTestData() {
        // Create Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opp;

        // Create Payment Plan
        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = opp.Id,
            Is_Active__c = true,
            Status__c = 'Active',
            Version_Number__c = 1
        );
        insert plan;

        // Create Payment Schedule Items with different statuses
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        for (Integer i = 1; i <= 5; i++) {
            items.add(new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Date__c = Date.today().addDays(i * 7),
                Total_Payment__c = 100,
                Status__c = 'Scheduled',
                Payment_Number__c = i,
                Draft_Number__c = String.valueOf(i)
            ));
        }
        insert items;
    }

    // ============ recalculateDraftNumbersOnStatusChange Tests ============

    @isTest
    static void testRecalculateDraftNumbers_StatusChangeToNSF() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];
        List<Payment_Schedule_Item__c> items = [
            SELECT Id, Status__c, Draft_Number__c, Payment_Date__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        // Verify initial draft numbers
        System.assertEquals('1', items[0].Draft_Number__c);
        System.assertEquals('2', items[1].Draft_Number__c);
        System.assertEquals('3', items[2].Draft_Number__c);

        Test.startTest();
        // Change second item to NSF
        items[1].Status__c = 'NSF';
        update items[1];
        Test.stopTest();

        // Query updated items
        List<Payment_Schedule_Item__c> updatedItems = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        // First item should still be 1
        System.assertEquals('1', updatedItems[0].Draft_Number__c, 'First item should be draft 1');
        // Second item (NSF) should be null
        System.assertEquals(null, updatedItems[1].Draft_Number__c, 'NSF item should have null draft number');
        // Third item should now be 2 (renumbered)
        System.assertEquals('2', updatedItems[2].Draft_Number__c, 'Third item should be renumbered to 2');
        // Fourth item should be 3
        System.assertEquals('3', updatedItems[3].Draft_Number__c, 'Fourth item should be renumbered to 3');
        // Fifth item should be 4
        System.assertEquals('4', updatedItems[4].Draft_Number__c, 'Fifth item should be renumbered to 4');
    }

    @isTest
    static void testRecalculateDraftNumbers_StatusChangeToCancelled() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];
        List<Payment_Schedule_Item__c> items = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        Test.startTest();
        // Change first item to Cancelled
        items[0].Status__c = 'Cancelled';
        update items[0];
        Test.stopTest();

        // Query updated items
        List<Payment_Schedule_Item__c> updatedItems = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        // First item (Cancelled) should be null
        System.assertEquals(null, updatedItems[0].Draft_Number__c, 'Cancelled item should have null draft number');
        // Second item should now be 1
        System.assertEquals('1', updatedItems[1].Draft_Number__c, 'Second item should be renumbered to 1');
        // Third item should be 2
        System.assertEquals('2', updatedItems[2].Draft_Number__c, 'Third item should be renumbered to 2');
    }

    @isTest
    static void testRecalculateDraftNumbers_StatusChangeFromNSFToScheduled() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];
        List<Payment_Schedule_Item__c> items = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        // First change to NSF
        items[1].Status__c = 'NSF';
        update items[1];

        // Verify NSF state
        Payment_Schedule_Item__c nsfItem = [SELECT Draft_Number__c FROM Payment_Schedule_Item__c WHERE Id = :items[1].Id];
        System.assertEquals(null, nsfItem.Draft_Number__c, 'NSF item should have null draft number');

        Test.startTest();
        // Change back to Scheduled
        items[1].Status__c = 'Scheduled';
        update items[1];
        Test.stopTest();

        // Query updated items
        List<Payment_Schedule_Item__c> updatedItems = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        // All items should be numbered 1-5 again
        System.assertEquals('1', updatedItems[0].Draft_Number__c);
        System.assertEquals('2', updatedItems[1].Draft_Number__c);
        System.assertEquals('3', updatedItems[2].Draft_Number__c);
        System.assertEquals('4', updatedItems[3].Draft_Number__c);
        System.assertEquals('5', updatedItems[4].Draft_Number__c);
    }

    @isTest
    static void testRecalculateDraftNumbers_MultipleNSF() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];
        List<Payment_Schedule_Item__c> items = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        Test.startTest();
        // Change items 2 and 4 to NSF
        items[1].Status__c = 'NSF';
        items[3].Status__c = 'NSF';
        update new List<Payment_Schedule_Item__c>{ items[1], items[3] };
        Test.stopTest();

        // Query updated items
        List<Payment_Schedule_Item__c> updatedItems = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        System.assertEquals('1', updatedItems[0].Draft_Number__c, 'First item should be 1');
        System.assertEquals(null, updatedItems[1].Draft_Number__c, 'Second item (NSF) should be null');
        System.assertEquals('2', updatedItems[2].Draft_Number__c, 'Third item should be 2');
        System.assertEquals(null, updatedItems[3].Draft_Number__c, 'Fourth item (NSF) should be null');
        System.assertEquals('3', updatedItems[4].Draft_Number__c, 'Fifth item should be 3');
    }

    @isTest
    static void testRecalculateDraftNumbers_NoStatusChange() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];
        List<Payment_Schedule_Item__c> items = [
            SELECT Id, Status__c, Draft_Number__c, Total_Payment__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        // Store original draft numbers
        Map<Id, String> originalDraftNumbers = new Map<Id, String>();
        for (Payment_Schedule_Item__c item : items) {
            originalDraftNumbers.put(item.Id, item.Draft_Number__c);
        }

        Test.startTest();
        // Update amount only (no status change)
        items[0].Total_Payment__c = 200;
        update items[0];
        Test.stopTest();

        // Query updated items
        List<Payment_Schedule_Item__c> updatedItems = [
            SELECT Id, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
        ];

        // Draft numbers should remain unchanged
        for (Payment_Schedule_Item__c item : updatedItems) {
            System.assertEquals(originalDraftNumbers.get(item.Id), item.Draft_Number__c, 'Draft number should not change when status is unchanged');
        }
    }

    @isTest
    static void testRecalculateDraftNumbers_EmptyPlanId() {
        // Create item without Payment Plan (edge case)
        Payment_Schedule_Item__c item = new Payment_Schedule_Item__c(
            Payment_Date__c = Date.today(),
            Total_Payment__c = 100,
            Status__c = 'Scheduled'
        );

        Test.startTest();
        // This should not throw an error
        try {
            insert item;
            item.Status__c = 'NSF';
            update item;
        } catch (Exception e) {
            // Expected if validation rules require Payment Plan
        }
        Test.stopTest();
    }

    @isTest
    static void testRecalculateDraftNumbers_StatusToCleared() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];
        List<Payment_Schedule_Item__c> items = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        Test.startTest();
        // Change first item to Cleared (should keep draft number)
        items[0].Status__c = 'Cleared';
        update items[0];
        Test.stopTest();

        // Query updated items
        List<Payment_Schedule_Item__c> updatedItems = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        // Cleared items should keep their draft numbers
        System.assertEquals('1', updatedItems[0].Draft_Number__c, 'Cleared item should keep draft number');
        System.assertEquals('2', updatedItems[1].Draft_Number__c);
        System.assertEquals('3', updatedItems[2].Draft_Number__c);
    }

    // ============ blockDMLWhileRelatedOppIsLocked Tests ============

    @isTest
    static void testBlockDML_OppNotLocked() {
        Payment_Schedule_Item__c item = [SELECT Id, Related_Opportunity__c FROM Payment_Schedule_Item__c LIMIT 1];

        Test.startTest();
        // Should not throw error when opp is not locked
        item.Total_Payment__c = 200;
        update item;
        Test.stopTest();

        Payment_Schedule_Item__c updated = [SELECT Total_Payment__c FROM Payment_Schedule_Item__c WHERE Id = :item.Id];
        System.assertEquals(200, updated.Total_Payment__c, 'Update should succeed when opp is not locked');
    }

    @isTest
    static void testBlockDML_NoRelatedOpp() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];

        // Create item without Related_Opportunity__c
        Payment_Schedule_Item__c item = new Payment_Schedule_Item__c(
            Payment_Plan__c = plan.Id,
            Payment_Date__c = Date.today().addDays(100),
            Total_Payment__c = 100,
            Status__c = 'Scheduled',
            Payment_Number__c = 100
        );
        insert item;

        Test.startTest();
        // Should not throw error when no related opp
        item.Total_Payment__c = 200;
        update item;
        Test.stopTest();

        Payment_Schedule_Item__c updated = [SELECT Total_Payment__c FROM Payment_Schedule_Item__c WHERE Id = :item.Id];
        System.assertEquals(200, updated.Total_Payment__c, 'Update should succeed when no related opp');
    }

    // ============ TriggerRecursionControl Tests ============

    @isTest
    static void testTriggerRecursionControl() {
        // Test the recursion control flag
        System.assertEquals(false, TriggerRecursionControl.isRecalculatingDraftNumbers, 'Should be false by default');

        TriggerRecursionControl.isRecalculatingDraftNumbers = true;
        System.assertEquals(true, TriggerRecursionControl.isRecalculatingDraftNumbers, 'Should be true after setting');

        TriggerRecursionControl.isRecalculatingDraftNumbers = false;
        System.assertEquals(false, TriggerRecursionControl.isRecalculatingDraftNumbers, 'Should be false after resetting');
    }

    // ============ Bulk Tests ============

    @isTest
    static void testRecalculateDraftNumbers_BulkUpdate() {
        PaymentPlan__c plan = [SELECT Id FROM PaymentPlan__c LIMIT 1];

        // Create more items for bulk testing
        List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();
        for (Integer i = 6; i <= 20; i++) {
            newItems.add(new Payment_Schedule_Item__c(
                Payment_Plan__c = plan.Id,
                Payment_Date__c = Date.today().addDays(i * 7),
                Total_Payment__c = 100,
                Status__c = 'Scheduled',
                Payment_Number__c = i,
                Draft_Number__c = String.valueOf(i)
            ));
        }
        insert newItems;

        List<Payment_Schedule_Item__c> allItems = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        Test.startTest();
        // Change every other item to NSF
        List<Payment_Schedule_Item__c> toUpdate = new List<Payment_Schedule_Item__c>();
        for (Integer i = 1; i < allItems.size(); i += 2) {
            allItems[i].Status__c = 'NSF';
            toUpdate.add(allItems[i]);
        }
        update toUpdate;
        Test.stopTest();

        // Verify all NSF items have null draft numbers and others are renumbered
        List<Payment_Schedule_Item__c> updatedItems = [
            SELECT Id, Status__c, Draft_Number__c
            FROM Payment_Schedule_Item__c
            WHERE Payment_Plan__c = :plan.Id
            ORDER BY Payment_Date__c
        ];

        Integer expectedDraftNumber = 1;
        for (Payment_Schedule_Item__c item : updatedItems) {
            if (item.Status__c == 'NSF') {
                System.assertEquals(null, item.Draft_Number__c, 'NSF item should have null draft number');
            } else {
                System.assertEquals(String.valueOf(expectedDraftNumber), item.Draft_Number__c, 'Non-NSF item should be numbered correctly');
                expectedDraftNumber++;
            }
        }
    }
}