import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import calculatePaymentPlan from '@salesforce/apex/PaymentCalculatorController.calculatePaymentPlan';
import updateOpportunityOnly from '@salesforce/apex/PaymentPlanEditorController.updateOpportunityOnly';
import getRequiredConfig from '@salesforce/apex/PaymentCalcConfigSvc.getRequiredConfig';
import getRequiredConfigForProgram from '@salesforce/apex/PaymentCalcConfigSvc.getRequiredConfigForProgram';
import OPP_EST_CURRENT_PAYMENT_FIELD from '@salesforce/schema/Opportunity.Estimated_Current_Payment__c';
import OPP_EST_TOTAL_DEBT_FIELD from '@salesforce/schema/Opportunity.Estimated_Total_Debt__c';
import OPP_ACCOUNT_STATE from '@salesforce/schema/Opportunity.Account.BillingState';
import OPP_SETUP_FEE_FIELD from '@salesforce/schema/Opportunity.Setup_Fee__c';


const OPP_FIELDS = [OPP_EST_CURRENT_PAYMENT_FIELD, OPP_EST_TOTAL_DEBT_FIELD, OPP_ACCOUNT_STATE, OPP_SETUP_FEE_FIELD];


export default class PaymentPlanEditorV2 extends LightningElement {
   @api recordId;
   @api objectApiName;


   isLoading = false;


   // Program Settings
   @track programType = 'DCG_MOD';
   paymentFrequency = 'WEEKLY';
   calculateBy = 'PERCENT';
   targetPaymentPercent = 59;
   targetPaymentAmount = 8255.00;
   setupFeePayments = 10;
   setupFeeTotal = 1000;
   noFeeProgram = false;


   // Payment Schedule Settings
   firstDraftDate = '';
   preferredDayOfWeek = '1';


   // Background Variables
   settlementPercent = 60;
   programFeePercent = 35;
   bankingFee = 35;
   bank2Fee = 0;
   programSplitRatio = 0.50;
   escrowSplitRatio = 0.50;


   // Config state
   configLoaded = false;
   configLoadError = null;


   // Config-loaded values
   _minWeeklyTargetPayment = null;
   _minWeeklyTargetPaymentDcgDebt = null;
   _weeklyToMonthlyFactor = null;
   _minTargetPercentDcgMod = null;
   _minTargetPercentDcgDebt = null;
   _maxTargetPercent = null;
   _defaultSetupFee = null;
   _noFeeSetupFee = null;
   _legalMonitoringWeeklyFee = null;
   _setupFeeMinPayments = null;
   _setupFeeMaxPayments = null;
   _minProgramWeeks = null;
   _maxProgramWeeks = null;


   // Number of weeks for manual entry
   _targetNumberOfWeeks = null;


   // Flag to track which field user is editing (prevents infinite loop)
   _isEditingWeeks = false;


   // Calculation Results
   totalDebt = 14000;
   currentPayment = 6300;
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
   _calcSeq = 0;


   // Slider numbers for setup fee
   @track sliderNumbers = [];


   connectedCallback() {
       this.setDefaultFirstDraftDate();
       this.loadConfig()
           .then(() => {
               this.sliderNumbers = this._generateSliderNumbers();
           })
           .catch((e) => {
               const errorMsg = e?.body?.message || e?.message || 'Unknown configuration error';
               console.error('[PaymentPlanEditorV2] CRITICAL: Failed to load configuration.', errorMsg);
               this.configLoadError = `Configuration Error: ${errorMsg}. Please contact your administrator.`;
               this.showToast('Configuration Error', this.configLoadError, 'error', false);
           });
   }


   hasBootstrapped = false;
   renderedCallback() {
       if (!this.hasBootstrapped && this.recordId && this.configLoaded && !this.configLoadError) {
           this.hasBootstrapped = true;
           this.bootstrapCalculator();
       }
   }


   get isConfigError() {
       return !!this.configLoadError;
   }


   async bootstrapCalculator() {
       try {
           this.isLoading = true;
           this.targetPaymentAmount = this.computeTargetPaymentAmountLocal();
           await this.performCalculations();
       } catch (e) {
           console.warn('[PaymentPlanEditorV2] bootstrapCalculator error', e?.body?.message || e?.message);
       } finally {
           this.isLoading = false;
       }
   }


   async loadConfig() {
       const cfg = await getRequiredConfig();


       this.settlementPercent = cfg.settlementPercent;
       this.programFeePercent = cfg.programFeePercent;
       this.bankingFee = cfg.bankingFee;
       this.bank2Fee = cfg.bank2Fee;
       this.programSplitRatio = cfg.programSplitRatio;
       this.escrowSplitRatio = cfg.escrowSplitRatio;


       this._minWeeklyTargetPayment = cfg.minWeeklyTargetPayment;
       this._minWeeklyTargetPaymentDcgDebt = cfg.minWeeklyTargetPaymentDcgDebt;
       this._weeklyToMonthlyFactor = cfg.weeklyToMonthlyFactor;
       this._minTargetPercentDcgMod = cfg.minTargetPercentDcgMod;
       this._minTargetPercentDcgDebt = cfg.minTargetPercentDcgDebt;
       this._maxTargetPercent = cfg.maxTargetPercent;
       this._defaultSetupFee = cfg.setupFee;
       this._noFeeSetupFee = cfg.noFeeSetupFee;
       this._legalMonitoringWeeklyFee = cfg.legalMonitoringWeeklyFee;
       this._setupFeeMinPayments = cfg.setupFeeMinPayments;
       this._setupFeeMaxPayments = cfg.setupFeeMaxPayments;
       this._minProgramWeeks = cfg.minProgramWeeks;
       this._maxProgramWeeks = cfg.maxProgramWeeks;


       this.setupFeeTotal = this._defaultSetupFee;


       this.configLoaded = true;
       this.configLoadError = null;
   }


   setDefaultFirstDraftDate() {
       const today = new Date();
       const dayOfWeek = today.getDay();
       const daysUntilMonday = dayOfWeek === 0 ? 1 : (8 - dayOfWeek) % 7 || 7;
       const nextMonday = new Date(today.getTime() + daysUntilMonday * 24 * 60 * 60 * 1000);


       const year = nextMonday.getFullYear();
       const month = String(nextMonday.getMonth() + 1).padStart(2, '0');
       const day = String(nextMonday.getDate()).padStart(2, '0');
       this.firstDraftDate = `${year}-${month}-${day}`;
   }


   @wire(getRecord, { recordId: '$recordId', fields: OPP_FIELDS })
   wiredRecord({ error, data }) {
       if (data) {
           this.totalDebt = getFieldValue(data, OPP_EST_TOTAL_DEBT_FIELD);
           this.currentPayment = getFieldValue(data, OPP_EST_CURRENT_PAYMENT_FIELD);
           // Read Setup Fee directly from Opportunity custom field
           const oppSetupFee = getFieldValue(data, OPP_SETUP_FEE_FIELD);
           if (oppSetupFee != null) {
               this.setupFeeTotal = oppSetupFee;
           }
           const state = getFieldValue(data, OPP_ACCOUNT_STATE);
           if (state === 'CA') {
               this.noFeeProgram = true;
               this.programFeePercent = 0;
               this.showToast('Info', 'California No-Fee Program automatically applied', 'info', false);
           }
       } else if (error) {
           console.error('[PaymentPlanEditorV2] Error loading record:', error);
       }
   }


   async performCalculations() {
       if (this.configLoadError) {
           return;
       }


       if (!this.recordId) {
           return;
       }


       this._enforcePaymentBounds();


       let seq;
       try {
           seq = ++this._calcSeq;
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
               additionalProductsWeeklyTotal: 0
           });


           if (result) {
               if (seq !== this._calcSeq) {
                   return;
               }


               const filteredResult = { ...result };
               delete filteredResult.programSplitPercentage;
               delete filteredResult.escrowSplitPercentage;


               this.settlementPercent = filteredResult.settlementPercentage;
               this.programFeePercent = filteredResult.programFeePercentage;
               if (typeof filteredResult.currentPayment !== 'undefined' && filteredResult.currentPayment !== null) {
                   this.currentPayment = filteredResult.currentPayment;
               }


               this.programSplitRatio = filteredResult.programSplitRatio;
               this.escrowSplitRatio = filteredResult.escrowSplitRatio;


               if (this.noFeeProgram) {
                   this.programFeePercent = 0;
                   this.programSplitRatio = 0;
                   this.escrowSplitRatio = 1.0;
               }


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


               if (filteredResult.paymentSchedule && filteredResult.paymentSchedule.length > 0) {
                   const convertedSchedule = this.convertScheduleForDisplay(filteredResult.paymentSchedule);
                   this.paymentSchedule = [...convertedSchedule];
               } else {
                   this.paymentSchedule = [];
               }


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
           if (this._calcSeq && typeof seq !== 'undefined' && seq !== this._calcSeq) {
               return;
           }
           console.error('[PaymentPlanEditorV2] ERROR calculating payment plan:', error);
           const errorMsg = error.body?.message || error.message || '';
           if (errorMsg.includes('PaymentCalcConfigException') || errorMsg.includes('Configuration') || errorMsg.includes('CMDT')) {
               this.configLoadError = `Configuration Error: ${errorMsg}. Please contact your administrator.`;
               this.configLoaded = false;
           }
           this.showToast('Error', 'Failed to calculate payment plan: ' + errorMsg, 'error', false);
           this.paymentSchedule = [];
       }
   }


   // Event Handlers
   // Note: Setup fee is read from Opportunity.Setup_Fee__c field, not changed by program type
   handleProgramTypeMod() {
       this.programType = 'DCG_MOD';
       this.programSplitRatio = 0.50;
       this.escrowSplitRatio = 0.50;
       this._enforcePaymentBounds();
       this.refreshConfigForProgram('DCG_MOD');
   }


   handleProgramTypeDebt() {
       this.programType = 'DCG_DEBT';
       if (this.noFeeProgram) {
           this.noFeeProgram = false;
       }
       this.programSplitRatio = 0.70;
       this.escrowSplitRatio = 0.30;
       this._enforcePaymentBounds();
       this.refreshConfigForProgram('DCG_DEBT');
   }


   handleProgramTypeModCa() {
       this.programType = 'DCG_MOD_CA';
       // DCG MOD CA is California variant - automatically enables No-Fee Program behavior
       // Use same ratios as DCG Mod
       this.programSplitRatio = 0.50;
       this.escrowSplitRatio = 0.50;
       // No-Fee Program is implicitly enabled for California variant
       this.noFeeProgram = true;
       this._enforcePaymentBounds();
       // Use DCG_MOD config as base for California variant
       this.refreshConfigForProgram('DCG_MOD');
   }


   async refreshConfigForProgram(programType) {
       try {
           const cfg = await getRequiredConfigForProgram({ programType });


           this.programSplitRatio = cfg.programSplitRatio;
           this.escrowSplitRatio = cfg.escrowSplitRatio;
           this.settlementPercent = cfg.settlementPercent;
           this.programFeePercent = cfg.programFeePercent;
           this.bankingFee = cfg.bankingFee;
           this.bank2Fee = cfg.bank2Fee;


           this.performCalculations();
       } catch (e) {
           const errorMsg = e?.body?.message || e?.message || 'Unknown configuration error';
           this.configLoadError = `Configuration Error: ${errorMsg}. Please contact your administrator.`;
           this.configLoaded = false;
           this.showToast('Configuration Error', this.configLoadError, 'error', false);
       }
   }


   handleCalculateByPercent() {
       this.calculateBy = 'PERCENT';
       this._enforcePaymentBounds();
       this.performCalculations();
   }


   handleCalculateByDesired() {
       this.calculateBy = 'DESIRED';
       this.targetPaymentAmount = this.targetPaymentAmount || this.computeTargetPaymentAmountLocal();
       this._syncPercentFromAmount(this.targetPaymentAmount);
       this._enforcePaymentBounds();
       this.performCalculations();
   }


   handleTargetPaymentInput(event) {
       const percent = this._setTargetPaymentPercent(parseInt(event.target.value, 10));
       event.target.value = percent;
       if (this.calculateBy === 'PERCENT') {
           const weeklyFromCurrent = (this.currentPayment || 0) * (percent / 100);
           const boundedWeekly = Math.max(this._minimumWeeklyTarget(), weeklyFromCurrent);
           this.targetPaymentAmount = this._toDisplay(boundedWeekly);
       }
       this.debouncedRecalc();
   }


   handleTargetPaymentChange(event) {
       const percent = this._setTargetPaymentPercent(parseInt(event.target.value, 10));
       event.target.value = percent;
       this._enforcePaymentBounds();
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
       // Setup fee is read from Opportunity.Setup_Fee__c, not changed here
       this.performCalculations();
   }


   handleFirstDraftDateChange(event) {
       this.firstDraftDate = event.target.value;
       this.performCalculations();
   }


   handlePreferredDayChange(event) {
       this.preferredDayOfWeek = event.target.value;
       this.performCalculations();
   }


   handleDesiredPaymentInput(event) {
       const raw = event.detail?.value ?? event.target.value;
       const val = Number(raw);
       if (Number.isNaN(val)) return;


       // User is editing payment, not weeks
       this._isEditingWeeks = false;


       this.targetPaymentAmount = val;
       this._syncPercentFromAmount(val);


       // Calculate and update Number of Weeks from payment
       const calculatedWeeks = this._calculateWeeksFromPayment(val);
       if (calculatedWeeks && calculatedWeeks > 0) {
           this._targetNumberOfWeeks = calculatedWeeks;
       }


       event.target.setCustomValidity('');
       event.target.reportValidity();
       this.debouncedRecalc(250);
   }


   handleDesiredPaymentChange(event) {
       const raw = event.detail?.value ?? event.target.value;
       let val = Number(raw);
       if (Number.isNaN(val)) return;


       // User is editing payment, not weeks
       this._isEditingWeeks = false;


       // Round to cents for comparison to avoid floating point issues
       const weeklyEquivalent = Math.round(this._toWeekly(val) * 100) / 100;
       const minWeekly = Math.round(this._minimumWeeklyTarget() * 100) / 100;
       const maxWeekly = this._maximumWeeklyTarget() != null
           ? Math.round(this._maximumWeeklyTarget() * 100) / 100
           : null;


       if (weeklyEquivalent < minWeekly) {
           const minDisplay = this.formatCurrency(this._toDisplay(minWeekly));
           event.target.setCustomValidity(`Desired payment must be at least ${minDisplay}.`);
           event.target.reportValidity();
           this.showToast('Invalid Payment', `Target payment must be at least ${minDisplay}.`, 'error', false);
           return;
       } else if (maxWeekly != null && weeklyEquivalent > maxWeekly) {
           const maxDisplay = this.formatCurrency(this._toDisplay(maxWeekly));
           event.target.setCustomValidity(`Desired payment must be at or below ${maxDisplay}.`);
           event.target.reportValidity();
           this.showToast('Invalid Payment', `Target payment must be at or below ${maxDisplay}.`, 'error', false);
           return;
       } else {
           event.target.setCustomValidity('');
           event.target.reportValidity();
       }


       this.targetPaymentAmount = val;
       this._syncPercentFromAmount(val);


       // Calculate and update Number of Weeks from payment
       const calculatedWeeks = this._calculateWeeksFromPayment(val);
       if (calculatedWeeks && calculatedWeeks > 0) {
           this._targetNumberOfWeeks = calculatedWeeks;
       }


       if (this.recalcTimer) {
           clearTimeout(this.recalcTimer);
           this.recalcTimer = null;
       }
       this.performCalculations();
   }


   handleNumberOfWeeksInput(event) {
       // Get value from lightning-input (uses event.target.value for number type)
       const raw = event.target.value;
       const val = parseInt(raw, 10);


       console.log('[handleNumberOfWeeksInput] raw:', raw, 'val:', val);


       if (Number.isNaN(val) || val <= 0) return;


       // Set flag - user is editing weeks
       this._isEditingWeeks = true;


       this._targetNumberOfWeeks = val;
       this.debouncedWeeksRecalc(300);
   }


   handleNumberOfWeeksChange(event) {
       // Get value from lightning-input
       const raw = event.target.value;
       let val = parseInt(raw, 10);


       console.log('[handleNumberOfWeeksChange] raw:', raw, 'val:', val);


       if (Number.isNaN(val) || val <= 0) return;


       // Set flag - user is editing weeks
       this._isEditingWeeks = true;


       // Log before clamping
       const originalVal = val;
       const minWeeks = this.minProgramWeeks;
       const maxWeeks = this.maxProgramWeeks;


       // Clamp to min/max
       val = Math.max(minWeeks, Math.min(maxWeeks, val));


       console.log('[handleNumberOfWeeksChange] original:', originalVal, 'min:', minWeeks, 'max:', maxWeeks, 'clamped:', val);


       this._targetNumberOfWeeks = val;


       // Clear any pending debounce
       if (this.weeksRecalcTimer) {
           clearTimeout(this.weeksRecalcTimer);
           this.weeksRecalcTimer = null;
       }


       // Calculate weekly payment from number of weeks
       this.calculateWeeklyPaymentFromWeeks(val);
   }


   async calculateWeeklyPaymentFromWeeks(numberOfWeeks) {
       if (!numberOfWeeks || numberOfWeeks <= 0) return;


       console.log('[calculateWeeklyPaymentFromWeeks] numberOfWeeks:', numberOfWeeks);
       console.log('[calculateWeeklyPaymentFromWeeks] totalDebt:', this.totalDebt);
       console.log('[calculateWeeklyPaymentFromWeeks] settlementPercent:', this.settlementPercent);
       console.log('[calculateWeeklyPaymentFromWeeks] programFeePercent:', this.programFeePercent);
       console.log('[calculateWeeklyPaymentFromWeeks] bankingFee:', this.bankingFee);


       // Formula: totalProgramCost = settlementAmount + programFee
       // netPerWeek = totalProgramCost / numberOfWeeks (exact division)
       // weeklyPayment = netPerWeek + bankingFee
       const totalDebt = this.totalDebt || 0;
       const settlementPct = this.settlementPercent || 60;
       const programFeePct = this.noFeeProgram ? 0 : (this.programFeePercent || 35);
       const bankingFee = this.bankingFee || 35;


       const settlementAmount = totalDebt * (settlementPct / 100);
       const programFee = totalDebt * (programFeePct / 100);


       // For no-fee programs, program fee is reallocated to settlement
       let totalProgramCost;
       if (this.noFeeProgram) {
           // Use baseline program fee for duration calculation
           const baselinePct = this.programFeePercent || 35;
           const baselineFee = totalDebt * (baselinePct / 100);
           totalProgramCost = settlementAmount + baselineFee;
       } else {
           totalProgramCost = settlementAmount + programFee;
       }


       console.log('[calculateWeeklyPaymentFromWeeks] settlementAmount:', settlementAmount);
       console.log('[calculateWeeklyPaymentFromWeeks] programFee:', programFee);
       console.log('[calculateWeeklyPaymentFromWeeks] totalProgramCost:', totalProgramCost);


       // Use exact division - bypass Apex's CEIL logic
       // weeklyPayment = (totalProgramCost / numberOfWeeks) + bankingFee
       const netPerWeek = totalProgramCost / numberOfWeeks;
       const weeklyPayment = Math.round((netPerWeek + bankingFee) * 100) / 100; // Round to cents


       console.log('[calculateWeeklyPaymentFromWeeks] netPerWeek:', netPerWeek);
       console.log('[calculateWeeklyPaymentFromWeeks] weeklyPayment:', weeklyPayment);


       // Update target payment amount - this should update the Desired Payment input
       this.targetPaymentAmount = weeklyPayment;


       // Sync the percent from the new amount
       this._syncPercentFromAmount(weeklyPayment);


       console.log('[calculateWeeklyPaymentFromWeeks] Updated targetPaymentAmount to:', this.targetPaymentAmount);


       // Trigger recalculation to update summary stats and schedule
       try {
           await this.performCalculations();


           // Override programLength with user-entered weeks (bypass Apex's CEIL)
           if (this.calculations && numberOfWeeks) {
               this.calculations.programLength = numberOfWeeks;
               console.log('[calculateWeeklyPaymentFromWeeks] Overrode programLength to:', numberOfWeeks);
           }


           console.log('[calculateWeeklyPaymentFromWeeks] performCalculations completed');
       } catch (e) {
           console.error('[calculateWeeklyPaymentFromWeeks] Error in performCalculations:', e);
       }
   }


   // Calculate Number of Weeks from Desired Payment (uses CEIL like Apex)
   _calculateWeeksFromPayment(weeklyPayment) {
       if (!weeklyPayment || weeklyPayment <= 0) return null;


       const totalDebt = this.totalDebt || 0;
       const settlementPct = this.settlementPercent || 60;
       const programFeePct = this.noFeeProgram ? 0 : (this.programFeePercent || 35);
       const bankingFee = this.bankingFee || 35;


       const settlementAmount = totalDebt * (settlementPct / 100);
       const programFee = totalDebt * (programFeePct / 100);


       // For no-fee programs, use baseline program fee for duration calculation
       let totalProgramCost;
       if (this.noFeeProgram) {
           const baselinePct = this.programFeePercent || 35;
           const baselineFee = totalDebt * (baselinePct / 100);
           totalProgramCost = settlementAmount + baselineFee;
       } else {
           totalProgramCost = settlementAmount + programFee;
       }


       const netPerWeek = weeklyPayment - bankingFee;
       if (netPerWeek <= 0) return null;


       // Use CEIL like Apex does
       const weeks = Math.ceil(totalProgramCost / netPerWeek);


       console.log('[_calculateWeeksFromPayment] weeklyPayment:', weeklyPayment, 'netPerWeek:', netPerWeek, 'weeks:', weeks);


       return weeks;
   }


   // Debounce for weeks input
   weeksRecalcTimer;
   debouncedWeeksRecalc(delay = 300) {
       if (this.weeksRecalcTimer) {
           clearTimeout(this.weeksRecalcTimer);
       }
       this.weeksRecalcTimer = setTimeout(() => {
           if (this._targetNumberOfWeeks) {
               this.calculateWeeklyPaymentFromWeeks(this._targetNumberOfWeeks);
           }
       }, delay);
   }


   // Save to Opportunity only (no drafts, no payment plans)
   async handleSave() {
       // Validate payment bounds before saving
       if (this.isDesiredMode) {
           // Round to cents for comparison to avoid floating point issues
           const weeklyEquivalent = Math.round(this._toWeekly(this.targetPaymentAmount) * 100) / 100;
           const minWeekly = Math.round(this._minimumWeeklyTarget() * 100) / 100;
           const maxWeekly = this._maximumWeeklyTarget() != null
               ? Math.round(this._maximumWeeklyTarget() * 100) / 100
               : null;


           if (weeklyEquivalent < minWeekly) {
               const minDisplay = this.formatCurrency(this._toDisplay(minWeekly));
               this.showToast('Validation Error', `Target payment must be at least ${minDisplay}.`, 'error', false);
               return;
           }
           if (maxWeekly != null && weeklyEquivalent > maxWeekly) {
               const maxDisplay = this.formatCurrency(this._toDisplay(maxWeekly));
               this.showToast('Validation Error', `Target payment must be at or below ${maxDisplay}.`, 'error', false);
               return;
           }
       }


       try {
           this.isLoading = true;


           const baseWeeklyPayment = this._calculateBaseWeeklyPayment();


           // Use manually entered weeks in Desired Mode, otherwise use calculated value
           const weeksToSave = this.isDesiredMode && this._targetNumberOfWeeks != null
               ? this._targetNumberOfWeeks
               : this.calculations.programLength;


           await updateOpportunityOnly({
               recordId: this.recordId,
               numberOfWeeks: weeksToSave,
               weeklyPayment: baseWeeklyPayment,
               firstDraftDate: this.firstDraftDate,
               bankingFee: this.bankingFee,
               setupFeeTerm: this.setupFeePayments,
               noFeeProgram: this.noFeeProgram,
               programType: this.programType,
               settlementAmount: this.calculations.settlementAmount,
               programFee: this.calculations.programFeeAmount
           });


           this.showToast('Success', 'Opportunity updated successfully', 'success', false);
       } catch (error) {
           const errorMessage = error?.body?.message || error?.message || 'Failed to save';
           this.showToast('Error', errorMessage, 'error', false);
       } finally {
           this.isLoading = false;
       }
   }


   async handleRefresh() {
       try {
           this.isLoading = true;
           await this.performCalculations();
           this.showToast('Success', 'Calculations refreshed', 'success', false);
       } catch (e) {
           this.showToast('Error', 'Failed to refresh', 'error', false);
       } finally {
           this.isLoading = false;
       }
   }


   // Schedule conversion helper
   convertScheduleForDisplay(apexSchedule) {
       if (!apexSchedule || apexSchedule.length === 0) {
           return [];
       }


       return apexSchedule.map((item, index) => {
           return {
               id: item.Id || `schedule-${index}`,
               draftNumber: item.weekNumber || item.paymentNumber || index + 1,
               paymentDate: item.paymentDate,
               paymentAmount: item.paymentAmount || item.totalPayment || 0,
               totalPayment: item.paymentAmount || item.totalPayment || 0,
               draftAmount: item.paymentAmount || item.totalPayment || 0,
               retainerFee: item.retainerFee || 0,
               setupFee: item.setupFee || 0,
               setupFeePortion: item.setupFee || 0,
               programFee: item.programAmount || item.programPayment || 0,
               programPortion: item.programAmount || item.programPayment || 0,
               bankingFee: item.bankingFee || 0,
               bankingFeePortion: item.bankingFee || 0,
               bank2Fee: item.bank2Fee || 0,
               bank2Portion: item.bank2Fee || 0,
               additionalProducts: item.additionalProducts || 0,
               escrowAmount: item.escrowAmount || item.escrowPayment || 0,
               savingsBalance: item.escrowAmount || item.escrowPayment || 0,
               runningBalance: item.runningBalance || item.remainingBalance || 0,
               runningTotal: item.runningBalance || item.remainingBalance || 0
           };
       });
   }


   // Helper methods
   _toWeekly(amount) {
       if (amount == null) return 0;
       return this.paymentFrequency === 'WEEKLY' ? Number(amount) : Number(amount) / this._weeklyToMonthlyFactor;
   }


   _toDisplay(weeklyAmount) {
       if (weeklyAmount == null) return 0;
       return this.paymentFrequency === 'WEEKLY' ? Number(weeklyAmount) : Number(weeklyAmount) * this._weeklyToMonthlyFactor;
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


   _calculateBaseWeeklyPayment() {
       if (this.paymentSchedule && this.paymentSchedule.length > 0) {
           const first = this.paymentSchedule[0] || {};
           const payment = first.paymentAmount ?? first.totalPayment ?? first.draftAmount ?? 0;
           const setup = first.setupFee ?? first.setupFeePortion ?? 0;
           return Math.max(0, payment - setup);
       }
       return this.calculations?.weeklyPayment || 0;
   }


   // Debounce helper
   recalcTimer;
   debouncedRecalc(delay = 200) {
       if (this.recalcTimer) {
           clearTimeout(this.recalcTimer);
       }
       this.recalcTimer = setTimeout(() => {
           this.performCalculations();
       }, delay);
   }


   computeTargetPaymentAmountLocal() {
       if (this.calculateBy !== 'PERCENT') {
           return this.targetPaymentAmount || 0;
       }
       const weeklyFromCurrent = (this.currentPayment || 0) * (this.targetPaymentPercent / 100);
       const boundedWeekly = Math.max(this._minimumWeeklyTarget(), weeklyFromCurrent);
       return this.paymentFrequency === 'WEEKLY' ? boundedWeekly : (boundedWeekly * this._weeklyToMonthlyFactor);
   }


   get displayWeeklyTarget() {
       const amount = this.calculateBy === 'PERCENT' ? this.computeTargetPaymentAmountLocal() : (this.targetPaymentAmount || 0);
       return this.paymentFrequency === 'WEEKLY' ? amount : (amount / this._weeklyToMonthlyFactor);
   }


   get summaryWeeklyPayment() {
       // In Desired Mode, always use the user's entered value
       if (this.isDesiredMode && this.targetPaymentAmount > 0) {
           return this.targetPaymentAmount;
       }
       // When user manually edits weeks, use the locally calculated payment
       if (this._isEditingWeeks && this.targetPaymentAmount > 0) {
           return this.targetPaymentAmount;
       }
       const calc = this.calculations?.weeklyPayment;
       if (calc && !Number.isNaN(calc) && calc > 0) return calc;
       return this.displayWeeklyTarget;
   }


   get summaryProgramLength() {
       // In Desired Mode, use manually entered weeks if available
       if (this.isDesiredMode && this._targetNumberOfWeeks != null) {
           return this._targetNumberOfWeeks;
       }
       return this.calculations?.programLength || 0;
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


   // Getters for Display
   get targetPaymentDisplay() {
       let displayAmount = 0;


       // In Desired Mode, always show the user's entered value
       if (this.isDesiredMode) {
           displayAmount = this.targetPaymentAmount || 0;
       } else if (this.paymentSchedule && this.paymentSchedule.length > 0) {
           const first = this.paymentSchedule[0] || {};
           const payment = first.paymentAmount ?? first.totalPayment ?? first.draftAmount ?? 0;
           const setup = first.setupFee ?? first.setupFeePortion ?? 0;
           displayAmount = Math.max(0, payment - setup);
       } else {
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
       return this.programType === 'DCG_MOD' ? 'selection-card selected' : 'selection-card';
   }


   get dcgDebtClass() {
       return this.programType === 'DCG_DEBT' ? 'selection-card selected' : 'selection-card';
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


   get percentButtonClass() {
       return this.calculateBy === 'PERCENT' ? 'toggle-button active' : 'toggle-button';
   }


   get desiredButtonClass() {
       return this.calculateBy === 'DESIRED' ? 'toggle-button active' : 'toggle-button';
   }


   get showNoFeeProgram() {
       return this.programType === 'DCG_MOD';
   }


   get setupFeeMinPayments() {
       return this._setupFeeMinPayments;
   }


   get setupFeeMaxPayments() {
       return this._setupFeeMaxPayments;
   }


   get minProgramWeeks() {
       // Calculate min weeks based on 80% of current payment (max payment = fewer weeks)
       const dynamicMin = this._calculateWeeksFromPercent(this.percentMax);
       const absoluteMin = this._minProgramWeeks || 26;
       return Math.max(absoluteMin, dynamicMin || absoluteMin);
   }


   get maxProgramWeeks() {
       // Calculate max weeks based on 40% of current payment (min payment = more weeks)
       const dynamicMax = this._calculateWeeksFromPercent(this.percentMin);
       const absoluteMax = this._maxProgramWeeks || 400;
       return Math.min(absoluteMax, dynamicMax || absoluteMax);
   }


   _calculateWeeksFromPercent(percent) {
       // Calculate number of weeks for a given percent of current payment
       const currentPayment = this.currentPayment || 0;
       if (currentPayment <= 0) return null;


       const totalDebt = this.totalDebt || 0;
       const settlementPct = this.settlementPercent || 60;
       const programFeePct = this.programFeePercent || 35;
       const bankingFee = this.bankingFee || 35;


       const settlementAmount = totalDebt * (settlementPct / 100);
       const programFee = totalDebt * (programFeePct / 100);
       const totalProgramCost = settlementAmount + programFee;


       const weeklyPayment = currentPayment * (percent / 100);
       const netPerWeek = weeklyPayment - bankingFee;


       if (netPerWeek <= 0) return null;


       // Use FLOOR to get correct min/max weeks based on percentage range
       return Math.floor(totalProgramCost / netPerWeek);
   }


   get targetNumberOfWeeks() {
       // If user has manually entered weeks, use that; otherwise use calculated value
       if (this._targetNumberOfWeeks != null) {
           return this._targetNumberOfWeeks;
       }
       return this.calculations?.programLength || this.minProgramWeeks;
   }


   handleWeeksIncrement() {
       const current = this.targetNumberOfWeeks || this.minProgramWeeks;
       const newVal = Math.min(current + 1, this.maxProgramWeeks);
       this._targetNumberOfWeeks = newVal;
       this.calculateWeeklyPaymentFromWeeks(newVal);
   }


   handleWeeksDecrement() {
       const current = this.targetNumberOfWeeks || this.minProgramWeeks;
       const newVal = Math.max(current - 1, this.minProgramWeeks);
       this._targetNumberOfWeeks = newVal;
       this.calculateWeeklyPaymentFromWeeks(newVal);
   }


   _generateSliderNumbers() {
       const min = this._setupFeeMinPayments || 1;
       const max = this._setupFeeMaxPayments || 10;
       const numbers = [];
       for (let i = min; i <= max; i++) {
           numbers.push(i);
       }
       return numbers;
   }


   formatCurrency(value) {
       return new Intl.NumberFormat('en-US', {
           style: 'currency',
           currency: 'USD',
           minimumFractionDigits: 2
       }).format(value || 0);
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
} 

