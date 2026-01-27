import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getLatestPaymentPlan from '@salesforce/apex/PaymentPlanEditorController.getLatestPaymentPlan';
import getWireFeesByPlanId from '@salesforce/apex/PaymentPlanEditorController.getWireFeesByPlanId';
import getStatusPicklistValues from '@salesforce/apex/PaymentPlanEditorController.getStatusPicklistValues';

// Default fallback if dynamic fetch fails
const DEFAULT_STATUS_OPTIONS = [
    { label: 'Scheduled', value: 'Scheduled' },
    { label: 'Cleared', value: 'Cleared' },
    { label: 'NSF', value: 'NSF' },
    { label: 'Cancelled', value: 'Cancelled' }
];

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2
});

export default class PaymentPlanViewer extends LightningElement {
    @api recordId;

    // State for payment plan data
    @track paymentPlan = null;
    @track scheduleItems = [];
    @track wireFeeMap = {};

    // Dynamic picklist values for Status field
    @track statusPicklistOptions = DEFAULT_STATUS_OPTIONS;

    // UI state
    @track isLoading = true;
    @track isMaximized = false;

    // ============ LIFECYCLE HOOKS ============

    async connectedCallback() {
        // Load status picklist values and active plan in parallel
        await Promise.all([
            this.loadStatusPicklistValues(),
            this.loadActivePlan()
        ]);
    }

    /**
     * Load status picklist values dynamically from Salesforce schema
     */
    async loadStatusPicklistValues() {
        try {
            const options = await getStatusPicklistValues();
            if (options && options.length > 0) {
                this.statusPicklistOptions = options;
            }
        } catch (error) {
            console.error('Error loading status picklist values:', error);
            this.statusPicklistOptions = DEFAULT_STATUS_OPTIONS;
        }
    }

    // ============ DATA LOADING METHODS ============

    /**
     * Load the currently active payment plan for this opportunity
     */
    async loadActivePlan() {
        this.isLoading = true;
        try {
            const wrapper = await getLatestPaymentPlan({ opportunityId: this.recordId });

            if (wrapper && wrapper.paymentPlan) {
                this.paymentPlan = wrapper.paymentPlan;
                this.scheduleItems = this.processItems(wrapper.scheduleItems || []);

                // Load Wire Fees for this plan
                await this.loadWireFees(wrapper.paymentPlan.Id);
            } else {
                this.paymentPlan = null;
                this.scheduleItems = [];
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.paymentPlan = null;
            this.scheduleItems = [];
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Load Wire Fees for all schedule items in the plan
     */
    async loadWireFees(planId) {
        try {
            const wireFeesResult = await getWireFeesByPlanId({ planId: planId });
            this.wireFeeMap = wireFeesResult || {};
        } catch (error) {
            console.error('Error loading wire fees:', error);
            this.wireFeeMap = {};
        }
    }

    /**
     * Handle manual refresh button click
     */
    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.loadActivePlan();
            this.showToast('Success', 'Data refreshed', 'success');
        } catch (error) {
            console.error('Error refreshing data:', error);
            this.showToast('Error', 'Failed to refresh data', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Handle maximize/minimize toggle
     */
    handleMaximize() {
        this.isMaximized = !this.isMaximized;
    }

    // ============ COMPUTED PROPERTIES ============

    get hasPaymentPlan() {
        return this.paymentPlan !== null;
    }

    get hasPlans() {
        // Now just checks if there's an active payment plan
        return this.paymentPlan !== null;
    }

    get planName() {
        return this.paymentPlan?.Name || 'Payment Plan';
    }

    get versionInfo() {
        if (!this.paymentPlan) return '';
        const version = this.paymentPlan.Version_Number__c || 1;
        const status = this.paymentPlan.Version_Status__c || '';
        return `v${version} - ${status}`;
    }

    get activeTabLabel() {
        if (!this.paymentPlan) return 'Active';
        const name = this.paymentPlan.Name || 'Plan';
        const version = this.paymentPlan.Version_Number__c || 1;
        return `${name} v${version}`;
    }

    get modalContainerClass() {
        return this.isMaximized ? 'payment-plan-viewer maximized' : 'payment-plan-viewer';
    }

    /**
     * Get display items with Draft # calculation and nested wire fees
     */
    get displayItems() {
        if (!this.scheduleItems || this.scheduleItems.length === 0) {
            return [];
        }

        // Sort by date ascending
        const sortedItems = [...this.scheduleItems].sort((a, b) => {
            const dateA = a.paymentDate ? new Date(a.paymentDate) : new Date(0);
            const dateB = b.paymentDate ? new Date(b.paymentDate) : new Date(0);
            return dateA - dateB;
        });

        // Calculate Draft # that skips NSF and Cancelled rows
        let draftCounter = 0;
        const result = [];

        sortedItems.forEach(item => {
            const skipStatuses = ['NSF', 'Cancelled'];
            const shouldSkip = skipStatuses.includes(item.status);

            if (!shouldSkip) {
                draftCounter++;
            }

            // Add the schedule item
            const scheduleItem = {
                ...item,
                calculatedDraftNumber: shouldSkip ? '-' : String(draftCounter),
                hasDraftNumber: !shouldSkip,
                isWireFee: false,
                uniqueKey: `schedule_${item.id || item.tempId}`
            };
            result.push(scheduleItem);

            // Add wire fees as nested rows (if any)
            const wireFees = this.wireFeeMap[item.id] || [];
            // Calculate wire status class based on total wires vs draft amount
            const wiresTotal = wireFees.reduce((sum, f) => sum + (Number(f.amount) || 0), 0);
            const wireStatusClass = wiresTotal >= draftAmount ? 'wire-row-green' : 'wire-row-orange';

            wireFees.forEach(fee => {
                result.push({
                    ...fee,
                    isWireFee: true,
                    parentScheduleItemId: item.id,
                    uniqueKey: `wire_${fee.id}`,
                    feeTypeFormatted: fee.feeType,
                    amountFormatted: this.formatCurrency(fee.amount || 0),
                    wireRowClass: `wire-sub-row ${wireStatusClass}`
                });
            });
        });

        return result;
    }

    get hasDisplayItems() {
        return this.displayItems && this.displayItems.length > 0;
    }

    get itemCount() {
        return this.scheduleItems.filter(item => !item.isDeleted).length;
    }

    // ============ AGGREGATE GETTERS (Footer Totals) ============

    get totalDraftAmount() {
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;

        let total = items.reduce((sum, item) => sum + (Number(item.draftAmount) || 0), 0);

        // Add wire fees
        Object.values(this.wireFeeMap).forEach(wireFees => {
            wireFees.forEach(fee => {
                total += Number(fee.amount) || 0;
            });
        });

        return total;
    }

    get totalDraftAmountFormatted() {
        return this.formatCurrency(this.totalDraftAmount);
    }

    get totalSetupFee() {
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.setupFee) || 0), 0);
    }

    get totalSetupFeeFormatted() {
        return this.formatCurrency(this.totalSetupFee);
    }

    get totalProgramFee() {
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.programFee) || 0), 0);
    }

    get totalProgramFeeFormatted() {
        return this.formatCurrency(this.totalProgramFee);
    }

    get totalBankingFee() {
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.bankingFee) || 0), 0);
    }

    get totalBankingFeeFormatted() {
        return this.formatCurrency(this.totalBankingFee);
    }

    get totalSavingsBalance() {
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.savingsBalance) || 0), 0);
    }

    get totalSavingsBalanceFormatted() {
        return this.formatCurrency(this.totalSavingsBalance);
    }

    get totalRowCount() {
        return this.scheduleItems ? this.scheduleItems.length : 0;
    }

    // ============ HELPER METHODS ============

    /**
     * Process items for display with formatting
     */
    processItems(items) {
        return items.map((item, index) => {
            const rowNumber = item.rowNumber || index + 1;

            const draftAmount = Number(item.draftAmount) || 0;
            const setupFee = Number(item.setupFee) || 0;
            const programFee = Number(item.programFee) || 0;
            const bankingFee = Number(item.bankingFee) || 0;
            const savingsBalance = Number(item.savingsBalance) || 0;

            const itemStatus = item.status || 'Scheduled';

            return {
                ...item,
                id: item.id || null,
                tempId: item.tempId || `temp_${Date.now()}_${index}`,
                rowNumber: rowNumber,
                rowNumberClass: 'row-number',
                draftNumber: item.draftNumber || String(rowNumber),
                paymentDate: item.paymentDate,
                paymentDateDisplay: this.formatDate(item.paymentDate),
                draftAmount: draftAmount,
                draftAmountFormatted: this.formatCurrency(draftAmount),
                draftAmountClass: this.getAmountClass(draftAmount),
                setupFee: setupFee,
                setupFeeFormatted: this.formatCurrency(setupFee),
                setupFeeClass: this.getAmountClass(setupFee),
                programFee: programFee,
                programFeeFormatted: this.formatCurrency(programFee),
                programFeeClass: this.getAmountClass(programFee),
                bankingFee: bankingFee,
                bankingFeeFormatted: this.formatCurrency(bankingFee),
                bankingFeeClass: this.getAmountClass(bankingFee),
                savingsBalance: savingsBalance,
                savingsBalanceFormatted: this.formatCurrency(savingsBalance),
                savingsClass: savingsBalance < 0 ? 'savings-negative' : 'savings-positive',
                status: itemStatus,
                statusBadgeClass: this.getStatusBadgeClass(itemStatus),
                rowClass: this.getRowClass({ ...item, status: itemStatus })
            };
        });
    }

    getAmountClass(value) {
        if (value === 0) return 'value-zero';
        if (value < 0) return 'value-negative';
        return '';
    }

    formatCurrency(value) {
        if (value === null || value === undefined || isNaN(value)) {
            return '$0.00';
        }
        return CURRENCY_FORMATTER.format(value);
    }

    formatDate(dateValue) {
        if (!dateValue) return '';
        try {
            const date = new Date(dateValue + 'T00:00:00');
            return date.toLocaleDateString('en-US', {
                month: '2-digit',
                day: '2-digit',
                year: 'numeric'
            });
        } catch (e) {
            return dateValue;
        }
    }

    getRowClass(item) {
        const classes = [];

        // Status-based row colors: Cleared=Green, NSF=Red, Cancelled=Yellow, Scheduled=Blue
        if (item.status === 'Cleared') {
            classes.push('row-cleared');
        } else if (item.status === 'NSF') {
            classes.push('row-nsf');
        } else if (item.status === 'Cancelled') {
            classes.push('row-cancelled');
        } else if (item.status === 'Scheduled') {
            classes.push('row-scheduled');
        }

        return classes.join(' ');
    }

    getStatusBadgeClass(status) {
        const statusMap = {
            'Scheduled': 'status-badge status-scheduled',
            'Cleared': 'status-badge status-cleared',
            'NSF': 'status-badge status-nsf',
            'Cancelled': 'status-badge status-cancelled'
        };
        return statusMap[status] || 'status-badge status-pending';
    }

    reduceErrors(error) {
        if (!error) {
            return 'An unknown error occurred';
        }

        if (typeof error === 'string') {
            return error;
        }

        if (Array.isArray(error)) {
            return error.map(e => this.reduceErrors(e)).join(', ');
        }

        if (error.body) {
            if (typeof error.body.message === 'string') {
                return error.body.message;
            }
            if (Array.isArray(error.body.pageErrors) && error.body.pageErrors.length > 0) {
                return error.body.pageErrors.map(e => e.message).join(', ');
            }
            if (error.body.fieldErrors) {
                const fieldErrors = Object.values(error.body.fieldErrors)
                    .flat()
                    .map(e => e.message);
                if (fieldErrors.length > 0) {
                    return fieldErrors.join(', ');
                }
            }
        }

        if (error.message) {
            return error.message;
        }

        if (error.statusText) {
            return error.statusText;
        }

        return 'An unexpected error occurred. Please try again.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}