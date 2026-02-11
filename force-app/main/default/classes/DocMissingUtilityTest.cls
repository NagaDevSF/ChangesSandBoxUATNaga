@IsTest
public class DocMissingUtilityTest {
    
    // Constants for test data
    private static final String TEST_ACCOUNT_NAME = 'Test Account for DocMissingUtility';
    private static final String TEST_CASE_SUBJECT = 'Test Case for DocMissingUtility';
    private static final String TEST_CASE_ORIGIN = 'Phone';
    private static final String TEST_CASE_STATUS = 'New';
    
    // Helper method to get Welcome Team Record Type ID
    private static Id getWelcomeTeamRecordTypeId() {
        try {
            RecordType welcomeTeamRT = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Case' 
                AND DeveloperName = 'Welcome_Team' 
                LIMIT 1
            ];
            return welcomeTeamRT.Id;
        } catch (QueryException e) {
            return null;
        }
    }
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = TEST_ACCOUNT_NAME,
            BillingStreet = '123 Test St',
            BillingCity = 'Test City',
            BillingState = 'CA',
            BillingPostalCode = '12345'
        );
        insert testAccount;
        
        // Get Welcome Team Record Type ID
        Id welcomeTeamRTId = getWelcomeTeamRecordTypeId();
        
        // Create test cases with different Docs_Missing__c field states
        List<Case> testCases = new List<Case>();
        
        // Case 1: Null Docs_Missing__c field
        testCases.add(new Case(
            Subject = TEST_CASE_SUBJECT + ' - Null Docs Missing',
            AccountId = testAccount.Id,
            Status = TEST_CASE_STATUS,
            Origin = TEST_CASE_ORIGIN,
            RecordTypeId = welcomeTeamRTId,
            Docs_Missing__c = null
        ));
        
        // Case 2: Empty Docs_Missing__c field
        testCases.add(new Case(
            Subject = TEST_CASE_SUBJECT + ' - Empty Docs Missing',
            AccountId = testAccount.Id,
            Status = TEST_CASE_STATUS,
            Origin = TEST_CASE_ORIGIN,
            RecordTypeId = welcomeTeamRTId,
            Docs_Missing__c = ''
        ));
        
        // Case 3: Populated Docs_Missing__c field (should not be affected)
        testCases.add(new Case(
            Subject = TEST_CASE_SUBJECT + ' - Populated Docs Missing',
            AccountId = testAccount.Id,
            Status = TEST_CASE_STATUS,
            Origin = TEST_CASE_ORIGIN,
            RecordTypeId = welcomeTeamRTId,
            Docs_Missing__c = 'Bank Statements;Voided Check'
        ));
        
        insert testCases;
    }
    
    @IsTest
    static void testRefreshAllCasesWithEmptyDocs() {
        // Get test cases
        List<Case> casesBeforeRefresh = [
            SELECT Id, Docs_Missing__c, Subject 
            FROM Case 
            WHERE Subject LIKE :TEST_CASE_SUBJECT + '%'
            ORDER BY Subject
        ];
        
        // Verify initial state
        System.assertEquals(3, casesBeforeRefresh.size(), 'Should have 3 test cases');
        
        // Note: The utility method may have already run during setup, so we need to check current state
        Case case1 = casesBeforeRefresh[0]; // Null case
        Case case2 = casesBeforeRefresh[1]; // Empty case  
        Case case3 = casesBeforeRefresh[2]; // Populated case
        
        Test.startTest();
        
        // Call the utility method
        DocMissingUtility.refreshAllCasesWithEmptyDocs();
        
        Test.stopTest();
        
        // Verify the results
        List<Case> casesAfterRefresh = [
            SELECT Id, Docs_Missing__c, Subject 
            FROM Case 
            WHERE Subject LIKE :TEST_CASE_SUBJECT + '%'
            ORDER BY Subject
        ];
        
        // All cases should now have Docs_Missing__c populated with all required docs
        for (Case c : casesAfterRefresh) {
            System.assertNotEquals(null, c.Docs_Missing__c, 'All cases should now have Docs_Missing__c populated');
            System.assertNotEquals('', c.Docs_Missing__c, 'All cases should not have empty Docs_Missing__c');
        }
        
        // Verify that the populated cases contain all required document types
        String expectedDocsMissing = 'Bank Statements;Contract/Agreement;EFT Form;Hardship Letter;Identification Document;Invoice/Receipt;Lender Agreements;Letter of Representation (LoR);No-Fee Retainer Form (DocuSign);Payoff Letter;Voided Check';
        
        // Check that all cases now have the expected missing docs (order may vary)
        for (Case c : casesAfterRefresh) {
            System.assert(c.Docs_Missing__c.contains('Bank Statements'), 'Case should contain Bank Statements');
            System.assert(c.Docs_Missing__c.contains('Voided Check'), 'Case should contain Voided Check');
            System.assert(c.Docs_Missing__c.contains('Contract/Agreement'), 'Case should contain Contract/Agreement');
            System.assert(c.Docs_Missing__c.contains('EFT Form'), 'Case should contain EFT Form');
        }
    }
    
    @IsTest
    static void testRefreshSpecificCase() {
        // Create a fresh test case for this specific test
        Account testAccount = [SELECT Id FROM Account WHERE Name = :TEST_ACCOUNT_NAME LIMIT 1];
        
        Case freshTestCase = new Case(
            Subject = 'Fresh Test Case for Specific Refresh',
            AccountId = testAccount.Id,
            Status = TEST_CASE_STATUS,
            Origin = TEST_CASE_ORIGIN,
            RecordTypeId = getWelcomeTeamRecordTypeId(),
            Docs_Missing__c = null
        );
        insert freshTestCase;
        
        // Verify initial state
        System.assertEquals(null, freshTestCase.Docs_Missing__c, 'Fresh test case should have null Docs_Missing__c initially');
        
        Test.startTest();
        
        // Call the utility method for specific case
        DocMissingUtility.refreshSpecificCase(freshTestCase.Id);
        
        Test.stopTest();
        
        // Verify the result
        Case updatedCase = [
            SELECT Id, Docs_Missing__c, Subject 
            FROM Case 
            WHERE Id = :freshTestCase.Id
        ];
        
        System.assertNotEquals(null, updatedCase.Docs_Missing__c, 'Case should now have Docs_Missing__c populated');
        System.assertNotEquals('', updatedCase.Docs_Missing__c, 'Case should not have empty Docs_Missing__c');
        
        // Verify it contains required document types
        System.assert(updatedCase.Docs_Missing__c.contains('Bank Statements'), 'Case should contain Bank Statements');
        System.assert(updatedCase.Docs_Missing__c.contains('Voided Check'), 'Case should contain Voided Check');
        System.assert(updatedCase.Docs_Missing__c.contains('Contract/Agreement'), 'Case should contain Contract/Agreement');
    }
    
    @IsTest
    static void testRefreshSpecificCaseWithInvalidId() {
        Test.startTest();
        
        // Test with invalid ID (should not throw exception)
        try {
            DocMissingUtility.refreshSpecificCase(null);
            System.assert(true, 'Should handle null ID gracefully');
        } catch (Exception e) {
            System.assert(false, 'Should not throw exception for null ID: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testRefreshAllCasesWithEmptyDocsNoCasesToRefresh() {
        // First, refresh all cases to populate their Docs_Missing__c fields
        DocMissingUtility.refreshAllCasesWithEmptyDocs();
        
        // Verify all cases now have Docs_Missing__c populated
        List<Case> populatedCases = [
            SELECT Id, Docs_Missing__c 
            FROM Case 
            WHERE Subject LIKE :TEST_CASE_SUBJECT + '%'
        ];
        
        for (Case c : populatedCases) {
            System.assertNotEquals(null, c.Docs_Missing__c, 'All cases should have Docs_Missing__c populated');
            System.assertNotEquals('', c.Docs_Missing__c, 'All cases should not have empty Docs_Missing__c');
        }
        
        Test.startTest();
        
        // Call the utility method again - should not affect already populated cases
        DocMissingUtility.refreshAllCasesWithEmptyDocs();
        
        Test.stopTest();
        
        // Verify no changes occurred
        List<Case> casesAfterSecondRefresh = [
            SELECT Id, Docs_Missing__c 
            FROM Case 
            WHERE Subject LIKE :TEST_CASE_SUBJECT + '%'
        ];
        
        // All cases should remain the same
        for (Integer i = 0; i < populatedCases.size(); i++) {
            System.assertEquals(
                populatedCases[i].Docs_Missing__c, 
                casesAfterSecondRefresh[i].Docs_Missing__c, 
                'Case Docs_Missing__c should remain unchanged after second refresh'
            );
        }
    }
    
    @IsTest
    static void testRefreshSpecificCaseWithAlreadyPopulatedCase() {
        // Create a fresh test case with populated Docs_Missing__c
        Account testAccount = [SELECT Id FROM Account WHERE Name = :TEST_ACCOUNT_NAME LIMIT 1];
        
        Case populatedCase = new Case(
            Subject = 'Fresh Populated Case for Testing',
            AccountId = testAccount.Id,
            Status = TEST_CASE_STATUS,
            Origin = TEST_CASE_ORIGIN,
            RecordTypeId = getWelcomeTeamRecordTypeId(),
            Docs_Missing__c = 'Bank Statements;Voided Check'
        );
        insert populatedCase;
        
        String originalDocsMissing = populatedCase.Docs_Missing__c;
        
        Test.startTest();
        
        // Call the utility method for already populated case
        DocMissingUtility.refreshSpecificCase(populatedCase.Id);
        
        Test.stopTest();
        
        // Verify the result - should be updated to show all required docs as missing
        Case updatedCase = [
            SELECT Id, Docs_Missing__c, Subject 
            FROM Case 
            WHERE Id = :populatedCase.Id
        ];
        
        // Should now show all required document types as missing
        System.assert(updatedCase.Docs_Missing__c.contains('Bank Statements'), 'Case should contain Bank Statements');
        System.assert(updatedCase.Docs_Missing__c.contains('Voided Check'), 'Case should contain Voided Check');
        System.assert(updatedCase.Docs_Missing__c.contains('Contract/Agreement'), 'Case should contain Contract/Agreement');
        System.assert(updatedCase.Docs_Missing__c.contains('EFT Form'), 'Case should contain EFT Form');
    }
    
    @IsTest
    static void testBulkRefreshPerformance() {
        // Create additional test cases to test bulk processing
        Account testAccount = [SELECT Id FROM Account WHERE Name = :TEST_ACCOUNT_NAME LIMIT 1];
        
        List<Case> bulkCases = new List<Case>();
        for (Integer i = 0; i < 50; i++) {
            bulkCases.add(new Case(
                Subject = 'Bulk Test Case ' + i,
                AccountId = testAccount.Id,
                Status = TEST_CASE_STATUS,
                Origin = TEST_CASE_ORIGIN,
                RecordTypeId = getWelcomeTeamRecordTypeId(),
                Docs_Missing__c = null
            ));
        }
        insert bulkCases;
        
        // Verify initial state
        List<Case> casesBeforeRefresh = [
            SELECT Id, Docs_Missing__c 
            FROM Case 
            WHERE Subject LIKE 'Bulk Test Case %'
        ];
        System.assertEquals(50, casesBeforeRefresh.size(), 'Should have created 50 bulk test cases');
        
        for (Case c : casesBeforeRefresh) {
            System.assertEquals(null, c.Docs_Missing__c, 'All bulk cases should have null Docs_Missing__c initially');
        }
        
        Test.startTest();
        
        // Call the utility method - should handle bulk cases efficiently
        DocMissingUtility.refreshAllCasesWithEmptyDocs();
        
        Test.stopTest();
        
        // Verify all bulk cases were processed
        List<Case> casesAfterRefresh = [
            SELECT Id, Docs_Missing__c 
            FROM Case 
            WHERE Subject LIKE 'Bulk Test Case %'
        ];
        
        for (Case c : casesAfterRefresh) {
            System.assertNotEquals(null, c.Docs_Missing__c, 'All bulk cases should now have Docs_Missing__c populated');
            System.assertNotEquals('', c.Docs_Missing__c, 'All bulk cases should not have empty Docs_Missing__c');
        }
    }
}