public class IntegrationLogUtil {

    private static final Integer MAX_REQUEST_SIZE = 10000;
    private static final Integer MAX_RESPONSE_SIZE = 50000;
	private static final Integer MAX_EXCEPTION_SIZE = 30000;

    public enum LogStatus { Success, Failure }

    private static List<Integration_Log__c> pendingLogs = new List<Integration_Log__c>();

    private static Map<String, Map<String, Object>> loggingSettingsCache =
        new Map<String, Map<String, Object>>();
    private static Map<String, Map<String, String>> metadataObjectMap =
        new Map<String, Map<String, String>>();

    // ------------------------------------------------------------
    // WRAPPER FOR LOG INPUT
    // ------------------------------------------------------------
    public class LogInput {
        public String settingsMetadataType;
        public String objectMetadataType;
        public Id recordId;
        public String methodName;
        public String requestBody;
        public String responseBody;
        public Integer httpStatusCode;
		public String exceptionMsg;
        public LogStatus status;
    }

    // ------------------------------------------------------------
    // PUBLIC SAFE ENTRYPOINT
    // ------------------------------------------------------------
    public static Integration_Log__c createLog(LogInput input) {

        if (input == null) return null;
        if (String.isBlank(input.settingsMetadataType)) return null;
        if (String.isBlank(input.objectMetadataType)) return null;
        if (input.status == null) return null;

        return createLog(
            input.settingsMetadataType,
            input.objectMetadataType,
            input.methodName,
            input.recordId,
            input.requestBody,
            input.responseBody,
            input.httpStatusCode,
			input.exceptionMsg,
            input.status
        );
    }

    // ------------------------------------------------------------
    // INTERNAL LOG CREATION ENGINE
    // ------------------------------------------------------------
    private static Integration_Log__c createLog(
        String settingsMetadataType,
        String objectMetadataType,
        String methodName,
        Id recordId,
        String requestBody,
        String responseBody,
        Integer httpStatusCode,
		String exceptionMsg,
        LogStatus status
    ) {
        Map<String, Object> settings = getDynamicSettings(settingsMetadataType);
        if (!shouldLog(settings, status)) return null;

        Integration_Log__c log = new Integration_Log__c();
        log.System__c = (String)settings.get('System_Name__c');
        log.Method__c = methodName;
        log.HTTP_Response_Code__c = String.valueOf(httpStatusCode);
        log.Status__c = status.name();
        log.Request__c = truncate(requestBody, MAX_REQUEST_SIZE);
        log.Response__c = truncate(responseBody, MAX_RESPONSE_SIZE);
		log.Exception_Message__c = truncate(exceptionMsg, MAX_EXCEPTION_SIZE);

        setRelatedRecordLookup(settingsMetadataType, objectMetadataType, recordId, log);

        pendingLogs.add(log);
        return log;
    }

    // ------------------------------------------------------------
    // BULK INSERT ONCE
    // ------------------------------------------------------------
    public static void flush() {
        if (!pendingLogs.isEmpty()) {
            try {
                insert pendingLogs;
            } catch (Exception ex) {
                System.debug('❌ Log insert failed: ' + ex.getMessage());
            }
            pendingLogs.clear();
        }
    }

    // ------------------------------------------------------------
    // DYNAMIC OBJECT LOOKUP FIELD MAPPING
    // ------------------------------------------------------------
    private static void setRelatedRecordLookup(
        String settingsMetadataType,
        String objectMetadataType,
        Id recordId,
        Integration_Log__c log
    ) {
        if (recordId == null) return;

        Map<String, String> mapping =
            getObjectFieldMapping(settingsMetadataType, objectMetadataType);

        String objectApi = recordId.getSobjectType().getDescribe().getName();
        if (mapping.containsKey(objectApi)) {
            log.put(mapping.get(objectApi), recordId);
        }
    }

    private static Map<String, String> getObjectFieldMapping(String settingsMetadataType, String objectMetadataType) {
        String cacheKey = settingsMetadataType + ':' + objectMetadataType;
        if (metadataObjectMap.containsKey(cacheKey))
            return metadataObjectMap.get(cacheKey);

        Map<String, String> mapping = new Map<String, String>();

		// Derive lookup field name dynamically from metadata type
		String settingsLookupField =
			settingsMetadataType.replace('__mdt', '__c');

		String soql =
			'SELECT Object__c, API_Name__c ' +
			'FROM ' + objectMetadataType + ' ' +
			'WHERE ' + settingsLookupField + ' IN (' +
				'SELECT Id FROM ' + settingsMetadataType +
			')';

        for (SObject row : Database.query(soql)) {
            mapping.put(
                (String)row.get('Object__c'),
                (String)row.get('API_Name__c')
            );
        }

        metadataObjectMap.put(cacheKey, mapping);
        return mapping;
    }

    // ------------------------------------------------------------
    // SETTINGS METADATA — SYSTEM + FLAGS
    // ------------------------------------------------------------
    private static Map<String, Object> getDynamicSettings(String metadataType) {

        if (loggingSettingsCache.containsKey(metadataType))
            return loggingSettingsCache.get(metadataType);

        Map<String, Object> out = null;

        try {
            String soql =
                'SELECT Log_Integration_Success_Records__c,' +
                       'Log_Integration_Failure_Records__c,' +
                       'System_Name__c ' +
                'FROM ' + metadataType + ' LIMIT 1';

            SObject rec = Database.query(soql);
            out = rec.getPopulatedFieldsAsMap();

        } catch (Exception ex) {
            System.debug('⚠ Settings metadata lookup failed: ' + ex.getMessage());
        }

        loggingSettingsCache.put(metadataType, out);
        return out;
    }

    private static Boolean shouldLog(Map<String, Object> settings, LogStatus status) {
        if (settings == null) return true;
        return (status == LogStatus.Success &&
                (Boolean)settings.get('Log_Integration_Success_Records__c'))
            || (status == LogStatus.Failure &&
                (Boolean)settings.get('Log_Integration_Failure_Records__c'));
    }

    // ------------------------------------------------------------
    // UTILITIES
    // ------------------------------------------------------------
    private static String truncate(String val, Integer max) {
        if (String.isBlank(val)) return val;
        return val.length() > max ? val.substring(0, max) : val;
    }

    public static void clear() {
        pendingLogs.clear();
        loggingSettingsCache.clear();
        metadataObjectMap.clear();
    }

	/**
 * Returns all populated fields for the first record
 * of a given Custom Metadata Type as a Map<APIName, Value>.
 *
 * Supports future fields automatically.
 */
public static Map<String, Object> getMetadataFieldValues(String metadataType) {

    if (String.isBlank(metadataType)) return null;

    // Reuse existing cache if available
    if (loggingSettingsCache.containsKey(metadataType)) {
        return loggingSettingsCache.get(metadataType);
    }

    Map<String, Object> result;

    try {
        // Describe the metadata type to get all fields
        Schema.SObjectType sObjType =
            Schema.getGlobalDescribe().get(metadataType);

        if (sObjType == null) {
            throw new IllegalArgumentException('Invalid metadata type: ' + metadataType);
        }

        Map<String, Schema.SObjectField> fieldMap =
            sObjType.getDescribe().fields.getMap();

        // Build dynamic SELECT with all fields
        List<String> fieldNames = new List<String>();
        for (String fieldName : fieldMap.keySet()) {
            fieldNames.add(fieldName);
        }

        String soql =
            'SELECT ' + String.join(fieldNames, ', ') +
            ' FROM ' + metadataType +
            ' LIMIT 1';

        SObject rec = Database.query(soql);

        // Only return populated fields
        result = rec.getPopulatedFieldsAsMap();

    } catch (Exception ex) {
        System.debug('⚠ Metadata field extraction failed: ' + ex.getMessage());
        result = null;
    }

    loggingSettingsCache.put(metadataType, result);
    return result;
}


    // ------------------------------------------------------------
    // FLUENT BUILDER SYNTAX
    // ------------------------------------------------------------
    public class LogBuilder {
        private LogInput input = new LogInput();
        public LogBuilder settings(String v){ input.settingsMetadataType=v; return this; }
        public LogBuilder objectMeta(String v){ input.objectMetadataType=v; return this; }
        public LogBuilder record(Id v){ input.recordId=v; return this; }
        public LogBuilder method(String v){ input.methodName=v; return this; }
        public LogBuilder request(String v){ input.requestBody=v; return this; }
        public LogBuilder response(String v){ input.responseBody=v; return this; }
        public LogBuilder httpCode(Integer v){ input.httpStatusCode=v; return this; }
		public LogBuilder exceptionMsg(String v) { input.exceptionMsg=v; return this; }
        public LogBuilder status(LogStatus v){ input.status=v; return this; }
        public LogInput build(){ return input; }
    }

    public static LogBuilder logBuilder() {
        return new LogBuilder();
    }
}