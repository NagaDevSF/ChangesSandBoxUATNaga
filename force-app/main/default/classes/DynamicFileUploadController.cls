/**
 * @description Controller for the Dynamic File Upload LWC component.
 *              Provides methods to discover available objects, retrieve field metadata,
 *              validate mapped Excel data against Salesforce field definitions, and
 *              create records with partial-success support.
 * @author      Naga / DCG Pro
 * @date        2026-03-25
 */
public with sharing class DynamicFileUploadController {

    // ============================================================
    // Logging Constants
    // ============================================================
    private static final String LOG_ENTRY   = '▶️';
    private static final String LOG_EXIT    = '◀️';
    private static final String LOG_ERROR   = '❌';
    private static final String LOG_WARN    = '⚠️';
    private static final String LOG_SUCCESS = '✅';
    private static final String LOG_DEBUG   = '🔧';
    private static final String LOG_PARAM   = '📋';
    private static final String LOG_QUERY   = '🔍';
    private static final String LOG_DML     = '💾';
    private static final String LOG_INFO    = 'ℹ️';

    // ============================================================
    // Constants
    // ============================================================
    private static final Integer MAX_UPLOAD_ROWS = 2000;

    // ============================================================
    // Wrapper DTOs
    // ============================================================

    /**
     * @description Represents an available SObject for the object selector dropdown.
     */
    public class ObjectOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Represents metadata for a single createable field on an SObject.
     */
    public class FieldMetadata {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Boolean isRequired;
        @AuraEnabled public Boolean isCreateable;
        @AuraEnabled public Integer maxLength;
        @AuraEnabled public Integer precision;
        @AuraEnabled public Integer scale;
        @AuraEnabled public List<PicklistOption> picklistValues;
        @AuraEnabled public String referenceTo;
    }

    /**
     * @description Represents a single picklist entry.
     */
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Deserialized representation of a single row sent from the LWC.
     *              fieldValues keys are Salesforce field API names; values are string
     *              representations from the Excel file.
     */
    public class MappedRow {
        public Integer rowIndex;
        public Map<String, String> fieldValues;
    }

    /**
     * @description Deserialized representation of a column-to-field mapping from the LWC.
     */
    public class FieldMapping {
        public String excelColumn;
        public String salesforceField;
    }

    /**
     * @description Response wrapper returned by validateMappedData.
     */
    public class ValidationResponse {
        @AuraEnabled public Integer totalRows;
        @AuraEnabled public Integer validCount;
        @AuraEnabled public Integer invalidCount;
        @AuraEnabled public List<RowValidation> rows;
    }

    /**
     * @description Per-row validation result.
     */
    public class RowValidation {
        @AuraEnabled public Integer rowIndex;
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public Map<String, String> data;
    }

    /**
     * @description Response wrapper returned by createMappedRecords.
     */
    public class CreationResponse {
        @AuraEnabled public Integer totalRows;
        @AuraEnabled public Integer successCount;
        @AuraEnabled public Integer failureCount;
        @AuraEnabled public List<CreationRow> results;
    }

    /**
     * @description Per-row creation result.
     */
    public class CreationRow {
        @AuraEnabled public Integer rowIndex;
        @AuraEnabled public Boolean isSuccess;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String recordId;
        @AuraEnabled public String recordName;
    }

    // ============================================================
    // getAvailableObjects
    // ============================================================

    /**
     * @description Returns a sorted list of custom, createable, accessible SObjects
     *              for the object selector dropdown in the LWC.
     * @return      List<ObjectOption> sorted alphabetically by label
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAvailableObjects() {
        System.debug(LOG_ENTRY + ' getAvailableObjects — entering');
        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            System.debug(LOG_INFO + ' getAvailableObjects — total SObject types in org: ' + globalDescribe.size());

            // Build a map of label -> ObjectOption so we can sort by label
            Map<String, ObjectOption> optionsByLabel = new Map<String, ObjectOption>();

            for (String apiName : globalDescribe.keySet()) {
                Schema.DescribeSObjectResult descResult = globalDescribe.get(apiName).getDescribe();

                // Filter: must be custom, createable, and accessible
                if (descResult.isCustom() && descResult.isCreateable() && descResult.isAccessible()) {
                    ObjectOption opt = new ObjectOption();
                    opt.label = descResult.getLabel();
                    opt.value = descResult.getName(); // API name with proper casing
                    optionsByLabel.put(opt.label, opt);
                }
            }

            // Sort alphabetically by label
            List<String> sortedLabels = new List<String>(optionsByLabel.keySet());
            sortedLabels.sort();

            List<ObjectOption> result = new List<ObjectOption>();
            for (String lbl : sortedLabels) {
                result.add(optionsByLabel.get(lbl));
            }

            System.debug(LOG_SUCCESS + ' getAvailableObjects — returning ' + result.size() + ' objects');
            System.debug(LOG_EXIT + ' getAvailableObjects — exiting');
            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            System.debug(LOG_ERROR + ' getAvailableObjects — ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
            throw new AuraHandledException('Error retrieving available objects: ' + ex.getMessage());
        }
    }

    // ============================================================
    // getObjectFields
    // ============================================================

    /**
     * @description Returns createable field metadata for the specified SObject,
     *              including picklist values and reference targets where applicable.
     * @param       objectApiName API name of the target SObject
     * @return      List<FieldMetadata> sorted alphabetically by label
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldMetadata> getObjectFields(String objectApiName) {
        System.debug(LOG_ENTRY + ' getObjectFields — entering');
        System.debug(LOG_PARAM + ' getObjectFields — objectApiName: ' + objectApiName);
        try {
            // Validate input
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('Object API name is required.');
            }

            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }

            Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();
            System.debug(LOG_INFO + ' getObjectFields — total fields on ' + objectApiName + ': ' + fieldMap.size());

            // Build map keyed by label for alphabetical sorting
            Map<String, FieldMetadata> metadataByLabel = new Map<String, FieldMetadata>();

            for (String fieldKey : fieldMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldMap.get(fieldKey).getDescribe();

                // Only include createable fields
                if (!dfr.isCreateable()) {
                    continue;
                }

                FieldMetadata fm = new FieldMetadata();
                fm.apiName      = dfr.getName();
                fm.label        = dfr.getLabel();
                fm.fieldType    = String.valueOf(dfr.getType());
                fm.isRequired   = !dfr.isNillable() && dfr.isCreateable();
                fm.isCreateable = dfr.isCreateable();
                fm.maxLength    = dfr.getLength();
                fm.precision    = dfr.getPrecision();
                fm.scale        = dfr.getScale();

                // Picklist values — only for PICKLIST / MULTIPICKLIST
                Schema.DisplayType dt = dfr.getType();
                if (dt == Schema.DisplayType.PICKLIST || dt == Schema.DisplayType.MULTIPICKLIST) {
                    fm.picklistValues = new List<PicklistOption>();
                    for (Schema.PicklistEntry ple : dfr.getPicklistValues()) {
                        if (ple.isActive()) {
                            PicklistOption po = new PicklistOption();
                            po.label = ple.getLabel();
                            po.value = ple.getValue();
                            fm.picklistValues.add(po);
                        }
                    }
                }

                // Reference target — only for REFERENCE
                if (dt == Schema.DisplayType.REFERENCE) {
                    List<Schema.SObjectType> refs = dfr.getReferenceTo();
                    if (refs != null && !refs.isEmpty()) {
                        fm.referenceTo = refs[0].getDescribe().getName();
                    }
                }

                // Use label + apiName as key to handle duplicate labels safely
                metadataByLabel.put(fm.label + '|' + fm.apiName, fm);
            }

            // Sort by label alphabetically
            List<String> sortedKeys = new List<String>(metadataByLabel.keySet());
            sortedKeys.sort();

            List<FieldMetadata> result = new List<FieldMetadata>();
            for (String key : sortedKeys) {
                result.add(metadataByLabel.get(key));
            }

            System.debug(LOG_SUCCESS + ' getObjectFields — returning ' + result.size() + ' createable fields');
            System.debug(LOG_EXIT + ' getObjectFields — exiting');
            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            System.debug(LOG_ERROR + ' getObjectFields — ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
            throw new AuraHandledException('Error retrieving fields for ' + objectApiName + ': ' + ex.getMessage());
        }
    }

    // ============================================================
    // validateMappedData
    // ============================================================

    /**
     * @description Validates each mapped row against the target object's field metadata.
     *              Checks required fields, data types, lengths, picklist membership, and
     *              ID format. Does NOT query the database for reference existence.
     * @param       recordsJson       JSON string of List<MappedRow>
     * @param       objectApiName     Target SObject API name
     * @param       fieldMappingsJson JSON string of List<FieldMapping> (for reference)
     * @return      ValidationResponse with per-row results
     */
    @AuraEnabled
    public static ValidationResponse validateMappedData(String recordsJson, String objectApiName, String fieldMappingsJson) {
        System.debug(LOG_ENTRY + ' validateMappedData — entering');
        System.debug(LOG_PARAM + ' validateMappedData — objectApiName: ' + objectApiName);
        try {
            // Validate inputs
            if (String.isBlank(recordsJson)) {
                throw new AuraHandledException('Records JSON is required.');
            }
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('Object API name is required.');
            }

            // Deserialize rows
            List<MappedRow> rows = (List<MappedRow>) JSON.deserialize(recordsJson, List<MappedRow>.class);
            System.debug(LOG_INFO + ' validateMappedData — deserialized ' + rows.size() + ' rows');

            if (rows.size() > MAX_UPLOAD_ROWS) {
                throw new AuraHandledException(
                    'Too many rows (' + rows.size() + '). Maximum allowed is ' + MAX_UPLOAD_ROWS + '.'
                );
            }

            // Describe the target object once
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }
            Map<String, Schema.SObjectField> fieldTokenMap = sObjectType.getDescribe().fields.getMap();

            // Pre-build a set of required field API names (lowercase) and picklist value sets
            Map<String, Schema.DescribeFieldResult> describeCache = new Map<String, Schema.DescribeFieldResult>();
            Set<String> requiredFieldsLower = new Set<String>();
            Map<String, Set<String>> picklistValuesMap = new Map<String, Set<String>>();

            for (String fieldKey : fieldTokenMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldTokenMap.get(fieldKey).getDescribe();
                describeCache.put(dfr.getName().toLowerCase(), dfr);

                if (!dfr.isNillable() && dfr.isCreateable()) {
                    requiredFieldsLower.add(dfr.getName().toLowerCase());
                }

                // Cache picklist values for validation
                Schema.DisplayType dt = dfr.getType();
                if (dt == Schema.DisplayType.PICKLIST || dt == Schema.DisplayType.MULTIPICKLIST) {
                    Set<String> vals = new Set<String>();
                    for (Schema.PicklistEntry ple : dfr.getPicklistValues()) {
                        if (ple.isActive()) {
                            vals.add(ple.getValue());
                        }
                    }
                    picklistValuesMap.put(dfr.getName().toLowerCase(), vals);
                }
            }

            // Validate each row
            Integer validCount = 0;
            Integer invalidCount = 0;
            List<RowValidation> rowValidations = new List<RowValidation>();

            for (MappedRow row : rows) {
                RowValidation rv = new RowValidation();
                rv.rowIndex = row.rowIndex;
                rv.errors   = new List<String>();
                rv.data     = row.fieldValues != null ? row.fieldValues : new Map<String, String>();

                if (row.fieldValues == null || row.fieldValues.isEmpty()) {
                    rv.errors.add('Row has no field values.');
                    rv.isValid = false;
                    invalidCount++;
                    rowValidations.add(rv);
                    continue;
                }

                // Collect the set of mapped field names (lowercase) for required-field checks
                Set<String> mappedFieldsLower = new Set<String>();
                for (String fieldApiName : row.fieldValues.keySet()) {
                    if (String.isNotBlank(fieldApiName)) {
                        mappedFieldsLower.add(fieldApiName.toLowerCase());
                    }
                }

                // Check required fields that are mapped but have blank values
                for (String fieldApiName : row.fieldValues.keySet()) {
                    if (String.isBlank(fieldApiName)) {
                        continue;
                    }
                    String fieldLower = fieldApiName.toLowerCase();
                    String cellValue  = row.fieldValues.get(fieldApiName);

                    if (requiredFieldsLower.contains(fieldLower) && String.isBlank(cellValue)) {
                        Schema.DescribeFieldResult dfr = describeCache.get(fieldLower);
                        String fieldLabel = dfr != null ? dfr.getLabel() : fieldApiName;
                        rv.errors.add('Required field "' + fieldLabel + '" is blank.');
                    }
                }

                // Validate each field value against its type
                for (String fieldApiName : row.fieldValues.keySet()) {
                    if (String.isBlank(fieldApiName)) {
                        continue;
                    }
                    String cellValue = row.fieldValues.get(fieldApiName);

                    // Skip blank values — they won't be set on the SObject
                    if (String.isBlank(cellValue)) {
                        continue;
                    }

                    String fieldLower = fieldApiName.toLowerCase();
                    Schema.DescribeFieldResult dfr = describeCache.get(fieldLower);
                    if (dfr == null) {
                        rv.errors.add('Field "' + fieldApiName + '" does not exist on ' + objectApiName + '.');
                        continue;
                    }

                    String fieldLabel = dfr.getLabel();
                    Schema.DisplayType dt = dfr.getType();

                    // Type-specific validation
                    if (dt == Schema.DisplayType.STRING ||
                        dt == Schema.DisplayType.TEXTAREA ||
                        dt == Schema.DisplayType.URL ||
                        dt == Schema.DisplayType.EMAIL ||
                        dt == Schema.DisplayType.PHONE) {

                        // Check max length
                        Integer maxLen = dfr.getLength();
                        if (maxLen > 0 && cellValue.length() > maxLen) {
                            rv.errors.add('"' + fieldLabel + '" exceeds max length of ' + maxLen + ' (got ' + cellValue.length() + ').');
                        }

                    } else if (dt == Schema.DisplayType.DOUBLE ||
                               dt == Schema.DisplayType.CURRENCY ||
                               dt == Schema.DisplayType.PERCENT) {

                        try {
                            Decimal val = Decimal.valueOf(cellValue.trim());
                            // Check precision and scale if defined
                            Integer fieldPrecision = dfr.getPrecision();
                            Integer fieldScale     = dfr.getScale();
                            if (fieldPrecision > 0) {
                                Integer maxIntDigits = fieldPrecision - fieldScale;
                                Decimal absVal       = val.abs();
                                // Count integer digits
                                Long intPart         = absVal.longValue();
                                String intStr        = String.valueOf(intPart);
                                if (intStr.length() > maxIntDigits) {
                                    rv.errors.add('"' + fieldLabel + '" exceeds allowed precision (' + fieldPrecision + ',' + fieldScale + ').');
                                }
                            }
                        } catch (Exception ex) {
                            rv.errors.add('"' + fieldLabel + '" is not a valid number: ' + cellValue);
                        }

                    } else if (dt == Schema.DisplayType.INTEGER) {

                        try {
                            Integer.valueOf(cellValue.trim());
                        } catch (Exception ex) {
                            rv.errors.add('"' + fieldLabel + '" is not a valid integer: ' + cellValue);
                        }

                    } else if (dt == Schema.DisplayType.DATE) {

                        try {
                            Date.valueOf(cellValue.trim());
                        } catch (Exception ex) {
                            rv.errors.add('"' + fieldLabel + '" is not a valid date (expected yyyy-MM-dd): ' + cellValue);
                        }

                    } else if (dt == Schema.DisplayType.DATETIME) {

                        try {
                            DateTime.valueOf(cellValue.trim());
                        } catch (Exception ex) {
                            rv.errors.add('"' + fieldLabel + '" is not a valid datetime: ' + cellValue);
                        }

                    } else if (dt == Schema.DisplayType.BOOLEAN) {

                        String lower = cellValue.trim().toLowerCase();
                        if (lower != 'true' && lower != 'false') {
                            rv.errors.add('"' + fieldLabel + '" must be "true" or "false" (got "' + cellValue + '").');
                        }

                    } else if (dt == Schema.DisplayType.PICKLIST || dt == Schema.DisplayType.MULTIPICKLIST) {

                        Set<String> validValues = picklistValuesMap.get(fieldLower);
                        if (validValues != null && !validValues.contains(cellValue)) {
                            // For multipicklist, check each semicolon-delimited value
                            if (dt == Schema.DisplayType.MULTIPICKLIST) {
                                for (String part : cellValue.split(';')) {
                                    String trimmed = part.trim();
                                    if (String.isNotBlank(trimmed) && !validValues.contains(trimmed)) {
                                        rv.errors.add('"' + fieldLabel + '" contains invalid picklist value: "' + trimmed + '".');
                                    }
                                }
                            } else {
                                rv.errors.add('"' + fieldLabel + '" has invalid picklist value: "' + cellValue + '".');
                            }
                        }

                    } else if (dt == Schema.DisplayType.REFERENCE || dt == Schema.DisplayType.ID) {

                        // Validate Salesforce ID format (15 or 18 alphanumeric characters)
                        String trimmedVal = cellValue.trim();
                        if (trimmedVal.length() != 15 && trimmedVal.length() != 18) {
                            rv.errors.add('"' + fieldLabel + '" is not a valid Salesforce ID (must be 15 or 18 characters): ' + trimmedVal);
                        } else {
                            // Verify it can be cast to Id
                            try {
                                Id testId = Id.valueOf(trimmedVal);
                            } catch (Exception ex) {
                                rv.errors.add('"' + fieldLabel + '" is not a valid Salesforce ID: ' + trimmedVal);
                            }
                        }
                    }
                    // Other types (ENCRYPTEDSTRING, BASE64, etc.) — skip deep validation
                }

                rv.isValid = rv.errors.isEmpty();
                if (rv.isValid) {
                    validCount++;
                } else {
                    invalidCount++;
                }
                rowValidations.add(rv);
            }

            ValidationResponse response = new ValidationResponse();
            response.totalRows    = rows.size();
            response.validCount   = validCount;
            response.invalidCount = invalidCount;
            response.rows         = rowValidations;

            System.debug(LOG_SUCCESS + ' validateMappedData — valid: ' + validCount + ', invalid: ' + invalidCount);
            System.debug(LOG_EXIT + ' validateMappedData — exiting');
            return response;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            System.debug(LOG_ERROR + ' validateMappedData — ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
            throw new AuraHandledException('Validation error: ' + ex.getMessage());
        }
    }

    // ============================================================
    // createMappedRecords
    // ============================================================

    /**
     * @description Creates records from mapped Excel data with partial-success support.
     *              Converts string values to proper Apex types, performs a bulk insert,
     *              and returns per-row results. Uses a savepoint to rollback if ALL rows fail.
     * @param       recordsJson       JSON string of List<MappedRow>
     * @param       objectApiName     Target SObject API name
     * @param       fieldMappingsJson JSON string of List<FieldMapping> (for reference)
     * @return      CreationResponse with per-row results
     */
    @AuraEnabled
    public static CreationResponse createMappedRecords(String recordsJson, String objectApiName, String fieldMappingsJson) {
        System.debug(LOG_ENTRY + ' createMappedRecords — entering');
        System.debug(LOG_PARAM + ' createMappedRecords — objectApiName: ' + objectApiName);
        try {
            // Validate inputs
            if (String.isBlank(recordsJson)) {
                throw new AuraHandledException('Records JSON is required.');
            }
            if (String.isBlank(objectApiName)) {
                throw new AuraHandledException('Object API name is required.');
            }

            // Deserialize rows
            List<MappedRow> rows = (List<MappedRow>) JSON.deserialize(recordsJson, List<MappedRow>.class);
            System.debug(LOG_INFO + ' createMappedRecords — deserialized ' + rows.size() + ' rows');

            if (rows.size() > MAX_UPLOAD_ROWS) {
                throw new AuraHandledException(
                    'Too many rows (' + rows.size() + '). Maximum allowed is ' + MAX_UPLOAD_ROWS + '.'
                );
            }

            // Get SObjectType and field describe map (single describe call)
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }

            Map<String, Schema.SObjectField> fieldTokenMap = sObjectType.getDescribe().fields.getMap();
            Map<String, Schema.DescribeFieldResult> describeCache = new Map<String, Schema.DescribeFieldResult>();
            for (String fieldKey : fieldTokenMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldTokenMap.get(fieldKey).getDescribe();
                describeCache.put(dfr.getName().toLowerCase(), dfr);
            }

            // Build SObjects and track conversion errors per row
            List<SObject> recordsToInsert    = new List<SObject>();
            List<Integer> insertRowIndices    = new List<Integer>(); // parallel list tracking which row each SObject belongs to
            List<CreationRow> conversionErrors = new List<CreationRow>();

            for (MappedRow row : rows) {
                if (row.fieldValues == null || row.fieldValues.isEmpty()) {
                    CreationRow cr = new CreationRow();
                    cr.rowIndex     = row.rowIndex;
                    cr.isSuccess    = false;
                    cr.errorMessage = 'Row has no field values.';
                    conversionErrors.add(cr);
                    continue;
                }

                SObject record = sObjectType.newSObject();
                List<String> rowErrors = new List<String>();

                for (String fieldApiName : row.fieldValues.keySet()) {
                    if (String.isBlank(fieldApiName)) {
                        continue;
                    }

                    String cellValue = row.fieldValues.get(fieldApiName);

                    // Skip blank values — do not attempt conversion
                    if (String.isBlank(cellValue)) {
                        continue;
                    }

                    String fieldLower = fieldApiName.toLowerCase();
                    Schema.DescribeFieldResult dfr = describeCache.get(fieldLower);
                    if (dfr == null) {
                        rowErrors.add('Field "' + fieldApiName + '" not found on ' + objectApiName + '.');
                        continue;
                    }

                    // Convert string value to the proper Apex type
                    try {
                        Object convertedValue = convertStringToFieldValue(cellValue, dfr);
                        record.put(dfr.getName(), convertedValue);
                    } catch (Exception ex) {
                        rowErrors.add('Field "' + dfr.getLabel() + '": ' + ex.getMessage());
                    }
                }

                if (!rowErrors.isEmpty()) {
                    CreationRow cr = new CreationRow();
                    cr.rowIndex     = row.rowIndex;
                    cr.isSuccess    = false;
                    cr.errorMessage = String.join(rowErrors, '; ');
                    conversionErrors.add(cr);
                } else {
                    recordsToInsert.add(record);
                    insertRowIndices.add(row.rowIndex);
                }
            }

            System.debug(LOG_INFO + ' createMappedRecords — records to insert: ' + recordsToInsert.size()
                         + ', conversion errors: ' + conversionErrors.size());

            // Perform DML with partial success
            List<CreationRow> dmlResults = new List<CreationRow>();
            Integer dmlSuccessCount  = 0;
            Integer dmlFailureCount  = 0;

            if (!recordsToInsert.isEmpty()) {
                // Set savepoint so we can rollback if ALL records fail
                Savepoint sp = Database.setSavepoint();
                System.debug(LOG_DML + ' createMappedRecords — inserting ' + recordsToInsert.size() + ' records');

                List<Database.SaveResult> saveResults = Database.insert(recordsToInsert, false);

                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    CreationRow cr = new CreationRow();
                    cr.rowIndex = insertRowIndices[i];

                    if (sr.isSuccess()) {
                        cr.isSuccess  = true;
                        cr.recordId   = sr.getId();
                        // Attempt to get Name field value; fall back to record Id
                        try {
                            Object nameVal = recordsToInsert[i].get('Name');
                            cr.recordName = nameVal != null ? String.valueOf(nameVal) : sr.getId();
                        } catch (Exception ex) {
                            cr.recordName = sr.getId();
                        }
                        dmlSuccessCount++;
                    } else {
                        cr.isSuccess = false;
                        List<String> errMsgs = new List<String>();
                        for (Database.Error err : sr.getErrors()) {
                            errMsgs.add(err.getMessage());
                        }
                        cr.errorMessage = String.join(errMsgs, '; ');
                        dmlFailureCount++;
                    }
                    dmlResults.add(cr);
                }

                // If ALL DML rows failed, rollback
                if (dmlSuccessCount == 0 && dmlFailureCount > 0) {
                    System.debug(LOG_WARN + ' createMappedRecords — all DML rows failed, rolling back');
                    Database.rollback(sp);
                }
            }

            // Merge conversion errors + DML results and sort by rowIndex
            List<CreationRow> allResults = new List<CreationRow>();
            allResults.addAll(conversionErrors);
            allResults.addAll(dmlResults);

            // Sort results by rowIndex using a map
            Map<Integer, CreationRow> resultsByIndex = new Map<Integer, CreationRow>();
            List<Integer> allIndices = new List<Integer>();
            for (CreationRow cr : allResults) {
                resultsByIndex.put(cr.rowIndex, cr);
                allIndices.add(cr.rowIndex);
            }
            allIndices.sort();

            List<CreationRow> sortedResults = new List<CreationRow>();
            for (Integer idx : allIndices) {
                sortedResults.add(resultsByIndex.get(idx));
            }

            // Build response
            Integer totalSuccess = dmlSuccessCount;
            Integer totalFailure = conversionErrors.size() + dmlFailureCount;

            CreationResponse response = new CreationResponse();
            response.totalRows    = rows.size();
            response.successCount = totalSuccess;
            response.failureCount = totalFailure;
            response.results      = sortedResults;

            System.debug(LOG_SUCCESS + ' createMappedRecords — success: ' + totalSuccess + ', failure: ' + totalFailure);
            System.debug(LOG_EXIT + ' createMappedRecords — exiting');
            return response;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            System.debug(LOG_ERROR + ' createMappedRecords — ' + ex.getMessage() + ' | ' + ex.getStackTraceString());
            throw new AuraHandledException('Record creation error: ' + ex.getMessage());
        }
    }

    // ============================================================
    // Private Utility Methods
    // ============================================================

    /**
     * @description Converts a string value from Excel to the appropriate Apex type
     *              based on the Salesforce field's DisplayType.
     * @param       cellValue Raw string value from the Excel file
     * @param       dfr       DescribeFieldResult for the target field
     * @return      Object    Properly-typed Apex value ready for SObject.put()
     */
    private static Object convertStringToFieldValue(String cellValue, Schema.DescribeFieldResult dfr) {
        Schema.DisplayType dt = dfr.getType();
        String trimmedValue   = cellValue.trim();

        if (dt == Schema.DisplayType.STRING ||
            dt == Schema.DisplayType.TEXTAREA ||
            dt == Schema.DisplayType.URL ||
            dt == Schema.DisplayType.EMAIL ||
            dt == Schema.DisplayType.PHONE ||
            dt == Schema.DisplayType.PICKLIST ||
            dt == Schema.DisplayType.MULTIPICKLIST ||
            dt == Schema.DisplayType.ENCRYPTEDSTRING) {

            return trimmedValue;

        } else if (dt == Schema.DisplayType.DOUBLE ||
                   dt == Schema.DisplayType.CURRENCY ||
                   dt == Schema.DisplayType.PERCENT) {

            return Decimal.valueOf(trimmedValue);

        } else if (dt == Schema.DisplayType.INTEGER) {

            return Integer.valueOf(trimmedValue);

        } else if (dt == Schema.DisplayType.LONG) {

            return Long.valueOf(trimmedValue);

        } else if (dt == Schema.DisplayType.DATE) {

            return Date.valueOf(trimmedValue);

        } else if (dt == Schema.DisplayType.DATETIME) {

            return DateTime.valueOf(trimmedValue);

        } else if (dt == Schema.DisplayType.BOOLEAN) {

            return Boolean.valueOf(trimmedValue);

        } else if (dt == Schema.DisplayType.REFERENCE || dt == Schema.DisplayType.ID) {

            return (Id) trimmedValue;

        } else {
            // Fallback — treat as string
            System.debug(LOG_WARN + ' convertStringToFieldValue — unhandled DisplayType ' + dt + ' for field ' + dfr.getName() + ', treating as string');
            return trimmedValue;
        }
    }
}
