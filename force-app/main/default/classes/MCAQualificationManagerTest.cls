@isTest
public class MCAQualificationManagerTest {
    
    @isTest
    static void testWelcomeStep() {
        // Test welcome/initial step
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = 'yes I need help';
        request.conversationStep = '';
        request.previousData = '';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('how many MCA lenders'), 'Should ask about lenders');
        System.assertEquals('mca_lenders', responses[0].nextConversationStep, 'Should move to mca_lenders step');
    }
    
    @isTest
    static void testLendersStep() {
        // Test lenders step with number
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = 'I have 5 lenders';
        request.conversationStep = 'mca_lenders';
        request.previousData = '';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('daily MCA payments'), 'Should ask about daily payments');
        System.assertEquals('daily_payments', responses[0].nextConversationStep, 'Should move to daily_payments step');
        System.assert(responses[0].updatedPreviousData.contains('Lenders: 5'), 'Should store lender count');
    }
    
    @isTest
    static void testLendersStepWithWord() {
        // Test lenders step with word number
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = 'five';
        request.conversationStep = 'mca_lenders';
        request.previousData = '';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('daily MCA payments'), 'Should ask about daily payments');
        System.assertEquals('daily_payments', responses[0].nextConversationStep, 'Should move to daily_payments step');
    }
    
    @isTest
    static void testDailyPaymentsStep() {
        // Test daily payments step
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = '$2000 per day';
        request.conversationStep = 'daily_payments';
        request.previousData = 'Lenders: 5';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('total debt amount'), 'Should ask about total debt');
        System.assertEquals('total_debt', responses[0].nextConversationStep, 'Should move to total_debt step');
        System.assert(responses[0].updatedPreviousData.contains('Daily Payments'), 'Should store payment amount');
    }
    
    @isTest
    static void testTotalDebtQualified() {
        // Test total debt step - qualified (>= $25,000)
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = '50000';
        request.conversationStep = 'total_debt';
        request.previousData = 'Lenders: 5 | Daily Payments: $2000';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('Good news'), 'Should show qualification message');
        System.assert(responses[0].promptResponse.contains('Savings Calculator'), 'Should include calculator link');
        System.assertEquals('qualified', responses[0].nextConversationStep, 'Should move to qualified status');
        System.assert(responses[0].updatedPreviousData.contains('QUALIFIED'), 'Should mark as qualified');
    }
    
    @isTest
    static void testTotalDebtNotQualified() {
        // Test total debt step - not qualified (< $25,000)
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = '15000';
        request.conversationStep = 'total_debt';
        request.previousData = 'Lenders: 2 | Daily Payments: $500';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('Unfortunately'), 'Should show non-qualification message');
        System.assert(responses[0].promptResponse.contains('$25,000 or more'), 'Should explain threshold');
        System.assertEquals('not_qualified', responses[0].nextConversationStep, 'Should move to not_qualified status');
        System.assert(responses[0].updatedPreviousData.contains('NOT QUALIFIED'), 'Should mark as not qualified');
    }
    
    @isTest
    static void testAmountWithKNotation() {
        // Test amount extraction with k notation
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = '100k';
        request.conversationStep = 'total_debt';
        request.previousData = 'Lenders: 5 | Daily Payments: $5000';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('Good news'), 'Should qualify with 100k');
        System.assertEquals('qualified', responses[0].nextConversationStep, 'Should be qualified');
    }
    
    @isTest
    static void testInvalidInput() {
        // Test invalid input handling
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = 'I dont know';
        request.conversationStep = 'mca_lenders';
        request.previousData = '';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('Please provide the number'), 'Should ask for clarification');
        System.assertEquals('mca_lenders', responses[0].nextConversationStep, 'Should stay on same step');
    }
    
    @isTest
    static void testRestartFlow() {
        // Test restart after qualification
        MCAQualificationManager.ConversationRequest request = new MCAQualificationManager.ConversationRequest();
        request.userMessage = 'I want to try again';
        request.conversationStep = 'qualified';
        request.previousData = 'Previous qualification data';
        
        List<MCAQualificationManager.ConversationRequest> requests = new List<MCAQualificationManager.ConversationRequest>{request};
        
        Test.startTest();
        List<MCAQualificationManager.ConversationResponse> responses = MCAQualificationManager.processConversation(requests);
        Test.stopTest();
        
        System.assertEquals(1, responses.size(), 'Should return one response');
        System.assert(responses[0].promptResponse.contains('how many MCA lenders'), 'Should restart flow');
        System.assertEquals('mca_lenders', responses[0].nextConversationStep, 'Should go back to lenders step');
        System.assertEquals('', responses[0].updatedPreviousData, 'Should clear previous data');
    }
}