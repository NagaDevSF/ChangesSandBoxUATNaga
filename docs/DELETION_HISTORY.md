# Salesforce UAT Metadata Deletion History

**Date:** 2026-01-26
**Target Org:** UAT (naga@dcgpro.com.uat)
**Org ID:** 00DgP000001rLovUAE
**Deploy ID:** 0AfgP000003yPHxSAM

---

## Summary

This document records all metadata components that were deleted from the Salesforce UAT org as part of the Payment Plan system cleanup.

---

## 1. CUSTOM OBJECTS DELETED (5 Objects)

| Object API Name | Fields Count | Description |
|-----------------|--------------|-------------|
| PaymentDraft__c | 37 fields | Payment draft records for calculating payment plans |
| Payment_Draft_Item__c | 11 fields | Individual line items within a payment draft |
| PaymentPlan__c | 49 fields | Active payment plans linked to opportunities |
| Payment_Schedule_Item__c | 39 fields | Individual scheduled payment items within a plan |
| Fee_Settlement_Detail__c | 9 fields | Fee and settlement tracking details |

### PaymentDraft__c Fields (37 fields deleted):
- Banking_Fee__c
- Calculation_Mode__c
- Calculations_JSON__c
- Configuration_JSON__c
- Created_By_Calculator__c
- Deactivated_Date__c
- Draft_Name__c
- Estimated_Current_Payment__c
- Estimated_Total_Debt__c
- First_Draft_Date__c
- Invalidated_Date__c
- Is_Active__c
- Is_Primary__c
- Lead__c
- Monthly_Payment__c
- No_Fee_Program__c
- Number_of_Weeks__c
- Opportunity__c
- Payment_Frequency__c
- Preferred_Day_of_Week__c
- Primary_Key__c
- Program_Fee_Amount__c
- Program_Fee_Percentage__c
- Program_Type__c
- Settlement_Amount__c
- Settlement_Percentage__c
- Setup_Fee__c
- Setup_Fee_Term__c
- Sync_Status__c
- Target_Payment_Percent__c
- Total_Additional_Product_Fee__c
- Total_Banking_Fee__c
- Total_Program__c
- Total_Savings__c
- Weekly_Payment__c
- Additional_Product_Fee__c

### Payment_Draft_Item__c Fields (11 fields deleted):
- Banking_Fee__c
- Calculation_Version__c
- Deactivated_Date__c
- Draft_Due_Date__c
- Draft_Number__c
- Is_Active__c
- Payment_Draft__c (Lookup to PaymentDraft__c)
- Program_Fee__c
- Savings__c
- Setup_Fee__c
- Total_Draft__c

### PaymentPlan__c Fields (49 fields deleted):
- Bank2_Fee__c
- Banking_Fee__c
- Calculation_Timestamp__c
- Cancelled_Count__c
- Cleared_Count__c
- Cleared_Escrow_Sum__c
- Cleared_Payment_Sum__c
- Cleared_Program_Fee_Sum__c
- Contract__c
- Current_Payment__c
- First_Payment_Date__c
- First_Payment_Date_Rollup__c
- Is_Active__c
- Last_Payment_Date_Rollup__c
- Monthly_Payment__c
- No_Fee_Program__c
- NSF_Count__c
- Number_of_Payments__c
- Opportunity__c
- Payment_Schedule_JSON__c
- Preferred_Day_of_Week__c
- Previous_Version__c
- Program_Fee_Amount__c
- Program_Fee_Percentage__c
- Program_Type__c
- Schedule_Item_Count__c
- Schedule_Item_Count_Rollup__c
- Scheduled_Count__c
- Settlement_Amount__c
- Settlement_Percentage__c
- Setup_Fee__c
- Setup_Fee_Payments__c
- Source__c
- Status__c
- Total_Banking_Fee_Rollup__c
- Total_Debt__c
- Total_Draft_Amount__c
- Total_Program_Cost__c
- Total_Program_Fee_Rollup__c
- Total_Savings_Rollup__c
- Total_Setup_Fee_Rollup__c
- Total_To_Escrow_Rollup__c
- Version_Notes__c
- Version_Number__c
- Version_Status__c
- Version_Type__c
- Weekly_Payment__c

### Payment_Schedule_Item__c Fields (39 fields deleted):
- Additional_Products_Amount__c
- Bank2_Fee_Amount__c
- Banking_Fee_Amount__c
- Cleared_Amount__c
- Draft_Number__c
- EPPS_EFT_Status__c
- EPPS_EFT_Transaction_Id__c
- EPPS_NSF_Return_Code__c
- EPPS_Returned_Date__c
- EPPS_Settlement_Date__c
- Escrow_Balance__c
- fee_ContactName__c
- fee_Description__c
- fee_PaidToCity__c
- fee_PaidToCustomerNumber__c
- fee_PaidToName__c
- fee_PaidToPhone__c
- fee_PaidToState__c
- fee_PaidToStreet__c
- fee_PaidToStreet2__c
- fee_PaidToZip__c
- Is_Program_Complete__c
- Last_EPPS_Integration__c
- Net_Draft_Amount__c
- Payment_Date__c
- Payment_Number__c
- Payment_Plan__c (Lookup to PaymentPlan__c)
- Program_Fee_Amount__c
- Related_Opportunity__c
- Retainer_Fee_Amount__c
- Running_Balance__c
- Savings_Balance__c
- Setup_Fee_Amount__c
- Status__c
- To_Escrow_Amount__c
- Total_Payment__c
- Wired_Payment_Count__c
- Wires_received__c

### Fee_Settlement_Detail__c Fields (9 fields deleted):
- Amount__c
- Fee_Id__c
- Payment_Schedule_Item__c (Lookup)
- Settlement_Plan_Item__c (Lookup)
- Status_Code__c
- Status_Date__c
- Transaction_Id__c
- Type__c

---

## 2. APEX CLASSES DELETED (22 Classes)

| Class Name | Type | Objects Used |
|------------|------|--------------|
| PaymentPlanService.cls | Service | PaymentDraft__c, Payment_Draft_Item__c, PaymentPlan__c, Payment_Schedule_Item__c |
| PaymentPlanServiceTest.cls | Test | PaymentDraft__c, Payment_Draft_Item__c, PaymentPlan__c, Payment_Schedule_Item__c |
| PaymentPlanEditorController.cls | Controller | PaymentPlan__c, Payment_Schedule_Item__c |
| PaymentPlanEditorControllerTest.cls | Test | PaymentPlan__c, Payment_Schedule_Item__c |
| PaymentCalculatorController.cls | Controller | PaymentDraft__c, Payment_Draft_Item__c |
| PaymentCalculatorControllerTest.cls | Test | PaymentDraft__c, Payment_Draft_Item__c |
| PaymentPlanVersionService.cls | Service | PaymentPlan__c |
| PaymentPlanVersionServiceTest.cls | Test | PaymentPlan__c |
| PaymentPlanTriggerHandler.cls | Handler | PaymentPlan__c |
| PaymentPlanVersionController.cls | Controller | PaymentPlan__c |
| PaymentPlanVersionControllerTest.cls | Test | PaymentPlan__c |
| PaymentScheduleItemTriggerHandler.cls | Handler | Payment_Schedule_Item__c |
| FeeSettlementDetailService.cls | Service | Fee_Settlement_Detail__c |
| FeeSettlementDetailServiceTest.cls | Test | Fee_Settlement_Detail__c |
| SalesCalculatorService.cls | Service | PaymentPlan__c |
| SalesCalculatorServiceTest.cls | Test | PaymentPlan__c |
| OpportunityTriggerHandler.cls | Handler | PaymentDraft__c, PaymentPlan__c |
| OpportunityTriggerHandlerTest.cls | Test | PaymentDraft__c |
| CreditorOpportunityTriggerHandlerTest.cls | Test | PaymentPlan__c |
| ApprovalService.cls | Service | PaymentPlan__c |
| ApprovalServiceTest.cls | Test | PaymentPlan__c |
| TestDataFactory.cls | Test Helper | PaymentDraft__c, Payment_Draft_Item__c, PaymentPlan__c, Payment_Schedule_Item__c |

---

## 3. APEX TRIGGERS DELETED (2 Triggers)

| Trigger Name | Object |
|--------------|--------|
| PaymentPlanTrigger.trigger | PaymentPlan__c |
| PaymentScheduleItemTrigger.trigger | Payment_Schedule_Item__c |

---

## 4. LIGHTNING WEB COMPONENTS DELETED (5 LWCs)

| Component Name | Files Deleted |
|----------------|---------------|
| paymentCalculator | paymentCalculator.js, paymentCalculator.html, paymentCalculator.css, paymentCalculator.js-meta.xml |
| paymentPlanEditor | paymentPlanEditor.js, paymentPlanEditor.html, paymentPlanEditor.css, paymentPlanEditor.js-meta.xml |
| paymentPlanEditorV2 | paymentPlanEditorV2.js, paymentPlanEditorV2.html, paymentPlanEditorV2.css, paymentPlanEditorV2.js-meta.xml |
| paymentPlanTable | paymentPlanTable.js, paymentPlanTable.html, paymentPlanTable.css, paymentPlanTable.js-meta.xml |
| paymentPlanViewer | paymentPlanViewer.js, paymentPlanViewer.html, paymentPlanViewer.css, paymentPlanViewer.js-meta.xml |

---

## 5. FLEXIPAGES / LIGHTNING PAGES DELETED (1 Page)

| Page Name | Object |
|-----------|--------|
| Fee_Settlement_Detail_Record_Page.flexipage-meta.xml | Fee_Settlement_Detail__c |

---

## 6. PAGE LAYOUTS DELETED (1 Layout)

| Layout Name | Object |
|-------------|--------|
| Fee_Settlement_Detail__c-Fee/Settlement Detail Layout | Fee_Settlement_Detail__c |

---

## 7. CUSTOM METADATA TYPES DELETED (1 Type)

| Metadata Type | Records Deleted |
|---------------|-----------------|
| Payment_Calc_Config__mdt | Payment_Calc_Config.Default |

---

## 8. LIST VIEWS DELETED (5 Views)

| Object | List View Name |
|--------|----------------|
| PaymentDraft__c | All |
| Payment_Draft_Item__c | All |
| PaymentPlan__c | All |
| Payment_Schedule_Item__c | All |
| Fee_Settlement_Detail__c | All |

---

## 9. OBJECT RELATIONSHIPS DELETED

```
Opportunity
    └── PaymentDraft__c (via Opportunity__c lookup)
            └── Payment_Draft_Item__c (via Payment_Draft__c lookup)
    └── PaymentPlan__c (via Opportunity__c lookup)
            └── Payment_Schedule_Item__c (via Payment_Plan__c lookup)
                    └── Fee_Settlement_Detail__c (via Payment_Schedule_Item__c lookup)
```

---

## 10. TOTAL COMPONENTS DELETED

| Component Type | Count |
|----------------|-------|
| Custom Objects | 5 |
| Custom Fields | 145 |
| Apex Classes | 22 |
| Apex Triggers | 2 |
| Lightning Web Components | 5 |
| FlexiPages | 1 |
| Page Layouts | 1 |
| Custom Metadata Types | 1 |
| Custom Metadata Records | 1 |
| List Views | 5 |
| **TOTAL** | **188** |

---

## Notes

- All deletions were performed via Salesforce Metadata API using destructive changes deployment
- The local source files remain in the Git repository for version control purposes
- This deletion was performed to clean up the UAT environment
- Backup of all code is available in GitHub: https://github.com/NagaDevSF/ChangesSandBoxUATNaga

---

*Document generated on 2026-01-26*
