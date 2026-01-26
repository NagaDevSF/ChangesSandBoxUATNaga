public with sharing class MCAQualificationManager {
    
    @InvocableMethod(label='MCA Qualification Chat' description='Manages MCA debt qualification conversation flow')
    public static List<ConversationResponse> processConversation(List<ConversationRequest> requests) {
        List<ConversationResponse> responses = new List<ConversationResponse>();
        
        for (ConversationRequest request : requests) {
            ConversationResponse response = new ConversationResponse();
            
            // Get or initialize conversation state
            String conversationStep = String.isBlank(request.conversationStep) ? 'welcome' : request.conversationStep;
            String previousData = String.isBlank(request.previousData) ? '' : request.previousData;
            String userMessage = request.userMessage != null ? request.userMessage.toLowerCase() : '';
            
            // Process based on current step
            if (conversationStep == 'welcome' || String.isBlank(conversationStep)) {
                // Initial welcome or help request
                if (userMessage.contains('yes') || userMessage.contains('help') || 
                    userMessage.contains('mca') || userMessage.contains('debt') || 
                    userMessage.contains('loan') || String.isBlank(userMessage)) {
                    
                    response.promptResponse = 'Quick question before I go ahead and help - can you tell us how many MCA lenders do you currently have?';
                    response.nextConversationStep = 'mca_lenders';
                    response.updatedPreviousData = previousData;
                }
            }
            else if (conversationStep == 'mca_lenders') {
                // Extract number from response
                String lenderCount = extractNumber(userMessage);
                if (!String.isBlank(lenderCount)) {
                    response.promptResponse = 'Great! Now, how much are your total daily MCA payments?';
                    response.nextConversationStep = 'daily_payments';
                    response.updatedPreviousData = 'Lenders: ' + lenderCount;
                } else {
                    response.promptResponse = 'Please provide the number of MCA lenders you currently have (for example: 3, five, or 10).';
                    response.nextConversationStep = 'mca_lenders';
                    response.updatedPreviousData = previousData;
                }
            }
            else if (conversationStep == 'daily_payments') {
                // Extract payment amount
                String paymentAmount = extractAmount(userMessage);
                if (!String.isBlank(paymentAmount)) {
                    response.promptResponse = 'Thanks! How much is your total debt amount?';
                    response.nextConversationStep = 'total_debt';
                    response.updatedPreviousData = previousData + ' | Daily Payments: $' + paymentAmount;
                } else {
                    response.promptResponse = 'Please provide your daily payment amount (for example: $1500, 2000, or 5k).';
                    response.nextConversationStep = 'daily_payments';
                    response.updatedPreviousData = previousData;
                }
            }
            else if (conversationStep == 'total_debt') {
                // Extract and evaluate total debt
                String debtAmount = extractAmount(userMessage);
                if (!String.isBlank(debtAmount)) {
                    Decimal debtValue = Decimal.valueOf(debtAmount);
                    
                    if (debtValue >= 25000) {
                        // URL should now work since it's in CORS and Trusted URLs
                        response.promptResponse = 'Good news, you meet the requirements for our MCA debt restructuring program! 🎉\n\n' +
                            'You can use the Savings Calculator to see how much you could save:\n' +
                            'https://mcarelief.debtconsultantsgroup.com/calculator/form?utm_source=dcg-quiz-ig&utm_medium=social&utm_campaign=ajs\n\n' +
                            'A specialist will also follow up with you to discuss your options further.';
                        response.nextConversationStep = 'qualified';
                        response.updatedPreviousData = previousData + ' | Total Debt: $' + debtAmount + ' | Status: QUALIFIED';
                    } else {
                        response.promptResponse = 'Unfortunately, your total debt amount may not qualify for our debt restructuring program.\n\n' +
                            'Our programs are designed for businesses with MCA debt of $25,000 or more.\n\n' +
                            'However, we recommend:\n' +
                            '- Speaking with your current MCA providers about payment adjustments\n' +
                            '- Consulting with a financial advisor\n' +
                            '- Exploring traditional business financing options\n\n' +
                            'If your situation changes or you\'d like to discuss other options, please feel free to contact us directly at 1-800-DCG-HELP.';
                        response.nextConversationStep = 'not_qualified';
                        response.updatedPreviousData = previousData + ' | Total Debt: $' + debtAmount + ' | Status: NOT QUALIFIED';
                    }
                } else {
                    response.promptResponse = 'Please provide your total debt amount (for example: $50000, 100k, or 250000).';
                    response.nextConversationStep = 'total_debt';
                    response.updatedPreviousData = previousData;
                }
            }
            else if (conversationStep == 'qualified' || conversationStep == 'not_qualified') {
                // End of flow - restart if user wants to try again
                if (userMessage.contains('again') || userMessage.contains('restart') || userMessage.contains('help')) {
                    response.promptResponse = 'I\'d be happy to help you again. Can you tell us how many MCA lenders do you currently have?';
                    response.nextConversationStep = 'mca_lenders';
                    response.updatedPreviousData = '';
                } else {
                    response.promptResponse = 'Thank you for using our MCA debt qualification service. If you have any other questions, please let us know!';
                    response.nextConversationStep = conversationStep;
                    response.updatedPreviousData = previousData;
                }
            }
            
            responses.add(response);
        }
        
        return responses;
    }
    
    // Helper method to extract numbers from text
    private static String extractNumber(String text) {
        if (String.isBlank(text)) return null;
        
        text = text.toLowerCase();
        
        // Word to number mapping
        Map<String, String> wordToNum = new Map<String, String>{
            'zero' => '0', 'one' => '1', 'two' => '2', 'three' => '3', 
            'four' => '4', 'five' => '5', 'six' => '6', 'seven' => '7',
            'eight' => '8', 'nine' => '9', 'ten' => '10', 'eleven' => '11',
            'twelve' => '12', 'fifteen' => '15', 'twenty' => '20'
        };
        
        // Check for word numbers
        for (String word : wordToNum.keySet()) {
            if (text.contains(word)) {
                return wordToNum.get(word);
            }
        }
        
        // Extract numeric values
        Pattern numPattern = Pattern.compile('\\d+');
        Matcher numMatcher = numPattern.matcher(text);
        if (numMatcher.find()) {
            return numMatcher.group();
        }
        
        return null;
    }
    
    // Helper method to extract amounts from text
    private static String extractAmount(String text) {
        if (String.isBlank(text)) return null;
        
        text = text.toLowerCase().replaceAll('[,$]', '');
        
        // Handle k notation (e.g., 100k = 100000)
        if (text.contains('k')) {
            text = text.replace('k', '000');
        }
        
        // Extract numeric values
        Pattern numPattern = Pattern.compile('\\d+(\\.\\d+)?');
        Matcher numMatcher = numPattern.matcher(text);
        if (numMatcher.find()) {
            return numMatcher.group();
        }
        
        return null;
    }
    
    // Request wrapper class
    public class ConversationRequest {
        @InvocableVariable(label='User Message' description='The user input message')
        public String userMessage;
        
        @InvocableVariable(label='Conversation Step' description='Current step in conversation')
        public String conversationStep;
        
        @InvocableVariable(label='Previous Data' description='Previously collected data')
        public String previousData;
    }
    
    // Response wrapper class
    public class ConversationResponse {
        @InvocableVariable(label='Prompt Response' description='Response to show to user')
        public String promptResponse;
        
        @InvocableVariable(label='Next Conversation Step' description='Next step in conversation')
        public String nextConversationStep;
        
        @InvocableVariable(label='Updated Previous Data' description='Updated data collection')
        public String updatedPreviousData;
    }
}