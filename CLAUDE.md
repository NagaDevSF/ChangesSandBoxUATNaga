# Mandatory Development Workflow - Naga's Rules

## ALWAYS DO THESE FOR EVERY TASK:

### 1. Asana Updates (MANDATORY)
- Update the relevant Asana task with detailed requirements before starting work
- Update Asana task status when development is complete
- Workspace: dcgpro.com (ID: 1207860012563297)
- Assignee: Naga (ID: 1210859739324139)

### 2. Git Updates (MANDATORY)
- Commit all changes with descriptive messages after completing each task
- Push to remote: https://github.com/NagaDevSF/ChangesSandBoxUATNaga.git (branch: master)
- Git user: naga <naga@dcgpro.com>

### 3. Salesforce Org
- Default org: naga@dcgpro.com.nagadsb
- Always deploy changes to the org after development

## Project Context
- This is a Salesforce DX project (dcgpro.com)
- Primary LWC components: paymentPlanEditorV2, paymentPlanEditor, paymentPlanViewer
- Apex controllers: PaymentPlanEditorController, PaymentFeeService
- EPPS integration classes for payment processing
