@isTest
public class HTTPCalloutInvocableTest {
    
    @isTest
    static void testHttpCallout() {
        Test.setMock(HttpCalloutMock.class, new MockHttpGenerator());
        
        HTTPCalloutInvocable.CalloutRequest request = new HTTPCalloutInvocable.CalloutRequest();
        request.endpoint = 'https://test.example.com/webhook';
        request.httpMethod = 'POST';
        request.requestBody = '{"test": "data"}';
        request.contentType = 'application/json';
        request.timeout = 60000;
        
        List<HTTPCalloutInvocable.CalloutRequest> requests = new List<HTTPCalloutInvocable.CalloutRequest>{request};
        
        Test.startTest();
        List<HTTPCalloutInvocable.CalloutResponse> responses = HTTPCalloutInvocable.makeHttpCallout(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size());
        System.assertEquals(200, responses[0].statusCode);
        System.assertEquals(true, responses[0].isSuccess);
    }
    
    @isTest
    static void testHttpCalloutError() {
        // Test error handling
        HTTPCalloutInvocable.CalloutRequest request = new HTTPCalloutInvocable.CalloutRequest();
        request.endpoint = 'invalid-url';
        request.httpMethod = 'POST';
        request.requestBody = '{"test": "data"}';
        request.contentType = 'application/json';
        request.timeout = 60000;
        
        List<HTTPCalloutInvocable.CalloutRequest> requests = new List<HTTPCalloutInvocable.CalloutRequest>{request};
        
        Test.startTest();
        List<HTTPCalloutInvocable.CalloutResponse> responses = HTTPCalloutInvocable.makeHttpCallout(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size());
        System.assertEquals(false, responses[0].isSuccess);
        System.assertNotEquals(null, responses[0].errorMessage);
    }
    
    @isTest
    static void testLeadFormatter() {
        // Create test data
        LeadWebhookHelper.InputData leadInput = new LeadWebhookHelper.InputData();
        leadInput.leadId = '00Q000000000001AAA';
        leadInput.firstName = 'John';
        leadInput.lastName = 'Doe';
        leadInput.email = 'john.doe@test.com';
        leadInput.phone = '1234567890';
        leadInput.mobile = '0987654321';
        leadInput.company = 'Test Company';
        leadInput.status = 'New';
        leadInput.leadSource = 'Web';
        leadInput.preDealStatus = 'NEW LEAD';
        leadInput.estimatedTotalDebt = 50000.00;
        leadInput.desiredWeeklyPayment = 200.00;
        leadInput.paymentFrequency = 'Weekly';
        leadInput.consumerDebt = true;
        leadInput.medicalDebt = false;
        leadInput.taxDebt = false;
        leadInput.funding = true;
        leadInput.timeZone = 'EST';
        leadInput.spanish = false;
        leadInput.blackListed = false;
        leadInput.duplicate = false;
        leadInput.nurturing = false;
        leadInput.doNotCall = false;
        leadInput.hasOptedOutOfEmail = false;
        leadInput.hasOptedOutOfFax = false;
        leadInput.sfmcSync = true;
        leadInput.utmSource = 'google';
        leadInput.utmCampaign = 'test-campaign';
        leadInput.tag = 'TEST';
        leadInput.leadNumber = '12345';
        leadInput.yearField = 2024;
        
        List<LeadWebhookHelper.InputData> inputs = new List<LeadWebhookHelper.InputData>{leadInput};
        
        Test.startTest();
        List<LeadWebhookHelper.PayloadData> payloads = LeadWebhookHelper.formatLeadData(inputs);
        Test.stopTest();
        
        System.assertEquals(1, payloads.size());
        System.assertNotEquals(null, payloads[0].jsonPayload);
        
        // Verify JSON contains expected data
        String jsonPayload = payloads[0].jsonPayload;
        System.assert(jsonPayload.contains('John'));
        System.assert(jsonPayload.contains('Doe'));
        System.assert(jsonPayload.contains('john.doe@test.com'));
        System.assert(jsonPayload.contains('Test Company'));
        System.assert(jsonPayload.contains('50000'));
    }
    
    @isTest
    static void testLeadFormatterWithMinimalData() {
        // Test with minimal required data
        LeadWebhookHelper.InputData leadInput = new LeadWebhookHelper.InputData();
        leadInput.leadId = '00Q000000000002AAA';
        leadInput.firstName = 'Jane';
        leadInput.lastName = 'Smith';
        leadInput.company = 'Minimal Company';
        
        List<LeadWebhookHelper.InputData> inputs = new List<LeadWebhookHelper.InputData>{leadInput};
        
        Test.startTest();
        List<LeadWebhookHelper.PayloadData> payloads = LeadWebhookHelper.formatLeadData(inputs);
        Test.stopTest();
        
        System.assertEquals(1, payloads.size());
        System.assertNotEquals(null, payloads[0].jsonPayload);
        
        String jsonPayload = payloads[0].jsonPayload;
        System.assert(jsonPayload.contains('Jane'));
        System.assert(jsonPayload.contains('Smith'));
    }
    
    @isTest 
    static void testLeadFormatterMultipleLeads() {
        // Test with multiple leads
        List<LeadWebhookHelper.InputData> inputs = new List<LeadWebhookHelper.InputData>();
        
        for (Integer i = 0; i < 3; i++) {
            LeadWebhookHelper.InputData leadInput = new LeadWebhookHelper.InputData();
            leadInput.leadId = '00Q00000000000' + i + 'AAA';
            leadInput.firstName = 'Test' + i;
            leadInput.lastName = 'User' + i;
            leadInput.company = 'Company' + i;
            leadInput.email = 'test' + i + '@example.com';
            inputs.add(leadInput);
        }
        
        Test.startTest();
        List<LeadWebhookHelper.PayloadData> payloads = LeadWebhookHelper.formatLeadData(inputs);
        Test.stopTest();
        
        System.assertEquals(3, payloads.size());
        
        for (Integer i = 0; i < 3; i++) {
            System.assertNotEquals(null, payloads[i].jsonPayload);
            System.assert(payloads[i].jsonPayload.contains('Test' + i));
        }
    }
}