# PaymentPlan Field Mapping & DCG Debt First Payment Fee Exclusion

## Task Summary
- **Asana Task ID:** 1213086198011783
- **Title:** Pablo's Request - Program Fee Adjusted
- **Business Objective:** Ensure PaymentPlan__c contains all calculator settings (Target Payment %, Calculation Mode, Payment Frequency, Total Savings, Total Banking Fee) so that payment plans have full parity with PaymentDraft__c. Also apply DCG Debt first payment program fee exclusion to Recalculate and Recalculate Remaining buttons.
- **Technical Objective:** Create 5 missing fields on PaymentPlan__c, map them across all 7 plan creation points, set FLS for all profiles, and add DCG Debt fee skip logic to PaymentPlanEditorController.

## Scope
- **In Scope:**
  - 5 new custom fields on PaymentPlan__c
  - Field mapping in all PaymentPlan__c creation/clone paths
  - FLS for all 47 org profiles
  - DCG Debt first payment fee exclusion in PaymentPlanEditorController (3 methods)
- **Out of Scope:** UI changes, PaymentDraft__c changes, production deployment
- **Assumptions:** PaymentDraft__c already has these fields; PaymentPlanService uses dynamic SOQL to query all draft fields
- **Risks:** None identified; all 120 tests pass

## Impact Analysis
- **Objects:**
  - PaymentPlan__c — 5 new fields created
- **Fields:**
  | Field | Type | Description |
  |---|---|---|
  | Target_Payment_Percent__c | Number(5,2) | Slider percentage value (e.g., 41.1%) |
  | Calculation_Mode__c | Picklist | PERCENT or DESIRED |
  | Payment_Frequency__c | Picklist | Weekly or Monthly |
  | Total_Savings__c | Currency | Total Debt - Total Program Cost |
  | Total_Banking_Fee__c | Currency | Banking Fee × Number of Payments |
- **Apex:**
  - PaymentPlanService.cls — Draft → Plan mapping in Contract Signed trigger
  - PaymentPlanEditorController.cls — 3 plan queries updated, 3 creation methods updated, DCG Debt fee exclusion added
  - PaymentCalculatorController.cls — createPaymentPlanRecord() updated
  - PaymentPlanVersionService.cls — Query + copy in createNewVersion()
  - PaymentPlanVersionController.cls — Query updated for clone in createNewVersion()
- **LWC:** No changes needed
- **Flow/Automation:** None
- **Permissions:** FLS (Read + Edit) set for all 47 profiles via FieldPermissions DML
- **Integrations:** None

## Build Summary
- **What was created:**
  - 5 custom field metadata files under `force-app/main/default/objects/PaymentPlan__c/fields/`
  - 235 FieldPermissions records (5 fields × 47 profiles)
- **What was updated:**

### 1. PaymentPlanService.cls — Contract Signed Trigger Path
**Method:** `buildPaymentScheduleItems()` (lines 32-36)
**When:** Opportunity stage changes to "Contract Signed"
**Mapping:**
```
thisPP.Target_Payment_Percent__c = thisDraft.Target_Payment_Percent__c;
thisPP.Calculation_Mode__c = thisDraft.Calculation_Mode__c;
thisPP.Payment_Frequency__c = thisDraft.Payment_Frequency__c;
thisPP.Total_Savings__c = thisDraft.Total_Savings__c;
thisPP.Total_Banking_Fee__c = thisDraft.Total_Banking_Fee__c;
```

### 2. PaymentPlanEditorController.cls — recalculatePaymentPlan()
**When:** User clicks "Recalculate" button in Payment Plan Editor V2
**Mapping:**
- `Target_Payment_Percent__c` ← carried from previous plan
- `Calculation_Mode__c` ← carried from previous plan
- `Payment_Frequency__c` ← Opportunity.Payment_Frequency__c (fallback: previous plan)
- `Total_Savings__c` ← calculated: Total_Debt - (Settlement + ProgramFee + SetupFee + TotalBankingFee)
- `Total_Banking_Fee__c` ← calculated: bankingFee × Number_of_Payments

### 3. PaymentPlanEditorController.cls — recalculateRemainingBalance()
**When:** User clicks "Recalculate Remaining" button in Payment Plan Editor V2
**Mapping:**
- Uses `.clone()` which carries forward all queried fields from current plan
- `Payment_Frequency__c` ← Opportunity.Payment_Frequency__c (fallback: cloned value)
- `Total_Banking_Fee__c` ← recalculated: bankingFee × Number_of_Payments
- `Total_Savings__c` ← recalculated: totalDebt - recalcTotalProgram

### 4. PaymentPlanEditorController.cls — createNewVersion()
**When:** Manual version creation from UI
**Mapping:** Uses `.clone()` — all 5 fields carry forward from queried plan (query updated to include new fields)

### 5. PaymentCalculatorController.cls — createPaymentPlanRecord()
**When:** Contract creation flow
**Mapping:**
- `Target_Payment_Percent__c` ← config.targetPaymentPercentage
- `Calculation_Mode__c` ← mapped from config.calculationMode ('percentage' → 'PERCENT', 'desired_payment' → 'DESIRED')
- `Payment_Frequency__c` ← config.paymentFrequency
- `Total_Savings__c` ← calculations.totalSavings
- `Total_Banking_Fee__c` ← calculations.bankingFeeTotal

### 6. PaymentPlanVersionService.cls — createNewVersion()
**When:** Version creation via service layer
**Mapping:** Explicit copy from existing plan:
```
newVersion.Target_Payment_Percent__c = existingPlan.Target_Payment_Percent__c;
newVersion.Calculation_Mode__c = existingPlan.Calculation_Mode__c;
newVersion.Payment_Frequency__c = existingPlan.Payment_Frequency__c;
newVersion.Total_Savings__c = existingPlan.Total_Savings__c;
newVersion.Total_Banking_Fee__c = existingPlan.Total_Banking_Fee__c;
```

### 7. PaymentPlanVersionController.cls — createNewVersion()
**When:** Version creation from paymentPlanTable LWC
**Mapping:** Uses `.clone()` — query updated to include new fields so clone carries them

### DCG Debt First Payment Fee Exclusion
Added `skipFeeThisPayment` logic to 3 methods in PaymentPlanEditorController:
- `recalculateRemainingBalance()` — `paymentNumber == 1 && normalizedProgramType == 'DCG_DEBT'`
- `calculateScheduleItems()` — `paymentNumber == 1 && plan.Program_Type__c == 'DCG DEBT'`
- `calculateFreshScheduleItems()` — `i == 1 && plan.Program_Type__c == 'DCG DEBT'`

- **What was reused:** Existing field definitions from PaymentDraft__c as templates; existing clone patterns for version creation
- **What was intentionally not changed:** PaymentDraft__c, LWC components, SalesCalculatorService.createNewVersion() (skeleton method — callers set fields)

## Testing Summary
- **Apex tests:** 120 tests, 100% pass rate
  - PaymentPlanEditorControllerTest: 85 tests passed
  - PaymentPlanVersionServiceTest: 22 tests passed
  - PaymentPlanVersionControllerTest: 13 tests passed
- **FLS verification:** 235 FieldPermissions records inserted successfully, 0 failures
- **Functional tests:** Deployed and verified on NagaDSB sandbox
- **Edge cases checked:** Clone operations carry new fields, calculated fields (Total_Savings, Total_Banking_Fee) are recomputed on recalculate

## Source Control
- **Branch:** master
- **Commit(s):**
  - `d76afbb` — `[1213086198011783] Add 5 new fields to PaymentPlan__c and map across all creation points`
  - `e0c905d` — `Improve saveDraft error toast to show actual error detail`
- **PR:** N/A (direct to master)

## Asana Update
- **Status:** Development Complete, Deployed to NagaDSB
- **Acceptance Criteria Met:**
  | Requirement | Status | Notes |
  |---|---|---|
  | PaymentPlan__c has all calculator settings | Completed | 5 new fields created with FLS |
  | Fields mapped in Contract Signed trigger | Completed | PaymentPlanService maps from draft |
  | Fields mapped in Recalculate/Recalculate Remaining | Completed | PaymentPlanEditorController updated |
  | Fields mapped in all version creation paths | Completed | 4 version creation methods updated |
  | DCG Debt first payment fee exclusion | Completed | 3 methods in PaymentPlanEditorController |
- **Notes:** Not deployed to Production per Naga's instruction
- **Follow-up Items:**
  - UAT validation on NagaDSB sandbox
  - Prod deployment pending Naga's approval
  - Consider backfilling existing PaymentPlan__c records with data from their linked PaymentDraft__c

## Deployment Notes
- Deployed to: NagaDSB sandbox (naga@dcgpro.com.nagadsb)
- NOT deployed to Production (per instruction)
- 5 new custom fields — no destructive changes
- FLS already configured for all 47 profiles
- Safe to deploy to production when ready — no dependencies
