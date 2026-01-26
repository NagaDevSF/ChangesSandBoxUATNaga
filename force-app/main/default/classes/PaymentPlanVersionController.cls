public with sharing class PaymentPlanVersionController {
    
    @AuraEnabled(cacheable=true)
    public static List<PaymentPlan__c> getPaymentPlanVersions(Id opportunityId) {
        try {
            return [
                SELECT Id, 
                       Name,
                       Version_Number__c,
                       Version_Status__c,
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
            throw new AuraHandledException('Failed to retrieve payment plan versions: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Payment_Schedule_Item__c> getPaymentScheduleItems(Id paymentPlanId) {
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
            throw new AuraHandledException('Failed to retrieve payment schedule items: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static PaymentPlan__c activateVersion(Id paymentPlanId) {
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
            
            return planToActivate;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to activate version: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static PaymentPlan__c createNewVersion(Id basePaymentPlanId) {
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
            newPlan.Version_Status__c = 'Draft';
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
            
            return newPlan;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to create new version: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void deleteVersion(Id paymentPlanId) {
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
        } catch (Exception e) {
            throw new AuraHandledException('Failed to delete version: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static PaymentPlan__c updateVersionNotes(Id paymentPlanId, String notes) {
        try {
            PaymentPlan__c plan = [
                SELECT Id, Version_Notes__c
                FROM PaymentPlan__c
                WHERE Id = :paymentPlanId
                LIMIT 1
            ];
            
            plan.Version_Notes__c = notes;
            update plan;
            
            return plan;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update version notes: ' + e.getMessage());
        }
    }
}