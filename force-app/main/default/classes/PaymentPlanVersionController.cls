public with sharing class PaymentPlanVersionController {

    // ==================================================================================
    // DEBUG LOGGING CONSTANTS
    // ==================================================================================
    private static final String LOG_PREFIX = '[PaymentPlanVersionController]';
    private static final String LOG_ENTRY = '▶️';
    private static final String LOG_EXIT = '◀️';
    private static final String LOG_ERROR = '❌';
    private static final String LOG_SUCCESS = '✅';
    private static final String LOG_DEBUG = '🔧';

    @AuraEnabled(cacheable=true)
    public static List<PaymentPlan__c> getPaymentPlanVersions(Id opportunityId) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' getPaymentPlanVersions | opportunityId=' + opportunityId);
        try {
            return [
                SELECT Id, 
                       Name,
                       Version_Number__c,
                       Status__c,
                       Version_Notes__c,
                       Is_Active__c,
                       CreatedDate,
                       CreatedBy.Name,
                       Previous_Version__c,
                       Settlement_Amount__c,
                       Program_Fee_Amount__c,
                       Setup_Fee__c,
                       Monthly_Payment__c,
                       Program_Type__c,
                       First_Payment_Date__c,
                       Number_of_Payments__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :opportunityId
                ORDER BY Version_Number__c DESC
                LIMIT 50
            ];
        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' getPaymentPlanVersions | ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve payment plan versions: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Payment_Schedule_Item__c> getPaymentScheduleItems(Id paymentPlanId) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' getPaymentScheduleItems | paymentPlanId=' + paymentPlanId);
        try {
            return [
                SELECT Id,
                       Name,
                       Payment_Date__c,
                       Payment_Number__c,
                       Draft_Number__c,
                       Total_Payment__c,
                       Banking_Fee_Amount__c,
                       Setup_Fee_Amount__c,
                       Program_Fee_Amount__c,
                       Bank2_Fee_Amount__c,
                       To_Escrow_Amount__c,
                       Escrow_Balance__c,
                       Status__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :paymentPlanId
                ORDER BY Payment_Number__c ASC
                LIMIT 500
            ];
        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' getPaymentScheduleItems | ' + e.getMessage());
            throw new AuraHandledException('Failed to retrieve payment schedule items: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static PaymentPlan__c activateVersion(Id paymentPlanId) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' activateVersion | paymentPlanId=' + paymentPlanId);
        try {
            // Get the payment plan to activate
            PaymentPlan__c planToActivate = [
                SELECT Id, Opportunity__c, Is_Active__c, Version_Number__c
                FROM PaymentPlan__c
                WHERE Id = :paymentPlanId
                LIMIT 1
            ];
            
            if (planToActivate.Is_Active__c) {
                throw new AuraHandledException('This version is already active.');
            }
            
            // Deactivate all other versions for the same opportunity
            List<PaymentPlan__c> otherPlans = [
                SELECT Id, Is_Active__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :planToActivate.Opportunity__c
                  AND Id != :paymentPlanId
                  AND Is_Active__c = true
            ];
            
            for (PaymentPlan__c plan : otherPlans) {
                plan.Is_Active__c = false;
            }
            
            // Activate the selected version
            planToActivate.Is_Active__c = true;
            
            // Update all plans
            List<PaymentPlan__c> plansToUpdate = new List<PaymentPlan__c>();
            plansToUpdate.addAll(otherPlans);
            plansToUpdate.add(planToActivate);
            
            update plansToUpdate;

            System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' activateVersion | ' + LOG_SUCCESS + ' version=' + planToActivate.Version_Number__c);
            return planToActivate;
        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' activateVersion | ' + e.getMessage());
            throw new AuraHandledException('Failed to activate version: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static PaymentPlan__c createNewVersion(Id basePaymentPlanId) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' createNewVersion | basePaymentPlanId=' + basePaymentPlanId);
        try {
            // Get the base payment plan
            PaymentPlan__c basePlan = [
                SELECT Id,
                       Opportunity__c,
                       Program_Type__c,
                       Settlement_Percentage__c,
                       Program_Fee_Percentage__c,
                       Setup_Fee__c,
                       Setup_Fee_Payments__c,
                       Banking_Fee__c,
                       Bank2_Fee__c,
                       No_Fee_Program__c,
                       First_Payment_Date__c,
                       Preferred_Day_of_Week__c,
                       Version_Number__c
                FROM PaymentPlan__c
                WHERE Id = :basePaymentPlanId
                LIMIT 1
            ];
            
            // Get the highest version number for this opportunity
            List<PaymentPlan__c> existingPlans = [
                SELECT Version_Number__c
                FROM PaymentPlan__c
                WHERE Opportunity__c = :basePlan.Opportunity__c
                ORDER BY Version_Number__c DESC
                LIMIT 1
            ];
            
            Decimal nextVersion = existingPlans.isEmpty() ? 1 : existingPlans[0].Version_Number__c + 1;
            
            // Clone the payment plan
            PaymentPlan__c newPlan = basePlan.clone(false, true, false, false);
            newPlan.Previous_Version__c = basePaymentPlanId;
            newPlan.Version_Number__c = nextVersion;
            newPlan.Status__c = 'Draft';
            newPlan.Is_Active__c = false;
            newPlan.Version_Notes__c = 'Created from Version ' + basePlan.Version_Number__c;
            newPlan.Calculation_Timestamp__c = DateTime.now();
            
            insert newPlan;
            
            // Clone payment schedule items if they exist
            List<Payment_Schedule_Item__c> baseItems = [
                SELECT Payment_Date__c,
                       Payment_Number__c,
                       Draft_Number__c,
                       Total_Payment__c,
                       Banking_Fee_Amount__c,
                       Setup_Fee_Amount__c,
                       Program_Fee_Amount__c,
                       Bank2_Fee_Amount__c,
                       To_Escrow_Amount__c,
                       Escrow_Balance__c
                FROM Payment_Schedule_Item__c
                WHERE Payment_Plan__c = :basePaymentPlanId
                ORDER BY Payment_Number__c
            ];
            
            if (!baseItems.isEmpty()) {
                List<Payment_Schedule_Item__c> newItems = new List<Payment_Schedule_Item__c>();
                for (Payment_Schedule_Item__c baseItem : baseItems) {
                    Payment_Schedule_Item__c newItem = baseItem.clone(false, true, false, false);
                    newItem.Payment_Plan__c = newPlan.Id;
                    newItem.Status__c = 'Scheduled';
                    newItems.add(newItem);
                }
                insert newItems;
            }

            System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' createNewVersion | ' + LOG_SUCCESS + ' newPlanId=' + newPlan.Id + ', version=' + newPlan.Version_Number__c);
            return newPlan;
        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' createNewVersion | ' + e.getMessage());
            throw new AuraHandledException('Failed to create new version: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteVersion(Id paymentPlanId) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' deleteVersion | paymentPlanId=' + paymentPlanId);
        try {
            PaymentPlan__c plan = [
                SELECT Id, Is_Active__c
                FROM PaymentPlan__c
                WHERE Id = :paymentPlanId
                LIMIT 1
            ];
            
            if (plan.Is_Active__c) {
                throw new AuraHandledException('Cannot delete an active version. Please activate another version first.');
            }
            
            // Delete related payment schedule items first
            delete [SELECT Id FROM Payment_Schedule_Item__c WHERE Payment_Plan__c = :paymentPlanId];
            
            // Delete the payment plan
            delete plan;
            System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' deleteVersion | ' + LOG_SUCCESS);
        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' deleteVersion | ' + e.getMessage());
            throw new AuraHandledException('Failed to delete version: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static PaymentPlan__c updateVersionNotes(Id paymentPlanId, String notes) {
        System.debug(LOG_PREFIX + ' ' + LOG_ENTRY + ' updateVersionNotes | paymentPlanId=' + paymentPlanId);
        try {
            PaymentPlan__c plan = [
                SELECT Id, Version_Notes__c
                FROM PaymentPlan__c
                WHERE Id = :paymentPlanId
                LIMIT 1
            ];
            
            plan.Version_Notes__c = notes;
            update plan;

            System.debug(LOG_PREFIX + ' ' + LOG_EXIT + ' updateVersionNotes | ' + LOG_SUCCESS);
            return plan;
        } catch (Exception e) {
            System.debug(LOG_PREFIX + ' ' + LOG_ERROR + ' updateVersionNotes | ' + e.getMessage());
            throw new AuraHandledException('Failed to update version notes: ' + e.getMessage());
        }
    }
}