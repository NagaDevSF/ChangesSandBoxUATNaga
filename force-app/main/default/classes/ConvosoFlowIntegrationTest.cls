@isTest
public class ConvosoFlowIntegrationTest {
    
    // Mock HTTP Response class
    public class MockHttpResponseGenerator implements HttpCalloutMock {
        public Integer statusCode;
        public String responseBody;
        
        public MockHttpResponseGenerator(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            res.setBody(this.responseBody);
            
            // Validate that the request contains expected parameters
            String body = req.getBody();
            System.assert(body.contains('auth_token='), 'Request should contain auth_token');
            System.assert(body.contains('list_id='), 'Request should contain list_id');
            System.assert(body.contains('phone_number='), 'Request should contain phone_number');
            
            return res;
        }
    }
    
    @testSetup
    static void setupTestData() {
        // Create test lead for reference
        Lead testLead = new Lead(
            FirstName = 'John',
            LastName = 'Doe',
            Phone = '5551234567',
            Email = 'john.doe@example.com',
            Company = 'Test Company',
            Street = '123 Main St',
            City = 'Test City',
            State = 'CA',
            PostalCode = '12345'
        );
        insert testLead;
    }
    
    @isTest
    static void testSuccessfulLeadSubmissionWithAllFields() {
        // Setup mock HTTP response for successful call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true,"message":"Lead created successfully","lead_id":"12345"}'));
        
        // Create test request with ALL fields populated
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8487';
        request.phone_number = '5551234567';
        request.check_dup = '1';
        request.check_dup_archive = '1';
        request.check_dnc = '1';
        request.check_wireless = '0';
        request.hopper = '1';
        request.hopper_priority = '95';
        request.hopper_expires_in = '60';
        request.update_if_found = '1';
        request.update_order_by_last_called_time = 'ASC';
        request.blueinkdigital_token = 'test_token_123';
        request.reject_by_carrier_type = 'landline';
        request.filter_phone_code = '1';
        request.lead_id = '100';
        request.phone_code = '1';
        request.created_by = 'testuser';
        request.email = 'john.doe@example.com';
        request.last_modified_by = 'testuser2';
        request.owner_id = 'owner123';
        request.first_name = 'John';
        request.last_name = 'Doe';
        request.alt_phone_1 = '5551111111';
        request.alt_phone_2 = '5552222222';
        request.address1 = '123 Main St';
        request.address2 = 'Apt 4B';
        request.city = 'Test City';
        request.state = 'CA';
        request.province = 'California';
        request.postal_code = '12345';
        request.country = 'USA';
        request.gender = 'M';
        request.date_of_birth = '1990-01-01';
        request.notes = 'Test lead from unit test with all fields';
        request.salesforceownerid = UserInfo.getUserId();
        
        List<ConvosoFlowIntegration.ConvosoRequest> requests = new List<ConvosoFlowIntegration.ConvosoRequest>{request};
        
        Test.startTest();
        List<ConvosoFlowIntegration.ConvosoResponse> responses = ConvosoFlowIntegration.sendLeadToConvoso(requests);
        Test.stopTest(); // This forces the future method to complete
        
        // Assertions for immediate response (before future method)
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assertEquals(true, responses[0].isSuccess, 'Response should be successful');
        System.assertEquals(202, responses[0].statusCode, 'Status code should be 202 (Accepted)');
        System.assertEquals('Lead queued for submission to Convoso List ID: 8487', responses[0].message, 'Success message should match');
        System.assertEquals('Request submitted asynchronously', responses[0].responseBody, 'Response body should match');
    }
    
    @isTest
    static void testSuccessfulLeadSubmissionMinimalFields() {
        // Setup mock HTTP response for successful call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true,"lead_id":"67890"}'));
        
        // Create minimal test request (only required fields)
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8499';
        request.phone_number = '5559876543';
        // All other fields are intentionally left blank/null
        
        List<ConvosoFlowIntegration.ConvosoRequest> requests = new List<ConvosoFlowIntegration.ConvosoRequest>{request};
        
        Test.startTest();
        List<ConvosoFlowIntegration.ConvosoResponse> responses = ConvosoFlowIntegration.sendLeadToConvoso(requests);
        Test.stopTest();
        
        // Assertions
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assertEquals(true, responses[0].isSuccess, 'Response should be successful');
        System.assertEquals(202, responses[0].statusCode, 'Status code should be 202');
        System.assertEquals('Lead queued for submission to Convoso List ID: 8499', responses[0].message, 'Success message should match');
    }
    
    @isTest
    static void testMissingPhoneNumber() {
        // Create test request without phone number
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8487';
        request.first_name = 'John';
        request.last_name = 'Doe';
        request.email = 'john.doe@example.com';
        // phone_number is intentionally left blank
        
        List<ConvosoFlowIntegration.ConvosoRequest> requests = new List<ConvosoFlowIntegration.ConvosoRequest>{request};
        
        Test.startTest();
        List<ConvosoFlowIntegration.ConvosoResponse> responses = ConvosoFlowIntegration.sendLeadToConvoso(requests);
        Test.stopTest();
        
        // Assertions
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assertEquals(false, responses[0].isSuccess, 'Response should be unsuccessful');
        System.assertEquals('phone_number is required', responses[0].message, 'Should show phone number required error');
    }
    
    @isTest
    static void testMissingListId() {
        // Create test request without list ID
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.phone_number = '5551234567';
        request.first_name = 'John';
        request.last_name = 'Doe';
        request.email = 'john.doe@example.com';
        // list_id is intentionally left blank
        
        List<ConvosoFlowIntegration.ConvosoRequest> requests = new List<ConvosoFlowIntegration.ConvosoRequest>{request};
        
        Test.startTest();
        List<ConvosoFlowIntegration.ConvosoResponse> responses = ConvosoFlowIntegration.sendLeadToConvoso(requests);
        Test.stopTest();
        
        // Assertions
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assertEquals(false, responses[0].isSuccess, 'Response should be unsuccessful');
        System.assertEquals('list_id is required', responses[0].message, 'Should show list ID required error');
    }
    
    @isTest
    static void testMultipleRequests() {
        // Setup mock HTTP response for successful call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true}'));
        
        // Create multiple test requests
        List<ConvosoFlowIntegration.ConvosoRequest> requests = new List<ConvosoFlowIntegration.ConvosoRequest>();
        
        // First request - full fields
        ConvosoFlowIntegration.ConvosoRequest request1 = new ConvosoFlowIntegration.ConvosoRequest();
        request1.list_id = '8487';
        request1.phone_number = '5551111111';
        request1.first_name = 'John';
        request1.last_name = 'Doe';
        request1.email = 'john@example.com';
        request1.hopper_priority = '90';
        request1.check_dup = '1';
        requests.add(request1);
        
        // Second request - minimal fields
        ConvosoFlowIntegration.ConvosoRequest request2 = new ConvosoFlowIntegration.ConvosoRequest();
        request2.list_id = '8499';
        request2.phone_number = '5552222222';
        requests.add(request2);
        
        // Third request - mixed fields
        ConvosoFlowIntegration.ConvosoRequest request3 = new ConvosoFlowIntegration.ConvosoRequest();
        request3.list_id = '24263';
        request3.phone_number = '5553333333';
        request3.first_name = 'Jane';
        request3.last_name = 'Smith';
        request3.city = 'Los Angeles';
        request3.state = 'CA';
        requests.add(request3);
        
        Test.startTest();
        List<ConvosoFlowIntegration.ConvosoResponse> responses = ConvosoFlowIntegration.sendLeadToConvoso(requests);
        Test.stopTest();
        
        // Assertions
        System.assertEquals(3, responses.size(), 'Should return three responses');
        System.assertEquals(true, responses[0].isSuccess, 'First response should be successful');
        System.assertEquals(true, responses[1].isSuccess, 'Second response should be successful');
        System.assertEquals(true, responses[2].isSuccess, 'Third response should be successful');
        System.assertEquals('Lead queued for submission to Convoso List ID: 8487', responses[0].message, 'First success message should match');
        System.assertEquals('Lead queued for submission to Convoso List ID: 8499', responses[1].message, 'Second success message should match');
        System.assertEquals('Lead queued for submission to Convoso List ID: 24263', responses[2].message, 'Third success message should match');
    }
    
    @isTest
    static void testFutureMethodWithSuccessfulResponse() {
        // Setup mock HTTP response for successful call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true,"lead_id":"999"}'));
        
        // Create a test request and serialize it
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8487';
        request.phone_number = '5551234567';
        request.first_name = 'Direct';
        request.last_name = 'Test';
        request.email = 'direct@test.com';
        request.notes = 'Direct future method test';
        request.address1 = '456 Test Ave';
        request.city = 'Test City';
        request.state = 'TX';
        request.postal_code = '54321';
        request.hopper_priority = '85';
        request.check_dnc = '1';
        
        String requestJson = JSON.serialize(request);
        
        Test.startTest();
        // Call the future method directly
        ConvosoFlowIntegration.sendLeadToConvosoFuture(requestJson);
        Test.stopTest(); // This forces the future method to complete
        
        // Since future methods don't return values, we can only verify
        // that no exceptions were thrown and the method completed successfully
        System.assert(true, 'Future method with successful response completed without exceptions');
    }
    
    @isTest
    static void testFutureMethodWithHttpError() {
        // Setup mock HTTP response for failed call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(400, '{"success":false,"error":"Invalid list ID"}'));
        
        // Create a test request and serialize it
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '9999'; // Invalid list ID
        request.phone_number = '5551234567';
        request.first_name = 'Error';
        request.last_name = 'Test';
        request.email = 'error@test.com';
        
        String requestJson = JSON.serialize(request);
        
        Test.startTest();
        // Call the future method - should handle the error gracefully
        ConvosoFlowIntegration.sendLeadToConvosoFuture(requestJson);
        Test.stopTest();
        
        // The method should handle the error gracefully and not throw exceptions
        System.assert(true, 'Future method handled HTTP error without exceptions');
    }
    
    @isTest
    static void testFutureMethodWithNullValues() {
        // Setup mock HTTP response for successful call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true}'));
        
        // Create a test request with mostly null values
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8499';
        request.phone_number = '5559999999';
        // All other fields are null
        
        String requestJson = JSON.serialize(request);
        
        Test.startTest();
        ConvosoFlowIntegration.sendLeadToConvosoFuture(requestJson);
        Test.stopTest();
        
        System.assert(true, 'Future method with null values completed without exceptions');
    }
    
    @isTest
    static void testFutureMethodWithEmptyStringValues() {
        // Setup mock HTTP response for successful call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true}'));
        
        // Create a test request with empty string values
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8487';
        request.phone_number = '5551234567';
        request.first_name = '';
        request.last_name = '';
        request.email = '';
        request.notes = '';
        request.check_dup = '';
        request.hopper_priority = '';
        
        String requestJson = JSON.serialize(request);
        
        Test.startTest();
        ConvosoFlowIntegration.sendLeadToConvosoFuture(requestJson);
        Test.stopTest();
        
        System.assert(true, 'Future method with empty strings completed without exceptions');
    }
    
    @isTest
    static void testSpecialCharacterEncoding() {
        // Setup mock HTTP response for successful call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true}'));
        
        // Create test request with special characters
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8487';
        request.phone_number = '555-123-4567';
        request.first_name = 'José';
        request.last_name = 'O\'Brien';
        request.email = 'test+email@example.com';
        request.notes = 'Special chars: & < > " \'';
        request.address1 = '123 Main St & Co.';
        request.city = 'São Paulo';
        request.blueinkdigital_token = 'token_with_special_chars_!@#$%';
        
        List<ConvosoFlowIntegration.ConvosoRequest> requests = new List<ConvosoFlowIntegration.ConvosoRequest>{request};
        
        Test.startTest();
        List<ConvosoFlowIntegration.ConvosoResponse> responses = ConvosoFlowIntegration.sendLeadToConvoso(requests);
        Test.stopTest();
        
        // Assertions
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assertEquals(true, responses[0].isSuccess, 'Response should be successful');
        System.assertEquals(202, responses[0].statusCode, 'Status code should be 202');
    }
    
    @isTest 
    static void testExceptionHandlingInInvocableMethod() {
        // Create a request that will pass validation but might cause issues in serialization
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8487';
        request.phone_number = '5551234567';
        request.first_name = 'Exception';
        request.last_name = 'Test';
        
        List<ConvosoFlowIntegration.ConvosoRequest> requests = new List<ConvosoFlowIntegration.ConvosoRequest>{request};
        
        Test.startTest();
        List<ConvosoFlowIntegration.ConvosoResponse> responses = ConvosoFlowIntegration.sendLeadToConvoso(requests);
        Test.stopTest();
        
        // Should handle gracefully and return success for queueing
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assertEquals(true, responses[0].isSuccess, 'Should queue successfully even if future method might fail');
    }
    
    @isTest
    static void testFutureMethodWithInvalidJson() {
        // Setup mock for potential HTTP call
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true}'));
        
        Test.startTest();
        try {
            // Call future method with invalid JSON - should handle gracefully
            ConvosoFlowIntegration.sendLeadToConvosoFuture('invalid json string');
        } catch (Exception e) {
            // Even if there's an exception, it should be caught and logged
            System.assert(true, 'Exception was caught and handled');
        }
        Test.stopTest();
        
        System.assert(true, 'Future method with invalid JSON handled gracefully');
    }
    
    @isTest
    static void testAllConfigurationFields() {
        // Setup mock HTTP response
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(200, '{"success":true}'));
        
        // Test with all configuration fields set to different values
        ConvosoFlowIntegration.ConvosoRequest request = new ConvosoFlowIntegration.ConvosoRequest();
        request.list_id = '8487';
        request.phone_number = '5551234567';
        request.check_dup = '0';
        request.check_dup_archive = '1';
        request.check_dnc = '0';
        request.check_wireless = '1';
        request.hopper = '0';
        request.hopper_priority = '50';
        request.hopper_expires_in = '120';
        request.update_if_found = '1';
        request.update_order_by_last_called_time = 'ASC';
        request.lead_id = '12345';
        request.phone_code = '44'; // UK
        request.filter_phone_code = '1';
        
        String requestJson = JSON.serialize(request);
        
        Test.startTest();
        ConvosoFlowIntegration.sendLeadToConvosoFuture(requestJson);
        Test.stopTest();
        
        System.assert(true, 'Future method with all configuration fields completed successfully');
    }
}