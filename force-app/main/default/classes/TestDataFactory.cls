@IsTest
public class TestDataFactory {

	public static final Id ACCOUNT_CREDITOR_RT_ID = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Creditor_Record').getRecordTypeId();

    public static Account makeAccount(String name) {
        Account a = new Account(Name = name);
        insert a;
        return a;
    }

    public static Opportunity makeOpp(Id accountId, String name) {
        Opportunity o = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert o;
        return o;
    }

    public static Lead makeLead(String lastName, String company, String status, String email) {
        Lead l = new Lead(
            LastName = lastName,
            Company = company,
            Status = status,
            Email = email
        );
        insert l;
        return l;
    }
	
	public static List<Account> makeCreditorsAsAccount(Integer count, String namePrefix) {
		List<Account> cs = new List<Account>();
        for (Integer i = 1; i <= count; i++) {
            cs.add(new Account(Name = namePrefix + ' ' + i, RecordTypeId = ACCOUNT_CREDITOR_RT_ID));
        }
        insert cs;
        return cs;
	}

	// TODO can depricate once all updates are made for Creditors as Accounts
    public static List<Creditor__c> makeCreditors(Integer count, String namePrefix) {
        List<Creditor__c> cs = new List<Creditor__c>();
        for (Integer i = 1; i <= count; i++) {
            cs.add(new Creditor__c(Name = namePrefix + ' ' + i));
        }
        insert cs;
        return cs;
    }

	public static List<CreditorOpportunity__c> linkCredsToLead(Id leadId, List<Account> cs, Decimal baseAmount, Decimal baseWeekly, Integer n) {
        List<CreditorOpportunity__c> links = new List<CreditorOpportunity__c>();
        for (Integer i = 0; i < Math.min(n, cs.size()); i++) {
            links.add(new CreditorOpportunity__c(
                Lead__c = leadId,
                CreditorAccount__c = cs[i].Id,
                Amount__c = baseAmount + (i * 1000),
                Weekly_Payment__c = baseWeekly + (i * 25),
                Frequency__c = 'Weekly'
            ));
        }
        insert links;
        return links;
    }

	// TODO can depricate once all updates are made for Creditors as Accounts
    public static List<CreditorOpportunity__c> linkCredsToLead(Id leadId, List<Creditor__c> cs, Decimal baseAmount, Decimal baseWeekly, Integer n) {
        List<CreditorOpportunity__c> links = new List<CreditorOpportunity__c>();
        for (Integer i = 0; i < Math.min(n, cs.size()); i++) {
            links.add(new CreditorOpportunity__c(
                Lead__c = leadId,
                Creditor__c = cs[i].Id,
                Amount__c = baseAmount + (i * 1000),
                Weekly_Payment__c = baseWeekly + (i * 25),
                Frequency__c = 'Weekly'
            ));
        }
        insert links;
        return links;
    }
	   
	public static List<CreditorOpportunity__c> linkCredsToOpp(Id oppId, List<Account> cs, Decimal baseAmount, Decimal baseWeekly, Integer n) {
        List<CreditorOpportunity__c> links = new List<CreditorOpportunity__c>();
        for (Integer i = 0; i < Math.min(n, cs.size()); i++) {
            links.add(new CreditorOpportunity__c(
                Opportunity__c = oppId,
                CreditorAccount__c = cs[i].Id,
                Amount__c = baseAmount + (i * 1000),
                Weekly_Payment__c = baseWeekly + (i * 25),
                Frequency__c = 'Weekly'
            ));
        }
        insert links;
        return links;
    }

	// TODO can depricate once all updates are made for Creditors as Accounts
    public static List<CreditorOpportunity__c> linkCredsToOpp(Id oppId, List<Creditor__c> cs, Decimal baseAmount, Decimal baseWeekly, Integer n) {
        List<CreditorOpportunity__c> links = new List<CreditorOpportunity__c>();
        for (Integer i = 0; i < Math.min(n, cs.size()); i++) {
            links.add(new CreditorOpportunity__c(
                Opportunity__c = oppId,
                Creditor__c = cs[i].Id,
                Amount__c = baseAmount + (i * 1000),
                Weekly_Payment__c = baseWeekly + (i * 25),
                Frequency__c = 'Weekly'
            ));
        }
        insert links;
        return links;
    }

    public static PaymentPlan__c makePaymentPlanForOpp(Id oppId, Decimal totalDebt, Decimal weeklyPayment, Integer numPayments) {
        PaymentPlan__c plan = new PaymentPlan__c(
            Opportunity__c = oppId,
            Total_Debt__c = totalDebt,
            Settlement_Percentage__c = 43,
            Program_Fee_Percentage__c = 35,
            Total_Program_Cost__c = 35000,
            Weekly_Payment__c = weeklyPayment,
            Number_of_Payments__c = numPayments,
            Version_Number__c = 1,
            First_Payment_Date__c = Date.today().addDays(7),
            Status__c = 'Draft'
        );
        insert plan;
        return plan;
    }

    public static PaymentDraft__c makeDraftForLead(Id leadId, String name, String configJson, String calcJson) {
        PaymentDraft__c d = new PaymentDraft__c(
            Lead__c = leadId,
            Draft_Name__c = name,
            Configuration_JSON__c = configJson,
            Calculations_JSON__c = calcJson,
            Created_By_Calculator__c = true
        );
        insert d;
        return d;
    }

    public static PaymentDraft__c makeDraftForOpp(Id oppId, String name, String configJson, String calcJson) {
        PaymentDraft__c d = new PaymentDraft__c(
            Opportunity__c = oppId,
            Draft_Name__c = name,
            Configuration_JSON__c = configJson,
            Calculations_JSON__c = calcJson,
            Created_By_Calculator__c = true
        );
        insert d;
        return d;
    }
}