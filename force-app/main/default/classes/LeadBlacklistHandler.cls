public class LeadBlacklistHandler {
    
    // API configuration
    private static final String API_BASE_URL = 'https://api.blacklistalliance.net/lookup';
    private static final String API_KEY = 'pXh4k4m9vt8vrAJ6DUND'; // Consider storing in Custom Metadata or Custom Settings
    
    public static void handleAfterInsert(List<Lead> newLeads) {
        System.debug('🚀 ═══════════════════════════════════════════════════════════════');
        System.debug('🚀 BLACKLIST HANDLER: Starting Lead processing after insert');
        System.debug('🚀 Total leads received: ' + newLeads.size());
        System.debug('🚀 ═══════════════════════════════════════════════════════════════');
        
        // Filter leads that have phone numbers and collect their IDs and phone numbers
        List<String> leadIds = new List<String>();
        List<String> phoneNumbers = new List<String>();
        
        Integer leadsWithPhone = 0;
        Integer leadsWithoutPhone = 0;
        
        for (Lead lead : newLeads) {
            if (String.isNotBlank(lead.Phone)) {
                leadIds.add(lead.Id);
                phoneNumbers.add(lead.Phone);
                leadsWithPhone++;
                System.debug('✅ Lead with phone found - ID: ' + lead.Id + ' | Phone: ' + lead.Phone);
            } else {
                leadsWithoutPhone++;
                System.debug('❌ Lead without phone skipped - ID: ' + lead.Id);
            }
        }
        
        System.debug('📊 ═══ FILTERING SUMMARY ═══');
        System.debug('📊 Leads with phone numbers: ' + leadsWithPhone);
        System.debug('📊 Leads without phone numbers: ' + leadsWithoutPhone);
        System.debug('📊 ═══════════════════════════');
        
        if (!leadIds.isEmpty()) {
            System.debug('🔄 Sending ' + leadIds.size() + ' leads for async processing...');
            // Process API calls asynchronously to avoid governor limits
            processLeadsAsync(leadIds, phoneNumbers);
        } else {
            System.debug('⚠️ No leads with phone numbers found - skipping async processing');
        }
        
        System.debug('🏁 BLACKLIST HANDLER: handleAfterInsert completed');
    }
    
    @future(callout=true)
    public static void processLeadsAsync(List<String> leadIds, List<String> phoneNumbers) {
        System.debug('⚡ ═══════════════════════════════════════════════════════════════');
        System.debug('⚡ ASYNC PROCESSING: Starting future method execution');
        System.debug('⚡ Processing ' + leadIds.size() + ' leads asynchronously');
        System.debug('⚡ ═══════════════════════════════════════════════════════════════');
        
        List<Lead> leadsToUpdate = new List<Lead>();
        Integer successfulApiCalls = 0;
        Integer failedApiCalls = 0;
        Integer goodNumbers = 0;
        Integer dncNumbers = 0;
        Integer leadsMarkedDNC = 0;
        
        for (Integer i = 0; i < leadIds.size(); i++) {
            String currentLeadId = leadIds[i];
            String currentPhone = phoneNumbers[i];
            
            System.debug('🔍 ─────────────────────────────────────────────────────────');
            System.debug('🔍 Processing Lead #' + (i + 1) + ' of ' + leadIds.size());
            System.debug('🔍 Lead ID: ' + currentLeadId);
            System.debug('🔍 Phone: ' + currentPhone);
            System.debug('🔍 ─────────────────────────────────────────────────────────');
            
            try {
                // Make API call for each lead
                BlacklistApiResponse response = callBlacklistApi(currentPhone);
                
                if (response != null) {
                    successfulApiCalls++;
                    System.debug('✅ API call successful for lead: ' + currentLeadId);
                    System.debug('📋 Response status: ' + response.status);
                    System.debug('📋 Response message: ' + response.message);
                    
                    if (response.status == 'success') {
                        // Check if message is NOT 'Good' (indicating DNC status)
                        if (String.isNotBlank(response.message) && response.message != 'Good') {
                            dncNumbers++;
                            leadsMarkedDNC++;
                            System.debug('🔴 DNC NUMBER DETECTED! Message: ' + response.message);
                            System.debug('🔴 Lead ' + currentLeadId + ' will be updated to DNC status');
                            
                            // Log additional details if available
                            if (response.code != null && !response.code.isEmpty()) {
                                System.debug('🔴 DNC Codes: ' + String.join(response.code, ', '));
                            }
                            
                            Lead leadToUpdate = new Lead(
                                Id = currentLeadId,
                                Pre_Deal_Status__c = 'DNC'
                            );
                            leadsToUpdate.add(leadToUpdate);
                        } else if (response.message == 'Good') {
                            goodNumbers++;
                            System.debug('🟢 GOOD NUMBER - No action needed');
                        } else {
                            System.debug('🟡 UNKNOWN MESSAGE STATUS: ' + response.message);
                        }
                    } else {
                        System.debug('❌ API returned non-success status: ' + response.status);
                    }
                } else {
                    failedApiCalls++;
                    System.debug('❌ API call failed for lead: ' + currentLeadId);
                }
            } catch (Exception e) {
                failedApiCalls++;
                // Log error but don't fail the entire process
                System.debug('💥 ═══ EXCEPTION OCCURRED ═══');
                System.debug('💥 Lead ID: ' + currentLeadId);
                System.debug('💥 Error: ' + e.getMessage());
                System.debug('💥 Line: ' + e.getLineNumber());
                System.debug('💥 Stack Trace: ' + e.getStackTraceString());
                System.debug('💥 ═══════════════════════════');
            }
        }
        
        System.debug('📊 ═══ API PROCESSING SUMMARY ═══');
        System.debug('📊 Total leads processed: ' + leadIds.size());
        System.debug('📊 Successful API calls: ' + successfulApiCalls);
        System.debug('📊 Failed API calls: ' + failedApiCalls);
        System.debug('📊 Good numbers: ' + goodNumbers);
        System.debug('📊 DNC numbers: ' + dncNumbers);
        System.debug('📊 Leads to mark as DNC: ' + leadsMarkedDNC);
        System.debug('📊 ═══════════════════════════════');
        
        // Update leads if any need to be updated
        if (!leadsToUpdate.isEmpty()) {
            System.debug('💾 Starting DML operation to update ' + leadsToUpdate.size() + ' leads...');
            try {
                update leadsToUpdate;
                System.debug('✅ Successfully updated ' + leadsToUpdate.size() + ' leads to DNC status');
                
                // Log each updated lead
                for (Lead updatedLead : leadsToUpdate) {
                    System.debug('✅ Lead updated - ID: ' + updatedLead.Id + ' | Status: DNC');
                }
            } catch (DmlException e) {
                System.debug('💥 ═══ DML EXCEPTION OCCURRED ═══');
                System.debug('💥 Error updating leads: ' + e.getMessage());
                System.debug('💥 Number of failed records: ' + e.getNumDml());
                for (Integer j = 0; j < e.getNumDml(); j++) {
                    System.debug('💥 Failed record index: ' + e.getDmlIndex(j));
                    System.debug('💥 Failed record error: ' + e.getDmlMessage(j));
                }
                System.debug('💥 ═══════════════════════════════');
            }
        } else {
            System.debug('ℹ️ No leads need to be updated');
        }
        
        System.debug('🏁 ═══════════════════════════════════════════════════════════════');
        System.debug('🏁 ASYNC PROCESSING: Future method execution completed');
        System.debug('🏁 ═══════════════════════════════════════════════════════════════');
    }
    
    private static BlacklistApiResponse callBlacklistApi(String phoneNumber) {
        System.debug('🌐 ═══ API CALL STARTING ═══');
        System.debug('🌐 Original phone number: ' + phoneNumber);
        
        // Clean phone number (remove non-digits)
        String cleanPhone = phoneNumber.replaceAll('[^0-9]', '');
        System.debug('🌐 Cleaned phone number: ' + cleanPhone);
        
        // Construct API URL
        String apiUrl = API_BASE_URL + '?key=' + API_KEY + '&phone=' + EncodingUtil.urlEncode(cleanPhone, 'UTF-8');
        System.debug('🌐 API URL: ' + apiUrl.replace(API_KEY, '***HIDDEN***')); // Hide API key in logs
        
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(apiUrl);
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(10000); // 10 second timeout
        
        System.debug('🌐 Request configured:');
        System.debug('🌐   Method: GET');
        System.debug('🌐   Timeout: 10000ms');
        System.debug('🌐   Accept: application/json');
        
        try {
            System.debug('🌐 Sending HTTP request...');
            Long startTime = System.currentTimeMillis();
            
            HttpResponse response = http.send(request);
            
            Long endTime = System.currentTimeMillis();
            Long responseTime = endTime - startTime;
            
            System.debug('🌐 HTTP response received in ' + responseTime + 'ms');
            System.debug('🌐 Response status code: ' + response.getStatusCode());
            System.debug('🌐 Response status: ' + response.getStatus());
            
            if (response.getStatusCode() == 200) {
                String responseBody = response.getBody();
                System.debug('🌐 Response body length: ' + responseBody.length() + ' characters');
                System.debug('🌐 Response body: ' + responseBody);
                
                try {
                    BlacklistApiResponse apiResponse = (BlacklistApiResponse) JSON.deserialize(responseBody, BlacklistApiResponse.class);
                    System.debug('✅ JSON deserialization successful');
                    System.debug('✅ Parsed response status: ' + apiResponse.status);
                    System.debug('✅ Parsed response message: ' + apiResponse.message);
                    
                    if (apiResponse.code != null && !apiResponse.code.isEmpty()) {
                        System.debug('✅ DNC codes found: ' + String.join(apiResponse.code, ', '));
                    }
                    
                    System.debug('🌐 ═══ API CALL SUCCESS ═══');
                    return apiResponse;
                } catch (JSONException je) {
                    System.debug('💥 JSON deserialization failed: ' + je.getMessage());
                    System.debug('💥 Raw response: ' + responseBody);
                    System.debug('🌐 ═══ API CALL FAILED ═══');
                    return null;
                }
            } else {
                System.debug('❌ API call failed with non-200 status');
                System.debug('❌ Status Code: ' + response.getStatusCode());
                System.debug('❌ Status: ' + response.getStatus());
                System.debug('❌ Response Body: ' + response.getBody());
                System.debug('🌐 ═══ API CALL FAILED ═══');
                return null;
            }
        } catch (CalloutException ce) {
            System.debug('💥 ═══ CALLOUT EXCEPTION ═══');
            System.debug('💥 Callout exception: ' + ce.getMessage());
            System.debug('💥 Exception type: ' + ce.getTypeName());
            System.debug('💥 Stack trace: ' + ce.getStackTraceString());
            System.debug('🌐 ═══ API CALL FAILED ═══');
            return null;
        } catch (Exception e) {
            System.debug('💥 ═══ GENERAL EXCEPTION ═══');
            System.debug('💥 General exception during API call: ' + e.getMessage());
            System.debug('💥 Exception type: ' + e.getTypeName());
            System.debug('💥 Line number: ' + e.getLineNumber());
            System.debug('💥 Stack trace: ' + e.getStackTraceString());
            System.debug('🌐 ═══ API CALL FAILED ═══');
            return null;
        }
    }
    
    // Wrapper classes for API response
    public class BlacklistApiResponse {
        public String sid { get; set; }
        public String status { get; set; }
        public String message { get; set; }
        public List<String> code { get; set; } // Updated to List<String> for multiple codes
        public Long offset { get; set; }
        public String phone { get; set; }
        public Integer results { get; set; }
        public Integer timeValue { get; set; } // Changed from 'time' to avoid reserved word
        public CarrierInfo carrier { get; set; }
        public Boolean scrubs { get; set; }
    }
    
    public class CarrierInfo {
        public String did { get; set; }
        public String carrierType { get; set; } // Changed from 'type' to avoid reserved word
        public String name { get; set; }
        public String state { get; set; }
        public String ratecenter { get; set; }
        public String country { get; set; }
        public String clli { get; set; }
        public String lata { get; set; }
        public String wireless { get; set; }
        public String lrn { get; set; }
        public String npa { get; set; }
        public String nxx { get; set; }
        public String nxxx { get; set; }
        public String ocn { get; set; }
        public String port_type { get; set; }
    }
}