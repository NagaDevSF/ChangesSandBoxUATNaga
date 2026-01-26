/**
 * Test class for AnswerForcePhoneLookupAPI
 * Tests waterfall lookup: Opportunity.Phone__c → Contact phones → Failure
 */
@isTest
private class AnswerForcePhoneLookupAPITest {

    /**
     * Setup test data - Creates Case Manager profile user, Account, Contact, and Opportunities
     */
    @testSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Account',
            Phone = '4047719726'
        );
        insert testAccount;

        // Create test contact with DIFFERENT phone numbers
        Contact testContact = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@test.com',
            Phone = '4047719726',           // Main phone
            MobilePhone = '8173000782',     // Mobile (different!)
            HomePhone = '5551234567',       // Home phone
            AccountId = testAccount.Id
        );
        insert testContact;

        // Get current user as proxy for Case Manager
        User caseManagerUser = [SELECT Id, Name, Email, Phone FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create Opportunity #1: Phone__c matches Opp phone (primary lookup test)
        // Use 'Build Plan' stage to avoid validation rules
        Opportunity opp1 = new Opportunity(
            Name = 'Test Opp - Primary Phone',
            AccountId = testAccount.Id,
            StageName = 'Build Plan',       // Active stage without strict validation
            CloseDate = Date.today().addDays(30),
            Amount = 50000,
            Phone__c = '4047719726',        // Matches Contact.Phone and Account.Phone
            Case_Manager__c = caseManagerUser.Id
        );
        insert opp1;

        // Create OpportunityContactRole for opp1
        OpportunityContactRole ocr1 = new OpportunityContactRole(
            OpportunityId = opp1.Id,
            ContactId = testContact.Id,
            Role = 'Decision Maker',
            IsPrimary = true
        );
        insert ocr1;

        // Create Opportunity #2: Phone__c DIFFERENT from Contact.MobilePhone (fallback test)
        Opportunity opp2 = new Opportunity(
            Name = 'Test Opp - Different Phone',
            AccountId = testAccount.Id,
            StageName = 'Qualified',        // Active stage without strict validation
            CloseDate = Date.today().addDays(60),
            Amount = 75000,
            Phone__c = '9999999999',        // Different from Contact phones
            Case_Manager__c = caseManagerUser.Id
        );
        insert opp2;

        // Create OpportunityContactRole for opp2
        OpportunityContactRole ocr2 = new OpportunityContactRole(
            OpportunityId = opp2.Id,
            ContactId = testContact.Id,
            Role = 'Decision Maker',
            IsPrimary = true
        );
        insert ocr2;
    }

    /**
     * Test STEP 1: Successful lookup via Opportunity.Phone__c (primary method)
     */
    @isTest
    static void testLookupViaOpportunityPhone() {
        // Setup REST context
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '4047719726');  // Matches Opportunity.Phone__c
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions - Should find via Opportunity.Phone__c
        System.assertEquals(true, response.success, 'Lookup should succeed via Opportunity.Phone__c');
        System.assertNotEquals(null, response.opportunityId, 'Opportunity ID should be returned');
        System.assertNotEquals(null, response.contact, 'Contact should be found');
        System.assertEquals('John Doe', response.contact.name, 'Contact name should match');
        System.assertNotEquals(null, response.caseManager, 'Case Manager should be returned');
        System.assertNotEquals(null, response.allCaseManagers, 'All case managers list should be populated');
    }

    /**
     * Test STEP 2: Fallback lookup via Contact.MobilePhone when Opportunity.Phone__c doesn't match
     */
    @isTest
    static void testFallbackLookupViaContactMobile() {
        // Setup REST context with Contact.MobilePhone that doesn't match any Opportunity.Phone__c
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '8173000782');  // Contact.MobilePhone (NOT in Opportunity.Phone__c)
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions - Should find via Contact phone fallback
        System.assertEquals(true, response.success, 'Lookup should succeed via Contact.MobilePhone fallback');
        System.assertNotEquals(null, response.opportunityId, 'Opportunity ID should be returned from Contact lookup');
        System.assertNotEquals(null, response.contact, 'Contact should be found');
        System.assertNotEquals(null, response.caseManager, 'Case Manager should be returned from related Opportunity');
    }

    /**
     * Test STEP 2: Fallback lookup via Contact.HomePhone
     */
    @isTest
    static void testFallbackLookupViaContactHome() {
        // Setup REST context with Contact.HomePhone
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '5551234567');  // Contact.HomePhone
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(true, response.success, 'Lookup should succeed via Contact.HomePhone');
        System.assertNotEquals(null, response.opportunityId, 'Opportunity should be found via Contact');
    }

    /**
     * Test formatted phone number handling
     */
    @isTest
    static void testFormattedPhoneNumber() {
        // Setup REST context with formatted phone
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '(404) 771-9726');  // Formatted version
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(true, response.success, 'Lookup should handle formatted phone numbers');
        System.assertNotEquals(null, response.contact, 'Contact should be found with formatted phone');
    }

    /**
     * Test international phone format with +1
     */
    @isTest
    static void testInternationalPhoneFormat() {
        // Setup REST context with +1 prefix
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '+1 817-300-0782');  // International format for mobile
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(true, response.success, 'Lookup should handle international format (+1)');
    }

    /**
     * Test no results found - phone doesn't exist anywhere
     */
    @isTest
    static void testNoResultsFound() {
        // Setup REST context with non-existent phone
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '1111111111');  // Doesn't exist
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(false, response.success, 'Lookup should fail for non-existent phone');
        System.assertNotEquals(null, response.message, 'Error message should be provided');
        System.assert(response.message.contains('No active opportunity'), 'Message should indicate no opportunity found');
    }

    /**
     * Test missing phone parameter
     */
    @isTest
    static void testMissingPhoneParameter() {
        // Setup REST context without phone parameter
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(false, response.success, 'Lookup should fail without phone parameter');
        System.assertNotEquals(null, response.message, 'Error message should be provided');
        System.assert(response.message.contains('required'), 'Message should indicate parameter is required');
    }

    /**
     * Test invalid phone format (all special characters)
     */
    @isTest
    static void testInvalidPhoneFormat() {
        // Setup REST context with invalid phone
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '---///***');
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(false, response.success, 'Lookup should fail for invalid format');
        System.assertNotEquals(null, response.message, 'Error message should be provided');
    }

    /**
     * Test opportunity in inactive stage (should not be found)
     */
    @isTest
    static void testInactiveStageOpportunity() {
        // Create opportunity in inactive/closed stage
        Account acct = new Account(Name = 'Inactive Stage Account');
        insert acct;

        Contact contact = new Contact(
            FirstName = 'Inactive',
            LastName = 'Stage',
            Email = 'inactive@test.com',
            Phone = '3331112222',
            AccountId = acct.Id
        );
        insert contact;

        User caseManager = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        Opportunity closedOpp = new Opportunity(
            Name = 'Closed Opp',
            AccountId = acct.Id,
            StageName = 'Closed Lost',  // NOT in ACTIVE_STAGES
            CloseDate = Date.today(),
            Phone__c = '3331112222',
            Case_Manager__c = caseManager.Id
        );
        insert closedOpp;

        // Setup REST context
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '3331112222');
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions - Should not find inactive stage opportunity
        System.assertEquals(false, response.success, 'Closed opportunities should not be found');
    }

    /**
     * Test opportunity without case manager (should not be found)
     */
    @isTest
    static void testOpportunityWithoutCaseManager() {
        // Create opportunity without case manager
        Account acct = new Account(Name = 'No CM Account');
        insert acct;

        Contact contact = new Contact(
            FirstName = 'No',
            LastName = 'CaseManager',
            Email = 'nocm@test.com',
            Phone = '6661112222',
            AccountId = acct.Id
        );
        insert contact;

        Opportunity oppNoCM = new Opportunity(
            Name = 'No Case Manager Opp',
            AccountId = acct.Id,
            StageName = 'Qualified',  // Active stage without strict validation
            CloseDate = Date.today().addDays(30),
            Phone__c = '6661112222'
            // Case_Manager__c is NULL
        );
        insert oppNoCM;

        // Setup REST context
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '6661112222');
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions - Should not find opportunity without case manager
        System.assertEquals(false, response.success, 'Opportunities without Case Manager should not be found');
    }

    /**
     * Test allCaseManagers list is populated
     */
    @isTest
    static void testAllCaseManagersReturned() {
        // Setup REST context
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '4047719726');
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions - allCaseManagers should always be populated
        System.assertNotEquals(null, response.allCaseManagers, 'All case managers list should be populated');
    }

    /**
     * Test CUSTOM FIELD: Successful lookup via Contact.Phone_2__c
     */
    @isTest
    static void testLookupViaContactPhone2() {
        // Create account
        Account acct = new Account(Name = 'Phone2 Test Account');
        insert acct;

        // Create contact with Phone_2__c only
        Contact contact = new Contact(
            FirstName = 'Phone2',
            LastName = 'Test',
            Email = 'phone2@test.com',
            Phone = '1111111111',
            Phone_2__c = '2222222222',  // Secondary phone
            AccountId = acct.Id
        );
        insert contact;

        User cm = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create opportunity with different phone
        // Use 'Build Plan' stage to avoid validation rules requiring additional fields
        Opportunity opp = new Opportunity(
            Name = 'Phone2 Opp',
            AccountId = acct.Id,
            StageName = 'Build Plan',
            CloseDate = Date.today().addDays(30),
            Phone__c = '1111111111',  // Different from Phone_2__c
            Case_Manager__c = cm.Id
        );
        insert opp;

        // Link contact to opportunity
        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contact.Id,
            IsPrimary = true
        );
        insert ocr;

        // Setup REST context - Query with Phone_2__c
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '2222222222');
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(true, response.success, 'Should find via Phone_2__c');
        System.assertNotEquals(null, response.opportunityId, 'Opportunity should be found');
        System.assertEquals('Phone2 Test', response.contact.name, 'Contact name should match');
        System.assertNotEquals(null, response.caseManager, 'Case Manager should be returned');
    }

    /**
     * Test CUSTOM FIELD: Successful lookup via Contact.Phone_3__c
     */
    @isTest
    static void testLookupViaContactPhone3() {
        // Create account
        Account acct = new Account(Name = 'Phone3 Test Account');
        insert acct;

        // Create contact with Phone_3__c only
        Contact contact = new Contact(
            FirstName = 'Phone3',
            LastName = 'Test',
            Email = 'phone3@test.com',
            Phone = '1111111111',
            Phone_3__c = '3333333333',  // Tertiary phone
            AccountId = acct.Id
        );
        insert contact;

        User cm = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create opportunity
        Opportunity opp = new Opportunity(
            Name = 'Phone3 Opp',
            AccountId = acct.Id,
            StageName = 'Build Plan',
            CloseDate = Date.today().addDays(30),
            Phone__c = '1111111111',
            Case_Manager__c = cm.Id
        );
        insert opp;

        // Link contact to opportunity
        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contact.Id,
            IsPrimary = true
        );
        insert ocr;

        // Setup REST context - Query with Phone_3__c
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '3333333333');
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(true, response.success, 'Should find via Phone_3__c');
        System.assertNotEquals(null, response.opportunityId, 'Opportunity should be found');
        System.assertEquals('Phone3 Test', response.contact.name, 'Contact name should match');
        System.assertNotEquals(null, response.caseManager, 'Case Manager should be returned');
    }

    /**
     * Test CUSTOM FIELD: Successful lookup via Contact.Fax
     */
    @isTest
    static void testLookupViaContactFax() {
        // Create account
        Account acct = new Account(Name = 'Fax Test Account');
        insert acct;

        // Create contact with Fax only
        Contact contact = new Contact(
            FirstName = 'Fax',
            LastName = 'Test',
            Email = 'fax@test.com',
            Phone = '1111111111',
            Fax = '4444444444',  // Fax number
            AccountId = acct.Id
        );
        insert contact;

        User cm = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // Create opportunity
        Opportunity opp = new Opportunity(
            Name = 'Fax Opp',
            AccountId = acct.Id,
            StageName = 'Qualified',
            CloseDate = Date.today().addDays(30),
            Phone__c = '1111111111',
            Case_Manager__c = cm.Id
        );
        insert opp;

        // Link contact to opportunity
        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = contact.Id,
            IsPrimary = true
        );
        insert ocr;

        // Setup REST context - Query with Fax
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AnswerForcePhoneLookup';
        req.httpMethod = 'GET';
        req.addParameter('phone', '4444444444');
        RestContext.request = req;
        RestContext.response = res;

        // Execute API call
        Test.startTest();
        AnswerForcePhoneLookupAPI.LookupResponse response = AnswerForcePhoneLookupAPI.lookupByPhone();
        Test.stopTest();

        // Assertions
        System.assertEquals(true, response.success, 'Should find via Fax field');
        System.assertNotEquals(null, response.opportunityId, 'Opportunity should be found');
        System.assertEquals('Fax Test', response.contact.name, 'Contact name should match');
        System.assertNotEquals(null, response.caseManager, 'Case Manager should be returned');
    }
}