@isTest
public class LeadBlacklistHandlerTest {
    
    // Test data constants
    private static final String GOOD_PHONE = '1234567890';
    private static final String BLACKLISTED_PHONE = '0987654321';
    private static final String FEDERAL_DNC_PHONE = '5551234567';
    private static final String STATE_DNC_PHONE = '7774567890';
    private static final String INVALID_PHONE = '1111111111';
    
    /**
     * Mock class for successful API response with "Good" message
     */
    public class MockHttpResponseGood implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String responseBody = '{' +
                '"sid": "test-sid-123",' +
                '"status": "success",' +
                '"message": "Good",' +
                '"code": [],' +
                '"offset": 1755289911548344,' +
                '"phone": "' + GOOD_PHONE + '",' +
                '"results": 0,' +
                '"timeValue": 0,' +
                '"carrier": {' +
                    '"did": "' + GOOD_PHONE + '",' +
                    '"carrierType": "PCS",' +
                    '"name": "T-Mobile",' +
                    '"state": "FL",' +
                    '"ratecenter": "",' +
                    '"country": "US",' +
                    '"clli": "MIAMFLGR78Z",' +
                    '"lata": "46017",' +
                    '"wireless": "Y",' +
                    '"lrn": "3058908999",' +
                    '"npa": "130",' +
                    '"nxx": "531",' +
                    '"nxxx": "7922",' +
                    '"ocn": "6889",' +
                    '"port_type": "1"' +
                '},' +
                '"scrubs": true' +
            '}';
            
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock class for successful API response with "Blacklisted" message
     */
    public class MockHttpResponseBlacklisted implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String responseBody = '{' +
                '"sid": "test-sid-456",' +
                '"status": "success",' +
                '"message": "Blacklisted",' +
                '"code": ["blacklisted", "anti-telemarketing"],' +
                '"offset": 1755289911548344,' +
                '"phone": "' + BLACKLISTED_PHONE + '",' +
                '"results": 2,' +
                '"timeValue": 0,' +
                '"carrier": {' +
                    '"did": "' + BLACKLISTED_PHONE + '",' +
                    '"carrierType": "Landline",' +
                    '"name": "Verizon",' +
                    '"state": "NY",' +
                    '"ratecenter": "New York",' +
                    '"country": "US",' +
                    '"clli": "NYCMNY01",' +
                    '"lata": "132",' +
                    '"wireless": "N",' +
                    '"lrn": "2125551234",' +
                    '"npa": "212",' +
                    '"nxx": "555",' +
                    '"nxxx": "1234",' +
                    '"ocn": "9999",' +
                    '"port_type": "0"' +
                '},' +
                '"scrubs": true' +
            '}';
            
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock class for successful API response with "FederalDNC" message
     */
    public class MockHttpResponseFederalDNC implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String responseBody = '{' +
                '"sid": "test-sid-789",' +
                '"status": "success",' +
                '"message": "FederalDNC",' +
                '"code": ["federal-dnc"],' +
                '"offset": 1755289911548344,' +
                '"phone": "' + FEDERAL_DNC_PHONE + '",' +
                '"results": 1,' +
                '"timeValue": 0,' +
                '"carrier": {' +
                    '"did": "' + FEDERAL_DNC_PHONE + '",' +
                    '"carrierType": "PCS",' +
                    '"name": "AT&T",' +
                    '"state": "CA",' +
                    '"ratecenter": "Los Angeles",' +
                    '"country": "US",' +
                    '"clli": "LSANCAOL",' +
                    '"lata": "730",' +
                    '"wireless": "Y",' +
                    '"lrn": "5551234567",' +
                    '"npa": "555",' +
                    '"nxx": "123",' +
                    '"nxxx": "4567",' +
                    '"ocn": "7421",' +
                    '"port_type": "1"' +
                '},' +
                '"scrubs": true' +
            '}';
            
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock class for successful API response with "StateDNC" message
     */
    public class MockHttpResponseStateDNC implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String responseBody = '{' +
                '"sid": "test-sid-state",' +
                '"status": "success",' +
                '"message": "StateDNC",' +
                '"code": ["florida-dnc"],' +
                '"offset": 1755289911548344,' +
                '"phone": "' + STATE_DNC_PHONE + '",' +
                '"results": 1,' +
                '"timeValue": 0,' +
                '"carrier": {' +
                    '"did": "' + STATE_DNC_PHONE + '",' +
                    '"carrierType": "PCS",' +
                    '"name": "Verizon Wireless",' +
                    '"state": "FL",' +
                    '"ratecenter": "Tampa",' +
                    '"country": "US",' +
                    '"clli": "TAMPAFLZ",' +
                    '"lata": "46017",' +
                    '"wireless": "Y",' +
                    '"lrn": "7774567890",' +
                    '"npa": "777",' +
                    '"nxx": "456",' +
                    '"nxxx": "7890",' +
                    '"ocn": "6003",' +
                    '"port_type": "1"' +
                '},' +
                '"scrubs": true' +
            '}';
            
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock class for failed API response (non-200 status)
     */
    public class MockHttpResponseFailed implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(400);
            res.setBody('{"error": "Invalid request"}');
            return res;
        }
    }
    
    /**
     * Mock class for API response with no carrier data
     */
    public class MockHttpResponseNoCarrier implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String responseBody = '{' +
                '"sid": "test-sid-nocarrier",' +
                '"status": "success",' +
                '"message": "Good",' +
                '"code": [],' +
                '"phone": "' + INVALID_PHONE + '",' +
                '"results": 0,' +
                '"timeValue": 0,' +
                '"carrier": null,' +
                '"scrubs": false' +
            '}';
            
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock class for invalid JSON response
     */
    public class MockHttpResponseInvalidJson implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"invalid": json"}'); // Malformed JSON
            return res;
        }
    }
    
    /**
     * Mock class for API response with error status
     */
    public class MockHttpResponseErrorStatus implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            String responseBody = '{' +
                '"sid": "test-sid-error",' +
                '"status": "error",' +
                '"message": "Invalid phone number",' +
                '"code": ["invalid_phone"],' +
                '"phone": "' + INVALID_PHONE + '",' +
                '"results": 0,' +
                '"timeValue": 0,' +
                '"carrier": null,' +
                '"scrubs": false' +
            '}';
            
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * Mock class for timeout/connection error (returns 500 error)
     */
    public class MockHttpResponseTimeout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"error": "Internal Server Error - Connection Timeout"}');
            return res;
        }
    }
    
    /**
     * Test successful processing of "Good" numbers (should not be marked as DNC)
     */
    @isTest
    public static void testGoodNumberProcessing() {
        System.debug('🧪 ═══ TEST: Good Number Processing ═══');
        
        // Set mock for "Good" response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGood());
        
        // Create test lead with good phone
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Good',
            Company = 'Test Company',
            Phone = GOOD_PHONE,
            Email = 'test@good.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead - this triggers the handler
        insert testLead;
        
        Test.stopTest(); // This processes all async methods
        
        // Query the lead to check current status
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead Pre_Deal_Status__c after processing: ' + updatedLead.Pre_Deal_Status__c);
        
        // Verify lead was NOT marked as DNC (should be null or not 'DNC')
        System.assertNotEquals('DNC', updatedLead.Pre_Deal_Status__c, 'Good number should not be marked as DNC');
        
        System.debug('✅ Good number test passed');
    }
    
    /**
     * Test successful processing of "Blacklisted" numbers (should be marked as DNC)
     */
    @isTest
    public static void testBlacklistedNumberProcessing() {
        System.debug('🧪 ═══ TEST: Blacklisted Number Processing ═══');
        
        // Set mock for "Blacklisted" response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseBlacklisted());
        
        // Create test lead with blacklisted phone
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Blacklisted',
            Company = 'Test Company',
            Phone = BLACKLISTED_PHONE,
            Email = 'test@blacklisted.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead - this triggers the handler
        insert testLead;
        
        Test.stopTest(); // This processes all async methods
        
        // Query the lead to check current status
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead Pre_Deal_Status__c after processing: ' + updatedLead.Pre_Deal_Status__c);
        
        // Verify lead was marked as DNC
        System.assertEquals('DNC', updatedLead.Pre_Deal_Status__c, 'Blacklisted number should be marked as DNC');
        
        System.debug('✅ Blacklisted number test passed');
    }
    
    /**
     * Test successful processing of "FederalDNC" numbers (should be marked as DNC)
     */
    @isTest
    public static void testFederalDNCProcessing() {
        System.debug('🧪 ═══ TEST: Federal DNC Number Processing ═══');
        
        // Set mock for "FederalDNC" response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseFederalDNC());
        
        // Create test lead with federal DNC phone
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'FederalDNC',
            Company = 'Test Company',
            Phone = FEDERAL_DNC_PHONE,
            Email = 'test@federaldnc.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead - this triggers the handler
        insert testLead;
        
        Test.stopTest(); // This processes all async methods
        
        // Query the lead to check current status
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead Pre_Deal_Status__c after processing: ' + updatedLead.Pre_Deal_Status__c);
        
        // Verify lead was marked as DNC
        System.assertEquals('DNC', updatedLead.Pre_Deal_Status__c, 'Federal DNC number should be marked as DNC');
        
        System.debug('✅ Federal DNC number test passed');
    }
    
    /**
     * Test successful processing of "StateDNC" numbers (should be marked as DNC)
     */
    @isTest
    public static void testStateDNCProcessing() {
        System.debug('🧪 ═══ TEST: State DNC Number Processing ═══');
        
        // Set mock for "StateDNC" response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseStateDNC());
        
        // Create test lead with state DNC phone
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'StateDNC',
            Company = 'Test Company',
            Phone = STATE_DNC_PHONE,
            Email = 'test@statednc.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead - this triggers the handler
        insert testLead;
        
        Test.stopTest(); // This processes all async methods
        
        // Query the lead to check current status
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead Pre_Deal_Status__c after processing: ' + updatedLead.Pre_Deal_Status__c);
        
        // Verify lead was marked as DNC
        System.assertEquals('DNC', updatedLead.Pre_Deal_Status__c, 'State DNC number should be marked as DNC');
        
        System.debug('✅ State DNC number test passed');
    }
    
    /**
     * Test leads without phone numbers (should be skipped)
     */
    @isTest
    public static void testLeadsWithoutPhoneNumbers() {
        System.debug('🧪 ═══ TEST: Leads Without Phone Numbers ═══');
        
        // Create test leads without phone numbers
        List<Lead> testLeads = new List<Lead>();
        for (Integer i = 0; i < 5; i++) {
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'NoPhone' + i,
                Company = 'Test Company ' + i,
                Email = 'test' + i + '@nophone.com',
                Status = 'Open - Not Contacted'
                // No Phone field set
            ));
        }
        
        Test.startTest();
        
        // Insert leads - should not trigger any API calls
        insert testLeads;
        
        Test.stopTest();
        
        // Verify no leads were updated to DNC (they should keep their original status)
        List<Lead> updatedLeads = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id IN :testLeads];
        for (Lead lead : updatedLeads) {
            System.debug('Lead without phone Pre_Deal_Status__c: ' + lead.Pre_Deal_Status__c);
            System.assertNotEquals('DNC', lead.Pre_Deal_Status__c, 'Leads without phone should not be processed to DNC');
        }
        
        System.debug('✅ No phone numbers test passed');
    }
    
    /**
     * Test API failure scenarios
     */
    @isTest
    public static void testApiFailureScenarios() {
        System.debug('🧪 ═══ TEST: API Failure Scenarios ═══');
        
        // Set mock for failed API response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseFailed());
        
        // Create test lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'ApiFail',
            Company = 'Test Company',
            Phone = INVALID_PHONE,
            Email = 'test@apifail.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead - API call will fail
        insert testLead;
        
        Test.stopTest();
        
        // Verify lead was not updated to DNC due to API failure
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead after API failure Pre_Deal_Status__c: ' + updatedLead.Pre_Deal_Status__c);
        System.assertNotEquals('DNC', updatedLead.Pre_Deal_Status__c, 'Failed API call should not update lead to DNC');
        
        System.debug('✅ API failure test passed');
    }
    
    /**
     * Test API response with error status (status != 'success')
     */
    @isTest
    public static void testApiErrorStatus() {
        System.debug('🧪 ═══ TEST: API Error Status Response ═══');
        
        // Set mock for error status response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseErrorStatus());
        
        // Create test lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'ApiError',
            Company = 'Test Company',
            Phone = INVALID_PHONE,
            Email = 'test@apierror.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead
        insert testLead;
        
        Test.stopTest();
        
        // Verify lead was not updated to DNC due to error status
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead after API error status Pre_Deal_Status__c: ' + updatedLead.Pre_Deal_Status__c);
        System.assertNotEquals('DNC', updatedLead.Pre_Deal_Status__c, 'API error status should not update lead to DNC');
        
        System.debug('✅ API error status test passed');
    }
    
    /**
     * Test server error handling (500 status code)
     */
    @isTest
    public static void testServerErrorHandling() {
        System.debug('🧪 ═══ TEST: Server Error Handling ═══');
        
        // Set mock that returns 500 error
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseTimeout());
        
        // Create test lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'ServerError',
            Company = 'Test Company',
            Phone = GOOD_PHONE,
            Email = 'test@servererror.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead - API will return 500 error
        insert testLead;
        
        Test.stopTest();
        
        // Verify lead was not updated to DNC due to server error
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead after server error Pre_Deal_Status__c: ' + updatedLead.Pre_Deal_Status__c);
        System.assertNotEquals('DNC', updatedLead.Pre_Deal_Status__c, 'Server error should not update lead to DNC');
        
        System.debug('✅ Server error test passed');
    }
    
    /**
     * Test response with no carrier data but good message
     */
    @isTest
    public static void testNoCarrierData() {
        System.debug('🧪 ═══ TEST: No Carrier Data Response ═══');
        
        // Set mock for response with no carrier data but "Good" message
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseNoCarrier());
        
        // Create test lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'NoCarrier',
            Company = 'Test Company',
            Phone = INVALID_PHONE,
            Email = 'test@nocarrier.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead
        insert testLead;
        
        Test.stopTest();
        
        // Verify lead was not updated to DNC since message is "Good"
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead after no carrier data Pre_Deal_Status__c: ' + updatedLead.Pre_Deal_Status__c);
        System.assertNotEquals('DNC', updatedLead.Pre_Deal_Status__c, 'Good message should not update lead to DNC even with no carrier data');
        
        System.debug('✅ No carrier data test passed');
    }
    
    /**
     * Test invalid JSON response handling
     */
    @isTest
    public static void testInvalidJsonResponse() {
        System.debug('🧪 ═══ TEST: Invalid JSON Response ═══');
        
        // Set mock for invalid JSON response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseInvalidJson());
        
        // Create test lead
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'InvalidJson',
            Company = 'Test Company',
            Phone = GOOD_PHONE,
            Email = 'test@invalidjson.com',
            Status = 'Open - Not Contacted'
        );
        
        Test.startTest();
        
        // Insert lead - JSON parsing will fail
        insert testLead;
        
        Test.stopTest();
        
        // Verify lead was not updated to DNC due to JSON parsing failure
        Lead updatedLead = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id = :testLead.Id];
        System.debug('Lead after invalid JSON Pre_Deal_Status__c: ' + updatedLead.Pre_Deal_Status__c);
        System.assertNotEquals('DNC', updatedLead.Pre_Deal_Status__c, 'Invalid JSON should not update lead to DNC');
        
        System.debug('✅ Invalid JSON test passed');
    }
    
    /**
     * Test bulk lead processing with DNC numbers
     */
    @isTest
    public static void testBulkLeadProcessing() {
        System.debug('🧪 ═══ TEST: Bulk Lead Processing ═══');
        
        // Set mock for blacklisted response (all leads will be marked DNC)
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseBlacklisted());
        
        // Create multiple test leads
        List<Lead> testLeads = new List<Lead>();
        for (Integer i = 0; i < 10; i++) {
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'Bulk' + i,
                Company = 'Test Company ' + i,
                Phone = '555000000' + i,
                Email = 'test' + i + '@bulk.com',
                Status = 'Open - Not Contacted'
            ));
        }
        
        Test.startTest();
        
        // Insert all leads at once
        insert testLeads;
        
        Test.stopTest();
        
        // Verify all leads were marked as DNC
        List<Lead> updatedLeads = [SELECT Id, Pre_Deal_Status__c FROM Lead WHERE Id IN :testLeads];
        for (Lead lead : updatedLeads) {
            System.assertEquals('DNC', lead.Pre_Deal_Status__c, 'All bulk leads should be marked as DNC');
        }
        
        System.debug('✅ Bulk processing test passed');
    }
    
    /**
     * Test mixed scenario with leads with and without phone numbers
     */
    @isTest
    public static void testMixedScenario() {
        System.debug('🧪 ═══ TEST: Mixed Scenario ═══');
        
        // Set mock for blacklisted response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseBlacklisted());
        
        // Create leads with and without phone numbers
        List<Lead> testLeads = new List<Lead>();
        
        // Leads with phone numbers
        for (Integer i = 0; i < 3; i++) {
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'WithPhone' + i,
                Company = 'Test Company ' + i,
                Phone = '555000' + String.valueOf(1000 + i),
                Email = 'testwp' + i + '@mixed.com',
                Status = 'Open - Not Contacted'
            ));
        }
        
        // Leads without phone numbers
        for (Integer i = 0; i < 3; i++) {
            testLeads.add(new Lead(
                FirstName = 'Test',
                LastName = 'WithoutPhone' + i,
                Company = 'Test Company No Phone ' + i,
                Email = 'testnp' + i + '@mixed.com',
                Status = 'Open - Not Contacted'
                // No phone number
            ));
        }
        
        Test.startTest();
        
        // Insert all leads
        insert testLeads;
        
        Test.stopTest();
        
        // Verify only leads with phone numbers were updated to DNC
        List<Lead> allLeads = [SELECT Id, FirstName, LastName, Phone, Pre_Deal_Status__c FROM Lead WHERE Id IN :testLeads];
        
        Integer withPhoneUpdated = 0;
        Integer withoutPhoneNotUpdated = 0;
        
        for (Lead lead : allLeads) {
            System.debug('Lead: ' + lead.FirstName + ' ' + lead.LastName + ' | Phone: ' + lead.Phone + ' | Status: ' + lead.Pre_Deal_Status__c);
            
            if (String.isNotBlank(lead.Phone)) {
                if (lead.Pre_Deal_Status__c == 'DNC') {
                    withPhoneUpdated++;
                    System.debug('✅ Lead with phone marked as DNC: ' + lead.LastName);
                } else {
                    System.debug('⚠️ Lead with phone NOT marked as DNC: ' + lead.LastName + ' | Status: ' + lead.Pre_Deal_Status__c);
                }
            } else {
                if (lead.Pre_Deal_Status__c != 'DNC') {
                    withoutPhoneNotUpdated++;
                    System.debug('✅ Lead without phone NOT marked as DNC: ' + lead.LastName);
                } else {
                    System.debug('❌ Lead without phone incorrectly marked as DNC: ' + lead.LastName);
                }
            }
        }
        
        System.debug('Leads with phone updated to DNC: ' + withPhoneUpdated);
        System.debug('Leads without phone not updated: ' + withoutPhoneNotUpdated);
        
        // Assert that we processed the expected number of leads correctly
        System.assertEquals(3, withPhoneUpdated, 'Should have 3 leads with phone updated to DNC');
        System.assertEquals(3, withoutPhoneNotUpdated, 'Should have 3 leads without phone not updated to DNC');
        
        System.debug('✅ Mixed scenario test passed');
    }
    
    /**
     * Test wrapper class instantiation for coverage
     */
    @isTest
    public static void testWrapperClasses() {
        System.debug('🧪 ═══ TEST: Wrapper Classes ═══');
        
        // Test BlacklistApiResponse
        LeadBlacklistHandler.BlacklistApiResponse response = new LeadBlacklistHandler.BlacklistApiResponse();
        response.sid = 'test-sid';
        response.status = 'success';
        response.message = 'Good';
        response.code = new List<String>{'test-code'};
        response.offset = 123456789L;
        response.phone = '1234567890';
        response.results = 0;
        response.timeValue = 100;
        response.scrubs = true;
        
        // Test CarrierInfo
        LeadBlacklistHandler.CarrierInfo carrier = new LeadBlacklistHandler.CarrierInfo();
        carrier.did = '1234567890';
        carrier.carrierType = 'PCS';
        carrier.name = 'Test Carrier';
        carrier.state = 'FL';
        carrier.ratecenter = 'Miami';
        carrier.country = 'US';
        carrier.clli = 'MIAMFLGR78Z';
        carrier.lata = '46017';
        carrier.wireless = 'Y';
        carrier.lrn = '3058908999';
        carrier.npa = '305';
        carrier.nxx = '890';
        carrier.nxxx = '8999';
        carrier.ocn = '6889';
        carrier.port_type = '1';
        
        response.carrier = carrier;
        
        // Assert wrapper classes work
        System.assertEquals('test-sid', response.sid);
        System.assertEquals('Test Carrier', response.carrier.name);
        System.assertEquals('Good', response.message);
        System.assertEquals(1, response.code.size());
        
        System.debug('✅ Wrapper classes test passed');
    }
}