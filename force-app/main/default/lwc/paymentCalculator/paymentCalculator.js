import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import calculatePaymentPlan from '@salesforce/apex/PaymentCalculatorController.calculatePaymentPlan';
//import getCreditors from '@salesforce/apex/PaymentCalculatorController.getCreditors';
import saveDraftV2 from '@salesforce/apex/PaymentCalculatorController.saveDraftV2';
import loadDrafts from '@salesforce/apex/PaymentCalculatorController.loadDrafts';
import getPrimaryDraft from '@salesforce/apex/PaymentCalculatorController.getPrimaryDraft';
import setPrimaryDraft from '@salesforce/apex/PaymentCalculatorController.setPrimaryDraft';
import deactivateDraft from '@salesforce/apex/PaymentCalculatorController.deactivateDraft';
import getPaymentDraftItemHistory from '@salesforce/apex/PaymentCalculatorController.getPaymentDraftItemHistory';
import getRequiredConfig from '@salesforce/apex/PaymentCalcConfigSvc.getRequiredConfig';
import getRequiredConfigForProgram from '@salesforce/apex/PaymentCalcConfigSvc.getRequiredConfigForProgram';
import { subscribe, onError } from 'lightning/empApi';
import LEAD_STATE_FIELD from '@salesforce/schema/Lead.State';
import OPP_EST_CURRENT_PAYMENT_FIELD from '@salesforce/schema/Opportunity.Estimated_Current_Payment__c';
import OPP_EST_TOTAL_DEBT_FIELD from '@salesforce/schema/Opportunity.Estimated_Total_Debt__c';
import OPP_ACCOUNT_STATE from '@salesforce/schema/Opportunity.Account.BillingState';

const FIELDS = [LEAD_STATE_FIELD];
const OPP_FIELDS = [OPP_EST_CURRENT_PAYMENT_FIELD, OPP_EST_TOTAL_DEBT_FIELD, OPP_ACCOUNT_STATE];

const SYNC_STATUS = { IN_SYNC: 'In Sync', OUT_OF_SYNC: 'Out of Sync' };

// No default constants - configuration MUST be loaded from CMDT or the calculator cannot function

export default class PaymentCalculator extends LightningElement {
    @api recordId;
    @api objectApiName;

    isLoading = false;
    @track creditors = [];
    opportunity;
    drafts = [];
    selectedDraftId = null;
    channelName = '/event/OpportunityUpdate__e';
    subscription = null;
    /**
     * Draft columns with dynamic row actions.
     * Uses getter so getDraftRowActions is properly bound at runtime.
     */
    get draftColumns() {
        return [
            {
                label: 'Sync Status', fieldName: 'syncStatus', type: 'text',
                cellAttributes: { class: { fieldName: 'rowClass' } }
            },
            {
                label: 'Name', fieldName: 'Name', type: 'text',
                cellAttributes: { class: { fieldName: 'rowClass' } }
            },
            {
                label: 'Primary', fieldName: 'isPrimary', type: 'boolean',
                cellAttributes: { class: { fieldName: 'rowClass' } }
            },
            {
                label: 'Weekly Payment', fieldName: 'weeklyPayment', type: 'currency',
                typeAttributes: { currencyCode: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 2 },
                cellAttributes: { class: { fieldName: 'rowClass' } }
            },
            {
                label: 'Savings %', fieldName: 'savingsPercent', type: 'number',
                typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 },
                cellAttributes: { class: { fieldName: 'rowClass' } }
            },
            {
                label: 'Duration', fieldName: 'numberOfWeeks', type: 'number',
                cellAttributes: { class: { fieldName: 'rowClass' } }
            },
            {
                type: 'action',
                typeAttributes: { rowActions: this.getDraftRowActions.bind(this) },
                cellAttributes: { class: { fieldName: 'rowClass' } }
            }
        ];
    }

    /**
     * Dynamically returns row actions for draft table.
     * Primary drafts cannot be deleted - user must set another draft as primary first.
     */
    getDraftRowActions(row, doneCallback) {
        const statusValue = (row.syncStatus || '').trim().toLowerCase();
        const isOutOfSync = statusValue === 'out of sync';

        if (isOutOfSync) {
            doneCallback([]); // no actions allowed
            return;
        }

        const actions = [
            { label: 'Load', name: 'load' },
            { label: 'Set Primary', name: 'set_primary' }
        ];

        if (!row.isPrimary) {
            actions.push({ label: 'Delete', name: 'delete' });
        }

        doneCallback(actions);
    }

    // Program Settings
    @track programType = 'DCG_MOD'; // DCG_MOD or DCG_DEBT
    paymentFrequency = 'WEEKLY'; // WEEKLY or MONTHLY
    calculateBy = 'PERCENT'; // PERCENT or DESIRED
    targetPaymentPercent = 59;
    targetPaymentAmount = 8255.00;
    setupFeePayments = 10;
    setupFeeTotal = 1000;
    noFeeProgram = false;

    // Payment Schedule Settings
    firstDraftDate = '';
    preferredDayOfWeek = '1'; // Default to Monday (1)

    // Background Variables (hidden from UI)
    settlementPercent = 60; // Unified 60% for all programs
    programFeePercent = 35; // Unified 35% for all programs
    bankingFee = 35; // Weekly banking fee ($35)
    bank2Fee = 0; // Secondary banking fee ($0)
    programSplitRatio = 0.50; // Default DCG Mod 50/50 (matches default programType)
    escrowSplitRatio = 0.50;

    // Config state - MUST be loaded from CMDT before calculator can function
    configLoaded = false;
    configLoadError = null;

    // Config-loaded values - no defaults, must be populated by loadConfig()
    _minWeeklyTargetPayment = null;
    _minWeeklyTargetPaymentDcgDebt = null;
    _weeklyToMonthlyFactor = null;
    _minTargetPercentDcgMod = null;
    _minTargetPercentDcgDebt = null;
    _maxTargetPercent = null;
    _defaultSetupFee = null;
    _noFeeSetupFee = null;
    _debtProgramSetupFee = null;  // Setup fee for DCG Debt program
    _legalMonitoringWeeklyFee = null;
    _setupFeeMinPayments = null;
    _setupFeeMaxPayments = null;

    // Calculation Results
    totalDebt = 14000; // Default for testing, will come from creditors
    currentPayment = 6300; // Default current payment
    @track calculations = {
        weeklyPayment: 0,
        monthlyPayment: 0,
        programLength: 0,
        settlementAmount: 0,
        programFeeAmount: 0,
        totalProgramCost: 0,
        savingsAmount: 0,
        savingsPercent: 0,
        setupFeePerPayment: 100,
        bankingFeeTotal: 0
    };

    // Payment Schedule
    @track paymentSchedule = [];
    showPaymentSchedule = false;
    // Sequence guard to ignore stale async results (Context7 pattern)
    _calcSeq = 0;

    // Additional Products (UI-only; backend wiring TBD)
    // Stub catalog; replace with backend fetch (e.g., CMDT or Product2 family)
    @track availableProducts = [
        { code: 'LEGAL_MONITORING', name: 'Legal Monitoring', weeklyFee: 25.00, selected: false }
    ];

    // Normalize product UI classes to match Program Settings cards
    decorateProducts(list) {
        return (list || []).map(p => ({
            ...p,
            cardClass: p.selected ? 'selection-card selected' : 'selection-card',
            checkClass: p.selected ? 'check-circle checked' : 'check-circle'
        }));
    }

    connectedCallback() {
        // Initialize simple UI values
        this.setDefaultFirstDraftDate();
        // Set initial product UI classes
        this.availableProducts = this.decorateProducts(this.availableProducts);

        this.subscribeToEvent();
        this.registerErrorListener();

        // Load configuration first - REQUIRED before calculator can function
        this.loadConfig()
            .then(() => {
                // Update slider numbers based on config
                this.sliderNumbers = this._generateSliderNumbers();
            })
            .catch((e) => {
                // Config loading failed - calculator cannot function
                const errorMsg = e?.body?.message || e?.message || 'Unknown configuration error';
                console.error('[PaymentCalculator] CRITICAL: Failed to load configuration. Calculator disabled.', errorMsg);
                this.configLoadError = `Configuration Error: ${errorMsg}. Please contact your administrator.`;
                this.showToast('Configuration Error', this.configLoadError, 'error', false);
            });
    }

    hasBootstrapped = false;
    renderedCallback() {
        // Only bootstrap if config loaded successfully and we have a recordId
        if (!this.hasBootstrapped && this.recordId && this.configLoaded && !this.configLoadError) {
            this.hasBootstrapped = true;
            this.bootstrapCalculator();
        }

        // Defer until datatable rows fully render
        setTimeout(() => {
            this.hideOutOfSyncChevronsOnDrafts();
        }, 0);
    }

    // Getter for template to check if calculator is disabled due to config error
    get isConfigError() {
        return !!this.configLoadError;
    }

    get configErrorMessage() {
        return this.configLoadError || '';
    }

    async bootstrapCalculator() {
        try {
            this.isLoading = true;
            await this.initializeDrafts();
            await this.loadCreditors();
            // Recompute after creditors load to ensure schedule aligns with loaded draft
            await this.performCalculations();
            if (!this.selectedDraftId && this.drafts && this.drafts.length > 0) {
                console.log('[PaymentCalculator] bootstrapCalculator: Fallback apply first draft');
                this.applyDraft(this.drafts[0]);
            }
        } catch (e) {
            console.warn('[PaymentCalculator] bootstrapCalculator error', e?.body?.message || e?.message);
        } finally {
            this.isLoading = false;
        }
    }

    async initializeDrafts() {
        try {
            await this.loadSavedDrafts();
            const listPrimary = (this.drafts || []).find(d => d.isPrimary);
            if (listPrimary && listPrimary.Id) {
                console.log('[PaymentCalculator] initializeDrafts: Applying primary from list', listPrimary.Id);
                this.applyDraft(listPrimary);
            } else {
                const primary = await getPrimaryDraft({ recordId: this.recordId });
                if (primary && primary.Id) {
                    console.log('[PaymentCalculator] initializeDrafts: Applying primary from Apex', primary.Id);
                    this.applyDraft(primary);
                } else if (this.drafts && this.drafts.length > 0) {
                    console.log('[PaymentCalculator] initializeDrafts: No primary, applying most recent', this.drafts[0]?.Id);
                    this.applyDraft(this.drafts[0]);
                } else {
                    console.log('[PaymentCalculator] initializeDrafts: No drafts found');
                }
            }
        } catch (e) {
            // Safe to ignore, continue without drafts
            console.warn('initializeDrafts error', e?.body?.message || e?.message);
        }
    }

    async loadConfig() {
        // Use getRequiredConfig which throws if config is unavailable or invalid
        const cfg = await getRequiredConfig();

        // Config is required - all values must be present
        // Apply background configuration (no fallbacks - config is validated by Apex)
        this.settlementPercent = cfg.settlementPercent;
        this.programFeePercent = cfg.programFeePercent;
        this.bankingFee = cfg.bankingFee;
        this.bank2Fee = cfg.bank2Fee;
        this.programSplitRatio = cfg.programSplitRatio;
        this.escrowSplitRatio = cfg.escrowSplitRatio;

        // Load additional config values for dynamic behavior
        this._minWeeklyTargetPayment = cfg.minWeeklyTargetPayment;
        this._minWeeklyTargetPaymentDcgDebt = cfg.minWeeklyTargetPaymentDcgDebt;
        this._weeklyToMonthlyFactor = cfg.weeklyToMonthlyFactor;
        this._minTargetPercentDcgMod = cfg.minTargetPercentDcgMod;
        this._minTargetPercentDcgDebt = cfg.minTargetPercentDcgDebt;
        this._maxTargetPercent = cfg.maxTargetPercent;
        this._defaultSetupFee = cfg.setupFee;
        this._noFeeSetupFee = cfg.noFeeSetupFee;
        this._debtProgramSetupFee = cfg.debtProgramSetupFee;  // Setup fee for DCG Debt
        this._legalMonitoringWeeklyFee = cfg.legalMonitoringWeeklyFee;
        this._setupFeeMinPayments = cfg.setupFeeMinPayments;
        this._setupFeeMaxPayments = cfg.setupFeeMaxPayments;

        // Set initial setupFeeTotal from config
        this.setupFeeTotal = this._defaultSetupFee;

        // Update available products with config-loaded fees
        this.availableProducts = this.decorateProducts(
            (this.availableProducts || []).map(p =>
                p.code === 'LEGAL_MONITORING'
                    ? { ...p, weeklyFee: this._legalMonitoringWeeklyFee }
                    : p
            )
        );

        // Mark config as successfully loaded
        this.configLoaded = true;
        this.configLoadError = null;
        console.log('[PaymentCalculator] Config loaded from CMDT', cfg);
    }

    setDefaultFirstDraftDate() {
        // Default to next Monday
        const today = new Date();
        const dayOfWeek = today.getDay();
        const daysUntilMonday = dayOfWeek === 0 ? 1 : (8 - dayOfWeek) % 7 || 7;
        const nextMonday = new Date(today.getTime() + daysUntilMonday * 24 * 60 * 60 * 1000);

        // Format as YYYY-MM-DD
        const year = nextMonday.getFullYear();
        const month = String(nextMonday.getMonth() + 1).padStart(2, '0');
        const day = String(nextMonday.getDate()).padStart(2, '0');
        this.firstDraftDate = `${year}-${month}-${day}`;
    }

    @wire(getRecord, { recordId: '$recordId', fields: OPP_FIELDS })
    wiredRecord({ error, data }) {
        console.log('[PaymentCalculator] wiredRecord called');
        if (data) {
            this.totalDebt = getFieldValue(data, OPP_EST_TOTAL_DEBT_FIELD);
            this.currentPayment = getFieldValue(data, OPP_EST_CURRENT_PAYMENT_FIELD);
            console.log('[PaymentCalculator] Record data loaded for recordId:', this.recordId);
            //const state = data.fields.State?.value;
            const state = getFieldValue(data, OPP_ACCOUNT_STATE);
            // CA State Special: Auto-enable No-Fee program
            if (state === 'CA' && !this.selectedDraftId) {
                console.log('[PaymentCalculator] CA state detected, enabling No-Fee program');
                this.noFeeProgram = true;
                // Setup fee is automatically set from config when No-Fee is enabled
                this.setupFeeTotal = this._noFeeSetupFee;
                this.programFeePercent = 0;
                this.showToast('Info', 'California No-Fee Program automatically applied', 'info', false);
            }
        } else if (error) {
            console.error('[PaymentCalculator] Error loading record:', error);
        }
    }

    async loadCreditors() {
        try {
            this.isLoading = true;
            //this.creditors = await getCreditors({ recordId: this.recordId });
            //this.calculateTotalDebt();
            // Precompute a local target payment for immediate UI accuracy while Apex runs
            this.targetPaymentAmount = this.computeTargetPaymentAmountLocal();
            await this.performCalculations();
        } catch (error) {
            console.error('Failed to load creditors', error);
            // Use default values for testing
            await this.performCalculations();
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Loads saved drafts from Apex for the current record.
     * Following LWC best practice: Clean async/await with guard clauses.
     */
    async loadSavedDrafts() {
        if (!this.recordId) {
            return;
        }

        try {
            const rows = await loadDrafts({ recordId: this.recordId });
            this.processDrafts(rows);
        } catch (error) {
            const errorMessage = error?.body?.message || error?.message || 'Failed to load drafts';
            this.showToast('Error', errorMessage, 'error', false);
        }
    }

    processDrafts(rows) {
        this.selectedDraftId = null; // ensure table redraw by clearing selection

        const processed = (rows || []).map(r => {
            // Handle both DraftWrapper (camelCase) and Map (Salesforce API names) formats
            const statusValue = (r.Sync_Status__c || r.syncStatus || '').trim().toLowerCase();
            const outOfSync = statusValue === 'out of sync';

            return {
                ...r,
                // Normalize field names for datatable (handle both formats)
                Id: r.Id || r.id,
                Name: r.Name || r.name,
                CreatedDate: r.CreatedDate || r.createdDate,
                CreatedBy: r.CreatedBy || r.createdBy,
                isPrimary: r.isPrimary,
                syncStatus: r.Sync_Status__c || r.syncStatus,
                isOutOfSync: outOfSync,
                rowClass: outOfSync
                    ? 'slds-theme_shade slds-text-color_default row-outofsync'
                    : ''
            };
        });

        // force Lightning datatable reactivity
        this.drafts = JSON.parse(JSON.stringify(processed));
    }

    async handleRefreshDrafts() {
        try {
            this.isLoading = true;
            await this.loadSavedDrafts();
            this.showToast('Success', `${this.drafts?.length || 0} drafts loaded`, 'success', false);
        } catch (e) {
            this.showToast('Error', 'Failed to refresh drafts', 'error', false);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Applies a draft's configuration to the UI and triggers recalculation.
     * Handles both DraftWrapper (from Apex) and processed draft objects (from datatable).
     * Following LWC best practice: Document parameters and handle multiple input formats.
     * @param {Object} draft - Draft object with config property (DraftWrapper or processed)
     */
    applyDraft(draft) {
        if (!draft || !draft.config) {
            return;
        }

        const cfg = draft.config;
        // Handle both wrapper (id) and processed (Id) formats
        const draftId = draft.Id || draft.id;
        const draftName = draft.Name || draft.name;

        this.selectedDraftId = draftId || this.selectedDraftId;

        // Apply configuration values with nullish coalescing for defaults
        this.programType = cfg.programType ?? this.programType;
        // Normalize paymentFrequency to uppercase (handles 'Weekly'/'Monthly' from saved drafts)
        const freq = cfg.paymentFrequency?.toUpperCase?.() ?? this.paymentFrequency;
        this.paymentFrequency = (freq === 'WEEKLY' || freq === 'MONTHLY') ? freq : this.paymentFrequency;
        this.calculateBy = cfg.calculateBy ?? this.calculateBy;
        this._setTargetPaymentPercent(cfg.targetPaymentPercent ?? this.targetPaymentPercent);
        this.targetPaymentAmount = cfg.targetPaymentAmount ?? this.targetPaymentAmount;
        this.setupFeePayments = cfg.setupFeePayments ?? this.setupFeePayments;
        this.setupFeeTotal = cfg.setupFeeTotal ?? this.setupFeeTotal;
        this.noFeeProgram = cfg.noFeeProgram ?? this.noFeeProgram;
        this.settlementPercent = cfg.settlementPercent ?? this.settlementPercent;
        this.programFeePercent = cfg.programFeePercent ?? this.programFeePercent;
        this.bankingFee = cfg.bankingFee ?? this.bankingFee;
        this.firstDraftDate = cfg.firstDraftDate ?? this.firstDraftDate;
        this.preferredDayOfWeek = cfg.preferredDayOfWeek ?? this.preferredDayOfWeek;

        // Restore additional product selections if present
        const selectedCodes = Array.isArray(cfg.selectedProductCodes) ? cfg.selectedProductCodes : [];
        if (selectedCodes.length > 0) {
            const selectedSet = new Set(selectedCodes);
            this.availableProducts = this.decorateProducts(
                (this.availableProducts || []).map(p => ({
                    ...p,
                    selected: selectedSet.has(p.code)
                }))
            );
        }

        // Recompute derived values and schedule
        this._enforcePaymentBounds();
        this.performCalculations();
        this.showToast('Success', `Loaded draft: ${draftName || ''}`, 'success', false);
    }

    /*calculateTotalDebt() {
        if (this.creditors && this.creditors.length > 0) {
            this.totalDebt = this.creditors.reduce((sum, creditor) => {
                return sum + (creditor.Amount__c || creditor.Current_Balance__c || 0);
            }, 0);
            // Also calculate current payment
            this.currentPayment = this.creditors.reduce((sum, creditor) => {
                return sum + (creditor.Estimated_Current_Weekly_Payment__c || creditor.Weekly_Payment__c || 0);
            }, 0);
            console.log('[PaymentCalculator] Total debt calculated:', this.totalDebt);
            console.log('[PaymentCalculator] Current payment calculated:', this.currentPayment);
        } else {
            console.log('[PaymentCalculator] No creditors, using default debt values');
        }
    }
    */
    async performCalculations() {
        console.log('[PaymentCalculator] performCalculations() called');
        console.log('[PaymentCalculator] Current programType:', this.programType);
        console.log('[PaymentCalculator] recordId:', this.recordId);

        // Do not perform calculations if config failed to load
        if (this.configLoadError) {
            console.error('[PaymentCalculator] Cannot calculate - config failed to load');
            return;
        }

        if (!this.recordId) {
            console.error('[PaymentCalculator] No recordId available, cannot calculate');
            return;
        }

        this._enforcePaymentBounds();

        let seq;
        try {
            seq = ++this._calcSeq;
            console.log('[PaymentCalculator] Calling Apex calculatePaymentPlan with programType:', this.programType, 'seq:', seq);
            // Call the Apex controller to perform calculations
            const result = await calculatePaymentPlan({
                recordId: this.recordId,
                programType: this.programType,
                paymentFrequency: this.paymentFrequency === 'WEEKLY' ? 'Weekly' : 'Monthly',
                calculationMode: this.calculateBy === 'PERCENT' ? 'percentage' : 'desired_payment',
                targetPaymentPercentage: this.targetPaymentPercent,
                targetPaymentAmount: this.targetPaymentAmount,
                setupFee: this.setupFeeTotal,
                setupFeeTerm: this.setupFeePayments,
                servicingFee: this.bankingFee,
                bank2Fee: this.bank2Fee,
                firstDraftDate: this.firstDraftDate,
                preferredDayOfWeek: this.preferredDayOfWeek ? parseInt(this.preferredDayOfWeek, 10) : null,
                noFeeProgram: this.noFeeProgram,
                additionalProductsWeeklyTotal: this.additionalProductsWeeklyTotal
            });

            console.log('[PaymentCalculator] Apex response received:', result ? 'SUCCESS' : 'NULL');

            if (result) {
                if (seq !== this._calcSeq) {
                    console.debug('[PaymentCalculator] Stale result ignored. seq:', seq, 'current:', this._calcSeq);
                    return;
                }
                console.log('[PaymentCalculator] Processing Apex result...');

                // Explicitly filter out getter-only properties to prevent proxy trap errors
                const filteredResult = { ...result };
                delete filteredResult.programSplitPercentage;
                delete filteredResult.escrowSplitPercentage;

                // Update local state with calculation results from Apex (no fallbacks)
                this.settlementPercent = filteredResult.settlementPercentage;
                this.programFeePercent = filteredResult.programFeePercentage;
                // Ensure UI currentPayment uses weekly value from Apex to avoid unit mismatch
                if (typeof filteredResult.currentPayment !== 'undefined' && filteredResult.currentPayment !== null) {
                    this.currentPayment = filteredResult.currentPayment;
                }

                // Update split ratios from Apex result (Apex determines these based on program type)
                console.log('[PaymentCalculator] Split ratios from Apex - Program:', filteredResult.programSplitRatio, 'Escrow:', filteredResult.escrowSplitRatio);

                // Trust Apex calculations - config is required, Apex must return these values
                this.programSplitRatio = filteredResult.programSplitRatio;
                this.escrowSplitRatio = filteredResult.escrowSplitRatio;
                console.log('[PaymentCalculator] Updated split ratios from Apex:', this.programSplitPercentage + '%/' + this.escrowSplitPercentage + '%');

                // California no-fee override
                if (this.noFeeProgram) {
                    this.programFeePercent = 0;
                    this.programSplitRatio = 0;
                    this.escrowSplitRatio = 1.0;
                }

                // Update calculations from Apex response
                this.calculations = {
                    weeklyPayment: filteredResult.weeklyPayment || 0,
                    monthlyPayment: filteredResult.monthlyPayment || 0,
                    programLength: filteredResult.numberOfWeeks || 0,
                    settlementAmount: filteredResult.settlementAmount || 0,
                    programFeeAmount: filteredResult.programFee || 0,
                    totalProgramCost: filteredResult.totalProgram || 0,
                    savingsAmount: filteredResult.totalSavings || 0,
                    savingsPercent: filteredResult.savingsPercentage || 0,
                    setupFeePerPayment: this.setupFeeTotal / this.setupFeePayments,
                    bankingFeeTotal: filteredResult.bankingFeeTotal || 0
                };

                // Store payment schedule if returned and convert for display
                if (filteredResult.paymentSchedule && filteredResult.paymentSchedule.length > 0) {
                    console.log('[PaymentCalculator] Payment schedule received from Apex with', filteredResult.paymentSchedule.length, 'items');
                    console.log('[PaymentCalculator] First payment item:', filteredResult.paymentSchedule[0]);
                    console.log('[PaymentCalculator] Program split for first item:', filteredResult.paymentSchedule[0].programPayment);
                    console.log('[PaymentCalculator] Escrow split for first item:', filteredResult.paymentSchedule[0].escrowPayment);

                    // Create new array reference to trigger reactive update
                    const convertedSchedule = this.convertScheduleForDisplay(filteredResult.paymentSchedule);
                    console.log('[PaymentCalculator] Converted schedule first item:', convertedSchedule[0]);

                    // Force new array reference
                    this.paymentSchedule = [...convertedSchedule];
                    this.showPaymentSchedule = true;

                    console.log('[PaymentCalculator] showPaymentSchedule set to:', this.showPaymentSchedule);
                    console.log('[PaymentCalculator] paymentSchedule updated with', this.paymentSchedule.length, 'items');
                    console.log('[PaymentCalculator] Split ratios in UI - Program:', this.programSplitPercentage + '%', 'Escrow:', this.escrowSplitPercentage + '%');

                    // Reactive binding will handle the update automatically
                    console.log('[PaymentCalculator] Payment schedule updated - reactive binding will update the table');
                } else {
                    console.log('[PaymentCalculator] WARNING: No payment schedule received from Apex');
                    this.paymentSchedule = [];
                    this.showPaymentSchedule = false;
                }

                // Update target payment amount only in Percent mode; preserve user-entered value in Desired mode
                if (this.calculateBy === 'PERCENT') {
                    if (filteredResult.weeklyPayment != null) {
                        const boundedWeekly = Math.max(this._minimumWeeklyTarget(), filteredResult.weeklyPayment);
                        const displayAmount = this._toDisplay(boundedWeekly);
                        this.targetPaymentAmount = displayAmount;
                        this._syncPercentFromAmount(displayAmount);
                    }
                }
            }
        } catch (error) {
            // If a newer calculation started, ignore this error
            if (this._calcSeq && typeof seq !== 'undefined' && seq !== this._calcSeq) {
                console.debug('[PaymentCalculator] Stale error ignored. seq:', seq, 'current:', this._calcSeq);
                return;
            }
            console.error('[PaymentCalculator] ERROR calculating payment plan:', error);
            console.error('[PaymentCalculator] Error details:', error.body?.message || error.message);

            // Check if this is a config-related error - if so, mark config as failed
            const errorMsg = error.body?.message || error.message || '';
            if (errorMsg.includes('PaymentCalcConfigException') || errorMsg.includes('Configuration') || errorMsg.includes('CMDT')) {
                this.configLoadError = `Configuration Error: ${errorMsg}. Please contact your administrator.`;
                this.configLoaded = false;
            }

            // Show error to user - NO fallback to local calculations
            this.showToast('Error', 'Failed to calculate payment plan: ' + errorMsg, 'error', false);

            // Clear any stale schedule data
            this.paymentSchedule = [];
            this.showPaymentSchedule = false;
        }
    }

    // Event Handlers
    handleProgramTypeMod() {
        console.log('[PaymentCalculator] === MOD CARD CLICKED ===');
        console.log('[PaymentCalculator] Previous programType:', this.programType);
        this.programType = 'DCG_MOD';
        // Immediate visual fallback while loading CMDT-configured ratios
        this.programSplitRatio = 0.50;
        this.escrowSplitRatio = 0.50;
        // Reset setup fee based on No-Fee Program status (switching from DCG Debt uses different fee)
        this.setupFeeTotal = this.noFeeProgram ? this._noFeeSetupFee : this._defaultSetupFee;
        this._enforcePaymentBounds();
        this.refreshConfigForProgram('DCG_MOD');
    }

    handleProgramTypeDebt() {
        console.log('[PaymentCalculator] === DEBT CARD CLICKED ===');
        console.log('[PaymentCalculator] Previous programType:', this.programType);
        this.programType = 'DCG_DEBT';
        // No-Fee Program applies only to DCG Mod; ensure it is off for Debt
        if (this.noFeeProgram) {
            this.noFeeProgram = false;
        }
        // Use Debt Program Setup Fee from CMDT for DCG Debt
        this.setupFeeTotal = this._debtProgramSetupFee ?? this._defaultSetupFee;
        console.log('[PaymentCalculator] Using Debt Program Setup Fee:', this.setupFeeTotal);
        // Immediate visual fallback while loading CMDT-configured ratios
        this.programSplitRatio = 0.70;
        this.escrowSplitRatio = 0.30;
        this._enforcePaymentBounds();
        this.refreshConfigForProgram('DCG_DEBT');
    }

    handleProgramTypeModCa() {
        console.log('[PaymentCalculator] === DCG MOD CA CARD CLICKED ===');
        console.log('[PaymentCalculator] Previous programType:', this.programType);
        this.programType = 'DCG_MOD_CA';
        // DCG MOD CA is California variant - automatically enables No-Fee Program behavior
        // Use same ratios as DCG Mod
        this.programSplitRatio = 0.50;
        this.escrowSplitRatio = 0.50;
        // No-Fee Program is implicitly enabled for California variant
        this.noFeeProgram = true;
        // Use No-Fee setup fee for California variant
        this.setupFeeTotal = this._noFeeSetupFee;
        this._enforcePaymentBounds();
        // Use DCG_MOD config as base for California variant
        this.refreshConfigForProgram('DCG_MOD');
    }

    async refreshConfigForProgram(programType) {
        try {
            // Use getRequiredConfigForProgram which throws if config is unavailable
            const cfg = await getRequiredConfigForProgram({ programType });

            // Apply program-specific config (no fallbacks - config is required)
            this.programSplitRatio = cfg.programSplitRatio;
            this.escrowSplitRatio = cfg.escrowSplitRatio;
            this.settlementPercent = cfg.settlementPercent;
            this.programFeePercent = cfg.programFeePercent;
            this.bankingFee = cfg.bankingFee;
            this.bank2Fee = cfg.bank2Fee;

            console.log('[PaymentCalculator] Calling performCalculations...');
            this.performCalculations();
        } catch (e) {
            // Config loading failed - set error state
            const errorMsg = e?.body?.message || e?.message || 'Unknown configuration error';
            console.error('[PaymentCalculator] CRITICAL: Failed to load program config for', programType, errorMsg);
            this.configLoadError = `Configuration Error: ${errorMsg}. Please contact your administrator.`;
            this.configLoaded = false;
            this.showToast('Configuration Error', this.configLoadError, 'error', false);
        }
    }

    handleFrequencyWeekly() {
        this.paymentFrequency = 'WEEKLY';
        this._enforcePaymentBounds();
        this.performCalculations();
    }

    handleFrequencyMonthly() {
        this.paymentFrequency = 'MONTHLY';
        this._enforcePaymentBounds();
        this.performCalculations();
    }

    handleCalculateByPercent() {
        this.calculateBy = 'PERCENT';
        this._enforcePaymentBounds();
        this.performCalculations();
    }

    handleCalculateByDesired() {
        this.calculateBy = 'DESIRED';
        // Allow manual input of desired payment
        // Ensure display reflects current desired value immediately
        this.targetPaymentAmount = this.targetPaymentAmount || this.computeTargetPaymentAmountLocal();
        // Sync percent to desired for consistent labeling
        this._syncPercentFromAmount(this.targetPaymentAmount);
        this._enforcePaymentBounds();
        // Trigger a calculation so weeks/schedule populate immediately after switching modes
        this.performCalculations();
    }

    // Live update while dragging slider
    handleTargetPaymentInput(event) {
        const percent = this._setTargetPaymentPercent(parseInt(event.target.value, 10));
        event.target.value = percent;
        // Update the displayed target amount immediately for a smooth UX
        if (this.calculateBy === 'PERCENT') {
            // Target payment is a percent of CURRENT weekly payment
            const weeklyFromCurrent = (this.currentPayment || 0) * (percent / 100);
            const boundedWeekly = Math.max(this._minimumWeeklyTarget(), weeklyFromCurrent);
            // Round to cents like CalculationService setScale(2, HALF_UP)
            this.targetPaymentAmount = this._roundToCents(this._toDisplay(boundedWeekly));
        }
        // Debounce the heavy calculation (Apex) while dragging
        this.debouncedRecalc();
    }

    handleTargetPaymentChange(event) {
        const percent = this._setTargetPaymentPercent(parseInt(event.target.value, 10));
        event.target.value = percent;
        this._enforcePaymentBounds();
        // Cancel any pending debounced calc to avoid duplicate runs on mouseup
        if (this.recalcTimer) {
            clearTimeout(this.recalcTimer);
            this.recalcTimer = null;
        }
        this.performCalculations();
    }

    handleSetupFeeChange(event) {
        this.setupFeePayments = parseInt(event.target.value);
        this.calculations = {
            ...this.calculations,
            setupFeePerPayment: this.setupFeeTotal / this.setupFeePayments
        };
        this.performCalculations();
    }

    handleNoFeeChange(event) {
        this.noFeeProgram = event.target.checked;
        // Set setup fee based on No-Fee Program status (from config)
        this.setupFeeTotal = this.noFeeProgram ? this._noFeeSetupFee : this._defaultSetupFee;
        this.performCalculations();
    }

    handleVersionCreated(event) {
        const { paymentPlanId } = event.detail;
        // Refresh or handle new version creation
        this.showToast('Success', 'New payment plan version created', 'success', false);
    }

    // Convert Apex schedule format to component display format
    convertScheduleForDisplay(apexSchedule) {
        console.log('PaymentCalculator: Converting schedule for display:', apexSchedule);

        if (!apexSchedule || apexSchedule.length === 0) {
            console.log('PaymentCalculator: No schedule data to convert');
            return [];
        }

        const converted = apexSchedule.map((item, index) => {
            console.log(`PaymentCalculator: Converting item ${index}:`, item);

            // Map Apex PaymentScheduleEntry fields to component fields
            return {
                id: item.Id || `schedule-${index}`,
                draftNumber: item.weekNumber || item.paymentNumber || index + 1, // Apex uses weekNumber
                paymentDate: item.paymentDate,
                paymentAmount: item.paymentAmount || item.totalPayment || 0, // Apex uses paymentAmount
                totalPayment: item.paymentAmount || item.totalPayment || 0,
                draftAmount: item.paymentAmount || item.totalPayment || 0, // For table display
                retainerFee: item.retainerFee || 0, // Now available in Apex
                setupFee: item.setupFee || 0, // Direct mapping
                setupFeePortion: item.setupFee || 0,
                programFee: item.programAmount || item.programPayment || 0, // Apex uses programAmount  
                programPortion: item.programAmount || item.programPayment || 0,
                bankingFee: item.bankingFee || 0, // Direct mapping
                bankingFeePortion: item.bankingFee || 0,
                bank2Fee: item.bank2Fee || 0, // Now available in Apex
                bank2Portion: item.bank2Fee || 0,
                additionalProducts: item.additionalProducts || 0, // Now available in Apex
                escrowAmount: item.escrowAmount || item.escrowPayment || 0, // Apex uses escrowAmount
                savingsBalance: item.escrowAmount || item.escrowPayment || 0,
                runningBalance: item.runningBalance || item.remainingBalance || 0, // Apex uses runningBalance
                runningTotal: item.runningBalance || item.remainingBalance || 0
            };
        });

        console.log('PaymentCalculator: Converted schedule:', converted);
        return converted;
    }

    // Helpers for enforcing payment bounds
    _toWeekly(amount) {
        if (amount == null) return 0;
        return this.paymentFrequency === 'WEEKLY' ? Number(amount) : Number(amount) / this._weeklyToMonthlyFactor;
    }

    _toDisplay(weeklyAmount) {
        if (weeklyAmount == null) return 0;
        return this.paymentFrequency === 'WEEKLY' ? Number(weeklyAmount) : Number(weeklyAmount) * this._weeklyToMonthlyFactor;
    }

    // Round to cents (2 decimal places) - matches Apex setScale(2, HALF_UP)
    _roundToCents(amount) {
        if (amount == null) return 0;
        return Math.round(amount * 100) / 100;
    }

    _minimumWeeklyTarget() {
        const current = this.currentPayment || 0;
        const percentFloor = this.hasCurrentPayment ? current * (this.percentMin / 100) : 0;
        const configMin = this.programType === 'DCG_DEBT'
            ? this._minWeeklyTargetPaymentDcgDebt
            : this._minWeeklyTargetPayment;
        return Math.max(configMin, percentFloor);
    }

    _maximumWeeklyTarget() {
        if (!this.hasCurrentPayment) return null;
        const current = this.currentPayment || 0;
        return current * (this.percentMax / 100);
    }

    _clampPercentValue(value) {
        let numeric = Number(value);
        if (Number.isNaN(numeric)) {
            numeric = this.percentMin;
        }
        numeric = Math.max(this.percentMin, numeric);
        numeric = Math.min(this.percentMax, numeric);
        return numeric;
    }

    _setTargetPaymentPercent(value) {
        const clamped = this._clampPercentValue(value);
        this.targetPaymentPercent = clamped;
        return clamped;
    }

    _syncPercentFromAmount(amount) {
        const pct = this._desiredPercentFrom(amount);
        if (pct != null) {
            this._setTargetPaymentPercent(Math.round(pct));
        }
    }

    _enforcePaymentBounds() {
        this._setTargetPaymentPercent(this.targetPaymentPercent);
        const weekly = this._toWeekly(this.targetPaymentAmount || this.computeTargetPaymentAmountLocal());
        const minWeekly = this._minimumWeeklyTarget();
        const boundedWeekly = Math.max(minWeekly, weekly);
        this.targetPaymentAmount = this._toDisplay(boundedWeekly);
    }

    // Get the actual "New Weekly Payment" as displayed in the UI
    // Uses the exact same calculation as summaryStats.js computedNewWeeklyPayment
    _getBaseWeeklyPaymentFromSchedule() {
        if (!this.paymentSchedule || this.paymentSchedule.length === 0) {
            // Fallback to calculated weekly payment when schedule is not yet available
            const weeklyPayment = this.calculations?.weeklyPayment || 0;
            console.log('[PaymentCalculator] _getBaseWeeklyPaymentFromSchedule: No schedule, using weeklyPayment:', weeklyPayment);
            return weeklyPayment;
        }

        // Exact same logic as summaryStats.js computedNewWeeklyPayment:
        // First payment amount from schedule minus setup fee
        const first = this.paymentSchedule[0] || {};
        const payment = first.paymentAmount ?? first.totalPayment ?? first.draftAmount ?? 0;
        const setup = first.setupFee ?? first.setupFeePortion ?? 0;
        const result = Math.max(0, payment - setup);

        console.log('[PaymentCalculator] _getBaseWeeklyPaymentFromSchedule: first=', first);
        console.log('[PaymentCalculator] _getBaseWeeklyPaymentFromSchedule: payment=', payment, 'setup=', setup, 'result=', result);

        return result;
    }

    handleFirstDraftDateChange(event) {
        this.firstDraftDate = event.target.value;
        this.performCalculations();
    }

    handlePreferredDayChange(event) {
        this.preferredDayOfWeek = event.target.value;
        this.performCalculations();
    }

    // Desired payment handlers
    handleDesiredPaymentInput(event) {
        const raw = event.detail?.value ?? event.target.value;
        const val = Number(raw);
        if (Number.isNaN(val)) return;
        // Always update local amount so UI responds immediately
        this.targetPaymentAmount = val;

        // Keep percent display in sync when computable
        this._syncPercentFromAmount(val);

        // Do not block live updates while typing
        event.target.setCustomValidity('');
        event.target.reportValidity();

        // Debounced calc while typing
        this.debouncedRecalc(250);
    }

    handleDesiredPaymentChange(event) {
        const raw = event.detail?.value ?? event.target.value;
        let val = Number(raw);
        if (Number.isNaN(val)) return;

        let weeklyEquivalent = this._toWeekly(val);
        const minWeekly = this._minimumWeeklyTarget();
        const maxWeekly = this._maximumWeeklyTarget();
        const weeklyTolerance = 0.01;

        // Set validation messages but don't auto-correct the value
        if (weeklyEquivalent < minWeekly - weeklyTolerance) {
            const minDisplay = this.formatCurrency(this._toDisplay(minWeekly));
            event.target.setCustomValidity(`Desired payment must be at least ${minDisplay}.`);
            event.target.reportValidity();
        } else if (maxWeekly != null && weeklyEquivalent > maxWeekly + weeklyTolerance) {
            const maxDisplay = this.formatCurrency(this._toDisplay(maxWeekly));
            event.target.setCustomValidity(`Desired payment must be at or below ${maxDisplay}.`);
            event.target.reportValidity();
        } else {
            event.target.setCustomValidity('');
            event.target.reportValidity();
        }

        // Always update the value and perform calculations
        this.targetPaymentAmount = val;
        this._syncPercentFromAmount(val);

        if (this.recalcTimer) {
            clearTimeout(this.recalcTimer);
            this.recalcTimer = null;
        }
        this.performCalculations();
    }

    // Debounce helper to avoid spamming Apex while dragging
    recalcTimer;
    debouncedRecalc(delay = 200) {
        if (this.recalcTimer) {
            clearTimeout(this.recalcTimer);
        }
        this.recalcTimer = setTimeout(() => {
            this.performCalculations();
        }, delay);
    }

    // Compute local target amount based on percent of CURRENT weekly payment
    // Applies rounding to match CalculationService behavior
    computeTargetPaymentAmountLocal() {
        if (this.calculateBy !== 'PERCENT') {
            return this._roundToCents(this.targetPaymentAmount || 0);
        }
        const weeklyFromCurrent = (this.currentPayment || 0) * (this.targetPaymentPercent / 100);
        const boundedWeekly = Math.max(this._minimumWeeklyTarget(), weeklyFromCurrent);
        // Round to cents like Apex setScale(2, HALF_UP)
        const roundedWeekly = this._roundToCents(boundedWeekly);
        // If UI is in monthly mode, show the equivalent monthly amount
        return this.paymentFrequency === 'WEEKLY' ? roundedWeekly : this._roundToCents(roundedWeekly * this._weeklyToMonthlyFactor);
    }

    // Display weekly target (user's input) for instant updates while dragging
    // Applies rounding to match CalculationService behavior
    get displayWeeklyTarget() {
        const amount = this.calculateBy === 'PERCENT' ? this.computeTargetPaymentAmountLocal() : (this.targetPaymentAmount || 0);
        // Always convert to weekly for the summary "New Weekly Payment"
        const weekly = this.paymentFrequency === 'WEEKLY' ? amount : (amount / this._weeklyToMonthlyFactor);
        return this._roundToCents(weekly);
    }

    // Local calculation of draft payment amount (target + banking fee)
    // This is what the user actually pays per draft, matching CalculationService
    get localDraftPayment() {
        const target = this.displayWeeklyTarget;
        const bFee = this.bankingFee || 0;
        // Draft payment = target payment (includes net + program portion) + banking fee
        // Note: Setup fee is added on top during schedule generation, not here
        return this._roundToCents(target + bFee);
    }

    // Value to show in Summary Stats: prefer Apex calculation, fallback to local estimate
    // Shows the actual draft payment amount (target + banking fee)
    get summaryWeeklyPayment() {
        // Use Apex result if available (from paymentSchedule first item)
        if (this.paymentSchedule && this.paymentSchedule.length > 0) {
            const firstItem = this.paymentSchedule[0];
            const payment = firstItem.paymentAmount || firstItem.totalPayment || firstItem.draftAmount;
            if (payment && !Number.isNaN(payment) && payment > 0) {
                return this._roundToCents(payment);
            }
        }
        // Fallback to calculations object
        const calc = this.calculations?.weeklyPayment;
        if (calc && !Number.isNaN(calc) && calc > 0) {
            // weeklyPayment from calc is the target; add banking fee for draft amount
            return this._roundToCents(calc + (this.bankingFee || 0));
        }
        // Final fallback to local calculation
        return this.localDraftPayment;
    }

    // Local estimate for Duration (number of weeks) during slider dragging
    // Uses Math.ceil() to match CalculationService behavior
    get localEstimatedWeeks() {
        const targetPayment = this.displayWeeklyTarget;
        if (!targetPayment || targetPayment <= 0) return 0;

        // Net per week is what goes to settlement/program (target - nothing, since target IS the net)
        // Actually, in CalculationService: netPerWeek = weeklyPayment - bankingFee
        // But weeklyPayment IS the target, so netPerWeek = target
        const netPerWeek = targetPayment;
        if (netPerWeek <= 0) return 0;

        // Calculate total program cost (settlement + program fee)
        const debt = this.totalDebt || 0;
        const settlementPct = this.settlementPercent || 50;
        const programFeePct = this.noFeeProgram ? 0 : (this.programFeePercent || 25);

        const settlementAmount = debt * (settlementPct / 100);
        const programFee = settlementAmount * (programFeePct / 100);
        const totalProgramCost = settlementAmount + programFee;

        if (totalProgramCost <= 0) return 0;

        // Use Math.ceil() like CalculationService
        const weeks = Math.ceil(totalProgramCost / netPerWeek);

        // Apply min/max bounds from config
        const minWeeks = this._minProgramWeeks || 1;
        const maxWeeks = this._maxProgramWeeks || 204;
        return Math.max(minWeeks, Math.min(maxWeeks, weeks));
    }

    // Program length for summary stats - prefer Apex result, fallback to local estimate
    get summaryProgramLength() {
        const calc = this.calculations?.programLength;
        if (calc && !Number.isNaN(calc) && calc > 0) return calc;
        return this.localEstimatedWeeks;
    }

    // Mode helpers
    get isPercentMode() { return this.calculateBy === 'PERCENT'; }
    get isDesiredMode() { return this.calculateBy === 'DESIRED'; }

    get percentMin() {
        return this.programType === 'DCG_DEBT'
            ? this._minTargetPercentDcgDebt
            : this._minTargetPercentDcgMod;
    }

    get percentMax() {
        return this._maxTargetPercent;
    }

    get percentLabels() {
        const min = this.percentMin;
        const max = this.percentMax;
        const steps = 4;
        const increment = (max - min) / steps;
        return Array.from({ length: steps + 1 }, (_, idx) => {
            const value = min + increment * idx;
            return Math.round(value);
        });
    }

    // Desired Payment constraints based on current weekly payment (40% - 80%)
    // Always show weekly amounts regardless of paymentFrequency
    get desiredMin() {
        return this._minimumWeeklyTarget();
    }
    get desiredMax() {
        return this._maximumWeeklyTarget();
    }
    get desiredMinLabel() {
        const min = this.desiredMin;
        return min === undefined ? 'N/A' : this.formatCurrency(min);
    }
    get desiredMaxLabel() {
        const max = this.desiredMax;
        return max === undefined ? 'N/A' : this.formatCurrency(max);
    }

    // Percent from desired payment vs current weekly payment
    get desiredPercent() {
        const pct = this._desiredPercentFrom(this.targetPaymentAmount || 0);
        return pct == null ? 0 : pct;
    }

    get hasCurrentPayment() {
        return (this.currentPayment ?? 0) > 0;
    }

    _desiredPercentFrom(amount) {
        const weekly = this.paymentFrequency === 'WEEKLY' ? amount : amount / this._weeklyToMonthlyFactor;
        const current = this.currentPayment || 0;
        if (!current) return null;
        return (weekly / current) * 100;
    }

    async handleSaveDraft() {
        try {
            this.isLoading = true;
            const config = {
                programType: this.programType,
                paymentFrequency: this.paymentFrequency,
                calculateBy: this.calculateBy,
                targetPaymentPercent: this.targetPaymentPercent,
                targetPaymentAmount: this.targetPaymentAmount,
                setupFeePayments: this.setupFeePayments,
                setupFeeTotal: this.setupFeeTotal,
                noFeeProgram: this.noFeeProgram,
                settlementPercent: this.settlementPercent,
                programFeePercent: this.programFeePercent,
                bankingFee: this.bankingFee,
                firstDraftDate: this.firstDraftDate,
                preferredDayOfWeek: this.preferredDayOfWeek,
                selectedProductCodes: this.selectedProductCodes
            };

            // Use schedule-derived value for consistency with payment table display
            // Schedule is front-loaded; use the first payment as the displayed base
            let baseWeeklyPayment = 0;
            if (this.paymentSchedule && this.paymentSchedule.length > 0) {
                const first = this.paymentSchedule[0] || {};
                const payment = first.paymentAmount ?? first.totalPayment ?? first.draftAmount ?? 0;
                const setup = first.setupFee ?? first.setupFeePortion ?? 0;
                baseWeeklyPayment = Math.max(0, payment - setup);
            } else {
                baseWeeklyPayment = this.calculations?.weeklyPayment || 0;
            }
            const weeklySavings = (this.currentPayment || 0) - baseWeeklyPayment;
            const percentSavings = this.currentPayment > 0
                ? (weeklySavings / this.currentPayment) * 100
                : 0;

            const newId = await saveDraftV2({
                recordId: this.recordId,
                draftName: `Draft ${new Date().toLocaleString()}`,
                config: config,
                draftIdToOverwrite: null,
                calculationsOptional: {
                    ...this.calculations,
                    paymentSchedule: this.paymentSchedule,
                    // Use backend's enforced weeklyPayment (includes minimum enforcement)
                    weeklyPayment: baseWeeklyPayment,
                    // Summary values that match UI display
                    totalDebt: this.totalDebt,
                    currentPayment: this.currentPayment,
                    newWeeklyPayment: baseWeeklyPayment,
                    weeklySavings: weeklySavings,
                    percentSavings: percentSavings,
                    firstDraftDate: this.firstDraftDate
                }
            });

            this.showToast('Success', 'Draft saved successfully', 'success', false);
            this.selectedDraftId = newId;
            await this.loadSavedDrafts();
            // Try to set current selection to the newly created draft's row
            const createdRow = (this.drafts || []).find(d => d.Id === newId);
            if (createdRow) {
                this.applyDraft(createdRow);
            }
        } catch (error) {
            this.showToast('Error', 'Failed to save draft', 'error', false);
        } finally {
            this.isLoading = false;
        }
    }

    async handleUpdateDraft() {
        if (!this.selectedDraftId) {
            this.showToast('Info', 'No draft loaded to update', 'info', false);
            return;
        }
        try {
            this.isLoading = true;
            const config = {
                programType: this.programType,
                paymentFrequency: this.paymentFrequency,
                calculateBy: this.calculateBy,
                targetPaymentPercent: this.targetPaymentPercent,
                targetPaymentAmount: this.targetPaymentAmount,
                setupFeePayments: this.setupFeePayments,
                setupFeeTotal: this.setupFeeTotal,
                noFeeProgram: this.noFeeProgram,
                settlementPercent: this.settlementPercent,
                programFeePercent: this.programFeePercent,
                bankingFee: this.bankingFee,
                firstDraftDate: this.firstDraftDate,
                preferredDayOfWeek: this.preferredDayOfWeek,
                selectedProductCodes: this.selectedProductCodes
            };

            // Use schedule-derived value for consistency with payment table display
            // Schedule is front-loaded; use the first payment as the displayed base
            let baseWeeklyPayment = 0;
            if (this.paymentSchedule && this.paymentSchedule.length > 0) {
                const first = this.paymentSchedule[0] || {};
                const payment = first.paymentAmount ?? first.totalPayment ?? first.draftAmount ?? 0;
                const setup = first.setupFee ?? first.setupFeePortion ?? 0;
                baseWeeklyPayment = Math.max(0, payment - setup);
            } else {
                baseWeeklyPayment = this.calculations?.weeklyPayment || 0;
            }
            const weeklySavings = (this.currentPayment || 0) - baseWeeklyPayment;
            const percentSavings = this.currentPayment > 0
                ? (weeklySavings / this.currentPayment) * 100
                : 0;

            const updatedId = await saveDraftV2({
                recordId: this.recordId,
                draftName: `Updated ${new Date().toLocaleString()}`,
                config: config,
                draftIdToOverwrite: this.selectedDraftId,
                calculationsOptional: {
                    ...this.calculations,
                    paymentSchedule: this.paymentSchedule,
                    // Use backend's enforced weeklyPayment (includes minimum enforcement)
                    weeklyPayment: baseWeeklyPayment,
                    // Summary values that match UI display
                    totalDebt: this.totalDebt,
                    currentPayment: this.currentPayment,
                    newWeeklyPayment: baseWeeklyPayment,
                    weeklySavings: weeklySavings,
                    percentSavings: percentSavings,
                    firstDraftDate: this.firstDraftDate
                }
            });

            this.showToast('Success', 'Draft updated', 'success', false);
            this.selectedDraftId = updatedId || this.selectedDraftId;
            await this.loadSavedDrafts();
        } catch (e) {
            this.showToast('Error', e?.body?.message || 'Failed to update draft', 'error', false);
        } finally {
            this.isLoading = false;
        }
    }

    // Drafts table actions
    async handleDraftRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        switch (action) {
            case 'load':
                this.selectedDraftId = row.Id;
                this.applyDraft(row);
                break;
            case 'set_primary':
                await this.handleSetPrimaryDraft(row.Id);
                break;
            case 'delete':
                await this.handleDeleteDraft(row.Id);
                break;
            default:
                break;
        }
    }

    async handleSetPrimaryDraft(draftId) {
        try {
            this.isLoading = true;
            await setPrimaryDraft({ draftId });
            this.showToast('Success', 'Primary draft updated', 'success', false);
            await this.loadSavedDrafts();
            // Select and apply the newly set primary as the loaded draft
            this.selectedDraftId = draftId;
            const row = (this.drafts || []).find(d => d.Id === draftId);
            if (row) {
                this.applyDraft(row);
            }
        } catch (e) {
            this.showToast('Error', e?.body?.message || 'Failed to set primary', 'error', false);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDeleteDraft(draftId) {
        try {
            this.isLoading = true;
            await deactivateDraft({ draftId });
            this.showToast('Success', 'Draft deactivated', 'success', false);
            if (this.selectedDraftId === draftId) this.selectedDraftId = null;
            await this.loadSavedDrafts();
            // If primary was deactivated, Apex may auto-promote; refresh list to reflect
        } catch (e) {
            this.showToast('Error', e?.body?.message || 'Failed to deactivate draft', 'error', false);
        } finally {
            this.isLoading = false;
        }
    }

    // Disable update button unless a draft is loaded
    get isUpdateDisabled() {
        return this.isLoading || !this.selectedDraftId;
    }

    get selectedDraftRows() {
        return this.selectedDraftId ? [this.selectedDraftId] : [];
    }

    showToast(title, message, variant, isSticky = false) {
        const event = new ShowToastEvent({
            title,
            message,
            variant,
            mode: isSticky ? 'sticky' : 'dismissable'
        });
        this.dispatchEvent(event);
    }

    // Getters for split percentages display
    get programSplitPercentage() {
        return Math.round(this.programSplitRatio * 100);
    }

    get escrowSplitPercentage() {
        return Math.round(this.escrowSplitRatio * 100);
    }

    // Getters for day of week options
    get dayOfWeekOptions() {
        return [
            { label: 'Monday', value: '1' },
            { label: 'Tuesday', value: '2' },
            { label: 'Wednesday', value: '3' },
            { label: 'Thursday', value: '4' },
            { label: 'Friday', value: '5' }
        ];
    }

    get dcgModClass() {
        const className = this.programType === 'DCG_MOD' ? 'selection-card selected' : 'selection-card';
        return className;
    }

    get dcgDebtClass() {
        const className = this.programType === 'DCG_DEBT' ? 'selection-card selected' : 'selection-card';
        return className;
    }

    get dcgModCheckClass() {
        return this.programType === 'DCG_MOD' ? 'check-circle checked' : 'check-circle';
    }

    get dcgDebtCheckClass() {
        return this.programType === 'DCG_DEBT' ? 'check-circle checked' : 'check-circle';
    }

    get dcgModCaClass() {
        return this.programType === 'DCG_MOD_CA' ? 'selection-card selected' : 'selection-card';
    }

    get dcgModCaCheckClass() {
        return this.programType === 'DCG_MOD_CA' ? 'check-circle checked' : 'check-circle';
    }

    get weeklyClass() {
        return this.paymentFrequency === 'WEEKLY' ? 'selection-card selected' : 'selection-card';
    }

    get monthlyClass() {
        return this.paymentFrequency === 'MONTHLY' ? 'selection-card selected' : 'selection-card';
    }

    get weeklyCheckClass() {
        return this.paymentFrequency === 'WEEKLY' ? 'check-circle checked' : 'check-circle';
    }

    get monthlyCheckClass() {
        return this.paymentFrequency === 'MONTHLY' ? 'check-circle checked' : 'check-circle';
    }

    get percentButtonClass() {
        return this.calculateBy === 'PERCENT' ? 'toggle-button active' : 'toggle-button';
    }

    get desiredButtonClass() {
        return this.calculateBy === 'DESIRED' ? 'toggle-button active' : 'toggle-button';
    }

    get noFeeDisabled() {
        // Allow No-Fee Program for both DCG Debt and DCG Mod
        return this.programType !== 'DCG_DEBT' && this.programType !== 'DCG_MOD';
    }

    // Show No-Fee Program toggle only for DCG Mod
    get showNoFeeProgram() {
        return this.programType === 'DCG_MOD';
    }

    // Additional Products helpers
    get hasAvailableProducts() {
        return Array.isArray(this.availableProducts) && this.availableProducts.length > 0;
    }

    get selectedProductCodes() {
        return (this.availableProducts || []).filter(p => p.selected).map(p => p.code);
    }

    get additionalProductsWeeklyTotal() {
        return (this.availableProducts || []).reduce((sum, p) => sum + (p.selected ? Number(p.weeklyFee || 0) : 0), 0);
    }

    get formattedAdditionalProductsWeeklyTotal() {
        return this.formatCurrency(this.additionalProductsWeeklyTotal);
    }

    handleToggleAdditionalProduct(event) {
        const code = event.target?.dataset?.code;
        if (!code) return;
        const checked = !!event.target.checked;
        this.availableProducts = this.decorateProducts((this.availableProducts || []).map(p => p.code === code ? { ...p, selected: checked } : p));
        this.performCalculations();
    }

    handleProductCardClick(event) {
        const code = event.currentTarget?.dataset?.code;
        if (!code) return;
        const next = (this.availableProducts || []).map(p => p.code === code ? { ...p, selected: !p.selected } : p);
        this.availableProducts = this.decorateProducts(next);
        this.performCalculations();
    }

    // Getters for Display Values
    get targetPaymentDisplay() {
        // Use the exact same calculation as summaryStats.js computedNewWeeklyPayment:
        // First payment amount from schedule minus setup fee
        // Always display weekly amounts
        let displayAmount = 0;

        if (this.paymentSchedule && this.paymentSchedule.length > 0) {
            const first = this.paymentSchedule[0] || {};
            const payment = first.paymentAmount ?? first.totalPayment ?? first.draftAmount ?? 0;
            const setup = first.setupFee ?? first.setupFeePortion ?? 0;
            displayAmount = Math.max(0, payment - setup);
        } else {
            // Fallback when schedule is not yet available
            displayAmount = this.targetPaymentAmount || 0;
        }

        const amount = this.formatCurrency(displayAmount);
        const pct = this.isDesiredMode ? (this.desiredPercent || 0) : (this.targetPaymentPercent || 0);
        const pctText = Number(pct).toFixed(1);
        return `${pctText}% → ${amount}/week`;
    }

    get setupFeePerPayment() {
        return (this.setupFeeTotal / this.setupFeePayments).toFixed(2);
    }

    get programLength() {
        const length = this.calculations.programLength || 0;
        return `${length} weeks`;
    }

    get formattedWeeklyPayment() {
        return this.formatCurrency(this.calculations.weeklyPayment);
    }

    get formattedSavings() {
        return this.formatCurrency(this.calculations.savingsAmount);
    }

    get formattedTotalDebt() {
        return this.formatCurrency(this.totalDebt);
    }

    get formattedSettlement() {
        return this.formatCurrency(this.calculations.settlementAmount);
    }

    get formattedProgramFee() {
        return this.formatCurrency(this.calculations.programFeeAmount);
    }

    get formattedTotalCost() {
        return this.formatCurrency(this.calculations.totalProgramCost);
    }

    get formattedSetupFeeTotal() {
        return this.formatCurrency(this.setupFeeTotal);
    }

    get formattedBankingFeeTotal() {
        return this.formatCurrency(this.calculations.bankingFeeTotal);
    }

    formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2
        }).format(value || 0);
    }

    // Setup fee slider range getters (for HTML template)
    get setupFeeMinPayments() {
        return this._setupFeeMinPayments;
    }

    get setupFeeMaxPayments() {
        return this._setupFeeMaxPayments;
    }

    // Generate slider numbers based on config range
    _generateSliderNumbers() {
        const min = this._setupFeeMinPayments || 1;
        const max = this._setupFeeMaxPayments || 10;
        const numbers = [];
        for (let i = min; i <= max; i++) {
            numbers.push(i);
        }
        return numbers;
    }

    hideOutOfSyncChevronsOnDrafts() {
        const table = this.template.querySelector('lightning-datatable');
        if (!table) return;

        // Find the <tr> rows that have our rowClass
        const rows = this.template.querySelectorAll('tr.row-outofsync');
        rows.forEach(row => {
            // Locate action cell (last column)
            const actionCell = row.querySelector('td:last-child');

            if (actionCell) {
                // Hide the overflow button
                const actionButton = actionCell.querySelector('button.slds-button_icon');
                if (actionButton) {
                    actionButton.style.display = 'none';
                    actionButton.setAttribute('disabled', 'true');
                }

                // Remove clickable area
                actionCell.style.pointerEvents = 'none';
            }
        });
    }

    subscribeToEvent() {
        const messageCallback = async (response) => {
            try {
                const payload = response?.data?.payload;
                const eventOppId = payload?.OpportunityId__c;
                const isInvalid = payload?.Payment_Draft_Invalidated__c;

                if (eventOppId === this.recordId && isInvalid === true) {

                    this.isLoading = true;
                    await this.loadSavedDrafts();

                    this.showToast(
                        'Drafts Updated',
                        'Drafts list updated due to Opportunity changes. Additionally at least one Payment Draft was invalidated due to this change.',
                        'warning',
                        true
                    );
                }

            } catch (e) {
                this.showToast('Error', 'Platform event handling failed', 'error', false);
                this.isLoading = false;
            } finally {
                this.isLoading = false;
            }
        };

        subscribe(this.channelName, -1, messageCallback)
            .then(resp => this.subscription = resp)
            .catch(e => console.error('Subscription failed', e));
    }

    registerErrorListener() {
        onError(error => {
            console.error('EMP API Error: ', JSON.stringify(error));
        });
    }
}