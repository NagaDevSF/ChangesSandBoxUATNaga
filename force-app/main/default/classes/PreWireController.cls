public with sharing class PreWireController {

    // ==================================================================================
    // CONSTANTS
    // ==================================================================================

    private static final String LOG_ENTRY = '▶️';
    private static final String LOG_EXIT  = '◀️';
    private static final String LOG_ERROR = '❌';
    private static final String LOG_SUCCESS = '✅';
    private static final String LOG_DEBUG = '🔧';
    private static final String LOG_QUERY = '🔍';
    private static final String LOG_DML   = '💾';
    private static final String LOG_PARAM = '📋';
    private static final String LOG_PREFIX = '[PreWireController]';

    // ==================================================================================
    // WRAPPER CLASSES
    // ==================================================================================

    public class PreWireContext {
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String accountName;
        @AuraEnabled public List<PreWireRecord> preWires;
    }

    public class PreWireRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String businessName;
        @AuraEnabled public Date dateValue;
        @AuraEnabled public Decimal amount;
    }

    public class PreWireInput {
        @AuraEnabled public String id;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public Date dateValue;
        @AuraEnabled public Decimal amount;
    }

    // ==================================================================================
    // PUBLIC METHODS
    // ==================================================================================

    @AuraEnabled(cacheable=true)
    public static PreWireContext getPreWireContext(String opportunityId) {
        System.debug(LOG_ENTRY + ' ' + LOG_PREFIX + ' getPreWireContext');
        System.debug(LOG_PARAM + ' ' + LOG_PREFIX + ' opportunityId=' + opportunityId);

        if (String.isBlank(opportunityId)) {
            throwAuraException('Opportunity ID is required.');
        }

        PreWireContext ctx = new PreWireContext();
        ctx.opportunityId = opportunityId;

        // Query Opportunity with Account Name
        List<Opportunity> opps = [
            SELECT Id, Account.Name
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        if (opps.isEmpty()) {
            throwAuraException('Opportunity not found.');
        }

        ctx.accountName = opps[0].Account != null ? opps[0].Account.Name : '';

        System.debug(LOG_QUERY + ' ' + LOG_PREFIX + ' accountName=' + ctx.accountName);

        // Query Pre Wire records
        List<Pre_Wire__c> wires = [
            SELECT Id, Name, Opportunity__c, Date_Value__c, Amount__c,
                   Opportunity__r.Account.Name
            FROM Pre_Wire__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY Date_Value__c ASC NULLS LAST
        ];

        ctx.preWires = new List<PreWireRecord>();
        for (Pre_Wire__c pw : wires) {
            ctx.preWires.add(mapToRecord(pw));
        }

        System.debug(LOG_SUCCESS + ' ' + LOG_PREFIX + ' Loaded ' + ctx.preWires.size() + ' pre wire records');
        System.debug(LOG_EXIT + ' ' + LOG_PREFIX + ' getPreWireContext');
        return ctx;
    }

    @AuraEnabled
    public static PreWireRecord createPreWire(String inputJson) {
        System.debug(LOG_ENTRY + ' ' + LOG_PREFIX + ' createPreWire');
        System.debug(LOG_PARAM + ' ' + LOG_PREFIX + ' inputJson=' + inputJson);

        if (String.isBlank(inputJson)) {
            throwAuraException('Input data is required.');
        }

        PreWireInput input;
        try {
            input = (PreWireInput) JSON.deserialize(inputJson, PreWireInput.class);
        } catch (Exception e) {
            System.debug(LOG_ERROR + ' ' + LOG_PREFIX + ' Failed to parse input: ' + e.getMessage());
            throwAuraException('Invalid input data: ' + e.getMessage());
        }

        validateInput(input);

        Pre_Wire__c pw = new Pre_Wire__c();
        pw.Opportunity__c = input.opportunityId;
        pw.Date_Value__c = input.dateValue;
        pw.Amount__c = input.amount;

        Savepoint sp = Database.setSavepoint();
        try {
            System.debug(LOG_DML + ' ' + LOG_PREFIX + ' Inserting Pre Wire record');
            insert pw;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LOG_ERROR + ' ' + LOG_PREFIX + ' Insert failed: ' + e.getMessage());
            throwAuraException('Failed to create Pre Wire: ' + e.getMessage());
        }

        // Re-query to get relationship fields
        Pre_Wire__c created = [
            SELECT Id, Name, Opportunity__c, Date_Value__c, Amount__c,
                   Opportunity__r.Account.Name
            FROM Pre_Wire__c
            WHERE Id = :pw.Id
            LIMIT 1
        ];

        System.debug(LOG_SUCCESS + ' ' + LOG_PREFIX + ' Created Pre Wire: ' + created.Id);
        System.debug(LOG_EXIT + ' ' + LOG_PREFIX + ' createPreWire');
        return mapToRecord(created);
    }

    @AuraEnabled
    public static PreWireRecord updatePreWire(String inputJson) {
        System.debug(LOG_ENTRY + ' ' + LOG_PREFIX + ' updatePreWire');
        System.debug(LOG_PARAM + ' ' + LOG_PREFIX + ' inputJson=' + inputJson);

        if (String.isBlank(inputJson)) {
            throwAuraException('Input data is required.');
        }

        PreWireInput input;
        try {
            input = (PreWireInput) JSON.deserialize(inputJson, PreWireInput.class);
        } catch (Exception e) {
            System.debug(LOG_ERROR + ' ' + LOG_PREFIX + ' Failed to parse input: ' + e.getMessage());
            throwAuraException('Invalid input data: ' + e.getMessage());
        }

        if (String.isBlank(input.id)) {
            throwAuraException('Pre Wire ID is required for update.');
        }

        validateInput(input);

        // Verify record exists
        List<Pre_Wire__c> existing = [
            SELECT Id
            FROM Pre_Wire__c
            WHERE Id = :input.id
            LIMIT 1
        ];

        if (existing.isEmpty()) {
            throwAuraException('Pre Wire record not found.');
        }

        Pre_Wire__c pw = existing[0];
        pw.Date_Value__c = input.dateValue;
        pw.Amount__c = input.amount;

        Savepoint sp = Database.setSavepoint();
        try {
            System.debug(LOG_DML + ' ' + LOG_PREFIX + ' Updating Pre Wire: ' + pw.Id);
            update pw;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LOG_ERROR + ' ' + LOG_PREFIX + ' Update failed: ' + e.getMessage());
            throwAuraException('Failed to update Pre Wire: ' + e.getMessage());
        }

        // Re-query to get relationship fields
        Pre_Wire__c updated = [
            SELECT Id, Name, Opportunity__c, Date_Value__c, Amount__c,
                   Opportunity__r.Account.Name
            FROM Pre_Wire__c
            WHERE Id = :pw.Id
            LIMIT 1
        ];

        System.debug(LOG_SUCCESS + ' ' + LOG_PREFIX + ' Updated Pre Wire: ' + updated.Id);
        System.debug(LOG_EXIT + ' ' + LOG_PREFIX + ' updatePreWire');
        return mapToRecord(updated);
    }

    @AuraEnabled
    public static void deletePreWire(String preWireId) {
        System.debug(LOG_ENTRY + ' ' + LOG_PREFIX + ' deletePreWire');
        System.debug(LOG_PARAM + ' ' + LOG_PREFIX + ' preWireId=' + preWireId);

        if (String.isBlank(preWireId)) {
            throwAuraException('Pre Wire ID is required.');
        }

        List<Pre_Wire__c> existing = [
            SELECT Id
            FROM Pre_Wire__c
            WHERE Id = :preWireId
            LIMIT 1
        ];

        if (existing.isEmpty()) {
            throwAuraException('Pre Wire record not found.');
        }

        Savepoint sp = Database.setSavepoint();
        try {
            System.debug(LOG_DML + ' ' + LOG_PREFIX + ' Deleting Pre Wire: ' + preWireId);
            delete existing[0];
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LOG_ERROR + ' ' + LOG_PREFIX + ' Delete failed: ' + e.getMessage());
            throwAuraException('Failed to delete Pre Wire: ' + e.getMessage());
        }

        System.debug(LOG_SUCCESS + ' ' + LOG_PREFIX + ' Deleted Pre Wire: ' + preWireId);
        System.debug(LOG_EXIT + ' ' + LOG_PREFIX + ' deletePreWire');
    }

    // ==================================================================================
    // PRIVATE HELPER METHODS
    // ==================================================================================

    private static void throwAuraException(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        throw ex;
    }

    private static void validateInput(PreWireInput input) {
        if (String.isBlank(input.opportunityId)) {
            throwAuraException('Opportunity is required.');
        }
        if (input.dateValue == null) {
            throwAuraException('Date Value is required.');
        }
        if (input.amount == null || input.amount <= 0) {
            throwAuraException('Amount must be greater than zero.');
        }
    }

    private static PreWireRecord mapToRecord(Pre_Wire__c pw) {
        PreWireRecord rec = new PreWireRecord();
        rec.id = pw.Id;
        rec.name = pw.Name;
        rec.opportunityId = pw.Opportunity__c;
        rec.dateValue = pw.Date_Value__c;
        rec.amount = pw.Amount__c;
        rec.businessName = pw.Opportunity__r != null && pw.Opportunity__r.Account != null
            ? pw.Opportunity__r.Account.Name
            : '';
        return rec;
    }
}
