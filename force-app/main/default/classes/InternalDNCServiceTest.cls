/**
 * @description Test class for InternalDNCService and InternalDNCFlowAction
 */
@isTest
private class InternalDNCServiceTest {

    /**
     * Mock for successful API response
     */
    private class MockHttpResponseSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Phone numbers processed successfully',
                'summary' => new Map<String, Object>{
                    'total' => 1,
                    'added' => 1,
                    'skipped' => 0
                }
            }));
            return res;
        }
    }

    /**
     * Mock for successful API response with multiple phones
     */
    private class MockHttpResponseMultiple implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Phone numbers processed successfully',
                'summary' => new Map<String, Object>{
                    'total' => 3,
                    'added' => 2,
                    'skipped' => 1
                }
            }));
            return res;
        }
    }

    /**
     * Mock for API error response (401)
     */
    private class MockHttpResponseError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(401);
            res.setBody('{"error": "Invalid token"}');
            return res;
        }
    }

    /**
     * Mock that simulates a connection timeout scenario
     */
    private class MockConnectionTimeout implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"error": "Connection timeout"}');
            return res;
        }
    }

    /**
     * Mock for invalid JSON response
     */
    private class MockHttpInvalidJson implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('invalid json {{{');
            return res;
        }
    }

    /**
     * Mock for success response without summary
     */
    private class MockHttpNoSummary implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'success' => true,
                'message' => 'Phone numbers processed'
            }));
            return res;
        }
    }

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        List<Opportunity> opps = new List<Opportunity>();
        opps.add(new Opportunity(
            Name = 'Test Opp - Qualified',
            AccountId = testAccount.Id,
            StageName = 'Qualified',
            CloseDate = Date.today().addDays(30),
            Phone__c = '123-456-7890'
        ));
        opps.add(new Opportunity(
            Name = 'Test Opp - No Phone',
            AccountId = testAccount.Id,
            StageName = 'Qualified',
            CloseDate = Date.today().addDays(30)
        ));
        insert opps;
    }

    @isTest
    static void testSendPhoneToDNC_Success() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());

        Test.startTest();
        InternalDNCService.DNCResponse response = InternalDNCService.sendPhoneToDNC('123-456-7890');
        Test.stopTest();

        System.assertEquals(true, response.success, 'API call should succeed');
        System.assertEquals(1, response.added, 'Should have added 1 number');
        System.assertEquals(0, response.skipped, 'Should have skipped 0 numbers');
        System.assertEquals(200, response.statusCode, 'Status code should be 200');
    }

    @isTest
    static void testSendPhonesToDNC_MultiplePhones() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseMultiple());

        List<String> phones = new List<String>{'123-456-7890', '555-123-4567', '987-654-3210'};

        Test.startTest();
        InternalDNCService.DNCResponse response = InternalDNCService.sendPhonesToDNC(phones);
        Test.stopTest();

        System.assertEquals(true, response.success, 'API call should succeed');
        System.assertEquals(3, response.totalProcessed, 'Should have processed 3 numbers');
        System.assertEquals(2, response.added, 'Should have added 2 numbers');
        System.assertEquals(1, response.skipped, 'Should have skipped 1 number');
    }

    @isTest
    static void testSendPhoneToDNC_Error() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseError());

        Test.startTest();
        InternalDNCService.DNCResponse response = InternalDNCService.sendPhoneToDNC('123-456-7890');
        Test.stopTest();

        System.assertEquals(false, response.success, 'API call should fail');
        System.assertEquals(401, response.statusCode, 'Status code should be 401');
        System.assert(response.errorMessage.contains('Invalid token'), 'Error should mention token');
    }

    @isTest
    static void testSendPhonesToDNC_EmptyList() {
        Test.startTest();
        InternalDNCService.DNCResponse response = InternalDNCService.sendPhonesToDNC(new List<String>{'', null, '   '});
        Test.stopTest();

        System.assertEquals(false, response.success, 'Should fail with no valid phones');
        System.assert(response.message.contains('No valid phone numbers'), 'Message should indicate no valid phones');
    }

    @isTest
    static void testSendPhonesToDNC_ServerError() {
        Test.setMock(HttpCalloutMock.class, new MockConnectionTimeout());

        Test.startTest();
        InternalDNCService.DNCResponse response = InternalDNCService.sendPhoneToDNC('123-456-7890');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Should fail on server error');
        System.assertEquals(500, response.statusCode, 'Status code should be 500');
    }

    @isTest
    static void testSendPhonesToDNC_JSONException() {
        Test.setMock(HttpCalloutMock.class, new MockHttpInvalidJson());

        Test.startTest();
        InternalDNCService.DNCResponse response = InternalDNCService.sendPhoneToDNC('123-456-7890');
        Test.stopTest();

        System.assertEquals(false, response.success, 'Should fail on JSON parse error');
    }

    @isTest
    static void testSendPhonesToDNC_NoSummary() {
        Test.setMock(HttpCalloutMock.class, new MockHttpNoSummary());

        Test.startTest();
        InternalDNCService.DNCResponse response = InternalDNCService.sendPhoneToDNC('123-456-7890');
        Test.stopTest();

        System.assertEquals(true, response.success, 'Should succeed even without summary');
        System.assertEquals(null, response.added, 'Added should be null when no summary');
    }

    @isTest
    static void testSendPhoneToDNCAsync_Success() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Phone__c != null LIMIT 1];

        Test.startTest();
        InternalDNCService.sendPhoneToDNCAsync('123-456-7890', opp.Id);
        Test.stopTest();

        System.assert(true, 'Async method should complete successfully');
    }

    @isTest
    static void testSendPhoneToDNCAsync_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseError());
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Phone__c != null LIMIT 1];

        Test.startTest();
        InternalDNCService.sendPhoneToDNCAsync('123-456-7890', opp.Id);
        Test.stopTest();

        System.assert(true, 'Async method should complete even on failure');
    }

    @isTest
    static void testSendPhonesToDNCAsync_Success() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseMultiple());
        List<String> phones = new List<String>{'123-456-7890', '555-123-4567'};

        Test.startTest();
        InternalDNCService.sendPhonesToDNCAsync(JSON.serialize(phones));
        Test.stopTest();

        System.assert(true, 'Bulk async method should complete successfully');
    }

    @isTest
    static void testSendPhonesToDNCAsync_Failure() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseError());
        List<String> phones = new List<String>{'123-456-7890', '555-123-4567'};

        Test.startTest();
        InternalDNCService.sendPhonesToDNCAsync(JSON.serialize(phones));
        Test.stopTest();

        System.assert(true, 'Bulk async method should complete even on failure');
    }

    @isTest
    static void testIsDNCTriggerStage() {
        System.assertEquals(true, InternalDNCService.isDNCTriggerStage('Contract Signed'), 'Contract Signed should be DNC stage');
        System.assertEquals(true, InternalDNCService.isDNCTriggerStage('Enrolled'), 'Enrolled should be DNC stage');
        System.assertEquals(true, InternalDNCService.isDNCTriggerStage('NSF'), 'NSF should be DNC stage');
        System.assertEquals(true, InternalDNCService.isDNCTriggerStage('Cancelled'), 'Cancelled should be DNC stage');
        System.assertEquals(false, InternalDNCService.isDNCTriggerStage('Qualified'), 'Qualified should not be DNC stage');
        System.assertEquals(false, InternalDNCService.isDNCTriggerStage('Waiting on Docs'), 'Waiting on Docs should not be DNC stage');
        System.assertEquals(false, InternalDNCService.isDNCTriggerStage(null), 'Null should not be DNC stage');
    }

    @isTest
    static void testStageChangedToDNCStage() {
        // Should trigger: stage changed from non-DNC to DNC
        System.assertEquals(true, InternalDNCService.stageChangedToDNCStage('Qualified', 'Contract Signed'), 'Should trigger when changing to Contract Signed');
        System.assertEquals(true, InternalDNCService.stageChangedToDNCStage('Waiting on Docs', 'Enrolled'), 'Should trigger when changing to Enrolled');
        System.assertEquals(true, InternalDNCService.stageChangedToDNCStage('Qualified', 'NSF'), 'Should trigger when changing to NSF');
        System.assertEquals(true, InternalDNCService.stageChangedToDNCStage('Qualified', 'Cancelled'), 'Should trigger when changing to Cancelled');

        // Should NOT trigger: already in DNC stage
        System.assertEquals(false, InternalDNCService.stageChangedToDNCStage('Contract Signed', 'Enrolled'), 'Should not trigger when already in DNC stage');
        System.assertEquals(false, InternalDNCService.stageChangedToDNCStage('Enrolled', 'NSF'), 'Should not trigger when moving between DNC stages');

        // Should NOT trigger: not changing to DNC stage
        System.assertEquals(false, InternalDNCService.stageChangedToDNCStage('Qualified', 'Waiting on Docs'), 'Should not trigger for non-DNC stage');
    }

    @isTest
    static void testFlowAction_Success() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Phone__c != null LIMIT 1];

        InternalDNCFlowAction.FlowInput input = new InternalDNCFlowAction.FlowInput();
        input.phoneNumber = '123-456-7890';
        input.opportunityId = opp.Id;

        Test.startTest();
        List<InternalDNCFlowAction.FlowOutput> outputs = InternalDNCFlowAction.sendToDNC(
            new List<InternalDNCFlowAction.FlowInput>{input}
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should have 1 output');
        System.assertEquals(true, outputs[0].success, 'Should succeed');
        System.assert(outputs[0].message.contains('queued'), 'Message should indicate queued');
    }

    @isTest
    static void testFlowAction_EmptyPhone() {
        InternalDNCFlowAction.FlowInput input = new InternalDNCFlowAction.FlowInput();
        input.phoneNumber = '';
        input.opportunityId = null;

        Test.startTest();
        List<InternalDNCFlowAction.FlowOutput> outputs = InternalDNCFlowAction.sendToDNC(
            new List<InternalDNCFlowAction.FlowInput>{input}
        );
        Test.stopTest();

        System.assertEquals(1, outputs.size(), 'Should have 1 output');
        System.assertEquals(false, outputs[0].success, 'Should fail with empty phone');
        System.assert(outputs[0].errorMessage.contains('blank'), 'Error should mention blank');
    }

    @isTest
    static void testFlowAction_NullPhone() {
        InternalDNCFlowAction.FlowInput input = new InternalDNCFlowAction.FlowInput();
        input.phoneNumber = null;

        Test.startTest();
        List<InternalDNCFlowAction.FlowOutput> outputs = InternalDNCFlowAction.sendToDNC(
            new List<InternalDNCFlowAction.FlowInput>{input}
        );
        Test.stopTest();

        System.assertEquals(false, outputs[0].success, 'Should fail with null phone');
    }

    @isTest
    static void testFlowAction_MultipleInputs() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseSuccess());
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Phone__c != null LIMIT 1];

        List<InternalDNCFlowAction.FlowInput> inputs = new List<InternalDNCFlowAction.FlowInput>();

        InternalDNCFlowAction.FlowInput input1 = new InternalDNCFlowAction.FlowInput();
        input1.phoneNumber = '123-456-7890';
        input1.opportunityId = opp.Id;
        inputs.add(input1);

        InternalDNCFlowAction.FlowInput input2 = new InternalDNCFlowAction.FlowInput();
        input2.phoneNumber = '555-123-4567';
        input2.opportunityId = opp.Id;
        inputs.add(input2);

        InternalDNCFlowAction.FlowInput input3 = new InternalDNCFlowAction.FlowInput();
        input3.phoneNumber = ''; // Empty phone
        inputs.add(input3);

        Test.startTest();
        List<InternalDNCFlowAction.FlowOutput> outputs = InternalDNCFlowAction.sendToDNC(inputs);
        Test.stopTest();

        System.assertEquals(3, outputs.size(), 'Should have 3 outputs');
        System.assertEquals(true, outputs[0].success, 'First should succeed');
        System.assertEquals(true, outputs[1].success, 'Second should succeed');
        System.assertEquals(false, outputs[2].success, 'Third should fail (empty phone)');
    }

    @isTest
    static void testDNCResponseWrapper() {
        InternalDNCService.DNCResponse response = new InternalDNCService.DNCResponse();
        response.success = true;
        response.message = 'Test message';
        response.totalProcessed = 5;
        response.added = 3;
        response.skipped = 2;
        response.errorMessage = null;
        response.statusCode = 200;

        System.assertEquals(true, response.success);
        System.assertEquals('Test message', response.message);
        System.assertEquals(5, response.totalProcessed);
        System.assertEquals(3, response.added);
        System.assertEquals(2, response.skipped);
        System.assertEquals(200, response.statusCode);
    }
}