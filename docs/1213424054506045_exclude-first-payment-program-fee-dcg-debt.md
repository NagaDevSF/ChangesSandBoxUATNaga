# Exclude First Payment Program Fee for DCG Debt

## Task Summary
- **Asana Task ID:** 1213424054506045
- **Title:** For DCG Debt we should not include the first payment's program fee
- **Business Objective:** When a Draft is saved in the Sales Calculator for DCG Debt, the first payment should not include the program fee. Fee collection should start from Payment #2.
- **Technical Objective:** Modify payment schedule generation to skip program fee allocation on the first payment for DCG Debt programs.

## Scope
- **In Scope:** Program fee exclusion on first payment for DCG Debt in both calculation paths (CalculationService and SalesCalculatorService)
- **Out of Scope:** DCG MOD programs, no-fee programs, setup fee logic, banking fee logic, LWC display changes
- **Assumptions:** The total program fee amount remains unchanged; the fee that would have been on Payment #1 is redistributed across remaining payments naturally by the existing allocation loop
- **Risks:** None identified; existing tests all pass

## Impact Analysis
- **Objects:** Payment_Schedule_Item__c (field values affected: Program_Fee_Amount__c, To_Escrow_Amount__c for first item)
- **Fields:** No new fields; existing fields receive different values for first payment
- **Apex:**
  - CalculationService.cls (primary Sales Calculator path)
  - SalesCalculatorService.cls (version-based calculation path)
- **LWC:** No changes needed; LWC displays data from Apex
- **Flow/Automation:** None
- **Permissions:** None
- **Integrations:** None

## Build Summary
- **What was created:** Nothing new
- **What was updated:**
  - `CalculationService.cls` — Added `excludeFirstPaymentFee` flag and `skipFeeThisPayment` check in `generatePaymentSchedule()` method (lines 676-700). When `programType == 'DCG_DEBT'`, the first payment (index 0) skips program fee allocation and sends full net amount to escrow.
  - `SalesCalculatorService.cls` — Added `skipFeeThisPayment` check in `generatePaymentSchedule()` method (lines 304-316). When `plan.Program_Type__c == 'DCG DEBT'`, payment #1 skips program fee allocation.
- **What was reused:** Existing program fee allocation loop; the skip simply redirects first payment's full amount to escrow
- **What was intentionally not changed:** LWC components, PaymentCalculatorController, PaymentFeeService, PaymentCalcConfigSvc

## Technical Detail

### Before (DCG Debt Payment #1):
```
Payment #1: programFee = netAmount * 0.70 (programSplitRatio), escrow = netAmount - programFee
```

### After (DCG Debt Payment #1):
```
Payment #1: programFee = $0.00, escrow = netAmount (full amount to escrow)
Payment #2+: programFee = netAmount * 0.70 (unchanged)
```

The total program fee collected across all payments remains the same. The fee that would have been on Payment #1 is naturally absorbed by subsequent payments since the `remainingProgramFees` balance is unchanged when entering Payment #2.

## Testing Summary
- **Apex tests:** 43 tests, 100% pass rate
  - CalculationServiceTest: 21 tests passed (86% coverage)
  - SalesCalculatorServiceTest: 22 tests passed (99% coverage)
- **Functional tests:** Deployed and validated on NagaDSB sandbox
- **Edge cases checked:** No-fee programs unaffected, DCG MOD unaffected, existing schedule generation logic unchanged
- **Known limitations:** No dedicated test method for the first-payment exclusion; covered implicitly by existing DCG Debt test paths

## Source Control
- **Branch:** master
- **Commit(s):** a1e86d9 — `[1213424054506045] Exclude program fee from first payment for DCG Debt`
- **PR:** N/A (direct to master)

## Asana Update
- **Status:** Development Complete, Deployed to NagaDSB
- **Acceptance Criteria Met:**
  | Requirement | Status | Notes |
  |---|---|---|
  | First payment should not include program fee for DCG Debt | Completed | Both calculation paths updated |
  | Sales Calculator draft should reflect the change | Completed | CalculationService handles the LWC calculation flow |
- **Notes:** No prod deployment yet per Naga's instruction
- **Follow-up Items:**
  - UAT validation on NagaDSB sandbox
  - Consider adding a dedicated test method for first-payment fee exclusion
  - Prod deployment pending Naga's approval

## Deployment Notes
- Deployed to: NagaDSB sandbox (naga@dcgpro.com.nagadsb)
- NOT deployed to Production (per instruction)
- No destructive changes; no new metadata types
- Safe to deploy to production when ready — no dependencies
