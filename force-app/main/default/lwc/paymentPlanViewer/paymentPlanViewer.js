import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getLatestPaymentPlan from '@salesforce/apex/PaymentPlanEditorController.getLatestPaymentPlan';
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
     * Note: Wire fee functionality disabled - Payment_Fee__c object not deployed
     */
    async loadWireFees(planId) {
        // Wire fee loading disabled until Payment_Fee__c object is deployed
        this.wireFeeMap = {};
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

    // ============ SUMMARY STATS COMPUTED PROPERTIES ============

    /**
     * Schedule items formatted for summaryStats component
     */
    get scheduleItemsForSummary() {
        if (!this.scheduleItems || this.scheduleItems.length === 0) {
            return [];
        }
        return this.scheduleItems.map(item => ({
            paymentAmount: item.draftAmount || 0,
            totalPayment: item.draftAmount || 0,
            draftAmount: item.draftAmount || 0,
            setupFee: item.setupFee || 0,
            setupFeePortion: item.setupFee || 0,
            paymentDate: item.paymentDate,
            date: item.paymentDate
        }));
    }

    /**
     * New Weekly Payment - first payment minus setup fee
     */
    get summaryWeeklyPayment() {
        if (!this.scheduleItems || this.scheduleItems.length === 0) {
            return 0;
        }
        const first = this.scheduleItems[0];
        const payment = Number(first.draftAmount) || 0;
        const setup = Number(first.setupFee) || 0;
        return Math.max(0, payment - setup);
    }

    /**
     * Program length - number of schedule items
     */
    get summaryProgramLength() {
        return this.scheduleItems ? this.scheduleItems.length : 0;
    }

    /**
     * Current payment from opportunity
     */
    get currentPayment() {
        return this.paymentPlan?.Opportunity__r?.Current_Weekly_Payment__c || 0;
    }

    /**
     * Total debt from opportunity
     */
    get totalDebt() {
        return this.paymentPlan?.Opportunity__r?.Estimated_Total_Debt__c || 0;
    }

    /**
     * First draft date from schedule
     */
    get firstDraftDate() {
        if (!this.scheduleItems || this.scheduleItems.length === 0) {
            return null;
        }
        // Sort by date and get the first one
        const sorted = [...this.scheduleItems].sort((a, b) => {
            const dateA = a.paymentDate ? new Date(a.paymentDate) : new Date(0);
            const dateB = b.paymentDate ? new Date(b.paymentDate) : new Date(0);
            return dateA - dateB;
        });
        return sorted[0]?.paymentDate || null;
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

    get createdByName() {
        return this.paymentPlan?.CreatedBy?.Name || '';
    }

    get activatedByName() {
        return this.paymentPlan?.LastModifiedBy?.Name || '';
    }

    get hasCreatedBy() {
        return !!this.createdByName;
    }

    get hasActivatedBy() {
        return !!this.activatedByName;
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
            const wireStatusClass = wiresTotal >= item.draftAmount ? 'wire-row-green' : 'wire-row-orange';

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
    // Uses rollup fields when available, falls back to live calculation

    // ----- TOTAL ROW -----
    get totalDraftAmount() {
        if (this.paymentPlan?.Total_Draft_Amount__c != null) {
            return Number(this.paymentPlan.Total_Draft_Amount__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.draftAmount) || 0), 0);
    }

    get totalDraftAmountFormatted() {
        return this.formatCurrency(this.totalDraftAmount);
    }

    get totalSetupFee() {
        if (this.paymentPlan?.Total_Setup_Fee_Rollup__c != null) {
            return Number(this.paymentPlan.Total_Setup_Fee_Rollup__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.setupFee) || 0), 0);
    }

    get totalSetupFeeFormatted() {
        return this.formatCurrency(this.totalSetupFee);
    }

    get totalProgramFee() {
        if (this.paymentPlan?.Total_Program_Fee_Rollup__c != null) {
            return Number(this.paymentPlan.Total_Program_Fee_Rollup__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.programFee) || 0), 0);
    }

    get totalProgramFeeFormatted() {
        return this.formatCurrency(this.totalProgramFee);
    }

    get totalBankingFee() {
        if (this.paymentPlan?.Total_Banking_Fee_Rollup__c != null) {
            return Number(this.paymentPlan.Total_Banking_Fee_Rollup__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.bankingFee) || 0), 0);
    }

    get totalBankingFeeFormatted() {
        return this.formatCurrency(this.totalBankingFee);
    }

    get totalSavingsBalance() {
        // Always calculate from items for fresh, accurate data
        // Each item's savingsBalance comes from To_Escrow_Amount__c (per-payment savings)
        // NOT from Savings_Balance__c (running balance) which would give wrong totals
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.savingsBalance) || 0), 0);
    }

    get totalSavingsBalanceFormatted() {
        return this.formatCurrency(this.totalSavingsBalance);
    }

    get totalRowCount() {
        if (this.paymentPlan?.Schedule_Item_Count_Rollup__c != null) {
            return Number(this.paymentPlan.Schedule_Item_Count_Rollup__c) || 0;
        }
        return this.scheduleItems ? this.scheduleItems.length : 0;
    }

    // ----- WIRES ROW -----
    get totalWiresReceived() {
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.wiresReceived) || 0), 0);
    }

    get totalWiresReceivedFormatted() {
        return this.formatCurrency(this.totalWiresReceived);
    }

    // ----- CLEARED ROW -----
    get clearedDraftAmount() {
        if (this.paymentPlan?.Cleared_Payment_Sum__c != null) {
            return Number(this.paymentPlan.Cleared_Payment_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.draftAmount) || 0), 0);
    }

    get clearedDraftAmountFormatted() {
        return this.formatCurrency(this.clearedDraftAmount);
    }

    get clearedSetupFee() {
        if (this.paymentPlan?.Cleared_Setup_Fee_Sum__c != null) {
            return Number(this.paymentPlan.Cleared_Setup_Fee_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.setupFee) || 0), 0);
    }

    get clearedSetupFeeFormatted() {
        return this.formatCurrency(this.clearedSetupFee);
    }

    get clearedProgramFee() {
        if (this.paymentPlan?.Cleared_Program_Fee_Sum__c != null) {
            return Number(this.paymentPlan.Cleared_Program_Fee_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.programFee) || 0), 0);
    }

    get clearedProgramFeeFormatted() {
        return this.formatCurrency(this.clearedProgramFee);
    }

    get clearedBankingFee() {
        if (this.paymentPlan?.Cleared_Banking_Fee_Sum__c != null) {
            return Number(this.paymentPlan.Cleared_Banking_Fee_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.bankingFee) || 0), 0);
    }

    get clearedBankingFeeFormatted() {
        return this.formatCurrency(this.clearedBankingFee);
    }

    get clearedSavingsBalance() {
        // Use Cleared_Escrow_Sum__c which sums To_Escrow_Amount__c for Cleared items
        // NOT Cleared_Savings_Sum__c which sums Savings_Balance__c (running balance)
        if (this.paymentPlan?.Cleared_Escrow_Sum__c != null) {
            return Number(this.paymentPlan.Cleared_Escrow_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.savingsBalance) || 0), 0);
    }

    get clearedSavingsBalanceFormatted() {
        return this.formatCurrency(this.clearedSavingsBalance);
    }

    // ----- NSF ROW -----
    get nsfDraftAmount() {
        if (this.paymentPlan?.NSF_Draft_Amount_Sum__c != null) {
            return Number(this.paymentPlan.NSF_Draft_Amount_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.draftAmount) || 0), 0);
    }

    get nsfDraftAmountFormatted() {
        return this.formatCurrency(this.nsfDraftAmount);
    }

    get nsfSetupFee() {
        if (this.paymentPlan?.NSF_Setup_Fee_Sum__c != null) {
            return Number(this.paymentPlan.NSF_Setup_Fee_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.setupFee) || 0), 0);
    }

    get nsfSetupFeeFormatted() {
        return this.formatCurrency(this.nsfSetupFee);
    }

    get nsfProgramFee() {
        if (this.paymentPlan?.NSF_Program_Fee_Sum__c != null) {
            return Number(this.paymentPlan.NSF_Program_Fee_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.programFee) || 0), 0);
    }

    get nsfProgramFeeFormatted() {
        return this.formatCurrency(this.nsfProgramFee);
    }

    get nsfBankingFee() {
        if (this.paymentPlan?.NSF_Banking_Fee_Sum__c != null) {
            return Number(this.paymentPlan.NSF_Banking_Fee_Sum__c) || 0;
        }
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.bankingFee) || 0), 0);
    }

    get nsfBankingFeeFormatted() {
        return this.formatCurrency(this.nsfBankingFee);
    }

    get nsfSavingsBalance() {
        // Calculate from items - no rollup field exists for NSF escrow
        // (org reached 25 rollup field limit)
        const items = this.scheduleItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.savingsBalance) || 0), 0);
    }

    get nsfSavingsBalanceFormatted() {
        return this.formatCurrency(this.nsfSavingsBalance);
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