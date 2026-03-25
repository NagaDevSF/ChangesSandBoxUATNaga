/**
 * @description Comprehensive test class for DynamicFileUploadController.
 *              Covers getAvailableObjects, getObjectFields, validateMappedData,
 *              and createMappedRecords with 5+ test categories:
 *              Happy Path, No Data / Null Input, Error Handling, Bulk Operations,
 *              and Edge Cases.
 * @author      Naga / DCG Pro
 * @date        2026-03-25
 */
@IsTest
private class DynamicFileUploadControllerTest {

    // ============================================================
    // Test Setup
    // ============================================================

    @TestSetup
    static void setupTestData() {
        // 1. Account
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;

        // 2. Opportunity
        Opportunity testOpp = new Opportunity(
            Name        = 'Test Opportunity',
            StageName   = 'Prospecting',
            CloseDate   = Date.today().addDays(30),
            AccountId   = testAccount.Id
        );
        insert testOpp;

        // 3. Payment Plan
        PaymentPlan__c testPlan = new PaymentPlan__c(
            Opportunity__c   = testOpp.Id,
            Is_Active__c     = true,
            Banking_Fee__c   = 15.00,
            Version_Number__c = 1
        );
        insert testPlan;

        // 4. Payment Schedule Items (3 records)
        List<Payment_Schedule_Item__c> psiList = new List<Payment_Schedule_Item__c>();
        for (Integer i = 0; i < 3; i++) {
            psiList.add(new Payment_Schedule_Item__c(
                Payment_Plan__c    = testPlan.Id,
                Payment_Date__c    = Date.today().addDays(7 * i),
                Total_Payment__c   = 500.00 + (100 * i),
                Status__c          = 'Scheduled',
                Payment_Number__c  = i + 1
            ));
        }
        insert psiList;

        // 5. Payment Fees (2 records on first PSI)
        List<Payment_Fee__c> feeList = new List<Payment_Fee__c>{
            new Payment_Fee__c(
                Payment_Schedule_Item__c = psiList[0].Id,
                Type__c                  = 'Banking Fee',
                Amount__c                = 15.00
            ),
            new Payment_Fee__c(
                Payment_Schedule_Item__c = psiList[0].Id,
                Type__c                  = 'Program Fee',
                Amount__c                = 50.00
            )
        };
        insert feeList;
    }

    // ============================================================
    // Helper Methods
    // ============================================================

    /**
     * @description Builds a JSON array of MappedRow objects from a list of field-value maps.
     *              Each map becomes one row with an auto-assigned rowIndex starting at 0.
     * @param rows  List of field-value maps (fieldApiName -> stringValue)
     * @return      JSON string matching the controller's expected format
     */
    private static String buildRecordsJson(List<Map<String, String>> rows) {
        List<Map<String, Object>> jsonRows = new List<Map<String, Object>>();
        for (Integer i = 0; i < rows.size(); i++) {
            Map<String, Object> rowObj = new Map<String, Object>();
            rowObj.put('rowIndex', i);
            rowObj.put('fieldValues', rows[i]);
            jsonRows.add(rowObj);
        }
        return JSON.serialize(jsonRows);
    }

    /**
     * @description Builds a JSON array of FieldMapping objects.
     * @param excelColumns List of Excel column names
     * @param sfFields     List of Salesforce field API names (parallel to excelColumns)
     * @return             JSON string of field mappings
     */
    private static String buildMappingsJson(List<String> excelColumns, List<String> sfFields) {
        List<Map<String, String>> mappings = new List<Map<String, String>>();
        for (Integer i = 0; i < excelColumns.size(); i++) {
            Map<String, String> mapping = new Map<String, String>();
            mapping.put('excelColumn', excelColumns[i]);
            mapping.put('salesforceField', sfFields[i]);
            mappings.add(mapping);
        }
        return JSON.serialize(mappings);
    }

    // ============================================================
    // Happy Path Tests
    // ============================================================

    @IsTest
    static void testGetAvailableObjects_Success() {
        // Arrange — no special setup needed

        // Act
        Test.startTest();
        List<DynamicFileUploadController.ObjectOption> result =
            DynamicFileUploadController.getAvailableObjects();
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(!result.isEmpty(), 'Result should contain at least one object');

        // Verify Payment_Fee__c is in the list
        Boolean foundPaymentFee = false;
        for (DynamicFileUploadController.ObjectOption opt : result) {
            System.assertNotEquals(null, opt.label, 'ObjectOption label should not be null');
            System.assertNotEquals(null, opt.value, 'ObjectOption value should not be null');
            System.assert(String.isNotBlank(opt.label), 'ObjectOption label should not be blank');
            System.assert(String.isNotBlank(opt.value), 'ObjectOption value should not be blank');
            if (opt.value == 'Payment_Fee__c') {
                foundPaymentFee = true;
            }
        }
        System.assert(foundPaymentFee, 'Available objects should include Payment_Fee__c');
    }

    @IsTest
    static void testGetObjectFields_PaymentFee() {
        // Arrange — no special setup needed

        // Act
        Test.startTest();
        List<DynamicFileUploadController.FieldMetadata> fields =
            DynamicFileUploadController.getObjectFields('Payment_Fee__c');
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, fields, 'Fields list should not be null');
        System.assert(!fields.isEmpty(), 'Fields list should not be empty for Payment_Fee__c');

        // Build map for easy lookup
        Map<String, DynamicFileUploadController.FieldMetadata> fieldsByApi =
            new Map<String, DynamicFileUploadController.FieldMetadata>();
        for (DynamicFileUploadController.FieldMetadata fm : fields) {
            fieldsByApi.put(fm.apiName, fm);
        }

        // Verify Amount__c
        System.assert(fieldsByApi.containsKey('Amount__c'), 'Should contain Amount__c field');
        DynamicFileUploadController.FieldMetadata amountField = fieldsByApi.get('Amount__c');
        System.assertEquals('CURRENCY', amountField.fieldType, 'Amount__c should be CURRENCY type');
        System.assertEquals(true, amountField.isCreateable, 'Amount__c should be createable');

        // Verify Type__c (picklist)
        System.assert(fieldsByApi.containsKey('Type__c'), 'Should contain Type__c field');
        DynamicFileUploadController.FieldMetadata typeField = fieldsByApi.get('Type__c');
        System.assertEquals('PICKLIST', typeField.fieldType, 'Type__c should be PICKLIST type');
        System.assertNotEquals(null, typeField.picklistValues, 'Type__c should have picklist values');
        System.assert(!typeField.picklistValues.isEmpty(), 'Type__c picklist values should not be empty');

        // Verify Payment_Schedule_Item__c (Reference)
        System.assert(fieldsByApi.containsKey('Payment_Schedule_Item__c'),
            'Should contain Payment_Schedule_Item__c field');
        DynamicFileUploadController.FieldMetadata psiField = fieldsByApi.get('Payment_Schedule_Item__c');
        System.assertEquals('REFERENCE', psiField.fieldType,
            'Payment_Schedule_Item__c should be REFERENCE type');
        System.assertEquals(true, psiField.isRequired,
            'Payment_Schedule_Item__c (master-detail) should be required');
        System.assertEquals('Payment_Schedule_Item__c', psiField.referenceTo,
            'Payment_Schedule_Item__c should reference Payment_Schedule_Item__c object');
    }

    @IsTest
    static void testValidateMappedData_AllValid() {
        // Arrange
        List<Payment_Schedule_Item__c> psis = [
            SELECT Id FROM Payment_Schedule_Item__c ORDER BY Payment_Date__c LIMIT 3
        ];
        System.assertEquals(3, psis.size(), 'Should have 3 PSIs from test setup');

        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer i = 0; i < 3; i++) {
            rows.add(new Map<String, String>{
                'Payment_Schedule_Item__c' => psis[i].Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => '100.50'
            });
        }
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = buildMappingsJson(
            new List<String>{'PSI ID', 'Fee Type', 'Amount'},
            new List<String>{'Payment_Schedule_Item__c', 'Type__c', 'Amount__c'}
        );

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(3, response.totalRows, 'Total rows should be 3');
        System.assertEquals(3, response.validCount, 'Valid count should be 3');
        System.assertEquals(0, response.invalidCount, 'Invalid count should be 0');
        System.assertNotEquals(null, response.rows, 'Rows should not be null');
        for (DynamicFileUploadController.RowValidation rv : response.rows) {
            System.assertEquals(true, rv.isValid, 'Row ' + rv.rowIndex + ' should be valid');
            System.assert(rv.errors.isEmpty(), 'Row ' + rv.rowIndex + ' should have no errors');
        }
    }

    @IsTest
    static void testCreateMappedRecords_Success() {
        // Arrange
        List<Payment_Schedule_Item__c> psis = [
            SELECT Id FROM Payment_Schedule_Item__c ORDER BY Payment_Date__c LIMIT 2
        ];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer i = 0; i < 2; i++) {
            rows.add(new Map<String, String>{
                'Payment_Schedule_Item__c' => psis[i].Id,
                'Type__c'                  => 'Wire Fee',
                'Amount__c'                => '250.75'
            });
        }
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = buildMappingsJson(
            new List<String>{'PSI ID', 'Fee Type', 'Amount'},
            new List<String>{'Payment_Schedule_Item__c', 'Type__c', 'Amount__c'}
        );

        // Count existing fees before insert
        Integer existingFeeCount = [SELECT COUNT() FROM Payment_Fee__c];

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(2, response.totalRows, 'Total rows should be 2');
        System.assertEquals(2, response.successCount, 'Success count should be 2');
        System.assertEquals(0, response.failureCount, 'Failure count should be 0');
        System.assertNotEquals(null, response.results, 'Results should not be null');

        for (DynamicFileUploadController.CreationRow cr : response.results) {
            System.assertEquals(true, cr.isSuccess, 'Row ' + cr.rowIndex + ' should be successful');
            System.assertNotEquals(null, cr.recordId, 'Row ' + cr.rowIndex + ' should have a recordId');
        }

        // Verify records were created in the database
        List<Payment_Fee__c> allFees = [
            SELECT Id, Type__c, Amount__c, Payment_Schedule_Item__c
            FROM Payment_Fee__c
        ];
        System.assertEquals(existingFeeCount + 2, allFees.size(),
            'Two new Payment_Fee__c records should have been created');

        // Verify field values on newly created records
        Set<Id> newRecordIds = new Set<Id>();
        for (DynamicFileUploadController.CreationRow cr : response.results) {
            newRecordIds.add(cr.recordId);
        }
        List<Payment_Fee__c> newFees = [
            SELECT Id, Type__c, Amount__c
            FROM Payment_Fee__c
            WHERE Id IN :newRecordIds
        ];
        System.assertEquals(2, newFees.size(), 'Should find 2 newly created fee records');
        for (Payment_Fee__c fee : newFees) {
            System.assertEquals('Wire Fee', fee.Type__c, 'Type__c should be Wire Fee');
            System.assertEquals(250.75, fee.Amount__c, 'Amount__c should be 250.75');
        }
    }

    // ============================================================
    // No Data / Null Input Tests
    // ============================================================

    @IsTest
    static void testGetObjectFields_NullObject() {
        // Arrange — null input

        // Act & Assert
        Test.startTest();
        try {
            DynamicFileUploadController.getObjectFields(null);
            System.assert(false, 'Should have thrown AuraHandledException for null input');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Object API name is required')
                || e.getMessage().contains('Script-thrown exception'),
                'Exception message should indicate missing object name, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetObjectFields_EmptyString() {
        // Arrange — empty string input

        // Act & Assert
        Test.startTest();
        try {
            DynamicFileUploadController.getObjectFields('');
            System.assert(false, 'Should have thrown AuraHandledException for empty string');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Object API name is required')
                || e.getMessage().contains('Script-thrown exception'),
                'Exception message should indicate missing object name, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetObjectFields_InvalidObject() {
        // Arrange — non-existent object

        // Act & Assert
        Test.startTest();
        try {
            DynamicFileUploadController.getObjectFields('NonExistent_Object__c');
            System.assert(false, 'Should have thrown AuraHandledException for invalid object');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Object not found')
                || e.getMessage().contains('Script-thrown exception'),
                'Exception message should indicate object not found, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateMappedData_EmptyPayload() {
        // Arrange
        String recordsJson  = '[]';
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(0, response.totalRows, 'Total rows should be 0 for empty payload');
        System.assertEquals(0, response.validCount, 'Valid count should be 0 for empty payload');
        System.assertEquals(0, response.invalidCount, 'Invalid count should be 0 for empty payload');
    }

    @IsTest
    static void testCreateMappedRecords_EmptyPayload() {
        // Arrange
        String recordsJson  = '[]';
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(0, response.totalRows, 'Total rows should be 0 for empty payload');
        System.assertEquals(0, response.successCount, 'Success count should be 0 for empty payload');
        System.assertEquals(0, response.failureCount, 'Failure count should be 0 for empty payload');
    }

    // ============================================================
    // Error Handling Tests
    // ============================================================

    @IsTest
    static void testValidateMappedData_InvalidFieldType() {
        // Arrange — Amount__c with non-numeric value
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => 'not_a_number'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(0, response.validCount, 'Valid count should be 0');
        System.assertEquals(1, response.invalidCount, 'Invalid count should be 1');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');
        System.assert(!response.rows[0].errors.isEmpty(), 'Row should have error messages');

        Boolean hasAmountError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('not a valid number') || err.containsIgnoreCase('Amount')) {
                hasAmountError = true;
            }
        }
        System.assert(hasAmountError, 'Should have an error about invalid number for Amount__c');
    }

    @IsTest
    static void testValidateMappedData_InvalidDate() {
        // Arrange — Payment_Date__c does not exist on Payment_Fee__c,
        // so we validate against Payment_Schedule_Item__c which has a Date field.
        // However, the spec says to use Payment_Fee__c. Since Payment_Fee__c doesn't
        // have a plain Date field, we simulate by using a nonexistent field to trigger
        // a different error, OR we test against Payment_Schedule_Item__c.
        // We'll test against Payment_Schedule_Item__c to exercise the Date validation path.
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Date__c'  => 'invalid-date',
                'Payment_Plan__c'  => psi.Id,
                'Total_Payment__c' => '100.00',
                'Status__c'        => 'Scheduled'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Schedule_Item__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount, 'Invalid count should be 1');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');

        Boolean hasDateError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('date') || err.containsIgnoreCase('invalid')) {
                hasDateError = true;
            }
        }
        System.assert(hasDateError, 'Should have an error about invalid date value');
    }

    @IsTest
    static void testValidateMappedData_InvalidPicklist() {
        // Arrange — Type__c with value not in picklist
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Invalid_Type_Value',
                'Amount__c'                => '100.00'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount, 'Invalid count should be 1');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');

        Boolean hasPicklistError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('picklist') || err.containsIgnoreCase('Invalid_Type_Value')) {
                hasPicklistError = true;
            }
        }
        System.assert(hasPicklistError, 'Should have an error about invalid picklist value');
    }

    @IsTest
    static void testCreateMappedRecords_MissingRequiredField() {
        // Arrange — Payment_Fee__c WITHOUT Payment_Schedule_Item__c (master-detail, required)
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Type__c'   => 'Banking Fee',
                'Amount__c' => '100.00'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assert(response.failureCount > 0, 'Failure count should be > 0 for missing required field');
        System.assertEquals(0, response.successCount, 'Success count should be 0');

        DynamicFileUploadController.CreationRow result = response.results[0];
        System.assertEquals(false, result.isSuccess, 'Row should not be successful');
        System.assert(String.isNotBlank(result.errorMessage),
            'Error message should be present for missing required field');
    }

    @IsTest
    static void testCreateMappedRecords_InvalidReferenceId() {
        // Arrange — Payment_Schedule_Item__c with a clearly invalid ID
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => 'fake_invalid_id',
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => '100.00'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert — should fail due to invalid Id conversion
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assert(response.failureCount > 0, 'Failure count should be > 0 for invalid reference ID');
        System.assertEquals(0, response.successCount, 'Success count should be 0');

        DynamicFileUploadController.CreationRow result = response.results[0];
        System.assertEquals(false, result.isSuccess, 'Row should not be successful');
        System.assert(String.isNotBlank(result.errorMessage),
            'Error message should be present for invalid reference ID');
    }

    // ============================================================
    // Bulk Operations Tests
    // ============================================================

    @IsTest
    static void testValidateMappedData_BulkRows() {
        // Arrange — 200+ rows, all valid
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer i = 0; i < 210; i++) {
            rows.add(new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => String.valueOf(10.00 + i)
            });
        }
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(210, response.totalRows, 'Total rows should be 210');
        System.assertEquals(210, response.validCount, 'All 210 rows should be valid');
        System.assertEquals(0, response.invalidCount, 'Invalid count should be 0');
    }

    @IsTest
    static void testCreateMappedRecords_BulkInsert() {
        // Arrange — 200+ valid records
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            rows.add(new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => String.valueOf(10.00 + i)
            });
        }
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        Integer existingFeeCount = [SELECT COUNT() FROM Payment_Fee__c];

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(200, response.totalRows, 'Total rows should be 200');
        System.assertEquals(200, response.successCount, 'All 200 rows should succeed');
        System.assertEquals(0, response.failureCount, 'Failure count should be 0');

        // Verify in database
        Integer newFeeCount = [SELECT COUNT() FROM Payment_Fee__c];
        System.assertEquals(existingFeeCount + 200, newFeeCount,
            '200 new Payment_Fee__c records should exist in the database');
    }

    @IsTest
    static void testValidateMappedData_ExceedsMaxRows() {
        // Arrange — 2001 rows to exceed MAX_UPLOAD_ROWS (2000)
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer i = 0; i < 2001; i++) {
            rows.add(new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => '10.00'
            });
        }
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act & Assert
        Test.startTest();
        try {
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
            System.assert(false, 'Should have thrown AuraHandledException for exceeding max rows');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Too many rows')
                || e.getMessage().contains('Maximum allowed')
                || e.getMessage().contains('Script-thrown exception'),
                'Exception should mention max rows exceeded, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // ============================================================
    // Edge Cases Tests
    // ============================================================

    @IsTest
    static void testGetObjectFields_StandardObject() {
        // Arrange — Account is a createable standard object

        // Act
        Test.startTest();
        List<DynamicFileUploadController.FieldMetadata> fields =
            DynamicFileUploadController.getObjectFields('Account');
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, fields, 'Fields list should not be null for Account');
        System.assert(!fields.isEmpty(), 'Account should have createable fields');

        // Verify at least the Name field is present
        Boolean hasNameField = false;
        for (DynamicFileUploadController.FieldMetadata fm : fields) {
            if (fm.apiName == 'Name') {
                hasNameField = true;
                break;
            }
        }
        System.assert(hasNameField, 'Account should have a createable Name field');
    }

    @IsTest
    static void testValidateMappedData_BlankFieldValues() {
        // Arrange — row with all blank/empty field values
        // Payment_Schedule_Item__c is required, so leaving it blank should trigger required error
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => '',
                'Type__c'                  => '',
                'Amount__c'                => ''
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert — should handle gracefully (no exceptions), but required field error expected
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount,
            'Row should be invalid due to required Payment_Schedule_Item__c being blank');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');

        Boolean hasRequiredError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('required') || err.containsIgnoreCase('blank')) {
                hasRequiredError = true;
            }
        }
        System.assert(hasRequiredError, 'Should have a required field error for Payment_Schedule_Item__c');
    }

    @IsTest
    static void testValidateMappedData_SpecialCharacters() {
        // Arrange — text fields with special characters
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => '100.00',
                'Fee_Id__c'                => 'FEE-#@!$%^&*()_+-=<>?/2024',
                'Transaction_Id__c'        => 'TXN_ABC-123.test~`'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert — special characters in text fields should be valid
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.validCount, 'Row with special characters should be valid');
        System.assertEquals(0, response.invalidCount, 'Invalid count should be 0');
        System.assertEquals(true, response.rows[0].isValid, 'Row should be valid');
    }

    @IsTest
    static void testCreateMappedRecords_PartialSuccess() {
        // Arrange — 3 valid rows + 2 invalid rows (missing master-detail)
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, Object>> jsonRows = new List<Map<String, Object>>();

        // 3 valid rows
        for (Integer i = 0; i < 3; i++) {
            Map<String, Object> rowObj = new Map<String, Object>();
            rowObj.put('rowIndex', i);
            rowObj.put('fieldValues', new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => String.valueOf(100.00 + i)
            });
            jsonRows.add(rowObj);
        }

        // 2 invalid rows — missing required Payment_Schedule_Item__c
        for (Integer i = 3; i < 5; i++) {
            Map<String, Object> rowObj = new Map<String, Object>();
            rowObj.put('rowIndex', i);
            rowObj.put('fieldValues', new Map<String, String>{
                'Type__c'   => 'Banking Fee',
                'Amount__c' => '50.00'
            });
            jsonRows.add(rowObj);
        }

        String recordsJson  = JSON.serialize(jsonRows);
        String mappingsJson = '[]';

        Integer existingFeeCount = [SELECT COUNT() FROM Payment_Fee__c];

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(5, response.totalRows, 'Total rows should be 5');
        System.assertEquals(3, response.successCount, 'Success count should be 3');
        System.assertEquals(2, response.failureCount, 'Failure count should be 2');

        // Verify successful rows have record IDs
        Integer successWithIds = 0;
        Integer failureWithErrors = 0;
        for (DynamicFileUploadController.CreationRow cr : response.results) {
            if (cr.isSuccess) {
                System.assertNotEquals(null, cr.recordId,
                    'Successful row ' + cr.rowIndex + ' should have a recordId');
                successWithIds++;
            } else {
                System.assert(String.isNotBlank(cr.errorMessage),
                    'Failed row ' + cr.rowIndex + ' should have an error message');
                failureWithErrors++;
            }
        }
        System.assertEquals(3, successWithIds, 'Should have 3 successful rows with IDs');
        System.assertEquals(2, failureWithErrors, 'Should have 2 failed rows with errors');

        // Verify valid records were actually created in database
        Integer newFeeCount = [SELECT COUNT() FROM Payment_Fee__c];
        System.assertEquals(existingFeeCount + 3, newFeeCount,
            '3 new Payment_Fee__c records should exist despite 2 failures');
    }

    @IsTest
    static void testCreateMappedRecords_CurrencyPrecision() {
        // Arrange — verify currency field stores precise value
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Setup Fee',
                'Amount__c'                => '1234.56'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.successCount, 'Should create 1 record successfully');
        System.assertNotEquals(null, response.results[0].recordId, 'Should have a record ID');

        // Verify stored value matches
        Payment_Fee__c createdFee = [
            SELECT Amount__c FROM Payment_Fee__c WHERE Id = :response.results[0].recordId
        ];
        System.assertEquals(1234.56, createdFee.Amount__c,
            'Currency value should be stored with correct precision (1234.56)');
    }

    @IsTest
    static void testValidateMappedData_NullFieldValuesInRow() {
        // Arrange — row with null fieldValues map
        String recordsJson = '[{"rowIndex": 0, "fieldValues": null}]';
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert — should be handled gracefully, row flagged as invalid
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount, 'Row with null fieldValues should be invalid');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');
        System.assert(!response.rows[0].errors.isEmpty(),
            'Should have error about no field values');
    }

    @IsTest
    static void testValidateMappedData_BooleanValidation() {
        // Arrange — test boolean field validation on a different object
        // Payment_Fee__c doesn't have boolean fields, but we can still test the
        // validation logic path via an object that does. PaymentPlan__c has Is_Active__c.
        // We'll use PaymentPlan__c for this test.
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Opportunity__c' => opp.Id,
                'Is_Active__c'   => 'maybe'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'PaymentPlan__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount, 'Row should be invalid for bad boolean');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');

        Boolean hasBooleanError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('true') && err.containsIgnoreCase('false')) {
                hasBooleanError = true;
            }
        }
        System.assert(hasBooleanError, 'Should have an error about boolean field requiring true/false');
    }

    @IsTest
    static void testValidateMappedData_ReferenceIdValidation() {
        // Arrange — test reference field with invalid ID format (wrong length)
        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => 'abc',
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => '100.00'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount, 'Row should be invalid for bad reference ID');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');

        Boolean hasIdError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('Salesforce ID') || err.containsIgnoreCase('15 or 18')) {
                hasIdError = true;
            }
        }
        System.assert(hasIdError, 'Should have an error about invalid Salesforce ID format');
    }

    @IsTest
    static void testCreateMappedRecords_NullRecordsJson() {
        // Arrange — null recordsJson should throw

        // Act & Assert
        Test.startTest();
        try {
            DynamicFileUploadController.createMappedRecords(null, 'Payment_Fee__c', '[]');
            System.assert(false, 'Should have thrown AuraHandledException for null records JSON');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Records JSON is required')
                || e.getMessage().contains('Script-thrown exception'),
                'Exception should mention missing records JSON, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateMappedRecords_NullObjectApiName() {
        // Arrange — null objectApiName should throw

        // Act & Assert
        Test.startTest();
        try {
            DynamicFileUploadController.createMappedRecords('[]', null, '[]');
            System.assert(false, 'Should have thrown AuraHandledException for null object API name');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Object API name is required')
                || e.getMessage().contains('Script-thrown exception'),
                'Exception should mention missing object API name, got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateMappedData_NonExistentField() {
        // Arrange — field that doesn't exist on Payment_Fee__c
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Fake_Field__c'            => 'some value'
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount, 'Row should be invalid for non-existent field');

        Boolean hasFieldError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('does not exist') || err.containsIgnoreCase('Fake_Field__c')) {
                hasFieldError = true;
            }
        }
        System.assert(hasFieldError, 'Should have an error about field not existing on the object');
    }

    @IsTest
    static void testValidateMappedData_MaxLengthExceeded() {
        // Arrange — Fee_Id__c is Text(255), exceed it
        Payment_Schedule_Item__c psi = [SELECT Id FROM Payment_Schedule_Item__c LIMIT 1];

        // Build a string longer than 255 characters
        String longValue = '';
        for (Integer i = 0; i < 260; i++) {
            longValue += 'X';
        }

        List<Map<String, String>> rows = new List<Map<String, String>>{
            new Map<String, String>{
                'Payment_Schedule_Item__c' => psi.Id,
                'Type__c'                  => 'Banking Fee',
                'Amount__c'                => '100.00',
                'Fee_Id__c'                => longValue
            }
        };
        String recordsJson  = buildRecordsJson(rows);
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.ValidationResponse response =
            DynamicFileUploadController.validateMappedData(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.invalidCount, 'Row should be invalid for exceeding max length');
        System.assertEquals(false, response.rows[0].isValid, 'Row should be invalid');

        Boolean hasLengthError = false;
        for (String err : response.rows[0].errors) {
            if (err.containsIgnoreCase('max length') || err.containsIgnoreCase('exceeds')) {
                hasLengthError = true;
            }
        }
        System.assert(hasLengthError, 'Should have an error about exceeding max length');
    }

    @IsTest
    static void testCreateMappedRecords_EmptyFieldValuesRow() {
        // Arrange — row with empty fieldValues map (no field-value pairs)
        String recordsJson = '[{"rowIndex": 0, "fieldValues": {}}]';
        String mappingsJson = '[]';

        // Act
        Test.startTest();
        DynamicFileUploadController.CreationResponse response =
            DynamicFileUploadController.createMappedRecords(recordsJson, 'Payment_Fee__c', mappingsJson);
        Test.stopTest();

        // Assert — should be treated as failure (no field values)
        System.assertEquals(1, response.totalRows, 'Total rows should be 1');
        System.assertEquals(1, response.failureCount, 'Should fail with empty field values');
        System.assertEquals(0, response.successCount, 'Success count should be 0');
        System.assertEquals(false, response.results[0].isSuccess, 'Row should not succeed');
    }

    @IsTest
    static void testValidateMappedData_NullRecordsJson() {
        // Arrange — null recordsJson

        // Act & Assert
        Test.startTest();
        try {
            DynamicFileUploadController.validateMappedData(null, 'Payment_Fee__c', '[]');
            System.assert(false, 'Should have thrown AuraHandledException for null records JSON');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Records JSON is required')
                || e.getMessage().contains('Script-thrown exception'),
                'Exception should mention missing records JSON, got: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
