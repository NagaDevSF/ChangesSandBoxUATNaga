# Pre Wire LWC Component — Implementation Document

## Task Summary
- **Asana Task ID:** 1213717837599698
- **Title:** Starting with initial data Entry — Pre Wire LWC + Custom Object
- **Business Objective:** Allow users to manage Pre Wire records related to an Opportunity in a spreadsheet-like interface directly on the Opportunity record page
- **Technical Objective:** Create a custom object (Pre_Wire__c), Apex controller (PreWireController), and LWC component (preWireManager) with full CRUD operations, inline editing, and validation

## Scope

### In Scope
- Custom object Pre_Wire__c with Auto Number naming (PW-{00000})
- Lookup to Opportunity (Opportunity__c)
- Date_Value__c (Date) and Amount__c (Currency) fields
- Apex controller with get/create/update/delete methods
- LWC component for Opportunity record page with:
  - Spreadsheet-like table with Business Name, Date Value, Amount, Actions columns
  - Insert new row button
  - Inline editing for Date Value and Amount
  - Save/Cancel/Edit/Delete actions
  - Business Name auto-populated from Opportunity → Account Name (read-only)
  - Toast notifications and confirmation dialogs
  - Empty state message
- Permission set (Pre_Wire_Admin) for object and field access
- Full Apex test class with 27 tests, 90% coverage

### Out of Scope
- Total amount footer
- Multi-row save
- Row cloning
- CSV/Excel import
- Sort/filter
- Duplicate validation
- Locking/edit permissions by stage
- Created by / Last modified columns
- Modal-based edit form

### Assumptions
- Business Name always comes from Opportunity → Account → Name
- The component is placed on the Opportunity record page only
- Users have the Pre_Wire_Admin permission set assigned for access
- All Pre Wire records sort by Date Value ascending

### Risks
- If Opportunity has no Account, Business Name displays as blank (handled gracefully)

## Impact Analysis
- **Objects:** Pre_Wire__c (new)
- **Fields:** Opportunity__c, Date_Value__c, Amount__c (new)
- **Apex:** PreWireController (new), PreWireControllerTest (new)
- **LWC:** preWireManager (new)
- **Flow/Automation:** None
- **Permissions:** Pre_Wire_Admin permission set (new)
- **Integrations:** None

## Build Summary

### What was created
| Component | Type | API Name |
|-----------|------|----------|
| Pre Wire | Custom Object | Pre_Wire__c |
| Opportunity | Lookup Field | Pre_Wire__c.Opportunity__c |
| Date Value | Date Field | Pre_Wire__c.Date_Value__c |
| Amount | Currency Field | Pre_Wire__c.Amount__c |
| PreWireController | Apex Class | PreWireController |
| PreWireControllerTest | Apex Test Class | PreWireControllerTest |
| preWireManager | LWC | preWireManager |
| Pre Wire Admin | Permission Set | Pre_Wire_Admin |

### What was reused
- Existing project patterns: emoji logging, section headers, wrapper DTOs, AuraHandledException, SLDS table styling

### What was intentionally not changed
- No existing components modified
- No existing automation affected

## Testing Summary

### Apex Tests (27 tests, 100% pass, 90% coverage)

**Happy Path (4 tests):**
- testGetPreWireContext_Success — loads context with account name and 5 records sorted by date
- testCreatePreWire_Success — creates record and verifies all fields including business name
- testUpdatePreWire_Success — updates date and amount, verifies persistence
- testDeletePreWire_Success — deletes record, verifies removal

**No Data / Null Input (6 tests):**
- testGetPreWireContext_BlankId / NullId
- testCreatePreWire_BlankInput / NullInput
- testUpdatePreWire_BlankInput
- testDeletePreWire_BlankId

**Error Handling (7 tests):**
- testGetPreWireContext_InvalidOpportunityId
- testCreatePreWire_InvalidJson / MissingOpportunityId / MissingDate / ZeroAmount / NegativeAmount
- testUpdatePreWire_InvalidJson

**Bulk Operations (1 test):**
- testGetPreWireContext_ManyRecords — 205 records loaded successfully

**Edge Cases (5 tests):**
- testGetPreWireContext_OpportunityWithNoAccount
- testGetPreWireContext_OpportunityWithNoWires
- testCreatePreWire_LargeAmount / SmallAmount
- testUpdatePreWire_MissingRecordId / NonExistentRecord
- testDeletePreWire_NonExistentRecord
- testCreateAndThenDelete — full lifecycle test

### Functional Tests
- Component renders on Opportunity record page
- Insert adds new editable row with auto-populated Business Name
- Save creates Pre_Wire__c record and refreshes table
- Edit switches row to edit mode with date/amount inputs
- Cancel restores original values (or removes unsaved new row)
- Delete shows LightningConfirm dialog, removes record on confirm
- Validation: Amount > 0, Date required
- Empty state displayed when no records exist

### Known Limitations
- 10% uncovered lines are DML catch blocks (rollback paths) — difficult to trigger in test without breaking DML deliberately

## Source Control
- **Branch:** master
- **Commit(s):** See git log
- **PR:** N/A (direct to master)

## Deployment Notes
- Deploy order: Pre_Wire__c object → fields → Apex classes → LWC → Permission set
- Assign Pre_Wire_Admin permission set to users who need access
- Add preWireManager component to Opportunity Lightning Record Page via App Builder
- The component auto-detects the recordId from page context

## Architecture Notes

### Apex Controller Pattern
- `public with sharing` class with emoji logging constants
- Wrapper DTOs: PreWireContext (top-level), PreWireRecord (row data), PreWireInput (save data)
- Helper: `throwAuraException()` with `setMessage()` for proper test context message access
- `Database.setSavepoint()` for DML rollback safety
- All SOQL outside loops, bulkified

### LWC Pattern
- Client-side row management with `clientKey` for template iteration
- `@track rows` array for mutation tracking
- Async/await for all Apex calls with try/catch/finally
- `reduceError()` utility for consistent error display
- `Intl.NumberFormat` for currency formatting
- `LightningConfirm` for delete confirmation
- `lwc:if` / `lwc:else` directives (not legacy if:true)
