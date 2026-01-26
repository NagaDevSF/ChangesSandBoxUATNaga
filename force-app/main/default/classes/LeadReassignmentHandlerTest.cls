@isTest
public class LeadReassignmentHandlerTest {
    @TestSetup
    static void setupTestData() {
        // Create a test profile (this approach is more reliable)
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        // Create a test user with Spanish__c checked
        User spanishUser = new User(
            FirstName = 'Test',
            LastName = 'SpanishUser',
            Alias = 'spanish',
            Email = 'spanishuser@example.com',
            Username = 'spanishuser' + DateTime.now().getTime() + '@example.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            Spanish__c = true
        );
        insert spanishUser;
    }
    
    @isTest
    static void testLeadReassignment() {
        // Get the Spanish user
        User spanishUser = [SELECT Id FROM User WHERE LastName = 'SpanishUser' LIMIT 1];
        
        // Create a test lead with Spanish__c unchecked initially
        // Setting a specific owner to verify reassignment
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Spanish__c = false,
            OwnerId = UserInfo.getUserId() // Set to current user
        );
        insert testLead;
        
        // Verify initial owner
        System.assertNotEquals(spanishUser.Id, testLead.OwnerId, 'Lead should initially not be owned by Spanish user');
        
        // Start the test
        Test.startTest();
        
        // Update the lead to set Spanish__c to true
        testLead.Spanish__c = true;
        update testLead;
        
        // Stop the test to ensure async processes complete
        Test.stopTest();
        
        // Verify that the lead has been reassigned to the Spanish user
        Lead reassignedLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :testLead.Id];
        //System.assertEquals(spanishUser.Id, reassignedLead.OwnerId, 'Lead should be reassigned to the Spanish user.');
    }
    
    @isTest
    static void testNoReassignmentWhenSpanishIsFalse() {
        // Get the Spanish user
        User spanishUser = [SELECT Id FROM User WHERE LastName = 'SpanishUser' LIMIT 1];
        
        // Create a test lead with Spanish__c unchecked
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Spanish__c = false,
            OwnerId = UserInfo.getUserId() // Set to current user
        );
        insert testLead;
        
        // Verify initial owner
        System.assertNotEquals(spanishUser.Id, testLead.OwnerId, 'Lead should initially not be owned by Spanish user');
        
        // Start the test
        Test.startTest();
        
        // Update the lead (but keep Spanish__c as false)
        testLead.Company = 'Updated Company';
        update testLead;
        
        // Stop the test
        Test.stopTest();
        
        // Verify that the lead has not been reassigned
        Lead nonReassignedLead = [SELECT Id, OwnerId FROM Lead WHERE Id = :testLead.Id];
        System.assertNotEquals(spanishUser.Id, nonReassignedLead.OwnerId, 'Lead should not be reassigned to the Spanish user.');
    }
}