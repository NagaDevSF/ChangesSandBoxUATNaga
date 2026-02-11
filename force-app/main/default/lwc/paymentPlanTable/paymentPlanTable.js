import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPaymentPlanVersions from '@salesforce/apex/PaymentPlanVersionController.getPaymentPlanVersions';
import getPaymentScheduleItems from '@salesforce/apex/PaymentPlanVersionController.getPaymentScheduleItems';
import activateVersion from '@salesforce/apex/PaymentPlanVersionController.activateVersion';
import createNewVersion from '@salesforce/apex/PaymentPlanVersionController.createNewVersion';

export default class PaymentPlanTable extends LightningElement {
    @api recordId; // Opportunity or Account ID - automatically populated when placed on record page
    @api paymentPlanId; // Optional: specific Payment Plan ID to display
    @api isReadOnly = false;
    @api showVersionHistory = false; // Changed to false to avoid LWC warning
    
    // NEW: Accept payment schedule data from parent component for reactive display
    _paymentScheduleData = [];
    @api 
    get paymentScheduleData() {
        return this._paymentScheduleData;
    }
    set paymentScheduleData(value) {
        console.log('PaymentPlanTable: paymentScheduleData setter called with:', value);
        // Always update the internal data, even if it's the same reference
        this._paymentScheduleData = value ? [...value] : [];
        if (this._paymentScheduleData && this._paymentScheduleData.length > 0) {
            console.log('PaymentPlanTable: Processing data from setter');
            // Force re-processing and re-render
            this.paymentScheduleItems = [...this.processScheduleItems(this._paymentScheduleData)];
            console.log('PaymentPlanTable: Schedule items updated:', this.paymentScheduleItems.length, 'items');
        } else {
            this.paymentScheduleItems = [];
            console.log('PaymentPlanTable: Schedule cleared');
        }
    }
    
    @api isReactiveMode = false; // When true, uses data from parent instead of fetching
    
    paymentPlanVersions = [];
    selectedVersionId;
    paymentScheduleItems = [];
    isLoading = false;
    showFullscreen = false;
    selectedVersion = {};
    
    // Version history columns
    versionColumns = [
        { label: 'Version', fieldName: 'Version_Number__c', type: 'number', initialWidth: 80 },
        { label: 'Status', fieldName: 'Version_Status__c', type: 'text', initialWidth: 100 },
        { label: 'Created Date', fieldName: 'CreatedDate', type: 'date', initialWidth: 130 },
        { label: 'Created By', fieldName: 'CreatedByName', type: 'text', initialWidth: 130 },
        { label: 'Notes', fieldName: 'Version_Notes__c', type: 'text' },
        { 
            label: 'Active', 
            fieldName: 'Is_Active__c', 
            type: 'boolean',
            initialWidth: 80,
            cellAttributes: { 
                iconName: { fieldName: 'activeIcon' },
                iconPosition: 'left' 
            }
        },
        {
            type: 'action',
            typeAttributes: { 
                rowActions: this.getRowActions.bind(this)
            }
        }
    ];
    
    // Payment schedule columns with all fees - removed Bank2, Retainer, and Running Total per requirements
    // Using flexible widths to fill container
    scheduleColumns = [
        { label: 'Draft #', fieldName: 'draftNumber', type: 'number', minColumnWidth: 70, maxColumnWidth: 100, cellAttributes: { alignment: 'center' } },
        { label: 'Date', fieldName: 'paymentDate', type: 'date-local', minColumnWidth: 100, maxColumnWidth: 150 },
        { label: 'Draft', fieldName: 'draftAmount', type: 'currency', minColumnWidth: 110, maxColumnWidth: 180, typeAttributes: { currencyCode: 'USD' } },
        { label: 'Setup', fieldName: 'setupFee', type: 'currency', minColumnWidth: 90, maxColumnWidth: 150, typeAttributes: { currencyCode: 'USD' } },
        { label: 'Program', fieldName: 'programFee', type: 'currency', minColumnWidth: 110, maxColumnWidth: 180, typeAttributes: { currencyCode: 'USD' } },
        { label: 'Banking', fieldName: 'bankingFee', type: 'currency', minColumnWidth: 90, maxColumnWidth: 150, typeAttributes: { currencyCode: 'USD' } },
        { label: 'Addl. Products', fieldName: 'additionalProducts', type: 'currency', minColumnWidth: 120, maxColumnWidth: 180, typeAttributes: { currencyCode: 'USD' } },
        { label: 'Savings', fieldName: 'escrowAmount', type: 'currency', minColumnWidth: 110, maxColumnWidth: 180, typeAttributes: { currencyCode: 'USD' } }
    ];
    
    connectedCallback() {
        console.log('PaymentPlanTable: connectedCallback called');
        console.log('PaymentPlanTable: isReactiveMode:', this.isReactiveMode);
        console.log('PaymentPlanTable: paymentScheduleData length:', this.paymentScheduleData?.length || 0);
        console.log('PaymentPlanTable: paymentScheduleData:', this.paymentScheduleData);
        console.log('PaymentPlanTable: recordId:', this.recordId);
        console.log('PaymentPlanTable: paymentPlanId:', this.paymentPlanId);
        
        // If in reactive mode, use parent-provided data
        if (this.isReactiveMode && this.paymentScheduleData) {
            console.log('PaymentPlanTable: Using reactive mode with parent data');
            this.paymentScheduleItems = this.processScheduleItems(this.paymentScheduleData);
        } else {
            console.log('PaymentPlanTable: Using independent data loading');
            // Original behavior: fetch data independently
            if (this.recordId) {
                // Check if recordId is an Opportunity or PaymentPlan
                this.determineRecordTypeAndLoad();
            } else if (this.paymentPlanId) {
                // Direct payment plan ID provided
                this.selectedVersionId = this.paymentPlanId;
                this.loadPaymentSchedule();
            }
        }
    }
    
    renderedCallback() {
        console.log('PaymentPlanTable: renderedCallback called');
        console.log('PaymentPlanTable: paymentScheduleItems length:', this.paymentScheduleItems?.length || 0);
        console.log('PaymentPlanTable: showVersionHistory:', this.showVersionHistory);
        console.log('PaymentPlanTable: isReactiveMode:', this.isReactiveMode);
        
        // If we have schedule items, ensure they're displayed
        if (this.paymentScheduleItems && this.paymentScheduleItems.length > 0) {
            console.log('PaymentPlanTable: Schedule items are available for display');
        } else {
            console.log('PaymentPlanTable: No schedule items available');
        }
    }
    
    determineRecordTypeAndLoad() {
        // If the recordId starts with '006', it's an Opportunity
        // If it starts with 'a' followed by alphanumeric, it's likely a custom object (PaymentPlan__c)
        const prefix = this.recordId.substring(0, 3);
        
        if (prefix === '006') {
            // Opportunity record
            this.loadPaymentPlanVersions();
        } else if (prefix.startsWith('a')) {
            // Likely a PaymentPlan__c record
            this.selectedVersionId = this.recordId;
            this.loadSinglePaymentPlan();
        } else {
            // Account or other object type
            this.loadPaymentPlanVersions();
        }
    }
    
    loadSinglePaymentPlan() {
        // Load the payment plan and its schedule when viewing a PaymentPlan__c record directly
        this.selectedVersionId = this.recordId;
        this.loadPaymentSchedule();
        
        // Optionally load version history for this payment plan's opportunity
        if (this.showVersionHistory) {
            this.loadRelatedVersions();
        }
    }
    
    loadRelatedVersions() {
        // This would load other versions related to the same opportunity
        // Implementation would require getting the opportunity ID from the payment plan first
        // For now, just load the schedule
        this.loadPaymentSchedule();
    }
    
    @api
    refreshData() {
        if (this.isReactiveMode && this.paymentScheduleData) {
            // In reactive mode, reprocess the parent-provided data
            this.paymentScheduleItems = this.processScheduleItems(this.paymentScheduleData);
        } else {
            // Original behavior
            this.loadPaymentPlanVersions();
        }
    }
    
    // NEW: Method to update schedule from parent component
    @api
    updateSchedule(scheduleData) {
        console.log('PaymentPlanTable: updateSchedule called with data:', scheduleData);
        if (scheduleData && scheduleData.length > 0) {
            this.paymentScheduleData = scheduleData;
            console.log('PaymentPlanTable: Processing schedule items');
            this.paymentScheduleItems = this.processScheduleItems(scheduleData);
            this.isReactiveMode = true;
            console.log('PaymentPlanTable: Processed schedule items:', this.paymentScheduleItems);
            console.log('PaymentPlanTable: isReactiveMode set to:', this.isReactiveMode);
        } else {
            console.log('PaymentPlanTable: No schedule data provided or empty array');
        }
    }
    
    loadPaymentPlanVersions() {
        this.isLoading = true;
        getPaymentPlanVersions({ opportunityId: this.recordId })
            .then(result => {
                this.paymentPlanVersions = result.map(version => ({
                    ...version,
                    CreatedByName: version.CreatedBy?.Name || '',
                    activeIcon: version.Is_Active__c ? 'utility:check' : ''
                }));
                
                // Auto-select active version
                const activeVersion = this.paymentPlanVersions.find(v => v.Is_Active__c);
                if (activeVersion) {
                    this.selectedVersionId = activeVersion.Id;
                    this.selectedVersion = activeVersion;
                    this.loadPaymentSchedule();
                }
            })
            .catch(error => {
                this.showError('Failed to load payment plan versions', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    loadPaymentSchedule() {
        if (!this.selectedVersionId) return;
        
        this.isLoading = true;
        getPaymentScheduleItems({ paymentPlanId: this.selectedVersionId })
            .then(result => {
                this.paymentScheduleItems = this.processScheduleItems(result);
            })
            .catch(error => {
                this.showError('Failed to load payment schedule', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    processScheduleItems(items) {
        console.log('PaymentPlanTable: processScheduleItems called with:', items);
        if (!items || items.length === 0) {
            console.log('PaymentPlanTable: No items to process');
            return [];
        }
        
        let runningTotal = 0;
        const processed = items.map((item, index) => {
            console.log(`PaymentPlanTable: Processing item ${index}:`, item);
            // Handle both database records and reactive data from parent
            const payment = item.Total_Payment__c || item.totalPayment || item.paymentAmount || 0;
            runningTotal += payment;
            
            const processedItem = {
                id: item.Id || `temp-${index}`,
                draftNumber: item.Draft_Number__c || item.draftNumber || (index + 1),
                paymentDate: item.Payment_Date__c || item.paymentDate || item.dueDate,
                draftAmount: payment,
                retainerFee: item.Retainer_Fee_Amount__c || item.retainerFee || 0,
                setupFee: item.Setup_Fee_Amount__c || item.setupFee || item.setupFeePortion || 0,
                programFee: item.Program_Fee_Amount__c || item.programFee || item.programPortion || 0,
                bankingFee: item.Banking_Fee_Amount__c || item.bankingFee || item.bankingFeePortion || 0,
                bank2Fee: item.Bank2_Fee_Amount__c || item.bank2Fee || item.bank2Portion || 0,
                additionalProducts: item.Additional_Products_Amount__c || item.additionalProducts || 0,
                escrowAmount: item.To_Escrow_Amount__c || item.escrowAmount || item.savingsBalance || 0,
                runningTotal: item.Running_Balance__c || item.runningBalance || runningTotal
            };
            console.log(`PaymentPlanTable: Processed item ${index}:`, processedItem);
            return processedItem;
        });
        
        console.log('PaymentPlanTable: All processed items:', processed);
        return processed;
    }
    
    getRowActions(row, doneCallback) {
        const actions = [];
        
        if (!row.Is_Active__c && !this.isReadOnly) {
            actions.push({ label: 'Activate', name: 'activate' });
        }
        actions.push({ label: 'View Details', name: 'view' });
        
        if (!this.isReadOnly) {
            actions.push({ label: 'Create New Version', name: 'create_version' });
        }
        
        doneCallback(actions);
    }
    
    handleVersionRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        
        switch (actionName) {
            case 'activate':
                this.handleActivateVersion(row.Id);
                break;
            case 'view':
                this.handleViewVersion(row);
                break;
            case 'create_version':
                this.handleCreateNewVersion(row.Id);
                break;
        }
    }
    
    handleActivateVersion(versionId) {
        this.isLoading = true;
        activateVersion({ paymentPlanId: versionId })
            .then(() => {
                this.showSuccess('Version activated successfully');
                this.loadPaymentPlanVersions();
            })
            .catch(error => {
                this.showError('Failed to activate version', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    handleViewVersion(version) {
        this.selectedVersionId = version.Id;
        this.selectedVersion = version;
        this.loadPaymentSchedule();
    }
    
    handleCreateNewVersion(baseVersionId) {
        this.isLoading = true;
        createNewVersion({ basePaymentPlanId: baseVersionId })
            .then(result => {
                this.showSuccess('New version created successfully');
                this.selectedVersionId = result.Id;
                this.loadPaymentPlanVersions();
                
                // Dispatch event for parent component
                this.dispatchEvent(new CustomEvent('versioncreated', {
                    detail: { paymentPlanId: result.Id }
                }));
            })
            .catch(error => {
                this.showError('Failed to create new version', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    handleVersionSelection(event) {
        const selectedRows = event.detail.selectedRows;
        if (selectedRows.length > 0) {
            this.handleViewVersion(selectedRows[0]);
        }
    }
    
    handleFullscreenToggle() {
        this.showFullscreen = !this.showFullscreen;
    }
    
    handleExportSchedule() {
        // Convert payment schedule to CSV
        const headers = this.scheduleColumns.map(col => col.label).join(',');
        const rows = this.paymentScheduleItems.map(item => {
            return this.scheduleColumns.map(col => {
                const value = item[col.fieldName];
                // Format currency and date values
                if (col.type === 'currency') {
                    return `$${(value || 0).toFixed(2)}`;
                } else if (col.type === 'date-local' && value) {
                    return new Date(value).toLocaleDateString();
                }
                return value || '';
            }).join(',');
        });
        
        const csv = [headers, ...rows].join('\n');
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `payment_schedule_v${this.selectedVersion.Version_Number__c || '1'}_${new Date().toISOString().split('T')[0]}.csv`;
        link.click();
        window.URL.revokeObjectURL(url);
        
        this.showSuccess('Payment schedule exported successfully');
    }
    
    handlePrintSchedule() {
        window.print();
    }
    
    // Summary calculations
    get totalDraftAmount() {
        return this.paymentScheduleItems.reduce((sum, item) => sum + item.draftAmount, 0);
    }
    
    get totalProgramFees() {
        return this.paymentScheduleItems.reduce((sum, item) => sum + item.programFee, 0);
    }
    
    get totalEscrow() {
        return this.paymentScheduleItems.reduce((sum, item) => sum + item.escrowAmount, 0);
    }
    
    get totalSetupFees() {
        return this.paymentScheduleItems.reduce((sum, item) => sum + item.setupFee, 0);
    }
    
    get numberOfPayments() {
        return this.paymentScheduleItems.length;
    }
    
    get firstPaymentDate() {
        return this.paymentScheduleItems[0]?.paymentDate || '';
    }
    
    get lastPaymentDate() {
        return this.paymentScheduleItems[this.paymentScheduleItems.length - 1]?.paymentDate || '';
    }
    
    // Utility methods
    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message: message,
            variant: 'success'
        }));
    }
    
    showError(title, error) {
        console.error(title, error);
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: error?.body?.message || error?.message || 'An error occurred',
            variant: 'error'
        }));
    }
}