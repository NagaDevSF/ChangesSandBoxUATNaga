public class DCGFlowControlledProcessor {
    
    // Updated Input class for Flow - All parameters now optional
    public class DCGFlowInput {
        @InvocableVariable(label='API Endpoint' description='Choose: /positives, /legals, or /legals-positives' required=false)
        public String apiEndpoint;
        
        @InvocableVariable(label='Interval (Days)' description='Number of days to look back (1-30)' required=false)
        public Integer interval;
        
        @InvocableVariable(label='Message Option' description='ALL, C_POSITIVES, or O_POSITIVES' required=false)
        public String messageOption;
        
        @InvocableVariable(label='Create Leads' description='True to create leads, False to just retrieve data' required=false)
        public Boolean createLeads;
    }
    
    // Output class for Flow
    public class DCGFlowOutput {
        @InvocableVariable(label='Success' description='True if API call was successful')
        public Boolean success;
        
        @InvocableVariable(label='Error Message' description='Error message if failed')
        public String errorMessage;
        
        @InvocableVariable(label='API Endpoint Used' description='Which API endpoint was called')
        public String apiEndpointUsed;
        
        @InvocableVariable(label='Total Records Retrieved' description='Number of records from API')
        public Integer totalRecordsRetrieved;
        
        @InvocableVariable(label='Leads Created' description='Number of leads created (if requested)')
        public Integer leadsCreated;
        
        @InvocableVariable(label='Created Lead IDs' description='IDs of created leads')
        public List<String> createdLeadIds;
        
        @InvocableVariable(label='API Response Details' description='Detailed API response information for debugging')
        public String apiResponseDetails;
        
        // ALL DATA COLLECTIONS - SMS/Positives Data
        @InvocableVariable(label='All Phone Numbers' description='Collection of all phone numbers')
        public List<String> allPhoneNumbers;
        
        @InvocableVariable(label='All Messages' description='Collection of all message text')
        public List<String> allMessages;
        
        @InvocableVariable(label='All User IDs' description='Collection of all user IDs')
        public List<String> allUserIds;
        
        @InvocableVariable(label='All Usernames' description='Collection of all usernames')
        public List<String> allUsernames;
        
        @InvocableVariable(label='All Sentiments' description='Collection of all sentiments')
        public List<String> allSentiments;
        
        @InvocableVariable(label='All Confidence Scores' description='Collection of all confidence scores')
        public List<String> allConfidenceScores;
        
        @InvocableVariable(label='All Group Names' description='Collection of all group names')
        public List<String> allGroupNames;
        
        @InvocableVariable(label='All Sent Dates' description='Collection of all sent dates')
        public List<String> allSentDates;
        
        @InvocableVariable(label='All Message IDs' description='Collection of all message IDs')
        public List<String> allMessageIds;
        
        @InvocableVariable(label='All Statuses' description='Collection of all message statuses')
        public List<String> allStatuses;
        
        @InvocableVariable(label='All SMS IDs' description='Collection of all SMS IDs')
        public List<String> allSmsIds;
        
        @InvocableVariable(label='All Sent From' description='Collection of all sent from numbers')
        public List<String> allSentFroms;
        
        @InvocableVariable(label='All Message Hashes' description='Collection of all message hashes')
        public List<String> allMessageHashes;
        
        // ALL DATA COLLECTIONS - Legal Data
        @InvocableVariable(label='All Company Names' description='Collection of all company names')
        public List<String> allCompanyNames;
        
        @InvocableVariable(label='All Contact Names' description='Collection of all contact names')
        public List<String> allContactNames;
        
        @InvocableVariable(label='All Email Addresses' description='Collection of all email addresses')
        public List<String> allEmailAddresses;
        
        @InvocableVariable(label='All Legal Phone Numbers' description='Collection of all legal phone numbers')
        public List<String> allLegalPhoneNumbers;
        
        @InvocableVariable(label='All Mailing Addresses' description='Collection of all mailing addresses')
        public List<String> allMailingAddresses;
        
        @InvocableVariable(label='All Tax IDs' description='Collection of all tax IDs')
        public List<String> allTaxIds;
        
        @InvocableVariable(label='All Amounts Sued For' description='Collection of all amounts sued for')
        public List<String> allAmountsSuedFor;
        
        @InvocableVariable(label='All Amounts Paid' description='Collection of all amounts already paid')
        public List<String> allAmountsPaid;
        
        @InvocableVariable(label='All Lawyers' description='Collection of all lawyer names')
        public List<String> allLawyers;
        
        @InvocableVariable(label='All PDF Files' description='Collection of all PDF file URLs')
        public List<String> allPdfFiles;
        
        @InvocableVariable(label='All Upload Dates' description='Collection of all upload dates')
        public List<String> allUploadDates;
    }
    
    // API Call Result wrapper class
    public class APICallResult {
        public Boolean success;
        public String errorMessage;
        public String details;
        public List<Object> data;
        
        public APICallResult() {
            this.success = false;
            this.errorMessage = '';
            this.details = '';
            this.data = new List<Object>();
        }
    }
    
    // Round Robin assignment counters and user cache
    private static Map<String, Integer> roundRobinCounters = new Map<String, Integer>();
    private static Map<String, List<User>> cachedUsersMap = new Map<String, List<User>>();
    
    // Method to clear cache for testing
    @TestVisible
    private static void clearUserCache() {
        cachedUsersMap.clear();
        roundRobinCounters.clear();
    }
    
    @InvocableMethod(label='DCG - Create Leads' description='Get DCG data and create leads with auto-populated fields' category='DCG Integration')
    public static List<DCGFlowOutput> getDataWithFlowControl(List<DCGFlowInput> inputs) {
        List<DCGFlowOutput> outputs = new List<DCGFlowOutput>();
        
        if (inputs == null) {
            return outputs;
        }
        
        for (DCGFlowInput input : inputs) {
            DCGFlowOutput output = new DCGFlowOutput();
            
            // Set defaults for null values
            String apiEndpoint = (input.apiEndpoint != null) ? input.apiEndpoint : '/positives';
            Integer interval = (input.interval != null) ? input.interval : 7;
            String messageOption = (input.messageOption != null) ? input.messageOption : 'ALL';
            Boolean createLeads = (input.createLeads != null) ? input.createLeads : false;
            
            output.apiEndpointUsed = apiEndpoint;
            output.apiResponseDetails = '';
            
            try {
                if (apiEndpoint == '/positives') {
                    output = handlePositivesEndpoint(interval, messageOption, createLeads, output);
                } else if (apiEndpoint == '/legals') {
                    output = handleLegalsEndpoint(createLeads, output);
                } else if (apiEndpoint == '/legals-positives') {
                    output = handleLegalsPositivesEndpoint(createLeads, output);
                } else {
                    output.success = false;
                    output.errorMessage = 'Invalid API Endpoint. Use: /positives, /legals, or /legals-positives';
                    initializeOutputCollections(output);
                }
            } catch (Exception e) {
                output.success = false;
                output.errorMessage = 'Unexpected error: ' + e.getMessage();
                initializeOutputCollections(output);
            }
            
            outputs.add(output);
        }
        
        return outputs;
    }
    
    private static DCGFlowOutput handlePositivesEndpoint(Integer interval, String messageOption, Boolean createLeads, DCGFlowOutput output) {
        if (interval < 1 || interval > 30) {
            output.success = false;
            output.errorMessage = 'Interval must be between 1 and 30 days';
            initializeOutputCollections(output);
            return output;
        }
        
        APICallResult apiResult = callPositivesAPI(interval, messageOption);
        
        if (!apiResult.success) {
            output.success = false;
            output.errorMessage = apiResult.errorMessage;
            initializeOutputCollections(output);
            return output;
        }
        
        List<Object> apiData = apiResult.data;
        output.success = true;
        output.totalRecordsRetrieved = apiData.size();
        initializeOutputCollections(output);
        
        // EMERGENCY FIX: Limit processing to prevent CPU timeout
        Integer maxRecordsToProcess = 50;
        Integer recordsToProcess = Math.min(apiData.size(), maxRecordsToProcess);
        
        for (Integer i = 0; i < recordsToProcess; i++) {
            Map<String, Object> record = (Map<String, Object>) apiData[i];
            output.allPhoneNumbers.add(getStringValue(record, 'sent_to'));
            output.allMessages.add(getStringValue(record, 'message'));
            output.allUserIds.add(getStringValue(record, 'user_id'));
            output.allUsernames.add(getStringValue(record, 'username'));
            output.allSentiments.add(getStringValue(record, 'sentiment'));
            output.allConfidenceScores.add(getStringValue(record, 'confidence'));
            output.allGroupNames.add(getStringValue(record, 'group_name'));
            output.allSentDates.add(getStringValue(record, 'sent_on'));
            output.allMessageIds.add(getStringValue(record, 'id'));
            output.allStatuses.add(getStringValue(record, 'status'));
            output.allSmsIds.add(getStringValue(record, 'sms_id'));
            output.allSentFroms.add(getStringValue(record, 'sent_from'));
            output.allMessageHashes.add(getStringValue(record, 'message_hash'));
        }
        
        if (createLeads) {
            preloadUsersForRoundRobin();
            
            List<Object> limitedData = new List<Object>();
            for (Integer i = 0; i < recordsToProcess; i++) {
                limitedData.add(apiData[i]);
            }
            
            Map<String, Object> leadResults = createLeadsFromPositivesData(limitedData);
            output.leadsCreated = (Integer) leadResults.get('leadsCreated');
            output.createdLeadIds = (List<String>) leadResults.get('createdLeadIds');
        } else {
            output.leadsCreated = 0;
            output.createdLeadIds = new List<String>();
        }
        
        return output;
    }
    
    private static DCGFlowOutput handleLegalsEndpoint(Boolean createLeads, DCGFlowOutput output) {
        APICallResult apiResult = callLegalsAPI();
        
        if (!apiResult.success) {
            output.success = false;
            output.errorMessage = apiResult.errorMessage;
            initializeOutputCollections(output);
            return output;
        }
        
        List<Object> apiData = apiResult.data;
        output.success = true;
        output.totalRecordsRetrieved = apiData.size();
        initializeOutputCollections(output);
        
        for (Object rawRecord : apiData) {
            Map<String, Object> record = (Map<String, Object>) rawRecord;
            output.allCompanyNames.add(getStringValue(record, 'Company Name'));
            output.allContactNames.add(getStringValue(record, 'Name'));
            output.allEmailAddresses.add(getStringValue(record, 'Email Address'));
            output.allLegalPhoneNumbers.add(getStringValue(record, 'Phone Number'));
            output.allMailingAddresses.add(getStringValue(record, 'Mailing Address'));
            output.allTaxIds.add(getStringValue(record, 'Tax ID'));
            output.allAmountsSuedFor.add(getStringValue(record, 'Amount Sued For'));
            output.allAmountsPaid.add(getStringValue(record, 'Amount Already Paid'));
            output.allLawyers.add(getStringValue(record, 'Lawyer'));
            output.allPdfFiles.add(getStringValue(record, 'PDF File'));
            output.allUploadDates.add(getStringValue(record, 'uploaded_on'));
        }
        
        if (createLeads) {
            preloadUsersForRoundRobin();
            Map<String, Object> leadResults = createLeadsFromLegalData(apiData);
            output.leadsCreated = (Integer) leadResults.get('leadsCreated');
            output.createdLeadIds = (List<String>) leadResults.get('createdLeadIds');
        } else {
            output.leadsCreated = 0;
            output.createdLeadIds = new List<String>();
        }
        
        return output;
    }
    
    private static DCGFlowOutput handleLegalsPositivesEndpoint(Boolean createLeads, DCGFlowOutput output) {
        APICallResult apiResult = callLegalsPositivesAPI();
        
        if (!apiResult.success) {
            output.success = false;
            output.errorMessage = apiResult.errorMessage;
            initializeOutputCollections(output);
            return output;
        }
        
        List<Object> apiData = apiResult.data;
        output.success = true;
        output.totalRecordsRetrieved = apiData.size();
        initializeOutputCollections(output);
        
        for (Object rawRecord : apiData) {
            Map<String, Object> rootRecord = (Map<String, Object>) rawRecord;
            Map<String, Object> legalsData = (Map<String, Object>) rootRecord.get('legals');
            
            if (legalsData != null) {
                output.allCompanyNames.add(getStringValue(legalsData, 'Company Name'));
                output.allContactNames.add(getStringValue(legalsData, 'Name'));
                output.allEmailAddresses.add(getStringValue(legalsData, 'Email Address'));
                output.allLegalPhoneNumbers.add(getStringValue(legalsData, 'Phone Number'));
                output.allMailingAddresses.add(getStringValue(legalsData, 'Mailing Address'));
                output.allTaxIds.add(getStringValue(legalsData, 'Tax ID'));
                output.allAmountsSuedFor.add(getStringValue(legalsData, 'Amount Sued For'));
                output.allAmountsPaid.add(getStringValue(legalsData, 'Amount Already Paid'));
                output.allLawyers.add(getStringValue(legalsData, 'Lawyer'));
                output.allPdfFiles.add(getStringValue(legalsData, 'PDF File'));
                output.allUploadDates.add(getStringValue(legalsData, 'uploaded_on'));
            }
        }
        
        if (createLeads) {
            Map<String, Object> leadResults = createLeadsFromLegalsPositivesData(apiData);
            output.leadsCreated = (Integer) leadResults.get('leadsCreated');
            output.createdLeadIds = (List<String>) leadResults.get('createdLeadIds');
        } else {
            output.leadsCreated = 0;
            output.createdLeadIds = new List<String>();
        }
        
        return output;
    }
    
    private static APICallResult callPositivesAPI(Integer interval, String messageOption) {
        APICallResult result = new APICallResult();
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://qu9lksdc1m.execute-api.us-east-1.amazonaws.com/positives?interval=' + interval + '&option=' + messageOption);
            req.setMethod('GET');
            req.setTimeout(60000);
            
            String credentials = 'salesforce:A#9zLr2!qXp$7DfVt@3m';
            String encodedCredentials = EncodingUtil.base64Encode(Blob.valueOf(credentials));
            req.setHeader('Authorization', 'Basic ' + encodedCredentials);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();
                if (String.isNotBlank(responseBody)) {
                    List<Object> data = (List<Object>) JSON.deserializeUntyped(responseBody);
                    result.success = true;
                    result.data = data;
                } else {
                    result.success = false;
                    result.errorMessage = 'Empty response';
                }
            } else {
                result.success = false;
                result.errorMessage = 'API call failed with status: ' + res.getStatusCode();
            }
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static APICallResult callLegalsAPI() {
        APICallResult result = new APICallResult();
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://qu9lksdc1m.execute-api.us-east-1.amazonaws.com/legals');
            req.setMethod('GET');
            req.setTimeout(60000);
            
            String credentials = 'salesforce:A#9zLr2!qXp$7DfVt@3m';
            String encodedCredentials = EncodingUtil.base64Encode(Blob.valueOf(credentials));
            req.setHeader('Authorization', 'Basic ' + encodedCredentials);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();
                if (String.isNotBlank(responseBody)) {
                    List<Object> data = (List<Object>) JSON.deserializeUntyped(responseBody);
                    result.success = true;
                    result.data = data;
                } else {
                    result.success = false;
                    result.errorMessage = 'Empty response';
                }
            } else {
                result.success = false;
                result.errorMessage = 'API call failed with status: ' + res.getStatusCode();
            }
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static APICallResult callLegalsPositivesAPI() {
        APICallResult result = new APICallResult();
        
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://qu9lksdc1m.execute-api.us-east-1.amazonaws.com/legals-positives');
            req.setMethod('GET');
            req.setTimeout(60000);
            
            String credentials = 'salesforce:A#9zLr2!qXp$7DfVt@3m';
            String encodedCredentials = EncodingUtil.base64Encode(Blob.valueOf(credentials));
            req.setHeader('Authorization', 'Basic ' + encodedCredentials);
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                String responseBody = res.getBody();
                if (String.isNotBlank(responseBody)) {
                    List<Object> data = (List<Object>) JSON.deserializeUntyped(responseBody);
                    result.success = true;
                    result.data = data;
                } else {
                    result.success = false;
                    result.errorMessage = 'Empty response';
                }
            } else {
                result.success = false;
                result.errorMessage = 'API call failed with status: ' + res.getStatusCode();
            }
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Error: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static Map<String, Object> createLeadsFromPositivesData(List<Object> apiData) {
        List<Lead> leadsToCreate = new List<Lead>();
        Map<String, List<Map<String, Object>>> phoneToRecords = new Map<String, List<Map<String, Object>>>();
        
        for (Object rawRecord : apiData) {
            Map<String, Object> record = (Map<String, Object>) rawRecord;
            String phoneValue = getStringValue(record, 'sent_to');
            
            if (String.isNotBlank(phoneValue)) {
                if (!phoneToRecords.containsKey(phoneValue)) {
                    phoneToRecords.put(phoneValue, new List<Map<String, Object>>());
                }
                phoneToRecords.get(phoneValue).add(record);
            }
        }
        
        for (String phoneValue : phoneToRecords.keySet()) {
            try {
                List<Map<String, Object>> phoneRecords = phoneToRecords.get(phoneValue);
                Map<String, Object> firstRecord = phoneRecords[0];
                
                Lead lead = new Lead();
                String sentToValue = getStringValue(firstRecord, 'sent_to');
                lead.Phone = sentToValue;
                lead.MobilePhone = sentToValue;
                lead.LastName = sentToValue;
                lead.Company = sentToValue;
                
                String usernameValue = getStringValue(firstRecord, 'username');
                
                try {
                    lead.put('Cherry_Box__c', usernameValue);
                } catch (Exception e) {
                    // Field does not exist
                }
                
                assignLeadOwnerRoundRobin(lead, usernameValue);
                
                List<String> messagesList = new List<String>();
                for (Map<String, Object> record : phoneRecords) {
                    String messageValue = getStringValue(record, 'message');
                    if (String.isNotBlank(messageValue)) {
                        messagesList.add(messageValue);
                    }
                }
                if (!messagesList.isEmpty()) {
                    String allMessages = String.join(messagesList, ' | ');
                    
                    // Truncate if too long for QuickNotes field (255 char limit)
                    if (allMessages.length() > 255) {
                        allMessages = allMessages.substring(0, 252) + '...';
                    }
                    
                    try {
                        lead.put('QuickNotes__c', allMessages);
                    } catch (Exception e) {
                        // If QuickNotes field doesn't exist or still fails, use Description
                        // Description field can handle longer text
                        lead.Description = allMessages;
                    }
                }
                
                try {
                    lead.put('Source__c', 'Cherry');
                } catch (Exception e) {
                    // Field does not exist
                }
                
                lead.LeadSource = 'SMS API';
                
                leadsToCreate.add(lead);
                
            } catch (Exception e) {
                // Skip this lead if there is an error
            }
        }
        
        List<String> createdLeadIds = new List<String>();
        Integer leadsCreatedCount = 0;
        
        if (!leadsToCreate.isEmpty()) {
            Database.SaveResult[] results = Database.insert(leadsToCreate);
            
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    leadsCreatedCount++;
                    createdLeadIds.add(results[i].getId());
                }
            }
        }
        
        Map<String, Object> resultMap = new Map<String, Object>();
        resultMap.put('leadsCreated', leadsCreatedCount);
        resultMap.put('createdLeadIds', createdLeadIds);
        
        return resultMap;
    }
    
    private static Map<String, Object> createLeadsFromLegalData(List<Object> apiData) {
        List<Lead> leadsToCreate = new List<Lead>();
        
        for (Object rawRecord : apiData) {
            try {
                Map<String, Object> record = (Map<String, Object>) rawRecord;
                
                Lead lead = new Lead();
                
                String companyNameValue = getStringValue(record, 'Company Name');
                lead.Company = String.isNotBlank(companyNameValue) ? companyNameValue : 'Legal Company';
                
                String fullNameValue = getStringValue(record, 'Name');
                if (String.isNotBlank(fullNameValue)) {
                    List<String> nameParts = fullNameValue.split(' ');
                    if (nameParts.size() == 1) {
                        lead.LastName = nameParts[0];
                    } else if (nameParts.size() >= 2) {
                        lead.FirstName = nameParts[0];
                        lead.LastName = nameParts[nameParts.size() - 1];
                    }
                } else {
                    lead.LastName = 'Legal Contact';
                }
                
                lead.Phone = getStringValue(record, 'Phone Number');
                lead.MobilePhone = getStringValue(record, 'Phone Number');
                lead.Email = getStringValue(record, 'Email Address');
                
                String mailingAddressValue = getStringValue(record, 'Mailing Address');
                if (String.isNotBlank(mailingAddressValue)) {
                    String addressCleaned = mailingAddressValue.replaceAll('\\r\\n|\\r|\\n', ' ');
                    List<String> addressParts = addressCleaned.split(',');
                    
                    if (addressParts.size() >= 1) {
                        lead.Street = addressParts[0].trim();
                    }
                    if (addressParts.size() >= 2) {
                        lead.City = addressParts[1].trim();
                    }
                    if (addressParts.size() >= 3) {
                        String stateZip = addressParts[2].trim();
                        List<String> stateZipParts = stateZip.split(' ');
                        if (stateZipParts.size() >= 1) {
                            lead.State = stateZipParts[0];
                        }
                        if (stateZipParts.size() >= 2) {
                            lead.PostalCode = stateZipParts[stateZipParts.size() - 1];
                        }
                    }
                }
                
                try {
                    lead.put('EIN__c', getStringValue(record, 'Tax ID'));
                } catch (Exception e) {
                    // Field does not exist
                }
                
                String amountSuedValue = getStringValue(record, 'Amount Sued For');
                if (String.isNotBlank(amountSuedValue)) {
                    try {
                        String cleanAmountValue = amountSuedValue.replaceAll('[^0-9.]', '');
                        if (String.isNotBlank(cleanAmountValue)) {
                            Decimal amountValue = Decimal.valueOf(cleanAmountValue);
                            try {
                                lead.put('Balance__c', amountValue);
                            } catch (Exception e) {
                                lead.AnnualRevenue = amountValue;
                            }
                        }
                    } catch (Exception e) {
                        // Parsing failed
                    }
                }
                
                String lawyerValue = getStringValue(record, 'Lawyer');
                if (String.isNotBlank(lawyerValue)) {
                    try {
                        lead.put('Lawyer__c', lawyerValue);
                    } catch (Exception e) {
                        lead.Title = lawyerValue;
                    }
                }
                
                try {
                    lead.put('Docs_links__c', getStringValue(record, 'PDF File'));
                } catch (Exception e) {
                    // Field does not exist
                }
                
                try {
                    String uploadedOnValue = getStringValue(record, 'uploaded_on');
                    if (String.isNotBlank(uploadedOnValue)) {
                        DateTime uploadDateValue = DateTime.valueOf(uploadedOnValue.replace('T', ' ').replace('Z', ''));
                        lead.put('Updated_date_ref__c', uploadDateValue);
                    }
                } catch (Exception e) {
                    // Field does not exist or parsing failed
                }
                
                try {
                    lead.put('Source__c', 'NY Legal Scraper');
                } catch (Exception e) {
                    // Field does not exist
                }
                
                lead.LeadSource = 'Legal Database';
                
                assignLeadOwnerRoundRobin(lead, companyNameValue);
                
                String descriptionValue = 'Legal Lead Details: ';
                descriptionValue += 'Company: ' + companyNameValue + ' | ';
                descriptionValue += 'Tax ID: ' + getStringValue(record, 'Tax ID') + ' | ';
                descriptionValue += 'Amount Sued For: ' + amountSuedValue + ' | ';
                descriptionValue += 'Amount Already Paid: ' + getStringValue(record, 'Amount Already Paid') + ' | ';
                descriptionValue += 'Lawyer: ' + getStringValue(record, 'Lawyer') + ' | ';
                descriptionValue += 'Upload Date: ' + getStringValue(record, 'uploaded_on');
                
                lead.Description = descriptionValue;
                
                leadsToCreate.add(lead);
                
            } catch (Exception e) {
                // Skip this lead if there is an error
            }
        }
        
        List<String> createdLeadIds = new List<String>();
        Integer leadsCreatedCount = 0;
        
        if (!leadsToCreate.isEmpty()) {
            Database.SaveResult[] results = Database.insert(leadsToCreate);
            
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    leadsCreatedCount++;
                    createdLeadIds.add(results[i].getId());
                }
            }
        }
        
        Map<String, Object> resultMap = new Map<String, Object>();
        resultMap.put('leadsCreated', leadsCreatedCount);
        resultMap.put('createdLeadIds', createdLeadIds);
        
        return resultMap;
    }
    
    private static Map<String, Object> createLeadsFromLegalsPositivesData(List<Object> apiData) {
        List<Lead> leadsToCreate = new List<Lead>();
        
        for (Object rawRecord : apiData) {
            try {
                Map<String, Object> rootRecord = (Map<String, Object>) rawRecord;
                Map<String, Object> legalsData = (Map<String, Object>) rootRecord.get('legals');
                
                if (legalsData == null) {
                    continue;
                }
                
                Lead lead = new Lead();
                
                String companyNameValue = getStringValue(legalsData, 'Company Name');
                lead.Company = String.isNotBlank(companyNameValue) ? companyNameValue : 'Legal Company';
                
                String fullNameValue = getStringValue(legalsData, 'Name');
                if (String.isNotBlank(fullNameValue)) {
                    List<String> nameParts = fullNameValue.split(' ');
                    if (nameParts.size() == 1) {
                        lead.LastName = nameParts[0];
                    } else if (nameParts.size() >= 2) {
                        lead.FirstName = nameParts[0];
                        lead.LastName = nameParts[nameParts.size() - 1];
                    }
                } else {
                    lead.LastName = 'Legal Contact';
                }
                
                lead.Phone = getStringValue(legalsData, 'Phone Number');
                lead.MobilePhone = getStringValue(legalsData, 'Phone Number');
                lead.Email = getStringValue(legalsData, 'Email Address');
                
                String mailingAddressValue = getStringValue(legalsData, 'Mailing Address');
                if (String.isNotBlank(mailingAddressValue)) {
                    String addressCleaned = mailingAddressValue.replaceAll('\\r\\n|\\r|\\n', ' ');
                    List<String> addressParts = addressCleaned.split(',');
                    
                    if (addressParts.size() >= 1) {
                        lead.Street = addressParts[0].trim();
                    }
                    if (addressParts.size() >= 2) {
                        lead.City = addressParts[1].trim();
                    }
                    if (addressParts.size() >= 3) {
                        String stateZip = addressParts[2].trim();
                        List<String> stateZipParts = stateZip.split(' ');
                        if (stateZipParts.size() >= 1) {
                            lead.State = stateZipParts[0];
                        }
                        if (stateZipParts.size() >= 2) {
                            lead.PostalCode = stateZipParts[stateZipParts.size() - 1];
                        }
                    }
                }
                
                try {
                    lead.put('EIN__c', getStringValue(legalsData, 'Tax ID'));
                } catch (Exception e) {
                    // Field does not exist
                }
                
                String amountSuedValue = getStringValue(legalsData, 'Amount Sued For');
                if (String.isNotBlank(amountSuedValue)) {
                    try {
                        String cleanAmountValue = amountSuedValue.replaceAll('[^0-9.]', '');
                        if (String.isNotBlank(cleanAmountValue)) {
                            Decimal amountValue = Decimal.valueOf(cleanAmountValue);
                            try {
                                lead.put('Balance__c', amountValue);
                            } catch (Exception e) {
                                lead.AnnualRevenue = amountValue;
                            }
                        }
                    } catch (Exception e) {
                        // Parsing failed
                    }
                }
                
                String lawyerValue = getStringValue(legalsData, 'Lawyer');
                if (String.isNotBlank(lawyerValue)) {
                    try {
                        lead.put('Lawyer__c', lawyerValue);
                    } catch (Exception e) {
                        lead.Title = lawyerValue;
                    }
                }
                
                try {
                    lead.put('Docs_links__c', getStringValue(legalsData, 'PDF File'));
                } catch (Exception e) {
                    // Field does not exist
                }
                
                try {
                    String uploadedOnValue = getStringValue(legalsData, 'uploaded_on');
                    if (String.isNotBlank(uploadedOnValue)) {
                        DateTime uploadDateValue = DateTime.valueOf(uploadedOnValue.replace('T', ' ').replace('Z', ''));
                        lead.put('Updated_date_ref__c', uploadDateValue);
                    }
                } catch (Exception e) {
                    // Field does not exist or parsing failed
                }
                
                try {
                    lead.put('Source__c', 'NY Legal Scraper');
                } catch (Exception e) {
                    // Field does not exist
                }
                
                lead.LeadSource = 'Legal Database';
                
                String descriptionValue = 'Legal-Positives Lead Details: ';
                descriptionValue += 'Company: ' + companyNameValue + ' | ';
                descriptionValue += 'Tax ID: ' + getStringValue(legalsData, 'Tax ID') + ' | ';
                descriptionValue += 'Amount Sued For: ' + amountSuedValue + ' | ';
                descriptionValue += 'Amount Already Paid: ' + getStringValue(legalsData, 'Amount Already Paid') + ' | ';
                descriptionValue += 'Lawyer: ' + getStringValue(legalsData, 'Lawyer') + ' | ';
                descriptionValue += 'PDF Document: ' + getStringValue(legalsData, 'PDF File') + ' | ';
                descriptionValue += 'Upload Date: ' + getStringValue(legalsData, 'uploaded_on');
                
                // Truncate Description if too long (32000 char limit but keep reasonable)
                if (descriptionValue.length() > 1000) {
                    descriptionValue = descriptionValue.substring(0, 997) + '...';
                }
                
                lead.Description = descriptionValue;
                
                leadsToCreate.add(lead);
                
            } catch (Exception e) {
                // Skip this lead if there is an error
            }
        }
        
        List<String> createdLeadIds = new List<String>();
        Integer leadsCreatedCount = 0;
        
        if (!leadsToCreate.isEmpty()) {
            // Insert leads first WITHOUT owner assignment
            Database.SaveResult[] results = Database.insert(leadsToCreate);
            
            // Collect successful leads for assignment
            List<Lead> successfulLeads = new List<Lead>();
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    leadsCreatedCount++;
                    createdLeadIds.add(results[i].getId());
                    leadsToCreate[i].Id = results[i].getId();
                    successfulLeads.add(leadsToCreate[i]);
                }
            }
            
            // DIRECT UPDATE LOOP - Assign Greg and Anthony to legal-positives leads
            if (!successfulLeads.isEmpty()) {
                updateLeadsToGregAndAnthony(successfulLeads);
            }
        }
        
        Map<String, Object> resultMap = new Map<String, Object>();
        resultMap.put('leadsCreated', leadsCreatedCount);
        resultMap.put('createdLeadIds', createdLeadIds);
        
        return resultMap;
    }
    
    // DIRECT UPDATE LOOP - Simple assignment to Greg and Anthony for legal-positives
    private static void updateLeadsToGregAndAnthony(List<Lead> leads) {
        try {
            // Anthony and Greg User IDs
            String anthonyId = '005fK000001ON1J';
            String gregId = '005fK000001OMWf';
            
            System.debug('*** STARTING DIRECT UPDATE FOR ' + leads.size() + ' LEGAL-POSITIVES LEADS ***');
            
            // DIRECT LOOP - Update each lead one by one
            for (Integer i = 0; i < leads.size(); i++) {
                try {
                    Lead leadToUpdate = new Lead();
                    leadToUpdate.Id = leads[i].Id;
                    
                    // Alternate between Anthony and Greg
                    if (Math.mod(i, 2) == 0) {
                        leadToUpdate.OwnerId = anthonyId; // Anthony
                        System.debug('Updating Lead ' + leadToUpdate.Id + ' to Anthony: ' + anthonyId);
                    } else {
                        leadToUpdate.OwnerId = gregId; // Greg  
                        System.debug('Updating Lead ' + leadToUpdate.Id + ' to Greg: ' + gregId);
                    }
                    
                    // INDIVIDUAL UPDATE - No assignment rules
                    Database.DMLOptions dmlOpts = new Database.DMLOptions();
                    dmlOpts.assignmentRuleHeader.useDefaultRule = false;
                    
                    Database.SaveResult result = Database.update(leadToUpdate, dmlOpts);
                    
                    if (result.isSuccess()) {
                        System.debug('✅ SUCCESS: Lead ' + leadToUpdate.Id + ' updated to owner ' + leadToUpdate.OwnerId);
                    } else {
                        System.debug('❌ FAILED: Lead ' + leadToUpdate.Id + ' update failed');
                        for (Database.Error err : result.getErrors()) {
                            System.debug('   Error: ' + err.getStatusCode() + ' - ' + err.getMessage());
                        }
                    }
                    
                } catch (Exception e) {
                    System.debug('❌ Exception updating lead ' + leads[i].Id + ': ' + e.getMessage());
                }
            }
            
            System.debug('*** DIRECT UPDATE COMPLETE ***');
            
        } catch (Exception e) {
            System.debug('❌ MAIN EXCEPTION: ' + e.getMessage());
        }
    }
    
    // Pre-load Users for Round Robin - UPDATED: Only Sales_Rep_Debtifi
    private static void preloadUsersForRoundRobin() {
        try {
            // Only query if not already cached
            if (cachedUsersMap.isEmpty()) {
                // Single optimized SOQL query - UPDATED: Only Sales_Rep_Debtifi
                List<User> allUsers = [
                    SELECT Id, Name, UserRole.Name 
                    FROM User 
                    WHERE IsActive = true 
                    AND UserRole.Name LIKE '%Sales_Rep_Debtifi%'
                    ORDER BY UserRole.Name, Name
                    LIMIT 50
                ];
                
                // Group users by role - optimized loop
                for (User u : allUsers) {
                    String roleName = u.UserRole?.Name;
                    
                    // Normalize role name for mapping - UPDATED: Only Debtifi
                    String normalizedRole = '';
                    if (roleName != null && roleName.contains('Debtifi')) {
                        normalizedRole = 'Sales_Rep_Debtifi';
                    }
                    
                    if (String.isNotBlank(normalizedRole)) {
                        if (!cachedUsersMap.containsKey(normalizedRole)) {
                            cachedUsersMap.put(normalizedRole, new List<User>());
                        }
                        cachedUsersMap.get(normalizedRole).add(u);
                    }
                }
            }
        } catch (Exception e) {
            // Silent fail to reduce CPU overhead
        }
    }
    
    // Round Robin Assignment Method - UPDATED: Only Sales_Rep_Debtifi
    private static void assignLeadOwnerRoundRobin(Lead lead, String criteriaValue) {
        try {
            // Quick exit if no criteria
            if (String.isBlank(criteriaValue)) {
                return;
            }
            
            String roleName = '';
            String criteriaLower = criteriaValue.toLowerCase();
            
            // Simple contains check - UPDATED: Both conditions now go to Sales_Rep_Debtifi
            if (criteriaLower.contains('qrmca')) {
                roleName = 'Sales_Rep_Debtifi';
            } else if (criteriaLower.contains('everyday')) {
                roleName = 'Sales_Rep_Debtifi';
            } else {
                return; // No match, exit early
            }
            
            // Get cached users for the role
            List<User> activeUsersInRole = cachedUsersMap.get(roleName);
            
            if (activeUsersInRole == null || activeUsersInRole.isEmpty()) {
                return; // No users, exit early
            }
            
            // Get current counter for this role
            Integer currentCounter = roundRobinCounters.get(roleName);
            if (currentCounter == null) {
                currentCounter = 0;
            }
            
            // Calculate next user index using modulo for round robin
            Integer userIndex = Math.mod(currentCounter, activeUsersInRole.size());
            
            // Assign the lead owner
            lead.OwnerId = activeUsersInRole[userIndex].Id;
            
            // Increment counter for next assignment
            roundRobinCounters.put(roleName, currentCounter + 1);
            
        } catch (Exception e) {
            // Silent fail to avoid CPU overhead
        }
    }
    
    private static String getStringValue(Map<String, Object> record, String fieldName) {
        Object value = record.get(fieldName);
        String result = (value != null) ? String.valueOf(value) : '';
        
        // Truncate very long individual field values to prevent field overflow
        if (result.length() > 500) {
            result = result.substring(0, 497) + '...';
        }
        
        return result;
    }
    
    private static void initializeOutputCollections(DCGFlowOutput output) {
        // SMS/Positives collections
        output.allPhoneNumbers = new List<String>();
        output.allMessages = new List<String>();
        output.allUserIds = new List<String>();
        output.allUsernames = new List<String>();
        output.allSentiments = new List<String>();
        output.allConfidenceScores = new List<String>();
        output.allGroupNames = new List<String>();
        output.allSentDates = new List<String>();
        output.allMessageIds = new List<String>();
        output.allStatuses = new List<String>();
        output.allSmsIds = new List<String>();
        output.allSentFroms = new List<String>();
        output.allMessageHashes = new List<String>();
        
        // Legal collections
        output.allCompanyNames = new List<String>();
        output.allContactNames = new List<String>();
        output.allEmailAddresses = new List<String>();
        output.allLegalPhoneNumbers = new List<String>();
        output.allMailingAddresses = new List<String>();
        output.allTaxIds = new List<String>();
        output.allAmountsSuedFor = new List<String>();
        output.allAmountsPaid = new List<String>();
        output.allLawyers = new List<String>();
        output.allPdfFiles = new List<String>();
        output.allUploadDates = new List<String>();
        
        // Default values
        if (output.totalRecordsRetrieved == null) output.totalRecordsRetrieved = 0;
        if (output.leadsCreated == null) output.leadsCreated = 0;
        if (output.createdLeadIds == null) output.createdLeadIds = new List<String>();
    }
}