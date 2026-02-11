/**
 * @description Minimal class - functionality removed
 */
public with sharing class NegotiationController {
    
    @AuraEnabled
    public static String getStatus() {
        return 'inactive';
    }
    
    @AuraEnabled  
    public static Boolean isActive() {
        return false;
    }
}