@isTest
public class DCGScheduledJobTest {
    
    // Mock HTTP Response class for testing API calls
    public class MockHttpResponse implements HttpCalloutMock {
        private String responseBody;
        private Integer statusCode;
        
        public MockHttpResponse(String body, Integer code) {
            this.responseBody = body;
            this.statusCode = code;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(this.statusCode);
            res.setBody(this.responseBody);
            return res;
        }
    }
    
    // Test constructor with all parameters
    @isTest
    static void testConstructor() {
        Test.startTest();
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'O_POSITIVES');
        Test.stopTest();
        
        System.assertNotEquals(null, job, 'Job should be instantiated');
    }
    
    // Test positives endpoint execution
    @isTest
    static void testPositivesEndpointExecution() {
        String mockResponse = '[{"sent_to":"5551234567","message":"Test message","user_id":"123","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg123","status":"sent","sms_id":"sms123","sent_from":"5559876543","message_hash":"hash123"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'O_POSITIVES');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Verify leads were created
        List<Lead> createdLeads = [SELECT Id, Phone, LeadSource FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead from positives endpoint');
        System.assertEquals('5551234567', createdLeads[0].Phone, 'Should set phone correctly');
    }
    
    // Test legals-positives endpoint execution
    @isTest
    static void testLegalsPositivesEndpointExecution() {
        String mockResponse = '[{"legals":{"Company Name":"Test Company","Name":"John Doe","Email Address":"john@test.com","Phone Number":"5551234567","Mailing Address":"123 Main St","Tax ID":"123456789","Amount Sued For":"$10,000","Amount Already Paid":"$2,000","Lawyer":"Jane Attorney","PDF File":"http://example.com/doc.pdf","uploaded_on":"2024-01-01T10:00:00Z"}}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/legals-positives', true, 1, null);
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Verify leads were created
        List<Lead> createdLeads = [SELECT Id, Company, LeadSource FROM Lead WHERE LeadSource = 'Legal Database'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead from legals-positives endpoint');
        System.assert(createdLeads[0].Company.equalsIgnoreCase('Test Company'), 'Should set company correctly');
    }
    
    // Test legals endpoint execution
    @isTest
    static void testLegalsEndpointExecution() {
        String mockResponse = '[{"Company Name":"Test Legal Company","Name":"Jane Smith","Email Address":"jane@test.com","Phone Number":"5557654321","Mailing Address":"456 Oak Ave","Tax ID":"987654321","Amount Sued For":"$15,000","Amount Already Paid":"$3,000","Lawyer":"Bob Attorney","PDF File":"http://example.com/doc2.pdf","uploaded_on":"2024-01-02T10:00:00Z"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/legals', true, null, null);
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Verify leads were created
        List<Lead> createdLeads = [SELECT Id, Company, LeadSource FROM Lead WHERE LeadSource = 'Legal Database'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead from legals endpoint');
        System.assert(createdLeads[0].Company.equalsIgnoreCase('Test Legal Company'), 'Should set company correctly');
    }
    
    // Test with createLeads = false
    @isTest
    static void testWithoutCreatingLeads() {
        String mockResponse = '[{"sent_to":"5551234567","message":"Test message","user_id":"123","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg123","status":"sent","sms_id":"sms123","sent_from":"5559876543","message_hash":"hash123"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', false, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Verify no leads were created
        List<Lead> createdLeads = [SELECT Id FROM Lead];
        System.assertEquals(0, createdLeads.size(), 'Should not create leads when createLeads is false');
    }
    
    // Test API failure scenario
    @isTest
    static void testAPIFailure() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse('Internal Server Error', 500));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Should handle failure gracefully without throwing exception
        List<Lead> createdLeads = [SELECT Id FROM Lead];
        System.assertEquals(0, createdLeads.size(), 'Should not create leads when API fails');
    }
    
    // Test with different message options - separate test methods
    @isTest
    static void testMessageOptionALL() {
        String mockResponse = '[{"sent_to":"5551111111","message":"Test message ALL","user_id":"123","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg123","status":"sent","sms_id":"sms123","sent_from":"5559876543","message_hash":"hash123"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead for ALL message option');
    }
    
    @isTest
    static void testMessageOptionCPositives() {
        String mockResponse = '[{"sent_to":"5552222222","message":"Test message C_POSITIVES","user_id":"124","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg124","status":"sent","sms_id":"sms124","sent_from":"5559876543","message_hash":"hash124"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'C_POSITIVES');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead for C_POSITIVES message option');
    }
    
    @isTest
    static void testMessageOptionOPositives() {
        String mockResponse = '[{"sent_to":"5553333333","message":"Test message O_POSITIVES","user_id":"125","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg125","status":"sent","sms_id":"sms125","sent_from":"5559876543","message_hash":"hash125"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'O_POSITIVES');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead for O_POSITIVES message option');
    }
    
    // Test with different intervals - separate test methods
    @isTest
    static void testInterval1Day() {
        String mockResponse = '[{"sent_to":"5554444444","message":"Test message interval 1","user_id":"126","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg126","status":"sent","sms_id":"sms126","sent_from":"5559876543","message_hash":"hash126"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead for 1 day interval');
    }
    
    @isTest
    static void testInterval7Days() {
        String mockResponse = '[{"sent_to":"5555555555","message":"Test message interval 7","user_id":"127","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg127","status":"sent","sms_id":"sms127","sent_from":"5559876543","message_hash":"hash127"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 7, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead for 7 day interval');
    }
    
    @isTest
    static void testInterval15Days() {
        String mockResponse = '[{"sent_to":"5556666666","message":"Test message interval 15","user_id":"128","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg128","status":"sent","sms_id":"sms128","sent_from":"5559876543","message_hash":"hash128"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 15, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead for 15 day interval');
    }
    
    @isTest
    static void testInterval30Days() {
        String mockResponse = '[{"sent_to":"5557777777","message":"Test message interval 30","user_id":"129","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg129","status":"sent","sms_id":"sms129","sent_from":"5559876543","message_hash":"hash129"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 30, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create 1 lead for 30 day interval');
    }
    
    // Test exception handling when no mock is set
    @isTest
    static void testExceptionHandling() {
        // Don't set any mock to force callout exception
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'ALL');
        
        Test.startTest();
        // This should not throw an exception even though the callout will fail
        job.execute(null);
        Test.stopTest();
        
        // Verify no leads were created due to exception
        List<Lead> createdLeads = [SELECT Id FROM Lead];
        System.assertEquals(0, createdLeads.size(), 'Should not create leads when exception occurs');
    }
    
    // Test with empty API response
    @isTest
    static void testEmptyAPIResponse() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse('[]', 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Should handle empty response gracefully
        List<Lead> createdLeads = [SELECT Id FROM Lead];
        System.assertEquals(0, createdLeads.size(), 'Should not create leads from empty API response');
    }
    
    // Test with malformed JSON response
    @isTest
    static void testMalformedJSONResponse() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse('{"invalid": json}', 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Should handle malformed JSON gracefully
        List<Lead> createdLeads = [SELECT Id FROM Lead];
        System.assertEquals(0, createdLeads.size(), 'Should not create leads from malformed JSON');
    }
    
    // Test with null parameters - separate test methods
    @isTest
    static void testNullMessageOption() {
        String mockResponse = '[{"sent_to":"5558888888","message":"Test message null option","user_id":"130","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg130","status":"sent","sms_id":"sms130","sent_from":"5559876543","message_hash":"hash130"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, null);
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create lead with null message option (defaults to ALL)');
    }
    
    @isTest
    static void testNullInterval() {
        String mockResponse = '[{"sent_to":"5559999999","message":"Test message null interval","user_id":"131","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg131","status":"sent","sms_id":"sms131","sent_from":"5559876543","message_hash":"hash131"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, null, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create lead with null interval (defaults to 7)');
    }
    
    // Test invalid endpoint
    @isTest
    static void testInvalidEndpoint() {
        DCGScheduledJob job = new DCGScheduledJob('/invalid-endpoint', true, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Should handle invalid endpoint gracefully
        List<Lead> createdLeads = [SELECT Id FROM Lead];
        System.assertEquals(0, createdLeads.size(), 'Should not create leads with invalid endpoint');
    }
    
    // Test large dataset processing
    @isTest
    static void testLargeDatasetProcessing() {
        // Create a response with multiple records
        List<String> recordList = new List<String>();
        for (Integer i = 0; i < 60; i++) {
            recordList.add('{"sent_to":"555123456' + String.valueOf(i).leftPad(2, '0') + '","message":"Test message ' + i + '","user_id":"' + i + '","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg' + i + '","status":"sent","sms_id":"sms' + i + '","sent_from":"5559876543","message_hash":"hash' + i + '"}');
        }
        String mockResponse = '[' + String.join(recordList, ',') + ']';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'ALL');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Should handle large datasets (processing limit should apply)
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assert(createdLeads.size() <= 50, 'Should respect processing limits for large datasets');
        System.assert(createdLeads.size() > 0, 'Should create some leads from large dataset');
    }
    
    // Test SchedulableContext parameter
    @isTest
    static void testSchedulableContextParameter() {
        String mockResponse = '[{"sent_to":"5551234567","message":"Test message","user_id":"123","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg123","status":"sent","sms_id":"sms123","sent_from":"5559876543","message_hash":"hash123"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'O_POSITIVES');
        
        Test.startTest();
        // Test with actual SchedulableContext (null is acceptable in test context)
        job.execute(null);
        Test.stopTest();
        
        // Should work regardless of SchedulableContext parameter
        List<Lead> createdLeads = [SELECT Id FROM Lead WHERE LeadSource = 'SMS API'];
        System.assertEquals(1, createdLeads.size(), 'Should create lead regardless of SchedulableContext');
    }
    
    // Test debug logging functionality
    @isTest
    static void testDebugLogging() {
        String mockResponse = '[{"sent_to":"5551234567","message":"Test message","user_id":"123","username":"everyDayDebt07","sentiment":"positive","confidence":"0.95","group_name":"test_group","sent_on":"2024-01-01T10:00:00Z","id":"msg123","status":"sent","sms_id":"sms123","sent_from":"5559876543","message_hash":"hash123"}]';
        Test.setMock(HttpCalloutMock.class, new MockHttpResponse(mockResponse, 200));
        
        DCGScheduledJob job = new DCGScheduledJob('/positives', true, 1, 'O_POSITIVES');
        
        Test.startTest();
        job.execute(null);
        Test.stopTest();
        
        // Debug logging is tested by ensuring no exceptions are thrown
        // In a real scenario, you could capture System.debug output
        System.assert(true, 'Debug logging should not cause exceptions');
    }
}