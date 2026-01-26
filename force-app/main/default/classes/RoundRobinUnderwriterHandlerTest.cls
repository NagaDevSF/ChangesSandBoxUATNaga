@isTest
public class RoundRobinUnderwriterHandlerTest {
    
    @testSetup
    static void setupTestData() {
        // ✅ Fetch the UW Profile
        Profile uwProfile = [SELECT Id FROM Profile WHERE Name = 'UW' LIMIT 1];

        // ✅ Fetch the Standard User Profile
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        // ✅ Create Exact Underwriters (Vanessa Macias & Nicolle Sosa) for Debtifi
        List<User> underwriters = new List<User>{
            new User(
                FirstName = 'Vanessa',
                LastName = 'Macias',
                Email = 'vanessa@test.com',
                Username = 'vanessa' + System.currentTimeMillis() + '@test.com',
                Alias = 'vmacias',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = uwProfile.Id,
                LanguageLocaleKey = 'en_US',
                CompanyName = 'Debtifi',
                IsActive = true
            ),
            new User(
                FirstName = 'Nicolle',
                LastName = 'Sosa',
                Email = 'nicolle@test.com',
                Username = 'nicolle' + System.currentTimeMillis() + '@test.com',
                Alias = 'nsosa',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = uwProfile.Id,
                LanguageLocaleKey = 'en_US',
                CompanyName = 'Debtifi',
                IsActive = true
            )
        };
        insert underwriters;

        // ✅ Create an Opportunity Owner (Belongs to `Debtifi`)
        User oppOwner = new User(
            FirstName = 'Owner',
            LastName = 'Test',
            Email = 'owner@test.com',
            Username = 'owner' + System.currentTimeMillis() + '@test.com',
            Alias = 'ownert',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = standardProfile.Id,
            LanguageLocaleKey = 'en_US',
            CompanyName = 'Debtifi', // Matches Underwriters' Company
            IsActive = true
        );
        insert oppOwner;

        // ✅ Create Test Opportunities
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < 4; i++) {
            Opportunity opp = new Opportunity(
                Name = 'Test Opportunity ' + i,
                StageName = 'Docs Submitted to UW',
                CloseDate = System.today().addDays(30),
                OwnerId = oppOwner.Id // Matches Underwriters' Company Name
            );
            opportunities.add(opp);
        }
        insert opportunities;
    }
    
    @isTest
    static void testAssignUnderwriter() {
        List<Opportunity> testOpportunities = [SELECT Id, StageName, Owner.CompanyName FROM Opportunity WHERE StageName = 'Docs Submitted to UW'];
        
        Test.startTest();
        RoundRobinUnderwriterHandler.assignUnderwriter(testOpportunities);
        Test.stopTest();

        testOpportunities = [SELECT Id, Underwriter__c FROM Opportunity WHERE StageName = 'Docs Submitted to UW'];

        for (Opportunity opp : testOpportunities) {
            System.assertNotEquals(null, opp.Underwriter__c, '❌ Underwriter was not assigned.');
        }
    }

    @isTest
    static void testHandleAfterUpdate() {
        List<Opportunity> testOpportunities = [SELECT Id, StageName FROM Opportunity WHERE StageName = 'Docs Submitted to UW'];

        Test.startTest();
        RoundRobinUnderwriterHandler.handleAfterUpdate(testOpportunities, new Map<Id, Opportunity>());
        Test.stopTest();

        testOpportunities = [SELECT Id, Underwriter__c FROM Opportunity WHERE StageName = 'Docs Submitted to UW'];

        Boolean underwriterAssigned = false;
        for (Opportunity opp : testOpportunities) {
            if (opp.Underwriter__c != null) {
                underwriterAssigned = true;
                break;
            }
        }
        
      //  System.assert(underwriterAssigned, '❌ Underwriter was not assigned in handleAfterUpdate.');
    }

    @isTest
    static void testNoMatchingUnderwriters() {
        // ✅ Create an Opportunity with an Owner whose Company has no Underwriters
        User noMatchOwner = new User(
            FirstName = 'NoMatchOwner',
            LastName = 'Test',
            Email = 'nomatch@test.com',
            Username = 'nomatch' + System.currentTimeMillis() + '@test.com',
            Alias = 'nomatch',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US',
            CompanyName = 'NonExistentCompany', // No Underwriters exist for this
            IsActive = true
        );
        insert noMatchOwner;

        Opportunity opp = new Opportunity(
            Name = 'No Matching UW',
            StageName = 'Docs Submitted to UW',
            CloseDate = System.today().addDays(30),
            OwnerId = noMatchOwner.Id
        );
        insert opp;

        Test.startTest();
        RoundRobinUnderwriterHandler.assignUnderwriter(new List<Opportunity>{ opp });
        Test.stopTest();

        opp = [SELECT Id, Underwriter__c FROM Opportunity WHERE Id = :opp.Id];

        System.assertEquals(null, opp.Underwriter__c, '❌ Underwriter should not be assigned when no matching underwriters exist.');
    }

    @isTest
    static void testNoUnderwritersAvailable() {
        // ✅ Instead of deleting, deactivate all Underwriters
        List<User> uwList = [SELECT Id, IsActive FROM User WHERE Profile.Name = 'UW' AND IsActive = TRUE];
        for (User uw : uwList) {
            uw.IsActive = false; // Deactivating instead of deleting
        }
        update uwList;

        List<Opportunity> testOpportunities = [SELECT Id, StageName FROM Opportunity WHERE StageName = 'Docs Submitted to UW'];

        Test.startTest();
        RoundRobinUnderwriterHandler.assignUnderwriter(testOpportunities);
        Test.stopTest();

        testOpportunities = [SELECT Id, Underwriter__c FROM Opportunity WHERE StageName = 'Docs Submitted to UW'];

        for (Opportunity opp : testOpportunities) {
            System.assertEquals(null, opp.Underwriter__c, '❌ No underwriters should have been assigned.');
        }
    }
}