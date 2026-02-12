@IsTest
private class PaymentPlanVersionControllerTest {

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'PPVC Acc');
        insert a;
        Opportunity o = new Opportunity(Name = 'PPVC Opp', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert o;

        // Base plan
        PaymentPlan__c base = new PaymentPlan__c(Opportunity__c = o.Id,
            Version_Number__c = 1,
            Status__c = 'Draft',
            Is_Active__c = false);
        insert base;

        // Some schedule items for the base
        List<Payment_Schedule_Item__c> items = new List<Payment_Schedule_Item__c>();
        for (Integer i = 1; i <= 3; i++) {
            Payment_Schedule_Item__c it = new Payment_Schedule_Item__c();
            it.Payment_Plan__c = base.Id;
            it.Payment_Number__c = i;
            it.Payment_Date__c = Date.today().addDays(7 * i);
            it.Total_Payment__c = 100;
            items.add(it);
        }
        insert items;
    }

    private static Opportunity getOpp() {
        return [SELECT Id FROM Opportunity LIMIT 1];
    }

    private static PaymentPlan__c anyPlan() {
        return [SELECT Id, Opportunity__c, Is_Active__c, Status__c, Version_Number__c FROM PaymentPlan__c LIMIT 1];
    }

    @IsTest
    static void testGetPaymentPlanVersions() {
        Opportunity opp = getOpp();

        // Add a second version to ensure list has more than one
        PaymentPlan__c p2 = new PaymentPlan__c(Opportunity__c = opp.Id,
            Version_Number__c = 2,
            Status__c = 'Draft',
            Is_Active__c = false);
        insert p2;

        Test.startTest();
        List<PaymentPlan__c> versions = PaymentPlanVersionController.getPaymentPlanVersions(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, versions, 'Versions should not be null');
        System.assert(versions.size() >= 1, 'Should return at least one version');
    }

    @IsTest
    static void testGetPaymentScheduleItems() {
        PaymentPlan__c plan = anyPlan();
        Test.startTest();
        List<Payment_Schedule_Item__c> retrieved = PaymentPlanVersionController.getPaymentScheduleItems(plan.Id);
        Test.stopTest();
        System.assertNotEquals(null, retrieved);
        System.assert(retrieved.size() >= 1, 'Should return schedule items');
    }

    @IsTest
    static void testCreateNewVersionAndActivate() {
        PaymentPlan__c base = anyPlan();

        Test.startTest();
        PaymentPlan__c newPlan = PaymentPlanVersionController.createNewVersion(base.Id);
        PaymentPlan__c activated = PaymentPlanVersionController.activateVersion(newPlan.Id);
        Test.stopTest();

        System.assertNotEquals(null, newPlan.Id, 'New version should be created');
        System.assertEquals(true, activated.Is_Active__c, 'Activated plan should be active');
    }

    @IsTest
    static void testUpdateNotesAndDeleteVersion() {
        Opportunity opp = getOpp();
        // Create a draft version we can safely delete
        PaymentPlan__c temp = new PaymentPlan__c(Opportunity__c = opp.Id,
            Version_Number__c = 99,
            Status__c = 'Draft',
            Is_Active__c = false);
        insert temp;

        Test.startTest();
        PaymentPlan__c updated = PaymentPlanVersionController.updateVersionNotes(temp.Id, 'Unit test note');
        PaymentPlanVersionController.deleteVersion(temp.Id);
        Test.stopTest();

        System.assertEquals('Unit test note', updated.Version_Notes__c);

        Integer countAfter = [SELECT count() FROM PaymentPlan__c WHERE Id = :temp.Id];
        System.assertEquals(0, countAfter, 'Version should be deleted');
    }
}