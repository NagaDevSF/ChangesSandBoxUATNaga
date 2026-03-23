/**
 * Service class for managing Payment Plan versions
 * Handles version control, activation, and comparison
 * @author DCG Development Team
 * @date 2025-09-02
 */
public with sharing class PaymentPlanVersionService {

    // ==================================================================================
    // DEBUG LOGGING CONSTANTS
    // ==================================================================================
    private static final String LOG_PREFIX = '[PaymentPlanVersionService]';
    private static final String LOG_ENTRY = '▶️';
    private static final String LOG_EXIT = '◀️';
    private static final String LOG_ERROR = '❌';
    private static final String LOG_SUCCESS = '✅';
    private static final String LOG_DEBUG = '🔧';

    /**
     * Activates a specific payment plan version
     * Deactivates all other versions for the same opportunity
     */
    @AuraEnabled
    public static PaymentPlan__c activateVersion(Id paymentPlanId) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' activateVersion | paymentPlanId=' + paymentPlanId);
        try {
            // Get the payment plan to activate
            PaymentPlan__c planToActivate = [
                SELECT Id, Opportunity__c, Version_Number__c, Is_Active__c, Status__c
                FROM PaymentPlan__c
                WHERE Id = :paymentPlanId
                WITH USER_MODE
                LIMIT 1
            ];
            
            if (planToActivate.Is_Active__c) {
                // Already active
                return planToActivate;
            }
            
            // Start transaction
            Savepoint sp = Database.setSavepoint();
            
            try {
                // Deactivate all other versions for this opportunity
                List<PaymentPlan__c> plansToDeactivate = [
                    SELECT Id, Is_Active__c, Status__c
                    FROM PaymentPlan__c
                    WHERE Opportunity__c = :planToActivate.Opportunity__c
                    AND Is_Active__c = true
                    AND Id != :paymentPlanId
                    WITH USER_MODE
                ];
                
                for (PaymentPlan__c plan : plansToDeactivate) {
                    plan.Is_Active__c = false;
                    // Align with Status__c picklist values
                    plan.Status__c = 'Archived';
                }
                
                if (!plansToDeactivate.isEmpty()) {
                    Database.update(plansToDeactivate, AccessLevel.USER_MODE);
                }
                
                // Activate the selected version
                planToActivate.Is_Active__c = true;
                planToActivate.Status__c = 'Active';
                Database.update(planToActivate, AccessLevel.USER_MODE);

                System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' activateVersion | ' + LOG_SUCCESS + ' version=' + planToActivate.Version_Number__c);
                return planToActivate;

            } catch (Exception e) {
                Database.rollback(sp);
                throw e;
            }

        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' activateVersion | ' + e.getMessage());
            throw new AuraHandledException('Failed to activate version: ' + e.getMessage());
        }
    }
    
    /**
     * Creates a new version based on an existing payment plan
     * Copies configuration but not calculation results
     */
    @AuraEnabled
    public static PaymentPlan__c createNewVersion(Id existingPlanId, String versionNotes) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' createNewVersion | existingPlanId=' + existingPlanId);
        try {
            // Get existing plan with ALL fields via describe (ensures no field is missed)
            Map<String, Schema.SObjectField> fieldMap =
                Schema.SObjectType.PaymentPlan__c.fields.getMap();
            List<String> fieldNames = new List<String>();
            fieldNames.add('Id');
            for (String fieldName : fieldMap.keySet()) {
                if (fieldName == 'id') continue;
                Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
                if (!fd.isAccessible()) continue;
                fieldNames.add(fieldName);
            }
            fieldNames.sort();
            String allFields = String.join(fieldNames, ', ');

            List<PaymentPlan__c> plans = Database.queryWithBinds(
                'SELECT ' + allFields + ' FROM PaymentPlan__c WHERE Id = :planId LIMIT 1',
                new Map<String, Object>{ 'planId' => existingPlanId },
                AccessLevel.USER_MODE
            );
            if (plans.isEmpty()) {
                throw new AuraHandledException('Payment Plan not found.');
            }
            PaymentPlan__c existingPlan = plans[0];

            // Get highest version number
            Integer maxVersion = getMaxVersionNumber(existingPlan.Opportunity__c);

            // Create new version and copy ALL createable fields from existing plan
            PaymentPlan__c newVersion = new PaymentPlan__c();
            Set<String> excludeFields = new Set<String>{'id', 'createddate', 'lastmodifieddate', 'systemmodstamp',
                'createdbyid', 'lastmodifiedbyid', 'isdeleted', 'name'};
            for (String fieldName : fieldMap.keySet()) {
                if (excludeFields.contains(fieldName)) continue;
                Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
                if (fd.isCalculated()) continue;
                if (!fd.isCreateable()) continue;
                newVersion.put(fieldName, existingPlan.get(fieldName));
            }

            // Override version-specific fields
            newVersion.Version_Number__c = maxVersion + 1;
            newVersion.Version_Type__c = 'Revision';
            newVersion.Status__c = 'Draft';
            newVersion.Is_Active__c = false;
            newVersion.Previous_Version__c = existingPlanId;
            newVersion.Version_Notes__c = versionNotes;
            newVersion.Calculation_Timestamp__c = DateTime.now();
            newVersion.Source__c = 'UI';

            Database.insert(newVersion, AccessLevel.USER_MODE);

            System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' createNewVersion | ' + LOG_SUCCESS + ' newId=' + newVersion.Id + ', version=' + newVersion.Version_Number__c);
            return newVersion;

        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' createNewVersion | ' + e.getMessage());
            throw new AuraHandledException('Failed to create new version: ' + e.getMessage());
        }
    }
    
    /**
     * Gets all versions for an opportunity
     */
    @AuraEnabled(cacheable=true)
    public static List<PaymentPlan__c> getVersionHistory(Id opportunityId) {
        if (opportunityId == null) {
            return new List<PaymentPlan__c>();
        }
        return [
            SELECT Id, Name, Version_Number__c, Version_Type__c, Status__c,
                   Is_Active__c, Calculation_Timestamp__c, Version_Notes__c,
                   Total_Program_Cost__c, Weekly_Payment__c, Number_of_Payments__c,
                   CreatedBy.Name, CreatedDate
            FROM PaymentPlan__c
            WHERE Opportunity__c = :opportunityId
            WITH USER_MODE
            ORDER BY Version_Number__c DESC
        ];
    }
    
    /**
     * Compares two payment plan versions
     */
    @AuraEnabled(cacheable=true)
    public static VersionComparison compareVersions(Id versionId1, Id versionId2) {
        try {
            List<PaymentPlan__c> plans = [
                SELECT Id, Version_Number__c, Version_Type__c,
                       Program_Type__c, Settlement_Percentage__c, Program_Fee_Percentage__c,
                       Setup_Fee__c, Setup_Fee_Payments__c, Banking_Fee__c, Bank2_Fee__c,
                       Total_Debt__c, Settlement_Amount__c, Program_Fee_Amount__c,
                       Total_Program_Cost__c, Weekly_Payment__c, Monthly_Payment__c,
                       Number_of_Payments__c, First_Payment_Date__c
                FROM PaymentPlan__c
                WHERE Id IN :new Set<Id>{versionId1, versionId2}
                WITH USER_MODE
            ];
            
            if (plans.size() != 2) {
                throw new AuraHandledException('Could not find both versions for comparison');
            }
            
            VersionComparison comparison = new VersionComparison();
            comparison.version1 = plans[0].Id == versionId1 ? plans[0] : plans[1];
            comparison.version2 = plans[0].Id == versionId2 ? plans[0] : plans[1];
            
            // Calculate differences
            comparison.differences = new List<FieldDifference>();
            
            // Compare key fields
            addDifference(comparison.differences, 'Program Type', 
                         comparison.version1.Program_Type__c, 
                         comparison.version2.Program_Type__c);
            
            addDifference(comparison.differences, 'Settlement %', 
                         comparison.version1.Settlement_Percentage__c, 
                         comparison.version2.Settlement_Percentage__c);
            
            addDifference(comparison.differences, 'Program Fee %', 
                         comparison.version1.Program_Fee_Percentage__c, 
                         comparison.version2.Program_Fee_Percentage__c);
            
            addDifference(comparison.differences, 'Setup Fee', 
                         comparison.version1.Setup_Fee__c, 
                         comparison.version2.Setup_Fee__c);
            
            addDifference(comparison.differences, 'Weekly Payment', 
                         comparison.version1.Weekly_Payment__c, 
                         comparison.version2.Weekly_Payment__c);
            
            addDifference(comparison.differences, 'Number of Payments', 
                         comparison.version1.Number_of_Payments__c, 
                         comparison.version2.Number_of_Payments__c);
            
            addDifference(comparison.differences, 'Total Program Cost', 
                         comparison.version1.Total_Program_Cost__c, 
                         comparison.version2.Total_Program_Cost__c);
            
            return comparison;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to compare versions: ' + e.getMessage());
        }
    }
    
    /**
     * Archives old draft versions
     */
    @AuraEnabled
    public static Integer archiveOldDrafts(Id opportunityId, Integer daysOld) {
        try {
            DateTime cutoffDate = DateTime.now().addDays(-daysOld);
            
            List<PaymentPlan__c> draftsToArchive = [
                SELECT Id, Status__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :opportunityId
                AND Status__c = 'Draft'
                AND Is_Active__c = false
                AND CreatedDate < :cutoffDate
            ];
            
            for (PaymentPlan__c draft : draftsToArchive) {
                draft.Status__c = 'Archived';
            }
            
            if (!draftsToArchive.isEmpty()) {
                Database.update(draftsToArchive, AccessLevel.USER_MODE);
            }
            
            return draftsToArchive.size();
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to archive drafts: ' + e.getMessage());
        }
    }
    
    /**
     * Helper method to get maximum version number
     */
    private static Integer getMaxVersionNumber(Id opportunityId) {
        List<PaymentPlan__c> plans = [
            SELECT Version_Number__c
            FROM PaymentPlan__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY Version_Number__c DESC
            LIMIT 1
        ];
        
        return plans.isEmpty() ? 0 : Integer.valueOf(plans[0].Version_Number__c);
    }
    
    /**
     * Helper method to add field differences
     */
    private static void addDifference(List<FieldDifference> differences, 
                                     String fieldName, 
                                     Object value1, 
                                     Object value2) {
        if (value1 != value2) {
            FieldDifference diff = new FieldDifference();
            diff.fieldName = fieldName;
            diff.value1 = String.valueOf(value1);
            diff.value2 = String.valueOf(value2);
            differences.add(diff);
        }
    }
    
    /**
     * Version comparison wrapper class
     */
    public class VersionComparison {
        @AuraEnabled public PaymentPlan__c version1 { get; set; }
        @AuraEnabled public PaymentPlan__c version2 { get; set; }
        @AuraEnabled public List<FieldDifference> differences { get; set; }
    }
    
    /**
     * Field difference wrapper class
     */
    public class FieldDifference {
        @AuraEnabled public String fieldName { get; set; }
        @AuraEnabled public String value1 { get; set; }
        @AuraEnabled public String value2 { get; set; }
    }
}