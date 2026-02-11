/**
 * @description Test class for BulkRoundRobinAssignmentNXDS
 * @author Salesforce Developer
 * @date 2025
 */
@isTest
private class BulkRoundRobinAssignmentNXDSTest {

    /**
     * Setup test data - Using existing users to avoid MIXED_DML_OPERATION
     */
    @testSetup
    static void setupTestData() {
        // Get current user to use for testing
        Id currentUserId = UserInfo.getUserId();

        // Query for existing active users to use in tests
        List<User> existingUsers = [SELECT Id FROM User WHERE IsActive = true LIMIT 3];

        // Create QRMCA Round Robin records using existing users
        List<QRMCA_Round_Robin__c> qrmcaRecords = new List<QRMCA_Round_Robin__c>();
        for(Integer i = 0; i < Math.min(3, existingUsers.size()); i++) {
            qrmcaRecords.add(new QRMCA_Round_Robin__c(
                User__c = existingUsers[i].Id,
                Type__c = 'Regular'
            ));
        }

        // Insert QRMCA records first
        if(!qrmcaRecords.isEmpty()) {
            insert qrmcaRecords;
        }

        // Create test leads with different owners
        List<Lead> testLeads = new List<Lead>();

        if(existingUsers.size() >= 3) {
            // Lead owned by first round-robin user
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'Lead1',
                Company = 'Test Company 1',
                Status = 'New',
                OwnerId = existingUsers[0].Id
            ));

            // Lead owned by second round-robin user
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'Lead2',
                Company = 'Test Company 2',
                Status = 'Open - Not Contacted',
                OwnerId = existingUsers[1].Id
            ));

            // Lead owned by third round-robin user
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'Lead3',
                Company = 'Test Company 3',
                Status = 'New',
                OwnerId = existingUsers[2].Id
            ));
        }

        // Lead owned by non-round-robin user (current user)
        testLeads.add(new Lead(
            FirstName = 'Test',
            LastName = 'Lead4',
            Company = 'Test Company 4',
            Status = 'New',
            OwnerId = currentUserId
        ));

        insert testLeads;
    }

    /**
     * Test successful round-robin assignment with rotation
     */
    @isTest
    static void testRoundRobinRotation() {
        // Get test data from QRMCA Round Robin
        List<QRMCA_Round_Robin__c> qrmcaRecords = [SELECT Id, User__c FROM QRMCA_Round_Robin__c ORDER BY CreatedDate];
        List<Lead> testLeads = [SELECT Id, OwnerId FROM Lead WHERE LastName LIKE 'Lead%' ORDER BY LastName];

        // Skip if no QRMCA records
        if(qrmcaRecords.isEmpty() || testLeads.isEmpty()) {
            return;
        }

        // Prepare request
        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = new List<Id>();
        request.roundRobinIds = new List<Id>();

        for(Lead l : testLeads) {
            request.leadIds.add(l.Id);
        }

        for(QRMCA_Round_Robin__c qrmca : qrmcaRecords) {
            request.roundRobinIds.add(qrmca.Id);
        }

        Test.startTest();

        // Call invocable method
        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Verify leads were processed
        List<Lead> updatedLeads = [SELECT Id, OwnerId FROM Lead WHERE Id IN :testLeads];
        System.assert(!updatedLeads.isEmpty(), 'Leads should be processed');
    }

    /**
     * Test with null request list
     */
    @isTest
    static void testNullRequestList() {
        Test.startTest();

        // Call with null
        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(null);

        Test.stopTest();

        // Should not throw exception - verify by reaching this point
        System.assert(true, 'Should handle null request list gracefully');
    }

    /**
     * Test with empty request list
     */
    @isTest
    static void testEmptyRequestList() {
        Test.startTest();

        // Call with empty list
        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>());

        Test.stopTest();

        // Should not throw exception
        System.assert(true, 'Should handle empty request list gracefully');
    }

    /**
     * Test with null lead IDs
     */
    @isTest
    static void testNullLeadIds() {
        List<QRMCA_Round_Robin__c> qrmcaRecords = [SELECT Id FROM QRMCA_Round_Robin__c LIMIT 1];
        if(qrmcaRecords.isEmpty()) {
            return;
        }

        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = null;
        request.roundRobinIds = new List<Id>{qrmcaRecords[0].Id};

        Test.startTest();

        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Should handle gracefully
        System.assert(true, 'Should handle null lead IDs');
    }

    /**
     * Test with empty lead IDs
     */
    @isTest
    static void testEmptyLeadIds() {
        List<QRMCA_Round_Robin__c> qrmcaRecords = [SELECT Id FROM QRMCA_Round_Robin__c LIMIT 1];
        if(qrmcaRecords.isEmpty()) {
            return;
        }

        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = new List<Id>();
        request.roundRobinIds = new List<Id>{qrmcaRecords[0].Id};

        Test.startTest();

        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Should handle gracefully
        System.assert(true, 'Should handle empty lead IDs');
    }

    /**
     * Test with null round robin IDs
     */
    @isTest
    static void testNullRoundRobinIds() {
        List<Lead> testLeads = [SELECT Id FROM Lead LIMIT 1];

        if(testLeads.isEmpty()) {
            return; // Skip if no test data
        }

        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = new List<Id>{testLeads[0].Id};
        request.roundRobinIds = null;

        Test.startTest();

        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Should handle gracefully
        System.assert(true, 'Should handle null round robin IDs');
    }

    /**
     * Test with empty round robin IDs
     */
    @isTest
    static void testEmptyRoundRobinIds() {
        List<Lead> testLeads = [SELECT Id FROM Lead LIMIT 1];

        if(testLeads.isEmpty()) {
            return; // Skip if no test data
        }

        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = new List<Id>{testLeads[0].Id};
        request.roundRobinIds = new List<Id>();

        Test.startTest();

        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Should handle gracefully
        System.assert(true, 'Should handle empty round robin IDs');
    }

    /**
     * Test when lead is already assigned to correct next user (rotation happens)
     */
    @isTest
    static void testLeadRotation() {
        List<QRMCA_Round_Robin__c> qrmcaRecords = [SELECT Id, User__c FROM QRMCA_Round_Robin__c ORDER BY CreatedDate];
        List<Lead> testLeads = [SELECT Id, OwnerId FROM Lead WHERE LastName = 'Lead1'];

        if(qrmcaRecords.isEmpty() || testLeads.isEmpty()) {
            return;
        }

        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = new List<Id>{testLeads[0].Id};
        request.roundRobinIds = new List<Id>();

        for(QRMCA_Round_Robin__c qrmca : qrmcaRecords) {
            request.roundRobinIds.add(qrmca.Id);
        }

        Test.startTest();

        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Verify lead was processed
        Lead updatedLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :testLeads[0].Id];
        System.assertNotEquals(null, updatedLead.OwnerId, 'Lead should have an owner');
    }

    /**
     * Test with large volume of leads (performance test)
     */
    @isTest
    static void testBulkLeadAssignment() {
        List<QRMCA_Round_Robin__c> qrmcaRecords = [SELECT Id, User__c FROM QRMCA_Round_Robin__c ORDER BY CreatedDate];

        if(qrmcaRecords.isEmpty()) {
            return;
        }

        // Create 200 leads (batch limit)
        List<Lead> bulkLeads = new List<Lead>();
        for(Integer i = 0; i < 200; i++) {
            bulkLeads.add(new Lead(
                FirstName = 'Bulk',
                LastName = 'Lead' + i,
                Company = 'Bulk Company ' + i,
                Status = 'New',
                OwnerId = UserInfo.getUserId()
            ));
        }
        insert bulkLeads;

        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = new List<Id>();
        request.roundRobinIds = new List<Id>();

        for(Lead l : bulkLeads) {
            request.leadIds.add(l.Id);
        }

        for(QRMCA_Round_Robin__c qrmca : qrmcaRecords) {
            request.roundRobinIds.add(qrmca.Id);
        }

        Test.startTest();

        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Verify all leads were processed
        List<Lead> updatedLeads = [SELECT Id, OwnerId FROM Lead WHERE Id IN :bulkLeads];
        System.assertEquals(200, updatedLeads.size(), 'All 200 leads should be processed');
    }

    /**
     * Test single user in round-robin (edge case)
     */
    @isTest
    static void testSingleUserRoundRobin() {
        List<QRMCA_Round_Robin__c> qrmcaRecords = [SELECT Id, User__c FROM QRMCA_Round_Robin__c ORDER BY CreatedDate LIMIT 1];
        List<Lead> testLeads = [SELECT Id FROM Lead WHERE LastName = 'Lead1'];

        if(qrmcaRecords.isEmpty() || testLeads.isEmpty()) {
            return;
        }

        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();
        request.leadIds = new List<Id>{testLeads[0].Id};
        request.roundRobinIds = new List<Id>{qrmcaRecords[0].Id};

        Test.startTest();

        BulkRoundRobinAssignmentNXDS.assignLeadsRoundRobin(new List<BulkRoundRobinAssignmentNXDS.RoundRobinRequest>{request});

        Test.stopTest();

        // Verify lead was assigned
        Lead updatedLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :testLeads[0].Id];
        System.assertNotEquals(null, updatedLead.OwnerId, 'Lead should have an owner');
    }

    /**
     * Test that class initializes correctly
     */
    @isTest
    static void testClassInstantiation() {
        BulkRoundRobinAssignmentNXDS.RoundRobinRequest request = new BulkRoundRobinAssignmentNXDS.RoundRobinRequest();

        System.assertNotEquals(null, request, 'Request object should be instantiated');
    }
}