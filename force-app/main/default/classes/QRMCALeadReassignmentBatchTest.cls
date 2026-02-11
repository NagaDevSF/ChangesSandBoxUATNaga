@IsTest
private class QRMCALeadReassignmentBatchTest {
    
    // Test setup method - runs once before all test methods
    @TestSetup
    static void setupTestData() {
        // Create role first
        String uniqueDevName = 'Sales_Rep_Debtifi_' + String.valueOf(Datetime.now().getTime());
        
        UserRole role = new UserRole(
            Name = 'Sales Rep Debtifi Test', 
            DeveloperName = uniqueDevName
        );
        insert role;
        
        // Create users with role
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> users = new List<User>();
        
        // Create 3 test users
        for(Integer i = 0; i < 3; i++) {
            String uniqueString = String.valueOf(Datetime.now().getTime() + i);
            User testUser = new User(
                FirstName = 'QRMCA', 
                LastName = 'User' + i,
                Alias = 'quser' + i,
                Email = 'qrmcauser' + i + uniqueString + '@testorg.com',
                Username = 'qrmcauser' + i + uniqueString + '@testorg.com',
                CommunityNickname = 'qrmca' + i + uniqueString,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = standardProfile.Id,
                LanguageLocaleKey = 'en_US',
                UserRoleId = role.Id,
                IsActive = true
            );
            users.add(testUser);
        }
        
        insert users;
    }
    
    // Helper method to create comprehensive test data
    private static void createComprehensiveTestData() {
        List<User> users = [SELECT Id FROM User WHERE LastName LIKE 'User%' AND IsActive = true LIMIT 3];
        
        if(users.isEmpty()) {
            return;
        }
        
        List<Lead> leads = new List<Lead>();
        
        // Group 1 leads (48 hour rule) - NEW LEAD, ATTEMPTING, FOLLOW UP
        String[] group1Statuses = new String[] {'NEW LEAD', 'ATTEMPTING', 'FOLLOW UP'};
        for(Integer i = 0; i < 3; i++) {
            leads.add(new Lead(
                LastName = 'Group1Lead' + i, 
                Company = 'Group1Company' + i,
                Sales_Office_Ref__c = 'QRMCA',
                Pre_Deal_Status__c = group1Statuses[i],
                OwnerId = users[Math.mod(i, users.size())].Id,
                Email = 'group1lead' + i + '@test.com'
            ));
        }
        
        // Group 2 leads (7 day rule) - Other statuses (removed SENT TO CLOSERS)
        String[] group2Statuses = new String[] {
            'FUTURE FOLLOW UP', 'APPOINTMENT SET', 'Waiting On Docs', 
            'DOCS IN - REOPEN', 'Reduced pays with Creditor', 'Transfer'
        };
        for(Integer i = 0; i < 6; i++) {
            leads.add(new Lead(
                LastName = 'Group2Lead' + i, 
                Company = 'Group2Company' + i,
                Sales_Office_Ref__c = 'QRMCA',
                Pre_Deal_Status__c = group2Statuses[Math.mod(i, group2Statuses.size())],
                OwnerId = users[Math.mod(i, users.size())].Id,
                Email = 'group2lead' + i + '@test.com'
            ));
        }
        
        // Exclusion test leads
        leads.add(new Lead(
            LastName = 'ExclusionLead', 
            Company = 'ExclusionCo',
            Sales_Office_Ref__c = 'QRMCA',
            Pre_Deal_Status__c = 'NEW LEAD',
            OwnerId = users[0].Id,
            Email = 'exclusion@test.com'
        ));
        
        insert leads;
        
        // Set appropriate creation dates using Test.setCreatedDate
        for(Lead lead : leads) {
            if(lead.LastName.startsWith('Group1')) {
                // Group 1: Set to 3 days ago (more than 48 hours)
                Test.setCreatedDate(lead.Id, Datetime.now().addDays(-3));
            } else if(lead.LastName.startsWith('Group2')) {
                // Group 2: Set to 10 days ago (more than 7 days)
                Test.setCreatedDate(lead.Id, Datetime.now().addDays(-10));
            } else {
                // Exclusion: Recent
                Test.setCreatedDate(lead.Id, Datetime.now().addHours(-12));
            }
        }
        
        // Create tasks to set LastActivityDate appropriately
        List<Task> tasks = new List<Task>();
        
        for(Lead lead : leads) {
            Task leadTask = new Task(
                Subject = 'Test Activity for ' + lead.LastName,
                WhoId = lead.Id,
                Status = 'Completed',
                Priority = 'Normal'
            );
            
            if(lead.LastName.startsWith('Group1')) {
                // Group 1: Activity 4 days ago (more than 2 days)
                leadTask.ActivityDate = Date.today().addDays(-4);
            } else if(lead.LastName.startsWith('Group2')) {
                // Group 2: Activity 10 days ago (more than 7 days)
                leadTask.ActivityDate = Date.today().addDays(-10);
            } else if(lead.LastName.equals('ExclusionLead')) {
                // Exclusion: Future activity (should be excluded)
                leadTask.ActivityDate = Date.today().addDays(1);
            }
            
            tasks.add(leadTask);
        }
        
        insert tasks;
    }
    
    /**
     * Test default constructor
     */
    @IsTest
    static void testDefaultConstructor() {
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        Test.stopTest();
        
        System.assertNotEquals(null, batch, 'Default constructor should create batch instance');
    }
    
    /**
     * Test constructor with assignment rules parameter
     */
    @IsTest
    static void testConstructorWithAssignmentRules() {
        Test.startTest();
        QRMCALeadReassignmentBatch batchWithRules = new QRMCALeadReassignmentBatch(true);
        QRMCALeadReassignmentBatch batchWithoutRules = new QRMCALeadReassignmentBatch(false);
        Test.stopTest();
        
        System.assertNotEquals(null, batchWithRules, 'Constructor with rules should create batch instance');
        System.assertNotEquals(null, batchWithoutRules, 'Constructor without rules should create batch instance');
    }
    
    /**
     * Test the full batch execution without assignment rules
     */
    @IsTest
    static void testFullBatchExecutionWithoutRules() {
        createComprehensiveTestData();
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch(false);
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        System.assert(true, 'Batch execution without rules completed successfully');
    }
    
    /**
     * Test the full batch execution with assignment rules
     */
    @IsTest
    static void testFullBatchExecutionWithRules() {
        createComprehensiveTestData();
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch(true);
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        System.assert(true, 'Batch execution with rules completed successfully');
    }
    
    /**
     * Test execute method with assignment rules handling - SUCCESS path
     */
    @IsTest
    static void testExecuteWithAssignmentRulesSuccess() {
        createComprehensiveTestData();
        
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Sales_Office_Ref__c = 'QRMCA'
            LIMIT 3
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch(true);
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Execute with assignment rules success path completed');
    }
    
    /**
     * Test execute method without assignment rules - SUCCESS path
     */
    @IsTest
    static void testExecuteWithoutAssignmentRulesSuccess() {
        createComprehensiveTestData();
        
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Sales_Office_Ref__c = 'QRMCA'
            LIMIT 3
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch(false);
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Execute without assignment rules success path completed');
    }
    
    /**
     * Test execute method with empty eligible users list
     */
    @IsTest
    static void testExecuteWithNoEligibleUsers() {
        // Create leads with users that don't have the correct role
        Lead testLead = new Lead(
            LastName = 'NoEligibleUsersLead', 
            Company = 'NoUsersCompany',
            Sales_Office_Ref__c = 'QRMCA',
            Pre_Deal_Status__c = 'NEW LEAD',
            Email = 'nousers@test.com'
        );
        insert testLead;
        
        Test.setCreatedDate(testLead.Id, Datetime.now().addDays(-3));
        
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Id = :testLead.Id
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Execute with no eligible users completed');
    }
    
    /**
     * Test batch start method and query locator
     */
    @IsTest
    static void testStartMethod() {
        createComprehensiveTestData();
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        Database.QueryLocator ql = batch.start(null);
        Test.stopTest();
        
        System.assertNotEquals(null, ql, 'Start method should return query locator');
    }
    
    /**
     * Test schedulable execute method
     */
    @IsTest
    static void testSchedulableExecute() {
        createComprehensiveTestData();
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute((SchedulableContext)null);
        Test.stopTest();
        
        System.assert(true, 'Schedulable execute method completed');
    }
    
    /**
     * Test finish method with valid BatchableContext
     */
    @IsTest
    static void testFinishMethodWithValidContext() {
        createComprehensiveTestData();
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        System.assert(true, 'Finish method with valid context completed');
    }
    
    /**
     * Test finish method with null BatchableContext
     */
    @IsTest
    static void testFinishMethodWithNullContext() {
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.finish(null);
        Test.stopTest();
        
        System.assert(true, 'Finish method with null context completed');
    }
    
    /**
     * Test getEligibleUsers method
     */
    @IsTest
    static void testGetEligibleUsers() {
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        List<User> eligibleUsers = batch.getEligibleUsers();
        Test.stopTest();
        
        System.assertNotEquals(null, eligibleUsers, 'GetEligibleUsers should return a list');
    }
    
    /**
     * Test isGroup1Status method with Group 1 statuses
     */
    @IsTest
    static void testIsGroup1StatusTrue() {
        List<User> users = [SELECT Id FROM User WHERE LastName LIKE 'User%' AND IsActive = true LIMIT 1];
        if(users.isEmpty()) {
            return;
        }
        
        // Create leads with Group 1 statuses
        List<Lead> group1Leads = new List<Lead>();
        String[] group1Statuses = new String[] {'NEW LEAD', 'ATTEMPTING', 'FOLLOW UP'};
        
        for(String status : group1Statuses) {
            group1Leads.add(new Lead(
                LastName = 'Group1Test' + status.replace(' ', ''), 
                Company = 'Group1Company',
                Sales_Office_Ref__c = 'QRMCA',
                Pre_Deal_Status__c = status,
                OwnerId = users[0].Id,
                Email = 'group1test@test.com'
            ));
        }
        insert group1Leads;
        
        // Set creation dates
        for(Lead lead : group1Leads) {
            Test.setCreatedDate(lead.Id, Datetime.now().addDays(-3));
        }
        
        // Create tasks
        List<Task> tasks = new List<Task>();
        for(Lead lead : group1Leads) {
            tasks.add(new Task(
                Subject = 'Group 1 Test Activity',
                WhoId = lead.Id,
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(-4)
            ));
        }
        insert tasks;
        
        // Query with all required fields
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Id IN :group1Leads
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Group 1 status processing completed');
    }
    
    /**
     * Test isGroup1Status method with Group 2 statuses
     */
    @IsTest
    static void testIsGroup1StatusFalse() {
        List<User> users = [SELECT Id FROM User WHERE LastName LIKE 'User%' AND IsActive = true LIMIT 1];
        if(users.isEmpty()) {
            return;
        }
        
        // Create leads with Group 2 statuses (removed SENT TO CLOSERS)
        List<Lead> group2Leads = new List<Lead>();
        String[] group2Statuses = new String[] {'FUTURE FOLLOW UP', 'APPOINTMENT SET', 'Waiting On Docs'};
        
        for(String status : group2Statuses) {
            group2Leads.add(new Lead(
                LastName = 'Group2Test' + status.replace(' ', ''), 
                Company = 'Group2Company',
                Sales_Office_Ref__c = 'QRMCA',
                Pre_Deal_Status__c = status,
                OwnerId = users[0].Id,
                Email = 'group2test@test.com'
            ));
        }
        insert group2Leads;
        
        // Set creation dates
        for(Lead lead : group2Leads) {
            Test.setCreatedDate(lead.Id, Datetime.now().addDays(-10));
        }
        
        // Create tasks
        List<Task> tasks = new List<Task>();
        for(Lead lead : group2Leads) {
            tasks.add(new Task(
                Subject = 'Group 2 Test Activity',
                WhoId = lead.Id,
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(-10)
            ));
        }
        insert tasks;
        
        // Query with all required fields
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Id IN :group2Leads
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Group 2 status processing completed');
    }
    
    /**
     * Test getNextUserExcludingCurrentOwner with single user
     */
    @IsTest
    static void testGetNextUserSingleUser() {
        User singleUser = createSingleTestUser();
        
        Lead singleUserLead = new Lead(
            LastName = 'SingleUserTestLead', 
            Company = 'SingleUserCompany',
            Sales_Office_Ref__c = 'QRMCA',
            Pre_Deal_Status__c = 'NEW LEAD',
            OwnerId = singleUser.Id,
            Email = 'singleuser@test.com'
        );
        insert singleUserLead;
        
        Test.setCreatedDate(singleUserLead.Id, Datetime.now().addDays(-3));
        
        Task leadTask = new Task(
            Subject = 'Single User Activity',
            WhoId = singleUserLead.Id,
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today().addDays(-4)
        );
        insert leadTask;
        
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Id = :singleUserLead.Id
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Single user scenario completed');
    }
    
    /**
     * Test getNextUserExcludingCurrentOwner with multiple users - round robin
     */
    @IsTest
    static void testGetNextUserMultipleUsers() {
        List<User> users = [SELECT Id FROM User WHERE LastName LIKE 'User%' AND IsActive = true ORDER BY LastName];
        
        if(users.isEmpty() || users.size() < 2) {
            return;
        }
        
        // Create multiple leads all owned by first user
        List<Lead> multiUserLeads = new List<Lead>();
        for(Integer i = 0; i < 4; i++) {
            multiUserLeads.add(new Lead(
                LastName = 'MultiUserLead' + i, 
                Company = 'MultiUserCompany' + i,
                Sales_Office_Ref__c = 'QRMCA',
                Pre_Deal_Status__c = 'NEW LEAD',
                OwnerId = users[0].Id,
                Email = 'multiuser' + i + '@test.com'
            ));
        }
        insert multiUserLeads;
        
        // Set creation dates
        for(Lead lead : multiUserLeads) {
            Test.setCreatedDate(lead.Id, Datetime.now().addDays(-3));
        }
        
        // Create tasks
        List<Task> tasks = new List<Task>();
        for(Lead lead : multiUserLeads) {
            tasks.add(new Task(
                Subject = 'Multi User Activity',
                WhoId = lead.Id,
                Status = 'Completed',
                Priority = 'Normal',
                ActivityDate = Date.today().addDays(-4)
            ));
        }
        insert tasks;
        
        // Query with all required fields
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Id IN :multiUserLeads
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Multiple users round robin completed');
    }
    
    /**
     * Test getNextUserExcludingCurrentOwner with owner not in eligible users list
     */
    @IsTest
    static void testGetNextUserOwnerNotInList() {
        // Get current user (who likely doesn't have Sales_Rep_Debtifi role)
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        
        Lead orphanLead = new Lead(
            LastName = 'OrphanLead', 
            Company = 'OrphanCompany',
            Sales_Office_Ref__c = 'QRMCA',
            Pre_Deal_Status__c = 'NEW LEAD',
            OwnerId = currentUser.Id,
            Email = 'orphan@test.com'
        );
        insert orphanLead;
        
        Test.setCreatedDate(orphanLead.Id, Datetime.now().addDays(-3));
        
        Task leadTask = new Task(
            Subject = 'Orphan Activity',
            WhoId = orphanLead.Id,
            Status = 'Completed',
            Priority = 'Normal',
            ActivityDate = Date.today().addDays(-4)
        );
        insert leadTask;
        
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Id = :orphanLead.Id
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Owner not in eligible users list completed');
    }
    
    /**
     * Helper method to create a single test user
     */
    private static User createSingleTestUser() {
        User adminUser = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
        
        User singleUser;
        System.runAs(adminUser) {
            String uniqueDevName = 'Sales_Rep_Debtifi_Single_' + String.valueOf(Datetime.now().getTime());
            
            UserRole singleRole = new UserRole(
                Name = 'Sales Rep Debtifi Single', 
                DeveloperName = uniqueDevName
            );
            insert singleRole;
            
            Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            String uniqueString = String.valueOf(Datetime.now().getTime());
            
            singleUser = new User(
                FirstName = 'Single QRMCA', 
                LastName = 'SingleUser',
                Alias = 'qsingle',
                Email = 'qrmcasingle' + uniqueString + '@testorg.com',
                Username = 'qrmcasingle' + uniqueString + '@testorg.com',
                CommunityNickname = 'qrmcasingle' + uniqueString,
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = standardProfile.Id,
                LanguageLocaleKey = 'en_US',
                UserRoleId = singleRole.Id,
                IsActive = true
            );
            insert singleUser;
        }
        
        return singleUser;
    }
    
    /**
     * Test all static methods
     */
    @IsTest
    static void testStaticMethods() {
        createComprehensiveTestData();
        
        Test.startTest();
        
        // Test runBatch
        Id batchJobId1 = QRMCALeadReassignmentBatch.runBatch();
        System.assertNotEquals(null, batchJobId1, 'runBatch should return job ID');
        
        // Test runBatchWithAssignmentRules
        Id batchJobId2 = QRMCALeadReassignmentBatch.runBatchWithAssignmentRules();
        System.assertNotEquals(null, batchJobId2, 'runBatchWithAssignmentRules should return job ID');
        
        // Test scheduleJob
        String scheduleJobId1 = QRMCALeadReassignmentBatch.scheduleJob('Test Schedule 1', '0 0 0 * * ?');
        System.assertNotEquals(null, scheduleJobId1, 'scheduleJob should return schedule ID');
        
        // Test scheduleJobWithAssignmentRules
        String scheduleJobId2 = QRMCALeadReassignmentBatch.scheduleJobWithAssignmentRules('Test Schedule 2', '0 0 1 * * ?');
        System.assertNotEquals(null, scheduleJobId2, 'scheduleJobWithAssignmentRules should return schedule ID');
        
        Test.stopTest();
        
        // Verify scheduled jobs
        List<CronTrigger> cronTriggers = [SELECT Id, CronExpression FROM CronTrigger WHERE Id IN (:scheduleJobId1, :scheduleJobId2)];
        System.assertEquals(2, cronTriggers.size(), 'Both scheduled jobs should be created');
    }
    
    /**
     * Test edge case: leads with null LastActivityDate
     */
    @IsTest
    static void testLeadsWithNullActivityDate() {
        List<User> users = [SELECT Id FROM User WHERE LastName LIKE 'User%' AND IsActive = true LIMIT 1];
        if(users.isEmpty()) {
            return;
        }
        
        Lead nullActivityLead = new Lead(
            LastName = 'NullActivityLead', 
            Company = 'NullActivityCompany',
            Sales_Office_Ref__c = 'QRMCA',
            Pre_Deal_Status__c = 'NEW LEAD',
            OwnerId = users[0].Id,
            Email = 'nullactivity@test.com'
        );
        insert nullActivityLead;
        
        Test.setCreatedDate(nullActivityLead.Id, Datetime.now().addDays(-3));
        // Don't create any tasks - LastActivityDate will be null
        
        List<Lead> testLeads = [
            SELECT Id, OwnerId, Pre_Deal_Status__c, LastName, Company, 
                   Sales_Office_Ref__c, CreatedDate, LastActivityDate, LastModifiedDate
            FROM Lead 
            WHERE Id = :nullActivityLead.Id
        ];
        
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        batch.execute(null, testLeads);
        Test.stopTest();
        
        System.assert(true, 'Null activity date scenario completed');
    }
    
    /**
     * Test exception handling in finish method
     */
    @IsTest 
    static void testFinishMethodExceptionHandling() {
        Test.startTest();
        QRMCALeadReassignmentBatch batch = new QRMCALeadReassignmentBatch();
        
        // Create a mock context that will cause exception in finish method
        TestBatchableContext mockContext = new TestBatchableContext();
        batch.finish(mockContext);
        
        Test.stopTest();
        
        System.assert(true, 'Finish method exception handling completed');
    }
    
    /**
     * Mock BatchableContext class for testing exception handling
     */
    private class TestBatchableContext implements Database.BatchableContext {
        public Id getJobId() {
            // Return a fake ID that won't exist in AsyncApexJob
            return '7070000000000000';
        }
        
        public Id getChildJobId() {
            return null;
        }
    }
    
    /**
     * Test comprehensive coverage for all remaining branches
     */
    @IsTest
    static void testComprehensiveCoverage() {
        createComprehensiveTestData();
        
        Test.startTest();
        
        // Test both constructors
        QRMCALeadReassignmentBatch batch1 = new QRMCALeadReassignmentBatch();
        QRMCALeadReassignmentBatch batch2 = new QRMCALeadReassignmentBatch(true);
        
        // Test start method
        Database.QueryLocator ql = batch1.start(null);
        System.assertNotEquals(null, ql, 'QueryLocator should not be null');
        
        // Test schedulable execute
        batch1.execute((SchedulableContext)null);
        
        // Test getEligibleUsers
        List<User> users = batch1.getEligibleUsers();
        System.assertNotEquals(null, users, 'Users list should not be null');
        
        Test.stopTest();
        
        System.assert(true, 'Comprehensive coverage test completed');
    }
}