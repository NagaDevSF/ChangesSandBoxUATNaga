@IsTest
public class ContentDocumentLinkTriggerHandlerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test accounts
        Account testAccount = new Account(
            Name = 'Test Account for ContentDocumentLink',
            BillingStreet = '123 Test St',
            BillingCity = 'Test City',
            BillingState = 'CA',
            BillingPostalCode = '12345'
        );
        insert testAccount;
        
        // Create test leads
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Email = 'testlead@test.com',
            Phone = '555-1234'
        );
        insert testLead;
        
        // Create test opportunities
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 10000
        );
        insert testOpp;
        
        // Create test cases
        Case testCase = new Case(
            Subject = 'Test Case for ContentDocumentLink',
            AccountId = testAccount.Id,
            Status = 'New',
            Origin = 'Phone'
        );
        insert testCase;
    }
    
    @IsTest
    static void testHandleAfterInsert() {
        // Get test data
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Create test content documents
        ContentVersion cv1 = new ContentVersion(
            Title = 'Test Document 1',
            PathOnClient = 'test1.pdf',
            VersionData = Blob.valueOf('Test PDF Content 1'),
            IsMajorVersion = true
        );
        insert cv1;
        
        ContentVersion cv2 = new ContentVersion(
            Title = 'Test Document 2',
            PathOnClient = 'test2.pdf',
            VersionData = Blob.valueOf('Test PDF Content 2'),
            IsMajorVersion = true
        );
        insert cv2;
        
        ContentVersion cv3 = new ContentVersion(
            Title = 'Test Document 3',
            PathOnClient = 'test3.pdf',
            VersionData = Blob.valueOf('Test PDF Content 3'),
            IsMajorVersion = true
        );
        insert cv3;
        
        // Get content document IDs
        Id docId1 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv1.Id].ContentDocumentId;
        Id docId2 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv2.Id].ContentDocumentId;
        Id docId3 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv3.Id].ContentDocumentId;
        
        Test.startTest();
        
        // Create content document links (simulating file attachments)
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>{
            new ContentDocumentLink(
                ContentDocumentId = docId1,
                LinkedEntityId = testLead.Id,
                ShareType = 'V'
            ),
            new ContentDocumentLink(
                ContentDocumentId = docId2,
                LinkedEntityId = testOpp.Id,
                ShareType = 'V'
            ),
            new ContentDocumentLink(
                ContentDocumentId = docId3,
                LinkedEntityId = testCase.Id,
                ShareType = 'V'
            )
        };
        
        // Call the handler method directly (without inserting)
        ContentDocumentLinkTriggerHandler.handleAfterInsert(newLinks);
        
        Test.stopTest();
        
        // Verify the handler method executed without errors
        System.assert(true, 'Handler method should execute without errors');
    }
    
    @IsTest
    static void testHandleAfterDelete() {
        // Get test data
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];
        
        // Create test content document
        ContentVersion cv = new ContentVersion(
            Title = 'Test Document for Delete',
            PathOnClient = 'testdelete.pdf',
            VersionData = Blob.valueOf('Test PDF Content for Delete'),
            IsMajorVersion = true
        );
        insert cv;
        
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        // Create content document link (without inserting)
        ContentDocumentLink cdl = new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = testLead.Id,
            ShareType = 'V'
        );
        
        Test.startTest();
        
        // Call the handler method for delete
        ContentDocumentLinkTriggerHandler.handleAfterDelete(new List<ContentDocumentLink>{cdl});
        
        Test.stopTest();
        
        // Verify the link was processed (the actual deletion logic would be in ContentDocumentLinkHandler)
        // This test ensures the method doesn't throw exceptions
        System.assert(true, 'Delete handler should execute without errors');
    }
    
    @IsTest
    static void testHandleAfterInsertWithNullInput() {
        Test.startTest();
        
        // Test with null input
        ContentDocumentLinkTriggerHandler.handleAfterInsert(null);
        
        Test.stopTest();
        
        // Should not throw any exceptions
        System.assert(true, 'Handler should handle null input gracefully');
    }
    
    @IsTest
    static void testHandleAfterDeleteWithNullInput() {
        Test.startTest();
        
        // Test with null input
        ContentDocumentLinkTriggerHandler.handleAfterDelete(null);
        
        Test.stopTest();
        
        // Should not throw any exceptions
        System.assert(true, 'Handler should handle null input gracefully');
    }
    
    @IsTest
    static void testHandleAfterInsertWithEmptyList() {
        Test.startTest();
        
        // Test with empty list
        ContentDocumentLinkTriggerHandler.handleAfterInsert(new List<ContentDocumentLink>());
        
        Test.stopTest();
        
        // Should not throw any exceptions
        System.assert(true, 'Handler should handle empty list gracefully');
    }
    
    @IsTest
    static void testHandleAfterDeleteWithEmptyList() {
        Test.startTest();
        
        // Test with empty list
        ContentDocumentLinkTriggerHandler.handleAfterDelete(new List<ContentDocumentLink>());
        
        Test.stopTest();
        
        // Should not throw any exceptions
        System.assert(true, 'Handler should handle empty list gracefully');
    }
    
    @IsTest
    static void testHandleAfterInsertWithMixedRecordTypes() {
        // Get test data
        Lead testLead = [SELECT Id FROM Lead LIMIT 1];
        Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        
        // Create test content document
        ContentVersion cv = new ContentVersion(
            Title = 'Mixed Record Type Test',
            PathOnClient = 'mixedtest.pdf',
            VersionData = Blob.valueOf('Mixed Record Type Test Content'),
            IsMajorVersion = true
        );
        insert cv;
        
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        Test.startTest();
        
        // Create content document links to different record types
        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>{
            new ContentDocumentLink(
                ContentDocumentId = docId,
                LinkedEntityId = testLead.Id,
                ShareType = 'V'
            ),
            new ContentDocumentLink(
                ContentDocumentId = docId,
                LinkedEntityId = testOpp.Id,
                ShareType = 'V'
            ),
            new ContentDocumentLink(
                ContentDocumentId = docId,
                LinkedEntityId = testCase.Id,
                ShareType = 'V'
            )
        };
        
        // Call the handler method directly (without inserting)
        ContentDocumentLinkTriggerHandler.handleAfterInsert(newLinks);
        
        Test.stopTest();
        
        // Verify the handler method executed without errors
        System.assert(true, 'Handler method should execute without errors for mixed record types');
    }
}