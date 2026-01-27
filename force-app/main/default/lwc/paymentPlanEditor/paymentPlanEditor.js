import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getPaymentPlanVersions from '@salesforce/apex/PaymentPlanEditorController.getPaymentPlanVersions';
import getPaymentPlanById from '@salesforce/apex/PaymentPlanEditorController.getPaymentPlanById';
import getPreviousVersionItems from '@salesforce/apex/PaymentPlanEditorController.getPreviousVersionItems';
import saveAsNewVersion from '@salesforce/apex/PaymentPlanEditorController.saveAsNewVersion';
import recalculatePaymentPlan from '@salesforce/apex/PaymentPlanEditorController.recalculatePaymentPlan';
import recalculateRemainingBalance from '@salesforce/apex/PaymentPlanEditorController.recalculateRemainingBalance';
import suspendPaymentPlan from '@salesforce/apex/PaymentPlanEditorController.suspendPaymentPlan';
import activatePaymentPlan from '@salesforce/apex/PaymentPlanEditorController.activatePaymentPlan';
import getWireFeesByPlanId from '@salesforce/apex/PaymentPlanEditorController.getWireFeesByPlanId';
import saveWireFee from '@salesforce/apex/PaymentPlanEditorController.saveWireFee';
import deleteWireFee from '@salesforce/apex/PaymentPlanEditorController.deleteWireFee';
import getStatusPicklistValues from '@salesforce/apex/PaymentPlanEditorController.getStatusPicklistValues';

// Default fallback if dynamic fetch fails
const DEFAULT_STATUS_OPTIONS = [
    { label: 'Scheduled', value: 'Scheduled' },
    { label: 'Cleared', value: 'Cleared' },
    { label: 'NSF', value: 'NSF' },
    { label: 'Cancelled', value: 'Cancelled' }
];

// Status value that allows editing
const EDITABLE_STATUS = 'Scheduled';

// Debounce delay in milliseconds
const DEBOUNCE_DELAY = 300;

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2
});

export default class PaymentPlanEditor extends LightningElement {
    @api recordId;

    // State for version selector dropdown (arrays need @track for mutation)
    @track plans = [];
    selectedPlanId = null;

    // State for selected plan data (arrays need @track for mutation)
    paymentPlan = null;
    @track scheduleItems = [];
    @track pendingItems = [];
    @track originalItems = [];

    // UI state (primitives don't need @track in modern LWC)
    isLoading = true;
    isEditMode = false;
    activeTab = 'Active';
    hasPendingChanges = false;
    // Checkbox functionality removed - was not working
    // @track selectedRowIds = new Set();
    showConfetti = false;
    @track confettiPieces = [];
    isMaximized = false;

    // Fill Handle state
    fillHandleActive = false;
    fillSourceCell = null;      // { rowIndex, field, value, tempId }
    @track fillTargetRows = [];        // Array of row indices being filled
    fillPreviewValue = null;    // Preview value shown during drag
    selectedCellKey = null;     // Key for currently selected cell

    // Wire Fee Modal state
    showWireModal = false;
    wireModalScheduleItemId = null;
    wireModalRowNumber = null;
    wireFeeType = 'Wire Fee';       // Default wire fee type
    wireFeeAmount = null;           // Wire fee amount (optional)

    // Wire Fees Hover state
    @track wireFeeMap = {};         // Map of Schedule Item ID to array of Wire Fees (object needs @track)
    hoveredRowId = null;            // Currently hovered row's Schedule Item ID
    popoverTop = 0;                 // Popover Y position
    popoverLeft = 0;                // Popover X position

    // Previous version comparison state (array needs @track)
    @track previousVersionItems = [];  // Items from previous version for comparison

    // Dynamic picklist values for Status field (array needs @track)
    @track statusPicklistOptions = DEFAULT_STATUS_OPTIONS;

    // Debounce timer reference
    _debounceTimer = null;

    // Flag to prevent double-click on save operations
    _isSaving = false;

    // Pagination state
    currentPage = 1;
    pageSize = 50; // Items per page

    // ============ LIFECYCLE HOOKS ============

    async connectedCallback() {
        // Load status picklist values and plans in parallel
        await Promise.all([
            this.loadStatusPicklistValues(),
            this.loadPlans()
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
            // Use default options if dynamic fetch fails
            console.error('Error loading status picklist values:', error);
            this.statusPicklistOptions = DEFAULT_STATUS_OPTIONS;
        }
    }

    // ============ DATA LOADING METHODS ============

    /**
     * Load all payment plan versions for the opportunity
     * Then auto-select the latest active plan
     */
    async loadPlans() {
        this.isLoading = true;
        try {
            const versions = await getPaymentPlanVersions({ opportunityId: this.recordId });

            if (versions && versions.length > 0) {
                // Build plans array for dropdown options and sort by version descending
                this.plans = versions.map(wrapper => ({
                    ...wrapper,
                    planId: wrapper.paymentPlan?.Id,
                    label: this.buildPlanLabel(wrapper),
                    value: wrapper.paymentPlan?.Id,
                    isActive: wrapper.paymentPlan?.Is_Active__c === true,
                    versionNum: wrapper.versionNumber || 1
                })).sort((a, b) => b.versionNum - a.versionNum);

                // Auto-select: prefer Is_Active__c = true, else first in list
                const activePlan = this.plans.find(p => p.isActive);
                const defaultPlan = activePlan || this.plans[0];

                if (defaultPlan && defaultPlan.planId) {
                    this.selectedPlanId = defaultPlan.planId;
                    await this.loadPlan(defaultPlan.planId);
                }
            } else {
                this.plans = [];
                this.paymentPlan = null;
                this.scheduleItems = [];
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.plans = [];
            this.paymentPlan = null;
            this.scheduleItems = [];
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Load a specific plan's data including schedule items
     */
    async loadPlan(planId) {
        this.isLoading = true;
        try {
            // Load current plan and previous version items in parallel
            const [wrapper, prevItems] = await Promise.all([
                getPaymentPlanById({ planId: planId }),
                getPreviousVersionItems({ planId: planId })
            ]);

            if (wrapper) {
                this.selectedPlanId = planId;
                this.paymentPlan = wrapper.paymentPlan;

                // Store previous version items for comparison
                this.previousVersionItems = prevItems || [];

                // Process items with previous version comparison
                this.scheduleItems = this.processItems(wrapper.scheduleItems || []);
                this.originalItems = this.deepCloneItems(this.scheduleItems);
                // Checkbox functionality removed
                // this.selectedRowIds = new Set();

                // Load Wired Payments for this plan
                await this.loadWireFees(planId);
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
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
            // Don't fail the whole load if wire fees fail
            console.error('Error loading wire fees:', error);
            this.wireFeeMap = {};
        }
    }

    /**
     * Refresh plans list (after save/version create)
     * @param {String} selectPlanId - Optional plan ID to select after refresh
     */
    async refreshPlans(selectPlanId = null) {
        this.isLoading = true;
        try {
            const versions = await getPaymentPlanVersions({ opportunityId: this.recordId });

            if (versions && versions.length > 0) {
                // Sort by version descending
                this.plans = versions.map(wrapper => ({
                    ...wrapper,
                    planId: wrapper.paymentPlan?.Id,
                    label: this.buildPlanLabel(wrapper),
                    value: wrapper.paymentPlan?.Id,
                    isActive: wrapper.paymentPlan?.Is_Active__c === true,
                    versionNum: wrapper.versionNumber || 1
                })).sort((a, b) => b.versionNum - a.versionNum);

                // If specific plan ID provided, select it
                if (selectPlanId) {
                    this.selectedPlanId = selectPlanId;
                    await this.loadPlan(selectPlanId);
                }
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Handle manual refresh button click
     */
    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.loadPlans();
            this.showToast('Success', 'Data refreshed', 'success');
        } catch (error) {
            console.error('Error refreshing data:', error);
            this.showToast('Error', 'Failed to refresh data', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ============ PLAN SELECTOR HELPERS ============

    /**
     * Build label for dropdown: "PP-00052 v1 (Active)"
     */
    buildPlanLabel(wrapper) {
        const name = wrapper.paymentPlan?.Name || 'Plan';
        const version = wrapper.versionNumber || 1;
        const status = wrapper.paymentPlan?.Version_Status__c || wrapper.versionStatus || '';
        const isActive = wrapper.paymentPlan?.Is_Active__c;

        let statusLabel = '';
        if (isActive) {
            statusLabel = ' (Active)';
        } else if (status === 'Draft') {
            statusLabel = ' (Draft)';
        } else if (status) {
            statusLabel = ` (${status})`;
        }

        return `${name} v${version}${statusLabel}`;
    }

    // ============ COMPUTED PROPERTIES ============

    get hasPaymentPlan() {
        return this.paymentPlan !== null;
    }

    get hasPlans() {
        return this.plans.length > 0;
    }

    get planCount() {
        return this.plans.length;
    }

    /**
     * Options for the plan selector dropdown
     */
    get planDropdownOptions() {
        return this.plans.map(plan => ({
            label: plan.label,
            value: plan.planId
        }));
    }

    get planName() {
        return this.paymentPlan?.Name || 'Payment Plan';
    }

    get planStatus() {
        return this.paymentPlan?.Version_Status__c || '';
    }

    get versionInfo() {
        if (!this.paymentPlan) return '';
        const version = this.paymentPlan.Version_Number__c || 1;
        const status = this.paymentPlan.Version_Status__c || '';
        return `v${version} - ${status}`;
    }

    // Active tab label shows the selected version name
    get activeTabLabel() {
        if (!this.paymentPlan) return 'Active';
        const name = this.paymentPlan.Name || 'Plan';
        const version = this.paymentPlan.Version_Number__c || 1;
        return `${name} v${version}`;
    }

    get activeItems() {
        if (!this.scheduleItems || this.scheduleItems.length === 0) {
            return [];
        }
        return this.scheduleItems.filter(item => !item.isDeleted);
    }

    get filteredPendingItems() {
        if (!this.pendingItems || this.pendingItems.length === 0) {
            return [];
        }
        return this.pendingItems.filter(item => !item.isDeleted);
    }

    /**
     * Get all items (sorted with draft numbers) before pagination
     * Used for totals calculation
     */
    get allSortedItems() {
        let items;
        if (this.activeTab === 'Active') {
            items = this.activeItems;
        } else {
            items = this.filteredPendingItems;
        }

        // Sort by date ascending
        if (items && items.length > 0) {
            const sortedItems = [...items].sort((a, b) => {
                const dateA = a.paymentDate ? new Date(a.paymentDate) : new Date(0);
                const dateB = b.paymentDate ? new Date(b.paymentDate) : new Date(0);
                return dateA - dateB;
            });

            // Calculate Draft # that skips NSF and Cancelled rows
            let draftCounter = 0;
            return sortedItems.map(item => {
                const skipStatuses = ['NSF', 'Cancelled'];
                const shouldSkip = skipStatuses.includes(item.status);

                if (!shouldSkip) {
                    draftCounter++;
                }

                return {
                    ...item,
                    calculatedDraftNumber: shouldSkip ? '-' : String(draftCounter),
                    hasDraftNumber: !shouldSkip
                };
            });
        }
        return items || [];
    }

    /**
     * Get all display items (no pagination - scroll to see all)
     */
    get displayItems() {
        const allItems = this.allSortedItems;
        if (!allItems || allItems.length === 0) {
            return [];
        }

        // Return all items (no pagination) - enrich with wire fees data
        return allItems.map(item => {
            const wireFees = this.wireFeeMap[item.id] || [];
            const wiresTotal = Number(item.wiresReceived) || 0;
            const draftAmount = Number(item.draftAmount) || 0;
            // Determine wire status: green if wires >= draft, orange if wires < draft
            const wireStatusClass = wiresTotal >= draftAmount ? 'wire-row-green' : 'wire-row-orange';

            return {
                ...item,
                wireFees: wireFees.map(fee => ({
                    ...fee,
                    feeTypeFormatted: fee.feeType,
                    amountFormatted: this.formatCurrency(fee.amount || 0),
                    wireRowClass: `wire-sub-row ${wireStatusClass}`
                })),
                hasWireFees: wireFees.length > 0,
                wireStatusClass: wireStatusClass
            };
        });
    }

    // ============ PAGINATION COMPUTED PROPERTIES ============

    get totalPages() {
        const allItems = this.allSortedItems;
        if (!allItems || allItems.length === 0) return 1;
        return Math.ceil(allItems.length / this.pageSize);
    }

    get hasPagination() {
        return this.totalPages > 1;
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get paginationInfo() {
        const allItems = this.allSortedItems;
        const total = allItems ? allItems.length : 0;
        const start = total === 0 ? 0 : ((this.currentPage - 1) * this.pageSize) + 1;
        const end = Math.min(this.currentPage * this.pageSize, total);
        return `${start}-${end} of ${total}`;
    }

    get hasDisplayItems() {
        return this.displayItems && this.displayItems.length > 0;
    }

    get isActiveTab() {
        return this.activeTab === 'Active';
    }

    get isPendingTab() {
        return this.activeTab === 'Pending';
    }

    get activeTabButtonClass() {
        return this.isActiveTab ? 'tab active' : 'tab';
    }

    get pendingTabButtonClass() {
        return this.isPendingTab ? 'tab active' : 'tab';
    }

    get statusOptions() {
        return this.statusPicklistOptions;
    }

    get activeItemCount() {
        return this.scheduleItems.filter(item => !item.isDeleted).length;
    }

    get pendingItemCount() {
        return this.pendingItems.filter(item => !item.isDeleted).length;
    }

    get hasModifiedItems() {
        return this.pendingItems.some(item => item.isModified || item.isNew || item.isDeleted);
    }

    get showPendingTab() {
        return this.hasPendingChanges || this.pendingItems.length > 0;
    }

    get canEdit() {
        return this.isEditMode && this.isPendingTab;
    }

    get isDraft() {
        return this.paymentPlan?.Version_Status__c === 'Draft';
    }

    get canActivate() {
        return this.isDraft && !this.isEditMode;
    }

    get isActivePlan() {
        return this.paymentPlan?.Is_Active__c === true;
    }

    /**
     * Show "No Plan State" when not loading and no plans exist
     */
    get showNoPlanState() {
        return !this.isLoading && !this.hasPlans;
    }

    /**
     * Show Wire button only when not in edit mode
     */
    get showWireButton() {
        return !this.isEditMode;
    }

    /**
     * Show empty state when no display items
     */
    get showEmptyState() {
        return !this.hasDisplayItems;
    }

    /**
     * Show Suspend button only when plan is not a Draft
     */
    get showSuspendButton() {
        return !this.isDraft;
    }

    // Checkbox functionality removed - was not working
    // get allSelected() {
    //     const items = this.displayItems;
    //     if (!items || items.length === 0) return false;
    //     return items.every(item => this.selectedRowIds.has(item.tempId));
    // }

    // ============ AGGREGATE GETTERS (Footer Totals) ============
    // Uses rollup summary fields from PaymentPlan__c when viewing (faster, no calculation)
    // Falls back to client-side calculation when editing (reflects unsaved changes)

    get totalDraftAmount() {
        // Calculate from items: SUM(Draft WHERE Status != 'NSF') + SUM(Wires_received)
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        // Sum draft amounts excluding NSF items
        const draftSum = items
            .filter(item => item.status !== 'NSF')
            .reduce((sum, item) => sum + (Number(item.draftAmount) || 0), 0);
        // Add wires received from all items (including NSF - they can have wires)
        const wiresSum = items.reduce((sum, item) => sum + (Number(item.wiresReceived) || 0), 0);
        return draftSum + wiresSum;
    }

    get totalDraftAmountFormatted() {
        return this.formatCurrency(this.totalDraftAmount);
    }

    get totalSetupFee() {
        // Calculate from items: SUM(Setup WHERE Status != 'NSF')
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status !== 'NSF')
            .reduce((sum, item) => sum + (Number(item.setupFee) || 0), 0);
    }

    get totalSetupFeeFormatted() {
        return this.formatCurrency(this.totalSetupFee);
    }

    get totalProgramFee() {
        // Calculate from items: SUM(Program WHERE Status != 'NSF')
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status !== 'NSF')
            .reduce((sum, item) => sum + (Number(item.programFee) || 0), 0);
    }

    get totalProgramFeeFormatted() {
        return this.formatCurrency(this.totalProgramFee);
    }

    get totalBankingFee() {
        // Calculate from items: SUM(Banking WHERE Status != 'NSF')
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status !== 'NSF')
            .reduce((sum, item) => sum + (Number(item.bankingFee) || 0), 0);
    }

    get totalBankingFeeFormatted() {
        return this.formatCurrency(this.totalBankingFee);
    }

    get totalSavingsBalance() {
        // Calculate from items: SUM(Savings WHERE Status != 'NSF')
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status !== 'NSF')
            .reduce((sum, item) => sum + (Number(item.savingsBalance) || 0), 0);
    }

    get totalSavingsBalanceFormatted() {
        return this.formatCurrency(this.totalSavingsBalance);
    }

    get totalWiresReceived() {
        // Sum of all wires received across all items
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items.reduce((sum, item) => sum + (Number(item.wiresReceived) || 0), 0);
    }

    get totalRowCount() {
        // Use rollup field when not editing, otherwise calculate from items
        if (!this.isEditMode && this.paymentPlan?.Schedule_Item_Count_Rollup__c != null) {
            return Number(this.paymentPlan.Schedule_Item_Count_Rollup__c) || 0;
        }
        const items = this.allSortedItems;
        return items ? items.length : 0;
    }

    get totalAmountCleared() {
        // Use rollup field from PaymentPlan__c (sums Cleared_Amount__c from all items)
        if (this.paymentPlan?.Total_Amount_Cleared__c != null) {
            return Number(this.paymentPlan.Total_Amount_Cleared__c) || 0;
        }
        return 0;
    }

    get totalAmountClearedFormatted() {
        return this.formatCurrency(this.totalAmountCleared);
    }

    // Cleared row totals - only from items where status === 'Cleared'
    get clearedSetupFee() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.setupFee) || 0), 0);
    }

    get clearedSetupFeeFormatted() {
        return this.formatCurrency(this.clearedSetupFee);
    }

    get clearedProgramFee() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.programFee) || 0), 0);
    }

    get clearedProgramFeeFormatted() {
        return this.formatCurrency(this.clearedProgramFee);
    }

    get clearedBankingFee() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.bankingFee) || 0), 0);
    }

    get clearedBankingFeeFormatted() {
        return this.formatCurrency(this.clearedBankingFee);
    }

    get clearedSavingsBalance() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'Cleared')
            .reduce((sum, item) => sum + (Number(item.savingsBalance) || 0), 0);
    }

    get clearedSavingsBalanceFormatted() {
        return this.formatCurrency(this.clearedSavingsBalance);
    }

    // NSF row totals - only from items where status === 'NSF'
    get nsfDraftAmount() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.draftAmount) || 0), 0);
    }

    get nsfDraftAmountFormatted() {
        return this.formatCurrency(this.nsfDraftAmount);
    }

    get nsfSetupFee() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.setupFee) || 0), 0);
    }

    get nsfSetupFeeFormatted() {
        return this.formatCurrency(this.nsfSetupFee);
    }

    get nsfProgramFee() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.programFee) || 0), 0);
    }

    get nsfProgramFeeFormatted() {
        return this.formatCurrency(this.nsfProgramFee);
    }

    get nsfBankingFee() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.bankingFee) || 0), 0);
    }

    get nsfBankingFeeFormatted() {
        return this.formatCurrency(this.nsfBankingFee);
    }

    get nsfSavingsBalance() {
        const items = this.allSortedItems;
        if (!items || items.length === 0) return 0;
        return items
            .filter(item => item.status === 'NSF')
            .reduce((sum, item) => sum + (Number(item.savingsBalance) || 0), 0);
    }

    get nsfSavingsBalanceFormatted() {
        return this.formatCurrency(this.nsfSavingsBalance);
    }

    // Wires total formatted
    get totalWiresReceivedFormatted() {
        return this.formatCurrency(this.totalWiresReceived);
    }

    // ============ EVENT HANDLERS ============

    /**
     * Handle dropdown selection change
     */
    async handlePlanDropdownChange(event) {
        const planId = event.detail.value;
        if (planId && planId !== this.selectedPlanId) {
            await this.loadPlan(planId);
        }
    }

    handleTabClick(event) {
        event.preventDefault();
        const tab = event.currentTarget.dataset.tab;
        if (tab) {
            if (tab === 'Pending' && !this.showPendingTab) {
                return;
            }
            this.activeTab = tab;
            this.currentPage = 1; // Reset to first page on tab change
        }
    }

    // ============ PAGINATION EVENT HANDLERS ============

    handleFirstPage() {
        this.currentPage = 1;
    }

    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    handleLastPage() {
        this.currentPage = this.totalPages;
    }

    // Checkbox functionality removed - was not working
    // handleSelectAll(event) {
    //     const isChecked = event.target.checked;
    //     const items = this.displayItems;

    //     if (isChecked) {
    //         items.forEach(item => this.selectedRowIds.add(item.tempId));
    //     } else {
    //         this.selectedRowIds.clear();
    //     }

    //     // Trigger reactivity
    //     this.selectedRowIds = new Set(this.selectedRowIds);
    //     this.updateItemSelection();
    // }

    // handleRowSelect(event) {
    //     const itemId = event.target.dataset.id;
    //     const isChecked = event.target.checked;

    //     if (isChecked) {
    //         this.selectedRowIds.add(itemId);
    //     } else {
    //         this.selectedRowIds.delete(itemId);
    //     }

    //     // Trigger reactivity
    //     this.selectedRowIds = new Set(this.selectedRowIds);
    //     this.updateItemSelection();
    // }

    // updateItemSelection() {
    //     if (this.activeTab === 'Active') {
    //         this.scheduleItems = this.scheduleItems.map(item => ({
    //             ...item,
    //             isSelected: this.selectedRowIds.has(item.tempId)
    //         }));
    //     } else {
    //         this.pendingItems = this.pendingItems.map(item => ({
    //             ...item,
    //             isSelected: this.selectedRowIds.has(item.tempId)
    //         }));
    //     }
    // }

    handleActionMenu(event) {
        const itemId = event.currentTarget.dataset.id;
        // Future: implement dropdown menu for row actions
        this.showToast('Info', `Action menu for row ${itemId}`, 'info');
    }

    /**
     * Debounce utility - delays function execution until after wait milliseconds
     * @param {Function} func - Function to debounce
     * @param {Number} wait - Delay in milliseconds
     * @returns {Function} - Debounced function
     */
    debounce(func, wait) {
        return (...args) => {
            clearTimeout(this._debounceTimer);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._debounceTimer = setTimeout(() => {
                func.apply(this, args);
            }, wait);
        };
    }

    /**
     * Handle blur (when user leaves the field) - sync value and recalculate
     * This is the main data sync point to avoid cursor issues during typing
     */
    handleFieldBlur(event) {
        const field = event.target.dataset.field;
        const itemId = event.target.dataset.id;
        let value = event.target.value;

        // Check if this is a numeric currency field
        const isNumeric = field === 'draftAmount' || field === 'setupFee' ||
            field === 'programFee' || field === 'bankingFee';

        if (isNumeric) {
            // Clean: remove any non-numeric chars except decimal and minus
            value = value.replace(/[^0-9.-]/g, '').replace(',', '.');
            value = parseFloat(value) || 0;

            // Update the input display with formatted value
            event.target.value = value.toFixed(2);
        }

        // Update the item
        this.pendingItems = this.pendingItems.map(item => {
            if (item.id === itemId || item.tempId === itemId) {
                const updatedItem = {
                    ...item,
                    [field]: value,
                    isModified: true
                };

                // Auto-recalculate Savings
                if (isNumeric) {
                    const draftAmount = parseFloat(updatedItem.draftAmount) || 0;
                    const bankingFee = parseFloat(updatedItem.bankingFee) || 0;
                    const programFee = parseFloat(updatedItem.programFee) || 0;
                    const setupFee = parseFloat(updatedItem.setupFee) || 0;

                    const savings = draftAmount - bankingFee - programFee - setupFee;
                    updatedItem.savingsBalance = Math.round(savings * 100) / 100;
                    updatedItem.toEscrowAmount = updatedItem.savingsBalance;
                }

                return updatedItem;
            }
            return item;
        });

        // Process items to update all formatting
        this.pendingItems = this.processItems(this.pendingItems, true);
    }

    /**
     * Handle field input during typing - update savings live while preserving typing flexibility
     */
    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const itemId = event.target.dataset.id;
        const rawValue = event.target.value; // Preserve exact user input

        // Handle status field change
        if (field === 'status') {
            this.pendingItems = this.pendingItems.map(item => {
                if (item.id === itemId || item.tempId === itemId) {
                    return {
                        ...item,
                        status: rawValue,
                        statusBadgeClass: this.getStatusBadgeClass(rawValue),
                        isModified: true
                    };
                }
                return item;
            });
            return;
        }

        // Handle paymentDate field change
        if (field === 'paymentDate') {
            this.pendingItems = this.pendingItems.map(item => {
                if (item.id === itemId || item.tempId === itemId) {
                    return {
                        ...item,
                        paymentDate: rawValue,
                        paymentDateFormatted: rawValue,
                        paymentDateDisplay: this.formatDate(rawValue),
                        isModified: true
                    };
                }
                return item;
            });
            return;
        }

        // Check if this field affects savings calculation
        const affectsSavings = field === 'draftAmount' || field === 'setupFee' ||
            field === 'programFee' || field === 'bankingFee';

        if (affectsSavings) {
            // Parse the current input value (allow partial input like "10." or "10.5")
            const cleanValue = rawValue.replace(/[^0-9.-]/g, '');
            const numericValue = parseFloat(cleanValue) || 0;

            // Map field to its edit field name
            const editFieldMap = {
                'draftAmount': 'draftAmountEdit',
                'setupFee': 'setupFeeEdit',
                'programFee': 'programFeeEdit',
                'bankingFee': 'bankingFeeEdit'
            };
            const editField = editFieldMap[field];

            // Update the item with live savings calculation
            this.pendingItems = this.pendingItems.map(item => {
                if (item.id === itemId || item.tempId === itemId) {
                    // Get all current values, using the new value for the changed field
                    const values = {
                        draftAmount: field === 'draftAmount' ? numericValue : (parseFloat(item.draftAmount) || 0),
                        setupFee: field === 'setupFee' ? numericValue : (parseFloat(item.setupFee) || 0),
                        programFee: field === 'programFee' ? numericValue : (parseFloat(item.programFee) || 0),
                        bankingFee: field === 'bankingFee' ? numericValue : (parseFloat(item.bankingFee) || 0)
                    };

                    // Calculate savings: Draft - Banking - Program - Setup
                    const savings = values.draftAmount - values.bankingFee - values.programFee - values.setupFee;
                    const roundedSavings = Math.round(savings * 100) / 100;

                    return {
                        ...item,
                        [field]: numericValue,           // Update numeric value for calculations
                        [editField]: rawValue,           // Preserve exact user input (no cursor jump)
                        savingsBalance: roundedSavings,
                        savingsBalanceFormatted: this.formatCurrency(roundedSavings),
                        savingsClass: roundedSavings < 0 ? 'savings-negative' : 'savings-positive',
                        toEscrowAmount: roundedSavings,
                        isModified: true
                    };
                }
                return item;
            });
        }
    }

    /**
     * Debounced version of processItems to prevent excessive re-renders
     * Called after user stops typing for DEBOUNCE_DELAY ms
     */
    debouncedProcessItems = this.debounce(() => {
        this.pendingItems = this.processItems(this.pendingItems, true);
    }, DEBOUNCE_DELAY);

    handleDeleteRow(event) {
        const itemId = event.currentTarget.dataset.id;

        this.pendingItems = this.pendingItems.map(item => {
            if (item.id === itemId || item.tempId === itemId) {
                if (item.isNew && !item.id) {
                    return null;
                }
                return { ...item, isDeleted: true };
            }
            return item;
        }).filter(item => item !== null);

        this.showToast('Success', 'Row marked for deletion', 'success');
    }

    handleAddRow() {
        const lastRowNumber = this.pendingItems.length > 0 ?
            Math.max(...this.pendingItems.filter(i => !i.isDeleted).map(i => i.rowNumber)) : 0;

        const newRowNumber = lastRowNumber + 1;
        const lastItem = this.pendingItems.filter(i => !i.isDeleted).pop();
        const nextDate = lastItem && lastItem.paymentDate ?
            this.addDays(lastItem.paymentDate, 7) : this.getTodayString();

        const defaultBankingFee = this.paymentPlan?.Banking_Fee__c || 15;
        const defaultStatus = 'Scheduled';

        // Build status options with Scheduled selected for new row
        const statusOptionsWithSelection = this.statusPicklistOptions.map(opt => ({
            label: opt.label,
            value: opt.value,
            selected: opt.value === defaultStatus
        }));

        const newItem = {
            id: null,
            tempId: `temp_${Date.now()}_${newRowNumber}`,
            rowNumber: newRowNumber,
            draftNumber: String(newRowNumber),
            paymentDate: nextDate,
            paymentDateFormatted: nextDate,
            paymentDateDisplay: this.formatDate(nextDate),
            draftAmount: 0,
            draftAmountEdit: '0.00',
            draftAmountFormatted: this.formatCurrency(0),
            draftAmountClass: 'value-zero',
            setupFee: 0,
            setupFeeEdit: '0.00',
            setupFeeFormatted: this.formatCurrency(0),
            setupFeeClass: 'value-zero',
            programFee: 0,
            programFeeEdit: '0.00',
            programFeeFormatted: this.formatCurrency(0),
            programFeeClass: 'value-zero',
            bankingFee: defaultBankingFee,
            bankingFeeEdit: this.safeToFixed(defaultBankingFee),
            bankingFeeFormatted: this.formatCurrency(defaultBankingFee),
            bankingFeeClass: '',
            savingsBalance: 0,
            savingsBalanceEdit: '0.00',
            savingsBalanceFormatted: this.formatCurrency(0),
            savingsClass: 'savings-positive',
            toEscrowAmount: 0,
            status: defaultStatus,
            statusBadgeClass: 'status-badge status-scheduled',
            statusOptionsWithSelection: statusOptionsWithSelection,
            isRowEditable: true,
            rowClass: 'row-new',
            rowNumberClass: 'row-number',
            isModified: false,
            isNew: true,
            isDeleted: false,
            isSelected: false
        };

        this.pendingItems = [...this.pendingItems, newItem];
        this.showToast('Success', 'New payment row added', 'success');
    }

    handleManualClick() {
        // Deep clone items and reset modification flags
        const clonedItems = this.deepCloneItems(this.scheduleItems).map(item => ({
            ...item,
            isModified: false,
            isNew: false,
            isDeleted: false,
            isSelected: false
        }));

        // Reprocess items to ensure isRowEditable and statusOptionsWithSelection are calculated
        // This is critical for non-Scheduled rows to be read-only
        this.pendingItems = this.processItems(clonedItems, false);

        this.hasPendingChanges = true;
        this.isEditMode = true;
        this.activeTab = 'Pending';
        // Checkbox functionality removed
        // this.selectedRowIds = new Set();
        this.showToast('Info', 'Edit mode enabled. Make your changes and click Save to create a new version.', 'info');
    }

    async handleSave() {
        this.isLoading = true;
        try {
            // IMPORTANT: Non-Scheduled items are FROZEN - preserve their exact data
            // Only 'Scheduled' items can be modified or have their status defaulted
            const itemsToSave = this.pendingItems
                .filter(item => !item.isDeleted)
                .map((item, index) => {
                    // Check if this is a non-Scheduled (frozen) item
                    // Any status that is NOT 'Scheduled' must be preserved exactly as-is
                    const isScheduledItem = item.status === EDITABLE_STATUS;
                    const isFrozenItem = item.status && !isScheduledItem;

                    return {
                        // Preserve original ID for frozen items so they're recognized by backend
                        id: isFrozenItem ? (item.id || item.Id || null) : null,
                        rowNumber: index + 1,
                        draftNumber: item.draftNumber || String(index + 1),
                        paymentDate: item.paymentDate,
                        // For frozen items, preserve exact values without modification
                        draftAmount: item.draftAmount || 0,
                        setupFee: item.setupFee || 0,
                        programFee: item.programFee || 0,
                        bankingFee: item.bankingFee || 0,
                        savingsBalance: item.savingsBalance || 0,
                        toEscrowAmount: item.toEscrowAmount || 0,
                        // CRITICAL: Never default non-Scheduled status to 'Scheduled'
                        // If item has a status, preserve it; only default to 'Scheduled' for truly new items
                        status: item.status || 'Scheduled',
                        isModified: false,
                        // Frozen items are NOT new - they should be preserved, not recreated
                        isNew: !isFrozenItem,
                        isDeleted: false,
                        // Flag to tell backend this item is frozen and should not be modified
                        isFrozen: isFrozenItem
                    };
                });

            const result = await saveAsNewVersion({
                currentPlanId: this.selectedPlanId,
                items: itemsToSave
            });

            if (result) {
                const newPlanId = result.paymentPlan.Id;

                // Update local state with new plan data
                this.selectedPlanId = newPlanId;
                this.paymentPlan = result.paymentPlan;
                this.scheduleItems = this.processItems(result.scheduleItems || []);
                this.originalItems = this.deepCloneItems(this.scheduleItems);

                this.pendingItems = [];
                this.hasPendingChanges = false;
                this.isEditMode = false;
                this.activeTab = 'Active';
                // Checkbox functionality removed
                // this.selectedRowIds = new Set();

                // Refresh plans list and keep the new plan selected
                await this.refreshPlans(newPlanId);

                this.showToast('Success', 'New version saved as Draft. Click Activate to make it active.', 'success');
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCancelEdit() {
        this.pendingItems = [];
        this.hasPendingChanges = false;
        this.isEditMode = false;
        this.activeTab = 'Active';
        // Checkbox functionality removed
        // this.selectedRowIds = new Set();
        this.showToast('Info', 'Edit cancelled. No changes were saved.', 'info');
    }

    async handleRecalculate() {
        this.isLoading = true;
        try {
            const result = await recalculatePaymentPlan({ planId: this.selectedPlanId });

            if (result) {
                const newPlanId = result.paymentPlan.Id;

                // Update local state with new plan data
                this.selectedPlanId = newPlanId;
                this.paymentPlan = result.paymentPlan;
                this.scheduleItems = this.processItems(result.scheduleItems || []);
                this.originalItems = this.deepCloneItems(this.scheduleItems);

                // Reset edit mode state
                this.pendingItems = [];
                this.hasPendingChanges = false;
                this.isEditMode = false;
                this.activeTab = 'Active';
                // Checkbox functionality removed
                // this.selectedRowIds = new Set();

                // Refresh plans list and select the new plan
                await this.refreshPlans(newPlanId);

                this.showToast('Success', 'New payment plan version created from Opportunity data. Click Activate to make it active.', 'success');
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRecalculateRemainingBalance() {
        this.isLoading = true;
        try {
            const result = await recalculateRemainingBalance({ planId: this.selectedPlanId });

            if (result) {
                const newPlanId = result.paymentPlan.Id;

                // Update local state with new plan data
                this.selectedPlanId = newPlanId;
                this.paymentPlan = result.paymentPlan;
                this.scheduleItems = this.processItems(result.scheduleItems || []);
                this.originalItems = this.deepCloneItems(this.scheduleItems);

                // Reset edit mode state
                this.pendingItems = [];
                this.hasPendingChanges = false;
                this.isEditMode = false;
                this.activeTab = 'Active';

                // Refresh plans list and select the new plan
                await this.refreshPlans(newPlanId);

                this.showToast('Success', 'Remaining balance recalculated and redistributed across future payments. Click Activate to make it active.', 'success');
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSuspend() {
        this.isLoading = true;
        try {
            const result = await suspendPaymentPlan({ planId: this.selectedPlanId });

            if (result) {
                const newPlanId = result.paymentPlan.Id;

                // Update local state with new suspended plan
                this.selectedPlanId = newPlanId;
                this.paymentPlan = result.paymentPlan;
                this.scheduleItems = this.processItems(result.scheduleItems || []);
                this.originalItems = this.deepCloneItems(this.scheduleItems);

                // Reset edit mode state
                this.pendingItems = [];
                this.hasPendingChanges = false;
                this.isEditMode = false;
                this.activeTab = 'Active';
                // Checkbox functionality removed
                // this.selectedRowIds = new Set();

                // Refresh plans list and select the new plan
                await this.refreshPlans(newPlanId);

                this.showToast('Success', 'Payment plan suspended. New version created with Scheduled items cancelled.', 'success');
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleActivate() {
        this.isLoading = true;
        try {
            const result = await activatePaymentPlan({ planId: this.selectedPlanId });

            if (result) {
                const activatedPlanId = result.paymentPlan.Id;

                // Update local state
                this.paymentPlan = result.paymentPlan;
                this.scheduleItems = this.processItems(result.scheduleItems || []);

                // Refresh plans and keep the activated plan selected
                await this.refreshPlans(activatedPlanId);

                // Trigger confetti celebration
                this.triggerConfetti();

                this.showToast('Success', 'Payment plan activated successfully!', 'success');
            }
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    triggerConfetti() {
        // Generate confetti pieces using tracked array (LWC-compatible)
        const colors = ['#ff6b6b', '#4ecdc4', '#45b7d1', '#96ceb4', '#ffeaa7', '#dfe6e9', '#fd79a8', '#a29bfe'];
        const shapes = ['square', 'circle', 'rectangle'];
        const confettiCount = 100;
        const pieces = [];

        for (let i = 0; i < confettiCount; i++) {
            const shape = shapes[Math.floor(Math.random() * shapes.length)];
            const left = Math.random() * 100;
            const color = colors[Math.floor(Math.random() * colors.length)];
            const delay = Math.random() * 3;
            const duration = Math.random() * 2 + 2;

            pieces.push({
                id: `confetti-${i}`,
                shapeClass: `confetti-piece confetti-${shape}`,
                style: `left: ${left}%; background-color: ${color}; animation-delay: ${delay}s; animation-duration: ${duration}s;`
            });
        }

        this.confettiPieces = pieces;
        this.showConfetti = true;

        // Hide confetti after animation
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showConfetti = false;
            this.confettiPieces = [];
        }, 5000);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleMaximize() {
        this.isMaximized = !this.isMaximized;
    }

    get modalContainerClass() {
        return this.isMaximized ? 'payment-plan-modal maximized' : 'payment-plan-modal';
    }

    // ============ WIRE FEE MODAL HANDLERS ============

    /**
     * Wire fee type options for the dropdown
     */
    get wireFeeTypeOptions() {
        return [
            { label: 'Wire Fee', value: 'Wire Fee' },
            { label: 'Wire Received Fee', value: 'Wire Received Fee' }
        ];
    }

    /**
     * Opens the Wire Fee creation modal
     * Pre-populates the Payment Schedule Item lookup
     */
    handleOpenWireModal(event) {
        const scheduleItemId = event.currentTarget.dataset.id;
        const rowNumber = event.currentTarget.dataset.rowNumber;

        if (!scheduleItemId) {
            this.showToast('Error', 'Cannot create wire fee: Schedule item not saved yet.', 'error');
            return;
        }

        this.wireModalScheduleItemId = scheduleItemId;
        this.wireModalRowNumber = rowNumber;
        this.wireFeeType = 'Wire Fee';  // Reset to default
        this.wireFeeAmount = null;      // Reset amount
        this.showWireModal = true;
    }

    /**
     * Closes the Wire Fee modal
     */
    handleCloseWireModal() {
        this.showWireModal = false;
        this.wireModalScheduleItemId = null;
        this.wireModalRowNumber = null;
        this.wireFeeType = 'Wire Fee';
        this.wireFeeAmount = null;
    }

    /**
     * Handle wire fee type dropdown change
     */
    handleWireFeeTypeChange(event) {
        this.wireFeeType = event.detail.value;
    }

    /**
     * Handle wire fee amount input change
     */
    handleWireFeeAmountChange(event) {
        this.wireFeeAmount = event.detail.value;
    }

    /**
     * Save the wire fee record
     */
    async handleSaveWireFee() {
        if (!this.wireFeeType) {
            this.showToast('Error', 'Please select a wire fee type.', 'error');
            return;
        }

        try {
            await saveWireFee({
                scheduleItemId: this.wireModalScheduleItemId,
                feeType: this.wireFeeType,
                amount: this.wireFeeAmount
            });

            this.showToast('Success', 'Wire fee created successfully!', 'success');
            this.handleCloseWireModal();

            // Refresh wire fees to show the new record
            this.loadWireFees(this.selectedPlanId);
        } catch (error) {
            const errorMessage = this.reduceErrors(error);
            this.showToast('Error', errorMessage, 'error');
        }
    }

    /**
     * Delete a wire fee record
     */
    async handleDeleteWireFee(event) {
        const feeId = event.currentTarget.dataset.feeId;
        if (!feeId) {
            return;
        }

        try {
            await deleteWireFee({ feeId: feeId });
            this.showToast('Success', 'Wire fee deleted successfully!', 'success');

            // Refresh wire fees
            this.loadWireFees(this.selectedPlanId);
        } catch (error) {
            const errorMessage = this.reduceErrors(error);
            this.showToast('Error', errorMessage, 'error');
        }
    }

    // ============ WIRE FEES HOVER HANDLERS (Native HTML Popover API) ============

    /**
     * Check if a row has wire fees
     * @param {String} rowId - The schedule item ID
     * @returns {Boolean} - True if the row has wire fees
     */
    rowHasWireFees(rowId) {
        return rowId &&
               this.wireFeeMap &&
               this.wireFeeMap[rowId] &&
               Array.isArray(this.wireFeeMap[rowId]) &&
               this.wireFeeMap[rowId].length > 0;
    }

    /**
     * Handle mouse enter on a table row
     * Shows the wire fees popover ONLY if the row has wire fees
     */
    handleRowMouseEnter(event) {
        const rowId = event.currentTarget.dataset.rowId;

        // Only show popover if not in edit mode AND row actually has wire fees
        if (!this.isEditMode && this.rowHasWireFees(rowId)) {
            // Calculate position first
            this.updatePopoverPosition(event.clientX, event.clientY);

            // Then show the popover by setting hoveredRowId
            this.hoveredRowId = rowId;

            // Bind mousemove for cursor following
            this._boundHandleMouseMove = this.handlePopoverMouseMove.bind(this);
            this._currentHoveredRow = event.currentTarget;
            event.currentTarget.addEventListener('mousemove', this._boundHandleMouseMove);
        }
    }

    /**
     * Handle mouse move on a table row
     * Updates popover position to follow cursor
     */
    handlePopoverMouseMove(event) {
        // Only update position if we have an active hovered row with wire fees
        if (!this.hoveredRowId || !this.rowHasWireFees(this.hoveredRowId)) {
            return;
        }
        this.updatePopoverPosition(event.clientX, event.clientY);
    }

    /**
     * Handle mouse leave on a table row
     * Hides the popover by clearing hoveredRowId
     */
    handleRowMouseLeave(event) {
        // Remove mousemove listener from the current row
        if (this._boundHandleMouseMove && this._currentHoveredRow) {
            this._currentHoveredRow.removeEventListener('mousemove', this._boundHandleMouseMove);
            this._boundHandleMouseMove = null;
            this._currentHoveredRow = null;
        }

        // Clear hovered row state - this hides the popover via lwc:if
        this.hoveredRowId = null;
    }

    /**
     * Update popover position based on cursor coordinates
     */
    updatePopoverPosition(clientX, clientY) {
        const popoverWidth = 500;
        const popoverHeight = 200;
        const offsetX = 15;
        const offsetY = 15;

        let top = clientY + offsetY;
        let left = clientX + offsetX;

        const viewportHeight = window.innerHeight;
        const viewportWidth = window.innerWidth;

        if (left + popoverWidth > viewportWidth - 10) {
            left = clientX - popoverWidth - offsetX;
        }
        if (top + popoverHeight > viewportHeight - 10) {
            top = clientY - popoverHeight - offsetY;
        }
        if (left < 10) left = 10;
        if (top < 10) top = 10;

        this.popoverTop = top;
        this.popoverLeft = left;
    }

    /**
     * Getter: Should the wire fees popover be shown?
     */
    get showWireFeePopover() {
        return this.hoveredRowId && this.rowHasWireFees(this.hoveredRowId);
    }

    /**
     * Getter: Inline style for popover positioning
     */
    get popoverStyle() {
        return `position: fixed; top: ${this.popoverTop}px; left: ${this.popoverLeft}px; z-index: 9999;`;
    }

    /**
     * Position the popover relative to a row's bounding rectangle
     * @param {HTMLElement} popover - The popover element
     * @param {DOMRect} rowRect - The row's bounding rectangle
     */
    positionPopover(popover, rowRect) {
        const popoverWidth = 500; // Approximate width
        const popoverHeight = 200; // Approximate height
        const offset = 10; // Offset from row

        // Calculate position - prefer below the row, but flip if not enough space
        let top = rowRect.bottom + offset;
        let left = rowRect.left + (rowRect.width / 2) - (popoverWidth / 2);

        // Viewport boundaries check
        const viewportHeight = window.innerHeight;
        const viewportWidth = window.innerWidth;

        // Flip to above if not enough space below
        if (top + popoverHeight > viewportHeight) {
            top = rowRect.top - popoverHeight - offset;
        }

        // Keep within horizontal bounds
        if (left < 10) {
            left = 10;
        } else if (left + popoverWidth > viewportWidth - 10) {
            left = viewportWidth - popoverWidth - 10;
        }

        // Apply position
        popover.style.top = `${top}px`;
        popover.style.left = `${left}px`;
    }

    /**
     * Position the popover at cursor location
     * @param {HTMLElement} popover - The popover element
     * @param {number} clientX - Cursor X position
     * @param {number} clientY - Cursor Y position
     */
    positionPopoverAtCursor(popover, clientX, clientY) {
        const popoverWidth = 500;
        const popoverHeight = 200;
        const offsetX = 15; // Offset from cursor
        const offsetY = 15;

        // Position to the right and below cursor by default
        let top = clientY + offsetY;
        let left = clientX + offsetX;

        // Viewport boundaries check
        const viewportHeight = window.innerHeight;
        const viewportWidth = window.innerWidth;

        // Flip to above cursor if not enough space below
        if (top + popoverHeight > viewportHeight) {
            top = clientY - popoverHeight - offsetY;
        }

        // Flip to left of cursor if not enough space on right
        if (left + popoverWidth > viewportWidth) {
            left = clientX - popoverWidth - offsetX;
        }

        // Keep within bounds
        if (top < 10) top = 10;
        if (left < 10) left = 10;

        // Apply position
        popover.style.top = `${top}px`;
        popover.style.left = `${left}px`;
    }

    /**
     * Get wire fees for the currently hovered row
     */
    get hoveredRowWireFees() {
        if (!this.hoveredRowId || !this.wireFeeMap[this.hoveredRowId]) {
            return [];
        }
        return this.wireFeeMap[this.hoveredRowId].map(fee => ({
            ...fee,
            feeTypeFormatted: fee.feeType,
            amountFormatted: this.formatCurrency(fee.amount || 0)
        }));
    }

    /**
     * Get count of wire fees for the currently hovered row
     */
    get hoveredRowWireFeesCount() {
        if (!this.hoveredRowId || !this.wireFeeMap[this.hoveredRowId]) {
            return 0;
        }
        return this.wireFeeMap[this.hoveredRowId].length;
    }

    /**
     * Check if a specific row has wire fees (for visual indicator)
     */
    hasWireFees(rowId) {
        return rowId && this.wireFeeMap[rowId]?.length > 0;
    }

    // ============ HELPER METHODS ============

    processItems(items, keepState = false) {
        return items.map((item, index) => {
            const rowNumber = item.rowNumber || index + 1;

            const draftAmount = Number(item.draftAmount) || 0;
            const setupFee = Number(item.setupFee) || 0;
            const programFee = Number(item.programFee) || 0;
            const bankingFee = Number(item.bankingFee) || 0;
            const savingsBalance = Number(item.savingsBalance) || 0;
            const toEscrowAmount = Number(item.toEscrowAmount) || 0;

            const isModified = keepState ? (item.isModified || false) : false;
            const isNew = keepState ? (item.isNew || false) : false;

            // Check if this item was modified from previous version (for star indicator)
            // Only check when not in keepState mode (i.e., when loading fresh data)
            const wasModifiedFromPrevious = keepState
                ? (item.wasModifiedFromPrevious || false)
                : this.isItemModifiedFromPrevious(item, rowNumber);

            // Preserve the original status from the item
            const itemStatus = item.status || 'Scheduled';

            // Only rows with 'Scheduled' status are editable
            const isRowEditable = itemStatus === EDITABLE_STATUS;

            // Build status options with correct selection for this item
            const statusOptionsWithSelection = this.statusPicklistOptions.map(opt => ({
                label: opt.label,
                value: opt.value,
                selected: opt.value === itemStatus
            }));

            // Show star if: currently modified in edit mode OR was modified from previous version
            const showModifiedStar = isModified || wasModifiedFromPrevious;

            return {
                ...item,
                id: item.id || null,
                tempId: item.tempId || `temp_${Date.now()}_${index}`,
                rowNumber: rowNumber,
                draftNumber: item.draftNumber || String(rowNumber),
                paymentDate: item.paymentDate,
                paymentDateFormatted: item.paymentDate,
                paymentDateDisplay: this.formatDate(item.paymentDate),
                draftAmount: draftAmount,
                draftAmountEdit: this.getEditValue(item, 'draftAmount', draftAmount),
                draftAmountFormatted: this.formatCurrency(draftAmount),
                draftAmountClass: this.getAmountClass(draftAmount),
                setupFee: setupFee,
                setupFeeEdit: this.getEditValue(item, 'setupFee', setupFee),
                setupFeeFormatted: this.formatCurrency(setupFee),
                setupFeeClass: this.getAmountClass(setupFee),
                programFee: programFee,
                programFeeEdit: this.getEditValue(item, 'programFee', programFee),
                programFeeFormatted: this.formatCurrency(programFee),
                programFeeClass: this.getAmountClass(programFee),
                bankingFee: bankingFee,
                bankingFeeEdit: this.getEditValue(item, 'bankingFee', bankingFee),
                bankingFeeFormatted: this.formatCurrency(bankingFee),
                bankingFeeClass: this.getAmountClass(bankingFee),
                savingsBalance: savingsBalance,
                savingsBalanceEdit: this.safeToFixed(savingsBalance),
                savingsBalanceFormatted: this.formatCurrency(savingsBalance),
                savingsClass: savingsBalance < 0 ? 'savings-negative' : 'savings-positive',
                toEscrowAmount: toEscrowAmount,
                status: itemStatus,
                statusBadgeClass: this.getStatusBadgeClass(itemStatus),
                statusOptionsWithSelection: statusOptionsWithSelection,
                isRowEditable: isRowEditable,
                rowClass: this.getRowClass({ ...item, isModified, isNew, status: itemStatus }),
                rowNumberClass: showModifiedStar ? 'row-number row-number-modified' : 'row-number',
                isModified: isModified,
                isNew: isNew,
                wasModifiedFromPrevious: wasModifiedFromPrevious,
                isDeleted: keepState ? (item.isDeleted || false) : false,
                isSelected: item.isSelected || false
            };
        });
    }

    /**
     * Check if an item was modified compared to the previous version
     * Compares by rowNumber (Payment_Number__c)
     * @param {Object} item - Current item to check
     * @param {Number} rowNumber - Row number to match
     * @returns {Boolean} - True if item is new or modified from previous version
     */
    isItemModifiedFromPrevious(item, rowNumber) {
        // If no previous version items, this is version 1 - no stars
        if (!this.previousVersionItems || this.previousVersionItems.length === 0) {
            return false;
        }

        // Find matching item in previous version by rowNumber
        const prevItem = this.previousVersionItems.find(p => p.rowNumber === rowNumber);

        // If no match found in previous version, this is a NEW item
        if (!prevItem) {
            return true;
        }

        // Compare key fields to detect modifications
        // Using loose comparison with Number() to handle string/number differences
        const fieldsToCompare = [
            { current: item.paymentDate, previous: prevItem.paymentDate },
            { current: Number(item.draftAmount) || 0, previous: Number(prevItem.draftAmount) || 0 },
            { current: Number(item.setupFee) || 0, previous: Number(prevItem.setupFee) || 0 },
            { current: Number(item.programFee) || 0, previous: Number(prevItem.programFee) || 0 },
            { current: Number(item.bankingFee) || 0, previous: Number(prevItem.bankingFee) || 0 },
            { current: Number(item.savingsBalance) || 0, previous: Number(prevItem.savingsBalance) || 0 },
            { current: item.status, previous: prevItem.status }
        ];

        // Check if any field is different
        for (const field of fieldsToCompare) {
            if (field.current !== field.previous) {
                return true;
            }
        }

        return false;
    }

    /**
     * Get edit value for an input field
     * Preserves the current input value if the field is being actively edited
     * to prevent cursor jump during typing
     */
    getEditValue(item, field, numericValue) {
        // Check if this field is currently focused (being edited)
        const activeElement = document.activeElement;
        if (activeElement && activeElement.tagName === 'INPUT') {
            const activeField = activeElement.dataset.field;
            const activeId = activeElement.dataset.id;

            // If this is the actively edited field, return its current value
            // to prevent reformatting and cursor jump
            if (activeField === field && (activeId === item.id || activeId === item.tempId)) {
                return activeElement.value;
            }
        }

        // Not being edited - return formatted value
        return this.safeToFixed(numericValue);
    }

    getAmountClass(value) {
        if (value === 0) return 'value-zero';
        if (value < 0) return 'value-negative';
        return '';
    }

    // Safe toFixed - ensures value is a number before calling toFixed
    safeToFixed(value, decimals = 2) {
        const num = Number(value);
        if (isNaN(num)) {
            return '0.00';
        }
        return num.toFixed(decimals);
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

    getTodayString() {
        const today = new Date();
        return today.toISOString().split('T')[0];
    }

    addDays(dateString, days) {
        const date = new Date(dateString + 'T00:00:00');
        date.setDate(date.getDate() + days);
        return date.toISOString().split('T')[0];
    }

    getRowClass(item) {
        const classes = [];

        if (item.isModified) {
            classes.push('row-modified');
        }
        if (item.isNew) {
            classes.push('row-new');
        }
        if (item.isDeleted) {
            classes.push('row-deleted');
        }

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

        // Add locked class for non-editable rows (status !== 'Scheduled')
        if (item.status && item.status !== EDITABLE_STATUS) {
            classes.push('row-locked');
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

    /**
     * Reduces one or more errors into a single string for display
     * Follows Salesforce best practices for LWC error handling
     * @param {Error|Array} error - Error object or array of errors
     * @returns {String} - Human-readable error message
     */
    reduceErrors(error) {
        // Handle null/undefined
        if (!error) {
            return 'An unknown error occurred';
        }

        // Handle string errors
        if (typeof error === 'string') {
            return error;
        }

        // Handle array of errors (recursively reduce each)
        if (Array.isArray(error)) {
            return error.map(e => this.reduceErrors(e)).join(', ');
        }

        // Handle Apex/LDS error response body
        if (error.body) {
            // Standard Apex error message
            if (typeof error.body.message === 'string') {
                return error.body.message;
            }
            // Page-level errors (from DML operations)
            if (Array.isArray(error.body.pageErrors) && error.body.pageErrors.length > 0) {
                return error.body.pageErrors.map(e => e.message).join(', ');
            }
            // Field-level errors (from validation rules, required fields)
            if (error.body.fieldErrors) {
                const fieldErrors = Object.values(error.body.fieldErrors)
                    .flat()
                    .map(e => e.message);
                if (fieldErrors.length > 0) {
                    return fieldErrors.join(', ');
                }
            }
            // Duplicate record errors
            if (Array.isArray(error.body.duplicateResults) && error.body.duplicateResults.length > 0) {
                return 'Duplicate record found';
            }
            // Output errors (from LDS)
            if (Array.isArray(error.body.output?.errors) && error.body.output.errors.length > 0) {
                return error.body.output.errors.map(e => e.message).join(', ');
            }
        }

        // Handle standard JavaScript Error objects
        if (error.message) {
            return error.message;
        }

        // Handle statusText from HTTP errors
        if (error.statusText) {
            return error.statusText;
        }

        // Fallback for unknown error format
        return 'An unexpected error occurred. Please try again.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    /**
     * Deep clone an array of items using spread operator
     * Follows Salesforce best practices for object cloning in LWC
     * @param {Array} items - Array of objects to clone
     * @returns {Array} - Deep cloned array
     */
    deepCloneItems(items) {
        if (!items || !Array.isArray(items)) {
            return [];
        }
        return items.map(item => ({ ...item }));
    }

    // ============ FILL HANDLE METHODS ============

    /**
     * Handle cell selection when clicked
     * Stores source cell info for potential fill operation
     * Single cell selection only - copies value to all target cells
     */
    handleCellSelect(event) {
        event.stopPropagation();

        const cellElement = event.currentTarget;
        const field = cellElement.dataset.field;
        const rowIndex = parseInt(cellElement.dataset.rowIndex, 10);

        // Find the item from active (non-deleted) items using rowIndex
        const activeItems = this.pendingItems.filter(i => !i.isDeleted);
        const item = activeItems[rowIndex];
        if (!item) return;

        // Get the actual value - read from input element if available (to capture unsaved typed values)
        const value = this.getValueFromCellByIndex ?
            this.getValueFromCellByIndex(rowIndex, field) :
            item[field];

        // Single cell selection - clear previous and select new
        this.clearCellSelection();

        // Use item.tempId for consistency (from active items array)
        const itemTempId = item.tempId;

        // Set new selection
        this.selectedCellKey = `${itemTempId}-${field}`;
        this.fillSourceCell = {
            rowIndex: rowIndex,
            field: field,
            value: value,
            tempId: itemTempId
        };

        // Add selected class to this cell
        cellElement.classList.add('cell-selected');
    }

    /**
     * Clear all cell selections
     */
    clearCellSelection() {
        const selectedCells = this.template.querySelectorAll('.cell-selected');
        selectedCells.forEach(cell => cell.classList.remove('cell-selected'));
        this.selectedCellKey = null;
    }

    /**
     * Handle fill handle mouse down - start drag operation
     * Single cell selection only - copies value to all target cells
     */
    handleFillHandleMouseDown(event) {
        event.preventDefault();
        event.stopPropagation();

        const cellElement = event.target.closest('.fill-cell');
        if (!cellElement) return;

        const field = cellElement.dataset.field;
        const tempId = cellElement.dataset.id;
        const rowIndex = parseInt(cellElement.dataset.rowIndex, 10);

        // Read value directly from the input element to get the current typed value
        const value = this.getValueFromCell(cellElement, field);

        // Set single cell selection
        this.fillSourceCell = {
            rowIndex: rowIndex,
            field: field,
            value: value,
            tempId: tempId
        };

        // Update visual selection
        this.clearCellSelectionVisual();
        cellElement.classList.add('cell-selected');
        this.selectedCellKey = `${tempId}-${field}`;

        if (!this.fillSourceCell) return;

        this.fillHandleActive = true;
        this.fillTargetRows = [];

        // Add dragging class to body
        document.body.classList.add('fill-dragging');

        // Bind event listeners
        this._boundFillMouseMove = this.handleFillMouseMove.bind(this);
        this._boundFillMouseUp = this.handleFillMouseUp.bind(this);

        document.addEventListener('mousemove', this._boundFillMouseMove);
        document.addEventListener('mouseup', this._boundFillMouseUp);
    }

    /**
     * Clear cell selection visual (CSS class only, not data)
     */
    clearCellSelectionVisual() {
        const selectedCells = this.template.querySelectorAll('.cell-selected');
        selectedCells.forEach(cell => cell.classList.remove('cell-selected'));
    }

    /**
     * Get current value from a cell element (reads from input if present, otherwise from data)
     */
    getValueFromCell(cellElement, field) {
        // Try to read from input element first (for edit mode)
        const input = cellElement.querySelector('input');
        if (input) {
            const inputValue = input.value;
            // Parse numeric values
            if (this.isNumericField(field)) {
                return parseFloat(inputValue) || 0;
            }
            return inputValue;
        }

        // Fall back to reading from pendingItems
        const rowIndex = parseInt(cellElement.dataset.rowIndex, 10);
        const activeItems = this.pendingItems.filter(i => !i.isDeleted);
        const item = activeItems[rowIndex];
        return item ? item[field] : null;
    }

    /**
     * Get current value from a cell by row index and field (reads from input if present)
     */
    getValueFromCellByIndex(rowIndex, field) {
        // Find the cell element
        const cellElement = this.template.querySelector(
            `.fill-cell[data-field="${field}"][data-row-index="${rowIndex}"]`
        );

        if (cellElement) {
            return this.getValueFromCell(cellElement, field);
        }

        // Fall back to pendingItems
        const activeItems = this.pendingItems.filter(i => !i.isDeleted);
        const item = activeItems[rowIndex];
        return item ? item[field] : null;
    }

    /**
     * Handle mouse move during fill drag
     * Track which rows the cursor is over and update fill range
     * Single cell selection - copies source value to all target cells
     */
    handleFillMouseMove(event) {
        if (!this.fillHandleActive || !this.fillSourceCell) return;

        const field = this.fillSourceCell.field;
        const sourceRowIndex = this.fillSourceCell.rowIndex;

        // Find all fill-cells for this field
        const cells = this.template.querySelectorAll(`.fill-cell[data-field="${field}"]`);

        // Clear previous fill range highlighting
        cells.forEach(cell => cell.classList.remove('in-fill-range'));

        // Determine which row the cursor is over
        let targetRowIndex = null;
        cells.forEach(cell => {
            const rect = cell.getBoundingClientRect();
            if (event.clientY >= rect.top && event.clientY <= rect.bottom) {
                targetRowIndex = parseInt(cell.dataset.rowIndex, 10);
            }
        });

        // Target must be different from source row
        const isOutsideSelection = targetRowIndex !== null && targetRowIndex !== sourceRowIndex;

        if (isOutsideSelection) {
            // Build array of rows to fill (from source to target, excluding source)
            this.fillTargetRows = [];

            if (targetRowIndex < sourceRowIndex) {
                // Filling UP
                for (let i = targetRowIndex; i < sourceRowIndex; i++) {
                    this.fillTargetRows.push(i);
                }
            } else {
                // Filling DOWN
                for (let i = sourceRowIndex + 1; i <= targetRowIndex; i++) {
                    this.fillTargetRows.push(i);
                }
            }

            // Highlight cells in fill range
            cells.forEach(cell => {
                const rowIdx = parseInt(cell.dataset.rowIndex, 10);
                if (this.fillTargetRows.includes(rowIdx)) {
                    cell.classList.add('in-fill-range');
                }
            });

            // Show preview value (always the source value for single cell)
            if (this.fillTargetRows.length > 0) {
                this.fillPreviewValue = this.fillSourceCell.value;
            }
        } else {
            this.fillTargetRows = [];
            this.fillPreviewValue = null;
        }
    }

    /**
     * Handle mouse up - end drag and apply fill
     */
    handleFillMouseUp(event) {
        // Remove event listeners
        document.removeEventListener('mousemove', this._boundFillMouseMove);
        document.removeEventListener('mouseup', this._boundFillMouseUp);

        // Remove dragging class
        document.body.classList.remove('fill-dragging');

        // Clear fill range highlighting
        const cells = this.template.querySelectorAll('.in-fill-range');
        cells.forEach(cell => cell.classList.remove('in-fill-range'));

        // Apply fill if we have target rows
        if (this.fillTargetRows.length > 0 && this.fillSourceCell) {
            this.applyFill();
        }

        // Reset fill state
        this.resetFillState();
    }

    /**
     * Apply fill values to target rows
     * Single cell selection - copies source value to all target cells
     */
    applyFill() {
        if (!this.fillSourceCell || this.fillTargetRows.length === 0) return;

        const field = this.fillSourceCell.field;
        const sourceValue = this.fillSourceCell.value;

        // Get filtered pending items (non-deleted)
        const activeItems = this.pendingItems.filter(item => !item.isDeleted);

        // Update each target row with the source value
        this.pendingItems = this.pendingItems.map((item, idx) => {
            // Find the display index (among non-deleted items)
            const displayIndex = activeItems.findIndex(ai => ai.tempId === item.tempId);

            if (displayIndex !== -1 && this.fillTargetRows.includes(displayIndex)) {
                return {
                    ...item,
                    [field]: sourceValue,
                    isModified: true
                };
            }
            return item;
        });

        // Re-process items to update formatted values
        this.pendingItems = this.processItems(this.pendingItems, true);

        const count = this.fillTargetRows.length;
        this.showToast('Success', `Filled ${count} cell${count > 1 ? 's' : ''}`, 'success');
    }

    /**
     * Check if field is a numeric type (editable numeric fields only)
     */
    isNumericField(field) {
        const numericFields = [
            'draftAmount',
            'setupFee',
            'programFee',
            'bankingFee'
        ];
        return numericFields.includes(field);
    }

    /**
     * Reset all fill-related state
     */
    resetFillState() {
        this.fillHandleActive = false;
        this.fillTargetRows = [];
        this.fillPreviewValue = null;
        // Keep fillSourceCell for keyboard shortcuts
    }

    // Checkbox functionality removed - Ctrl+D fill down was not working
    // /**
    //  * Handle keyboard shortcuts on cells
    //  * Ctrl+D: Fill down from selected cell
    //  */
    // handleCellKeyDown(event) {
    //     // Ctrl+D or Cmd+D: Fill down
    //     if ((event.ctrlKey || event.metaKey) && event.key === 'd') {
    //         event.preventDefault();
    //         this.fillDown();
    //     }
    // }

    // /**
    //  * Fill down from current cell to all selected rows
    //  */
    // fillDown() {
    //     if (!this.fillSourceCell) {
    //         this.showToast('Info', 'Select a cell first to fill down', 'info');
    //         return;
    //     }

    //     // Get selected row IDs
    //     if (this.selectedRowIds.size === 0) {
    //         this.showToast('Info', 'Select rows using checkboxes to fill down', 'info');
    //         return;
    //     }

    //     const field = this.fillSourceCell.field;
    //     const sourceValue = this.fillSourceCell.value;
    //     let filledCount = 0;

    //     this.pendingItems = this.pendingItems.map(item => {
    //         if (this.selectedRowIds.has(item.tempId) && item.tempId !== this.fillSourceCell.tempId) {
    //             filledCount++;
    //             return {
    //                 ...item,
    //                 [field]: sourceValue,
    //                 isModified: true
    //             };
    //         }
    //         return item;
    //     });

    //     if (filledCount > 0) {
    //         this.pendingItems = this.processItems(this.pendingItems, true);
    //         this.showToast('Success', `Filled ${filledCount} cell${filledCount > 1 ? 's' : ''}`, 'success');
    //     }
    // }

    /**
     * Get CSS class for fill cell based on selection state
     */
    getFillCellClass(tempId, field) {
        const key = `${tempId}-${field}`;
        let classes = 'fill-cell';

        if (this.selectedCellKey === key) {
            classes += ' cell-selected';
        }

        return classes;
    }
}