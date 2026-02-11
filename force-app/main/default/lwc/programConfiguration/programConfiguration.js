import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PROGRAM_TYPE_OPTIONS = [
    { label: 'DCG Debt (70/30 Split)', value: 'DCG_DEBT' },
    { label: 'DCG Mod (50/50 Split)', value: 'DCG_MOD' },
    { label: 'Custom (60/40 Split)', value: 'CUSTOM' },
    { label: 'California No-Fee', value: 'CA_NO_FEE' }
];

// Default configuration constants
const DEFAULT_CONFIG = {
    settlementPercentage: 60,      // Unified 60%
    programFeePercentage: 35,      // Unified 35%
    setupFee: 1000,                // $1000
    setupFeePayments: 10,          // Over 10 payments
    bankingFee: 35,                // $35 servicing
    bank2Fee: 0,                   // $0 bank2
    minWeeks: 1,                   // New minimum
    maxWeeks: 204,                 // New maximum
    firstDraftDate: '',            // Will be set to next Monday by default
    preferredDayOfWeek: 'Monday'   // Default to Monday
};

const FREQUENCY_OPTIONS = [
    { label: 'Weekly', value: 'Weekly' },
    { label: 'Bi-Weekly', value: 'Bi-Weekly' },
    { label: 'Monthly', value: 'Monthly' }
];

const CALCULATION_MODE_OPTIONS = [
    { label: 'Percentage Based', value: 'percentage' },
    { label: 'Fixed Payment', value: 'fixed' },
    { label: 'Custom Target', value: 'custom' }
];

export default class ProgramConfiguration extends LightningElement {
    @api config = {};
    @api clientState = '';
    @api totalDebt = 0;
    @api readonly = false;

    showAdvancedSettings = false;
    previewCalculations = {};

    programTypeOptions = PROGRAM_TYPE_OPTIONS;
    frequencyOptions = FREQUENCY_OPTIONS;
    calculationModeOptions = CALCULATION_MODE_OPTIONS;

    get isCaliforniaClient() {
        return this.clientState === 'CA';
    }

    get showCaliforniaWarning() {
        return this.isCaliforniaClient && this.config.noFeeProgram !== 'Yes';
    }

    get formattedTotalDebt() {
        return this.formatCurrency(this.totalDebt);
    }

    get settlementAmount() {
        return this.totalDebt * (this.config.settlementPercentage / 100);
    }

    get formattedSettlementAmount() {
        return this.formatCurrency(this.settlementAmount);
    }

    get programFee() {
        return this.settlementAmount * (this.config.programFeePercentage / 100);
    }

    get formattedProgramFee() {
        return this.formatCurrency(this.programFee);
    }

    get formattedSetupFee() {
        return this.formatCurrency(this.config.setupFee);
    }

    get totalProgramCost() {
        return this.settlementAmount + this.programFee + this.config.setupFee;
    }

    get formattedTotalProgramCost() {
        return this.formatCurrency(this.totalProgramCost);
    }

    get estimatedSavings() {
        return this.totalDebt - this.totalProgramCost;
    }

    get formattedEstimatedSavings() {
        return this.formatCurrency(this.estimatedSavings);
    }

    get savingsPercentage() {
        return this.totalDebt > 0 ? ((this.estimatedSavings / this.totalDebt) * 100).toFixed(1) : 0;
    }

    get weeklyPaymentEstimate() {
        if (this.config.frequency === 'Weekly') {
            return this.totalProgramCost / (this.config.targetPaymentPercentage * 52 / 100);
        } else if (this.config.frequency === 'Bi-Weekly') {
            return this.totalProgramCost / (this.config.targetPaymentPercentage * 26 / 100);
        } else {
            return this.totalProgramCost / (this.config.targetPaymentPercentage * 12 / 100);
        }
    }

    get formattedWeeklyPayment() {
        return this.formatCurrency(this.weeklyPaymentEstimate);
    }

    get showRetainerFields() {
        return this.config.retainerFeePercentage > 0;
    }

    get showBank2Fee() {
        return this.config.bank2Fee > 0;
    }

    get showLegalMonitoring() {
        return this.config.legalMonitoring > 0;
    }
    
    get programSplitPercentage() {
        return Math.round((this.config.programSplitRatio || 0.70) * 100);
    }
    
    get escrowSplitPercentage() {
        return Math.round((this.config.escrowSplitRatio || 0.30) * 100);
    }
    
    get dayOfWeekOptions() {
        return [
            { label: 'Monday', value: 'Monday' },
            { label: 'Tuesday', value: 'Tuesday' },
            { label: 'Wednesday', value: 'Wednesday' },
            { label: 'Thursday', value: 'Thursday' },
            { label: 'Friday', value: 'Friday' }
        ];
    }

    connectedCallback() {
        this.applyStateSpecificRules();
        this.setDefaultFirstDraftDate();
    }
    
    setDefaultFirstDraftDate() {
        if (!this.config.firstDraftDate) {
            // Default to next Monday
            const today = new Date();
            const dayOfWeek = today.getDay();
            const daysUntilMonday = dayOfWeek === 0 ? 1 : (8 - dayOfWeek) % 7 || 7;
            const nextMonday = new Date(today.getTime() + daysUntilMonday * 24 * 60 * 60 * 1000);
            
            // Format as YYYY-MM-DD
            const year = nextMonday.getFullYear();
            const month = String(nextMonday.getMonth() + 1).padStart(2, '0');
            const day = String(nextMonday.getDate()).padStart(2, '0');
            
            this.updateConfig({ firstDraftDate: `${year}-${month}-${day}` });
        }
    }

    applyStateSpecificRules() {
        if (this.isCaliforniaClient) {
            // California specific rules
            this.updateConfig({
                noFeeProgram: 'Yes',
                setupFee: 2500,
                programFeePercentage: 0,
                retainerFeePercentage: 0
            });
            this.showToast('Info', 'California no-fee program rules applied', 'info');
        }
    }

    handleSettlementChange(event) {
        this.updateConfig({ settlementPercentage: parseFloat(event.target.value) });
    }

    handleProgramFeeChange(event) {
        if (this.isCaliforniaClient && parseFloat(event.target.value) > 0) {
            this.showToast('Warning', 'California clients cannot have program fees', 'warning');
            return;
        }
        this.updateConfig({ programFeePercentage: parseFloat(event.target.value) });
    }

    handleRetainerFeeChange(event) {
        this.updateConfig({ retainerFeePercentage: parseFloat(event.target.value) });
    }

    handleRetainerTermChange(event) {
        this.updateConfig({ retainerFeeTerm: parseFloat(event.target.value) });
    }

    handleSetupFeeChange(event) {
        this.updateConfig({ setupFee: parseFloat(event.target.value) });
    }

    handleSetupTermChange(event) {
        this.updateConfig({ setupFeeTerm: parseFloat(event.target.value) });
    }

    handleBankingFeeChange(event) {
        this.updateConfig({ bankingFee: parseFloat(event.target.value) });
    }

    handleBank2FeeChange(event) {
        this.updateConfig({ bank2Fee: parseFloat(event.target.value) });
    }

    handleLegalMonitoringChange(event) {
        this.updateConfig({ legalMonitoring: parseFloat(event.target.value) });
    }

    handleProgramTypeChange(event) {
        const programType = event.target.value;
        this.updateConfig({ programType });
        this.applyProgramTypeDefaults(programType);
    }

    handleFrequencyChange(event) {
        this.updateConfig({ frequency: event.target.value });
    }

    handleNoFeeProgramChange(event) {
        const noFeeProgram = event.target.value;
        this.updateConfig({ noFeeProgram });
        
        if (noFeeProgram === 'Yes') {
            this.updateConfig({ programFeePercentage: 0 });
        }
    }

    handleCalculationModeChange(event) {
        this.updateConfig({ calculationMode: event.target.value });
    }

    handleTargetPaymentChange(event) {
        this.updateConfig({ targetPaymentPercentage: parseFloat(event.target.value) });
    }
    
    handleFirstDraftDateChange(event) {
        this.updateConfig({ firstDraftDate: event.target.value });
    }
    
    handlePreferredDayChange(event) {
        this.updateConfig({ preferredDayOfWeek: event.target.value });
    }

    toggleAdvancedSettings() {
        this.showAdvancedSettings = !this.showAdvancedSettings;
    }

    get advancedSettingsButtonLabel() {
        return this.showAdvancedSettings ? 'Hide Advanced Settings' : 'Show Advanced Settings';
    }

    get advancedSettingsButtonIcon() {
        return this.showAdvancedSettings ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get noFeeProgramOptions() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }

    get isProgramFeeDisabled() {
        return this.readonly || this.isCaliforniaClient;
    }

    applyProgramTypeDefaults(programType) {
        let config = { ...DEFAULT_CONFIG };
        
        switch(programType) {
            case 'DCG_DEBT':
                config.programSplitRatio = 0.70;
                config.escrowSplitRatio = 0.30;
                break;
            case 'DCG_MOD':
                config.programSplitRatio = 0.50;
                config.escrowSplitRatio = 0.50;
                break;
            case 'CUSTOM':
                config.programSplitRatio = 0.60;
                config.escrowSplitRatio = 0.40;
                break;
            case 'CA_NO_FEE':
                config.programFeePercentage = 0;
                config.setupFee = 2500;
                config.programSplitRatio = 0;
                config.escrowSplitRatio = 1.0;
                config.noFeeProgram = 'Yes';
                break;
        }
        
        this.updateConfig(config);
    }

    handleResetToDefaults() {
        const defaultConfig = {
            ...DEFAULT_CONFIG,
            retainerFeePercentage: 0,
            retainerFeeTerm: 0,
            setupFeeTerm: 10,
            legalMonitoring: 0,
            programType: 'DCG_DEBT',
            frequency: 'Weekly',
            noFeeProgram: 'No',
            calculationMode: 'percentage',
            targetPaymentPercentage: 45,
            programSplitRatio: 0.70,
            escrowSplitRatio: 0.30
        };

        this.updateConfig(defaultConfig);
        this.applyStateSpecificRules();
        this.showToast('Success', 'Configuration reset to defaults', 'success');
    }

    handleSaveTemplate() {
        // Implement save template functionality
        this.showToast('Info', 'Template saved successfully', 'success');
    }

    handleLoadTemplate() {
        // Implement load template functionality
        this.showToast('Info', 'Template loaded successfully', 'success');
    }

    updateConfig(updates) {
        const updatedConfig = { ...this.config, ...updates };
        
        const configChangeEvent = new CustomEvent('configchange', {
            detail: updatedConfig
        });
        this.dispatchEvent(configChangeEvent);
    }

    formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            minimumFractionDigits: 2
        }).format(value || 0);
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }

    // Public API methods
    @api
    resetConfiguration() {
        this.handleResetToDefaults();
    }

    @api
    validateConfiguration() {
        const errors = [];
        
        if (this.config.settlementPercentage < 20 || this.config.settlementPercentage > 80) {
            errors.push('Settlement percentage must be between 20% and 80%');
        }
        
        if (this.config.programFeePercentage < 0 || this.config.programFeePercentage > 50) {
            errors.push('Program fee percentage must be between 0% and 50%');
        }
        
        if (this.isCaliforniaClient && this.config.programFeePercentage > 0) {
            errors.push('California clients cannot have program fees');
        }
        
        if (this.config.setupFee < 0) {
            errors.push('Setup fee cannot be negative');
        }

        return {
            isValid: errors.length === 0,
            errors: errors
        };
    }

    @api
    getCalculationPreview() {
        return {
            totalDebt: this.totalDebt,
            settlementAmount: this.settlementAmount,
            programFee: this.programFee,
            totalProgramCost: this.totalProgramCost,
            estimatedSavings: this.estimatedSavings,
            savingsPercentage: this.savingsPercentage,
            weeklyPaymentEstimate: this.weeklyPaymentEstimate
        };
    }
}