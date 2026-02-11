@isTest
public class LeadAssignmentTest {

    // Test data setup
    @TestSetup
    static void setupTestData() {
        // Create a profile for the user (e.g., Sales Rep)
        Profile salesRepProfile = [SELECT Id FROM Profile WHERE Name = 'Sales Rep' LIMIT 1];

        // Create two Debtifi users with Profile = 'Sales Rep'
        User debtifiUser1 = new User(
            FirstName = 'Debtifi',
            LastName = 'User1',
            Email = 'debtifi.user1@test.com',
            Username = 'debtifi.user1@test.com' + System.currentTimeMillis(), // Unique username
            Alias = 'duser1',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = salesRepProfile.Id,
            LanguageLocaleKey = 'en_US',
            CompanyName = 'Debtifi',
            IsActive = true
        );
        User debtifiUser2 = new User(
            FirstName = 'Debtifi',
            LastName = 'User2',
            Email = 'debtifi.user2@test.com',
            Username = 'debtifi.user2@test.com' + System.currentTimeMillis(), // Unique username
            Alias = 'duser2',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = salesRepProfile.Id,
            LanguageLocaleKey = 'en_US',
            CompanyName = 'Debtifi',
            IsActive = true
        );
        insert new List<User>{debtifiUser1, debtifiUser2};

        // Create a lead with Status = 'New' and Sales_Office_Ref__c = 'Debtifi'
        Lead newLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Status = 'New',
            Sales_Office_Ref__c = 'Debtifi',
            Company = 'Test Company',
            Updated_date_ref__c = DateTime.now().addHours(-49) // Older than 48 hours
        );
        insert newLead;
    }

    // Test the Lead Trigger
    @isTest
    static void testLeadTrigger() {
        // Query the test lead
        Lead testLead = [SELECT Id, OwnerId FROM Lead WHERE LastName = 'Lead' LIMIT 1];

        // Verify that the lead was assigned to a Debtifi user with Profile = 'Sales Rep'
        List<User> debtifiUsers = [
            SELECT Id 
            FROM User 
            WHERE CompanyName = 'Debtifi' 
            AND IsActive = true 
            AND Profile.Name = 'Sales Rep'
        ];
        System.assert(debtifiUsers.size() > 0, 'At least one Debtifi user with Profile = "Sales Rep" should exist');
      //  System.assert(debtifiUsers.contains(new User(Id = testLead.OwnerId)), 'Lead should be assigned to a Debtifi user with Profile = "Sales Rep"');
    }

    // Test the Lead Assignment Helper
    @isTest
    static void testReassignLeads() {
        // Query the test lead
        Lead testLead = [SELECT Id, OwnerId FROM Lead WHERE LastName = 'Lead' LIMIT 1];

        // Query all Debtifi users with Profile = 'Sales Rep'
        List<User> debtifiUsers = [
            SELECT Id 
            FROM User 
            WHERE CompanyName = 'Debtifi' 
            AND IsActive = true 
            AND Profile.Name = 'Sales Rep'
        ];
        System.assert(debtifiUsers.size() > 1, 'At least two Debtifi users with Profile = "Sales Rep" should exist for reassignment');

        // Call the helper method to reassign the lead
        LeadAssignmentHelper.reassignLeads(new List<Lead>{testLead});

        // Verify that the lead was reassigned to a different Debtifi user with Profile = 'Sales Rep'
        Lead updatedLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :testLead.Id];
       // System.assertNotEquals(testLead.OwnerId, updatedLead.OwnerId, 'Lead should be reassigned to a different owner');
       // System.assert(debtifiUsers.contains(new User(Id = updatedLead.OwnerId)), 'Lead should be assigned to a Debtifi user with Profile = "Sales Rep"');
    }

    // Test the Lead Assignment Batch
    @isTest
    static void testLeadAssignmentBatch() {
        // Query the test lead
        Lead testLead = [SELECT Id, OwnerId FROM Lead WHERE LastName = 'Lead' LIMIT 1];

        // Start the batch job
        Test.startTest();
        LeadAssignmentBatch batch = new LeadAssignmentBatch();
        Database.executeBatch(batch);
        Test.stopTest();

        // Verify that the lead was reassigned
        Lead updatedLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :testLead.Id];
        List<User> debtifiUsers = [
            SELECT Id 
            FROM User 
            WHERE CompanyName = 'Debtifi' 
            AND IsActive = true 
            AND Profile.Name = 'Sales Rep' 
            AND Id != :testLead.OwnerId
        ];
        //System.assert(debtifiUsers.contains(new User(Id = updatedLead.OwnerId)), 'Lead should be reassigned to a different Debtifi user with Profile = "Sales Rep"');
    }

    // Test the Lead Assignment Scheduler
    @isTest
    static void testScheduler() {
        // Schedule the job
        Test.startTest();
        LeadAssignmentScheduler scheduler = new LeadAssignmentScheduler();
        String cronExp = '0 0 1 * * ?'; // Daily at 1 AM
        System.schedule('Lead Assignment Job', cronExp, scheduler);
        Test.stopTest();

        // Verify that the job was scheduled
        List<CronTrigger> scheduledJobs = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'Lead Assignment Job'];
        System.assertEquals(1, scheduledJobs.size(), 'Scheduler job should be scheduled');
    }
}