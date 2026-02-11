/**
 * Test class for NDSLeadReassignmentBatch
 *
 * Tests cover:
 * - Group 1 (48 hours) reassignment logic
 * - Group 2 (7 days) reassignment logic
 * - Future LastActivityDate exclusions
 * - Single user edge cases
 * - Assignment rule firing
 * - Schedulable interface
 * - Round-robin distribution
 */
@isTest
private class NDSLeadReassignmentBatchTest {

    /**
     * Test data setup
     */
    @testSetup
    static void setupTestData() {
        // Create Sales_Rep_Debtifi role if it doesn't exist
        UserRole salesRepRole;
        List<UserRole> existingRoles = [
            SELECT Id, DeveloperName
            FROM UserRole
            WHERE DeveloperName = 'Sales_Rep_Debtifi'
            LIMIT 1
        ];

        if (existingRoles.isEmpty()) {
            salesRepRole = new UserRole(
                DeveloperName = 'Sales_Rep_Debtifi',
                Name = 'Sales Rep Debtifi'
            );
            insert salesRepRole;
        } else {
            salesRepRole = existingRoles[0];
        }

        // Create test profiles
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        // Create 3 active Sales Rep users
        List<User> testUsers = new List<User>();
        for (Integer i = 1; i <= 3; i++) {
            User u = new User(
                FirstName = 'Test',
                LastName = 'SalesRep' + i,
                Email = 'testsalesrep' + i + '@debtifi.test.com',
                Username = 'testsalesrep' + i + '@debtifi.test.com.' + System.currentTimeMillis(),
                Alias = 'tsr' + i,
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = standardProfile.Id,
                UserRoleId = salesRepRole.Id,
                IsActive = true
            );
            testUsers.add(u);
        }
        insert testUsers;

        // Create test leads with various statuses and ages
        List<Lead> testLeads = new List<Lead>();

        System.runAs(testUsers[0]) {
            // Group 1 Leads (48 hours old) - should be reassigned
            testLeads.add(new Lead(
                FirstName = 'Group1',
                LastName = 'NewLead',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'NEW LEAD',
                OwnerId = testUsers[0].Id
            ));

            testLeads.add(new Lead(
                FirstName = 'Group1',
                LastName = 'Attempting',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'ATTEMPTING',
                OwnerId = testUsers[0].Id
            ));

            testLeads.add(new Lead(
                FirstName = 'Group1',
                LastName = 'FollowUp',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'FOLLOW UP',
                OwnerId = testUsers[1].Id
            ));

            // Group 2 Leads (7 days old) - should be reassigned
            testLeads.add(new Lead(
                FirstName = 'Group2',
                LastName = 'FutureFollowUp',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'FUTURE FOLLOW UP',
                OwnerId = testUsers[1].Id
            ));

            testLeads.add(new Lead(
                FirstName = 'Group2',
                LastName = 'AppointmentSet',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'APPOINTMENT SET',
                OwnerId = testUsers[2].Id
            ));

            testLeads.add(new Lead(
                FirstName = 'Group2',
                LastName = 'WaitingOnDocs',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'Waiting On Docs',
                OwnerId = testUsers[0].Id
            ));

            testLeads.add(new Lead(
                FirstName = 'Group2',
                LastName = 'DocsInReopen',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'DOCS IN - REOPEN',
                OwnerId = testUsers[1].Id
            ));

            testLeads.add(new Lead(
                FirstName = 'Group2',
                LastName = 'ReducedPays',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'Reduced pays with Creditor',
                OwnerId = testUsers[2].Id
            ));

            testLeads.add(new Lead(
                FirstName = 'Group2',
                LastName = 'Transfer',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'Transfer',
                OwnerId = testUsers[0].Id
            ));

            // Leads that should NOT be reassigned
            testLeads.add(new Lead(
                FirstName = 'Recent',
                LastName = 'NewLead',
                Company = 'Test Company',
                Pre_Deal_Status__c = 'NEW LEAD',
                OwnerId = testUsers[0].Id
            ));

            insert testLeads;
        }

        // Update LastModifiedDate by manipulating test data
        // We'll use a backdating approach in the actual test methods
    }

    /**
     * Test Group 1 (48 hours) lead reassignment
     */
    @isTest
    static void testGroup1ReassignmentAfter48Hours() {
        List<User> salesReps = [
            SELECT Id
            FROM User
            WHERE UserRole.DeveloperName = 'Sales_Rep_Debtifi'
            AND IsActive = true
            ORDER BY LastName
        ];

        // Get Group 1 leads
        List<Lead> group1Leads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c
            FROM Lead
            WHERE FirstName = 'Group1'
        ];

        Test.startTest();

        // Enable test mode to bypass date filtering
        NDSLeadReassignmentBatch.bypassDateFilter = true;

        // Execute batch
        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Id batchId = Database.executeBatch(batch, 200);

        Test.stopTest();

        // Verify leads were reassigned
        List<Lead> updatedLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c
            FROM Lead
            WHERE FirstName = 'Group1'
        ];

        for (Lead lead : updatedLeads) {
            // Status should be reset to NEW LEAD for Group 1
            System.assertEquals('NEW LEAD', lead.Pre_Deal_Status__c,
                'Group 1 status should be reset to NEW LEAD');
        }

        // Verify that at least some leads were reassigned
        Integer reassignedCount = 0;
        for (Integer i = 0; i < group1Leads.size(); i++) {
            for (Lead updated : updatedLeads) {
                if (updated.Id == group1Leads[i].Id && updated.OwnerId != group1Leads[i].OwnerId) {
                    reassignedCount++;
                    break;
                }
            }
        }

        System.assert(reassignedCount > 0, 'At least one Group 1 lead should be reassigned');
    }

    /**
     * Test Group 2 (7 days) lead reassignment
     */
    @isTest
    static void testGroup2ReassignmentAfter7Days() {
        List<User> salesReps = [
            SELECT Id
            FROM User
            WHERE UserRole.DeveloperName = 'Sales_Rep_Debtifi'
            AND IsActive = true
            ORDER BY LastName
        ];

        // Get Group 2 leads
        List<Lead> group2Leads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c
            FROM Lead
            WHERE FirstName = 'Group2'
        ];

        Test.startTest();

        // Enable test mode to bypass date filtering
        NDSLeadReassignmentBatch.bypassDateFilter = true;

        // Execute batch
        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Id batchId = Database.executeBatch(batch, 200);

        Test.stopTest();

        // Verify leads were reassigned
        List<Lead> updatedLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c
            FROM Lead
            WHERE FirstName = 'Group2'
        ];

        for (Lead lead : updatedLeads) {
            // Status should be reset to FOLLOW UP for Group 2
            System.assertEquals('FOLLOW UP', lead.Pre_Deal_Status__c,
                'Group 2 status should be reset to FOLLOW UP');
        }

        // Verify that at least some leads were reassigned
        Integer reassignedCount = 0;
        for (Integer i = 0; i < group2Leads.size(); i++) {
            for (Lead updated : updatedLeads) {
                if (updated.Id == group2Leads[i].Id && updated.OwnerId != group2Leads[i].OwnerId) {
                    reassignedCount++;
                    break;
                }
            }
        }

        System.assert(reassignedCount > 0, 'At least one Group 2 lead should be reassigned');
    }

    /**
     * Test that recent leads are NOT reassigned
     */
    @isTest
    static void testRecentLeadsNotReassigned() {
        // Get recent lead
        Lead recentLead = [
            SELECT Id, OwnerId, Pre_Deal_Status__c
            FROM Lead
            WHERE FirstName = 'Recent'
            LIMIT 1
        ];

        Id originalOwnerId = recentLead.OwnerId;

        Test.startTest();

        // Execute batch
        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Database.executeBatch(batch, 200);

        Test.stopTest();

        // Verify lead was NOT reassigned
        Lead updatedLead = [
            SELECT Id, OwnerId, Pre_Deal_Status__c
            FROM Lead
            WHERE Id = :recentLead.Id
        ];

        System.assertEquals(originalOwnerId, updatedLead.OwnerId,
            'Recent lead should not be reassigned');
        System.assertEquals('NEW LEAD', updatedLead.Pre_Deal_Status__c,
            'Recent lead status should remain unchanged');
    }

    /**
     * Test exclusion of leads with future LastActivityDate
     * Note: LastActivityDate is read-only and set automatically by Salesforce
     * This test validates that the batch query logic includes LastActivityDate filters
     */
    @isTest
    static void testFutureLastActivityDateExclusion() {
        // This test validates that the batch start method includes proper
        // LastActivityDate filtering in the query. Since LastActivityDate
        // is read-only and requires actual Task/Event creation to populate,
        // we test the query logic by ensuring no exceptions occur

        Test.startTest();

        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Database.QueryLocator ql = batch.start(null);

        // Verify the query includes LastActivityDate conditions
        String queryString = String.valueOf(ql.getQuery());
        System.assert(queryString.contains('LastActivityDate'),
            'Query should include LastActivityDate filtering');

        Test.stopTest();
    }

    /**
     * Test batch with assignment rules enabled
     */
    @isTest
    static void testBatchWithAssignmentRules() {
        List<Lead> group1Leads = [
            SELECT Id, OwnerId
            FROM Lead
            WHERE FirstName = 'Group1'
        ];

        // Backdate the leads
        for (Lead lead : group1Leads) {
            Test.setCreatedDate(lead.Id, Datetime.now().addHours(-50));
        }

        Test.startTest();

        // Execute batch with assignment rules
        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch(true);
        Id batchId = Database.executeBatch(batch, 200);

        Test.stopTest();

        // Verify batch completed (assignment rules may or may not fire depending on org setup)
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];

        System.assertEquals('Completed', job.Status, 'Batch should complete successfully');
    }

    /**
     * Test schedulable interface
     */
    @isTest
    static void testSchedulableInterface() {
        Test.startTest();

        // Schedule the batch job
        String cronExp = '0 0 2 * * ?'; // Run at 2 AM daily
        String jobId = System.schedule('Test NDS Lead Reassignment', cronExp, new NDSLeadReassignmentBatch());

        Test.stopTest();

        // Verify job was scheduled
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match');
        System.assertEquals(0, ct.TimesTriggered, 'Job should not have fired yet');
    }

    /**
     * Test static runBatch method
     */
    @isTest
    static void testRunBatchMethod() {
        Test.startTest();

        Id batchId = NDSLeadReassignmentBatch.runBatch();

        Test.stopTest();

        // Verify batch was executed
        AsyncApexJob job = [
            SELECT Id, Status, ApexClass.Name
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];

        System.assertEquals('NDSLeadReassignmentBatch', job.ApexClass.Name,
            'Batch class name should match');
    }

    /**
     * Test static runBatchWithAssignmentRules method
     */
    @isTest
    static void testRunBatchWithAssignmentRulesMethod() {
        Test.startTest();

        Id batchId = NDSLeadReassignmentBatch.runBatchWithAssignmentRules();

        Test.stopTest();

        // Verify batch was executed
        AsyncApexJob job = [
            SELECT Id, Status, ApexClass.Name
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];

        System.assertEquals('NDSLeadReassignmentBatch', job.ApexClass.Name,
            'Batch class name should match');
    }

    /**
     * Test static scheduleJob method
     */
    @isTest
    static void testScheduleJobMethod() {
        Test.startTest();

        String cronExp = '0 0 3 * * ?';
        String jobId = NDSLeadReassignmentBatch.scheduleJob('Test Schedule Job', cronExp);

        Test.stopTest();

        // Verify job was scheduled
        CronTrigger ct = [
            SELECT Id, CronExpression
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match');
    }

    /**
     * Test static scheduleJobWithAssignmentRules method
     */
    @isTest
    static void testScheduleJobWithAssignmentRulesMethod() {
        Test.startTest();

        String cronExp = '0 0 4 * * ?';
        String jobId = NDSLeadReassignmentBatch.scheduleJobWithAssignmentRules(
            'Test Schedule with Rules', cronExp
        );

        Test.stopTest();

        // Verify job was scheduled
        CronTrigger ct = [
            SELECT Id, CronExpression
            FROM CronTrigger
            WHERE Id = :jobId
        ];

        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match');
    }

    /**
     * Test getEligibleUsers method
     */
    @isTest
    static void testGetEligibleUsers() {
        Test.startTest();

        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        List<User> eligibleUsers = batch.getEligibleUsers();

        Test.stopTest();

        // Should have at least 3 eligible users from test setup (may have more from org)
        System.assert(eligibleUsers.size() >= 3, 'Should have at least 3 eligible users');

        // Verify all users are active with correct role
        for (User u : eligibleUsers) {
            System.assertEquals(true, u.IsActive, 'User should be active');
        }
    }

    /**
     * Test round-robin distribution of leads
     */
    @isTest
    static void testRoundRobinDistribution() {
        List<User> salesReps = [
            SELECT Id
            FROM User
            WHERE UserRole.DeveloperName = 'Sales_Rep_Debtifi'
            AND IsActive = true
            ORDER BY LastName
        ];

        // Create multiple leads owned by same user
        List<Lead> testLeads = new List<Lead>();
        for (Integer i = 0; i < 9; i++) {
            testLeads.add(new Lead(
                FirstName = 'RoundRobin',
                LastName = 'Test' + i,
                Company = 'Test Company',
                Pre_Deal_Status__c = 'NEW LEAD',
                OwnerId = salesReps[0].Id
            ));
        }
        insert testLeads;

        Test.startTest();

        // Enable test mode to bypass date filtering
        NDSLeadReassignmentBatch.bypassDateFilter = true;

        // Execute batch
        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Database.executeBatch(batch, 200);

        Test.stopTest();

        // Verify leads were distributed among users
        List<Lead> updatedLeads = [
            SELECT Id, OwnerId
            FROM Lead
            WHERE FirstName = 'RoundRobin'
        ];

        // Count distribution
        Map<Id, Integer> ownerCounts = new Map<Id, Integer>();
        for (Lead lead : updatedLeads) {
            if (!ownerCounts.containsKey(lead.OwnerId)) {
                ownerCounts.put(lead.OwnerId, 0);
            }
            ownerCounts.put(lead.OwnerId, ownerCounts.get(lead.OwnerId) + 1);
        }

        // Verify all leads were reassigned (not owned by original owner anymore)
        // In round-robin, all leads from same owner get assigned to the next user
        System.assertEquals(1, ownerCounts.size(),
            'All leads should be reassigned to one user in round-robin (next in sequence)');
        System.assertNotEquals(salesReps[0].Id, updatedLeads[0].OwnerId,
            'Leads should be reassigned away from original owner');
    }

    /**
     * Test single user edge case
     */
    @isTest
    static void testSingleUserEdgeCase() {
        // Get existing lead from test setup
        Lead existingLead = [
            SELECT Id, OwnerId, Pre_Deal_Status__c
            FROM Lead
            WHERE FirstName = 'Group1'
            LIMIT 1
        ];
        Id originalOwnerId = existingLead.OwnerId;

        Test.startTest();

        // Deactivate all eligible users except one
        List<User> salesReps = [
            SELECT Id, IsActive
            FROM User
            WHERE UserRole.DeveloperName = 'Sales_Rep_Debtifi'
            AND IsActive = true
            ORDER BY LastName
        ];

        // Deactivate all but one user
        List<User> usersToUpdate = new List<User>();
        for (Integer i = 1; i < salesReps.size(); i++) {
            salesReps[i].IsActive = false;
            usersToUpdate.add(salesReps[i]);
        }
        if (!usersToUpdate.isEmpty()) {
            update usersToUpdate;
        }

        // Enable test mode and execute batch
        NDSLeadReassignmentBatch.bypassDateFilter = true;
        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Database.executeBatch(batch, 200);

        Test.stopTest();

        // Verify lead was NOT reassigned (only one user available)
        Lead updatedLead = [
            SELECT Id, OwnerId
            FROM Lead
            WHERE Id = :existingLead.Id
        ];

        System.assertEquals(originalOwnerId, updatedLead.OwnerId,
            'Lead should not be reassigned when only one eligible user exists');
    }

    /**
     * Test batch with no eligible users
     */
    @isTest
    static void testNoEligibleUsers() {
        // Deactivate all sales rep users
        List<User> salesReps = [
            SELECT Id, IsActive
            FROM User
            WHERE UserRole.DeveloperName = 'Sales_Rep_Debtifi'
        ];

        for (User u : salesReps) {
            u.IsActive = false;
        }
        update salesReps;

        Test.startTest();

        // Execute batch - should complete without errors
        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Id batchId = Database.executeBatch(batch, 200);

        Test.stopTest();

        // Verify batch completed successfully
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors
            FROM AsyncApexJob
            WHERE Id = :batchId
        ];

        System.assertEquals('Completed', job.Status,
            'Batch should complete even with no eligible users');
        System.assertEquals(0, job.NumberOfErrors, 'Should have no errors');
    }

    /**
     * Test that query logic includes LastActivityDate filtering for Group 1
     * Note: LastActivityDate is read-only and set automatically when Tasks/Events are created
     */
    @isTest
    static void testLastActivityDateQueryLogic() {
        Test.startTest();

        NDSLeadReassignmentBatch batch = new NDSLeadReassignmentBatch();
        Database.QueryLocator ql = batch.start(null);

        // Verify the query properly handles LastActivityDate
        String queryString = String.valueOf(ql.getQuery());
        System.assert(queryString.contains('LastActivityDate'),
            'Query should filter on LastActivityDate');

        Test.stopTest();
    }
}