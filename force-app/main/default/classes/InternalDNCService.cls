/**
 * @description Service class to handle Internal DNC (Do Not Call) API integration
 * Adds phone numbers to the internal DNC list when Opportunities reach specific stages
 * Target Stages: Contract Signed, Enrolled, NSF, Cancelled
 */
public with sharing class InternalDNCService {

    // API Configuration
    private static final String API_ENDPOINT = 'https://9bggwo0fq8.execute-api.us-east-1.amazonaws.com/Prod/salesforce/opportunity/phones';
    private static final String AUTH_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiIwN2E4MjgxYi0zOTUzLTRlYTEtODE0Ni1hMGU0NzZkMDRiNjQiLCJjb21wYW55IjoiZGNnIiwicm9sZSI6ImFkbWluIiwic291cmNlIjoic2FsZXNmb3JjZSIsImlhdCI6MTc2NTM4MDA4N30.3_jge5tDcROfnOXztw8Zns_-pGaSborYUhR5dkD-wEo';

    // Debug symbols for formatted logging
    private static final String LOG_PREFIX = '[DNC API]';
    private static final String SYMBOL_SUCCESS = '[SUCCESS]';
    private static final String SYMBOL_ERROR = '[ERROR]';
    private static final String SYMBOL_WARNING = '[WARNING]';
    private static final String SYMBOL_INFO = '[INFO]';
    private static final String SYMBOL_REQUEST = '[REQUEST]';
    private static final String SYMBOL_RESPONSE = '[RESPONSE]';
    private static final String LINE_SEPARATOR = '════════════════════════════════════════════════════════════';
    private static final String SECTION_SEPARATOR = '────────────────────────────────────────────────────────────';

    // Target stages that should trigger DNC API call
    public static final Set<String> DNC_TRIGGER_STAGES = new Set<String>{
        'Contract Signed',
        'Enrolled',
        'NSF',
        'Cancelled'
    };

    /**
     * @description Response wrapper class for API results
     */
    public class DNCResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer totalProcessed;
        @AuraEnabled public Integer added;
        @AuraEnabled public Integer skipped;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Integer statusCode;
    }

    /**
     * @description Sends a single phone number to the DNC API
     * @param phoneNumber The phone number to add to DNC list
     * @return DNCResponse with the result of the API call
     */
    public static DNCResponse sendPhoneToDNC(String phoneNumber) {
        return sendPhonesToDNC(new List<String>{ phoneNumber });
    }

    /**
     * @description Sends multiple phone numbers to the DNC API
     * @param phoneNumbers List of phone numbers to add to DNC list
     * @return DNCResponse with the result of the API call
     */
    public static DNCResponse sendPhonesToDNC(List<String> phoneNumbers) {
        DNCResponse response = new DNCResponse();
        Long startTime = System.currentTimeMillis();

        logInfo('Starting DNC API Call');
        logDebug(SECTION_SEPARATOR);
        logDebug(SYMBOL_INFO + ' Phone Numbers Received: ' + phoneNumbers.size());

        // Filter out null/empty phone numbers
        List<String> validPhones = new List<String>();
        for (String phone : phoneNumbers) {
            if (String.isNotBlank(phone)) {
                validPhones.add(phone);
            }
        }

        logDebug(SYMBOL_INFO + ' Valid Phone Numbers: ' + validPhones.size());

        if (validPhones.isEmpty()) {
            response.success = false;
            response.message = 'No valid phone numbers provided';
            response.errorMessage = 'No valid phone numbers provided';
            logWarning('No valid phone numbers provided - aborting API call');
            return response;
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(API_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Authorization', 'Bearer ' + AUTH_TOKEN);
            req.setTimeout(120000); // 2 minute timeout

            // Build request body
            Map<String, Object> requestBody = new Map<String, Object>();
            if (validPhones.size() == 1) {
                requestBody.put('phones', validPhones[0]);
            } else {
                requestBody.put('phones', validPhones);
            }
            String requestBodyJson = JSON.serialize(requestBody);
            req.setBody(requestBodyJson);

            // Log request details
            logDebug(SECTION_SEPARATOR);
            logDebug(SYMBOL_REQUEST + ' API Request Details:');
            logDebug('  -> Endpoint: ' + API_ENDPOINT);
            logDebug('  -> Method: POST');
            logDebug('  -> Phone Count: ' + validPhones.size());
            logDebug('  -> Phones: ' + String.join(validPhones, ', '));

            Http http = new Http();
            HttpResponse res = http.send(req);

            response.statusCode = res.getStatusCode();
            Long endTime = System.currentTimeMillis();
            Long duration = endTime - startTime;

            // Log response details
            logDebug(SECTION_SEPARATOR);
            logDebug(SYMBOL_RESPONSE + ' API Response Details:');
            logDebug('  -> Status Code: ' + res.getStatusCode());
            logDebug('  -> Duration: ' + duration + 'ms');

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                response.success = (Boolean) responseMap.get('success');
                response.message = (String) responseMap.get('message');

                Map<String, Object> summary = (Map<String, Object>) responseMap.get('summary');
                if (summary != null) {
                    response.totalProcessed = (Integer) summary.get('total');
                    response.added = (Integer) summary.get('added');
                    response.skipped = (Integer) summary.get('skipped');
                }

                // Log success details
                logSuccess('API call completed successfully');
                logDebug('  -> Total Processed: ' + response.totalProcessed);
                logDebug('  -> Numbers Added: ' + response.added);
                logDebug('  -> Numbers Skipped: ' + response.skipped);
            } else {
                response.success = false;
                Map<String, Object> errorMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                response.errorMessage = (String) errorMap.get('error');
                response.message = 'API Error: ' + response.errorMessage;

                // Log error details
                logError('API returned error status');
                logDebug('  -> Status Code: ' + res.getStatusCode());
                logDebug('  -> Error Message: ' + response.errorMessage);
                logDebug('  -> Response Body: ' + res.getBody());
            }

        } catch (System.CalloutException ce) {
            response.success = false;
            response.errorMessage = ce.getMessage();
            response.message = 'Callout Exception: ' + ce.getMessage();
            logException('CalloutException', ce);
        } catch (System.JSONException je) {
            response.success = false;
            response.errorMessage = je.getMessage();
            response.message = 'JSON Parse Exception: ' + je.getMessage();
            logException('JSONException', je);
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = e.getMessage();
            response.message = 'Exception: ' + e.getMessage();
            logException('General Exception', e);
        }

        logDebug(LINE_SEPARATOR);
        return response;
    }

    /**
     * @description Logs info message with formatting
     */
    private static void logInfo(String message) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' ' + SYMBOL_INFO + ' ' + message);
    }

    /**
     * @description Logs debug message with formatting
     */
    private static void logDebug(String message) {
        System.debug(LoggingLevel.DEBUG, LOG_PREFIX + ' ' + message);
    }

    /**
     * @description Logs success message with formatting
     */
    private static void logSuccess(String message) {
        System.debug(LoggingLevel.INFO, LOG_PREFIX + ' ' + SYMBOL_SUCCESS + ' ' + message);
    }

    /**
     * @description Logs warning message with formatting
     */
    private static void logWarning(String message) {
        System.debug(LoggingLevel.WARN, LOG_PREFIX + ' ' + SYMBOL_WARNING + ' ' + message);
    }

    /**
     * @description Logs error message with formatting
     */
    private static void logError(String message) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + SYMBOL_ERROR + ' ' + message);
    }

    /**
     * @description Logs exception with full details
     */
    private static void logException(String exceptionType, Exception e) {
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + LINE_SEPARATOR);
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + SYMBOL_ERROR + ' EXCEPTION OCCURRED');
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + SECTION_SEPARATOR);
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + '   Type: ' + exceptionType);
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + '   Message: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + '   Line Number: ' + e.getLineNumber());
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + '   Stack Trace: ' + e.getStackTraceString());
        System.debug(LoggingLevel.ERROR, LOG_PREFIX + ' ' + LINE_SEPARATOR);
    }

    /**
     * @description Future method to send phone to DNC API asynchronously
     * Used for single record operations from triggers/flows
     * @param phoneNumber The phone number to send
     * @param opportunityId The Opportunity ID for logging purposes
     */
    @future(callout=true)
    public static void sendPhoneToDNCAsync(String phoneNumber, Id opportunityId) {
        logInfo('Async DNC Call Started for Opportunity: ' + opportunityId);
        logDebug('  -> Phone Number: ' + phoneNumber);

        DNCResponse response = sendPhoneToDNC(phoneNumber);

        if (response.success) {
            logSuccess('Async DNC Call Completed for Opportunity: ' + opportunityId);
        } else {
            logError('Async DNC Call Failed for Opportunity: ' + opportunityId);
            logDebug('  -> Error: ' + response.errorMessage);
        }
    }

    /**
     * @description Future method to send multiple phones to DNC API asynchronously
     * Used for bulk operations
     * @param phoneNumbers JSON serialized list of phone numbers
     */
    @future(callout=true)
    public static void sendPhonesToDNCAsync(String phoneNumbersJson) {
        logInfo('Bulk Async DNC Call Started');

        List<String> phoneNumbers = (List<String>) JSON.deserialize(phoneNumbersJson, List<String>.class);
        logDebug('  -> Phone Count: ' + phoneNumbers.size());

        DNCResponse response = sendPhonesToDNC(phoneNumbers);

        if (response.success) {
            logSuccess('Bulk Async DNC Call Completed');
            logDebug('  -> Added: ' + response.added + ', Skipped: ' + response.skipped);
        } else {
            logError('Bulk Async DNC Call Failed');
            logDebug('  -> Error: ' + response.errorMessage);
        }
    }

    /**
     * @description Checks if the given stage is a DNC trigger stage
     * @param stageName The stage name to check
     * @return True if the stage should trigger a DNC API call
     */
    public static Boolean isDNCTriggerStage(String stageName) {
        return DNC_TRIGGER_STAGES.contains(stageName);
    }

    /**
     * @description Checks if stage changed to a DNC trigger stage
     * @param oldStage The previous stage
     * @param newStage The new stage
     * @return True if the stage changed TO a DNC trigger stage (and wasn't already one)
     */
    public static Boolean stageChangedToDNCStage(String oldStage, String newStage) {
        return !DNC_TRIGGER_STAGES.contains(oldStage) && DNC_TRIGGER_STAGES.contains(newStage);
    }
}