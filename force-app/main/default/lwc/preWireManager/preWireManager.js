import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getPreWireContext from '@salesforce/apex/PreWireController.getPreWireContext';
import createPreWire from '@salesforce/apex/PreWireController.createPreWire';
import updatePreWire from '@salesforce/apex/PreWireController.updatePreWire';
import deletePreWire from '@salesforce/apex/PreWireController.deletePreWire';

// ==================================================================================
// CONSTANTS
// ==================================================================================

const CURRENCY_FORMATTER = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 2
});

let clientKeyCounter = 0;

export default class PreWireManager extends LightningElement {

    // ==================================================================================
    // Public Properties
    // ==================================================================================

    @api recordId;

    // ==================================================================================
    // Tracked Properties
    // ==================================================================================

    @track rows = [];
    isLoading = false;
    isSaving = false;
    errorMessage = '';
    accountName = '';

    // ==================================================================================
    // Computed Properties
    // ==================================================================================

    get isReady() {
        return !this.isLoading;
    }

    get hasRecords() {
        return this.rows.length > 0;
    }

    get hasNoRecords() {
        return this.rows.length === 0;
    }

    // ==================================================================================
    // Lifecycle Hooks
    // ==================================================================================

    connectedCallback() {
        this.loadData();
    }

    // ==================================================================================
    // Data Loading
    // ==================================================================================

    async loadData() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            const ctx = await getPreWireContext({ opportunityId: this.recordId });
            this.accountName = ctx.accountName || '';
            this.rows = (ctx.preWires || []).map(pw => this.mapServerRecord(pw));
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.showToast('Error', this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ==================================================================================
    // Event Handlers
    // ==================================================================================

    handleInsert() {
        const newRow = {
            clientKey: this.generateKey(),
            id: null,
            name: '',
            businessName: this.accountName,
            dateValue: null,
            amount: null,
            formattedDate: '',
            formattedAmount: '',
            isEditing: true,
            isNew: true
        };
        this.rows = [...this.rows, newRow];
    }

    handleEdit(event) {
        const key = event.currentTarget.dataset.key;
        this.rows = this.rows.map(row => {
            if (row.clientKey === key) {
                return {
                    ...row,
                    isEditing: true,
                    _originalDateValue: row.dateValue,
                    _originalAmount: row.amount
                };
            }
            return row;
        });
    }

    handleCancel(event) {
        const key = event.currentTarget.dataset.key;
        this.rows = this.rows.reduce((acc, row) => {
            if (row.clientKey === key) {
                // If it was a new unsaved row, remove it
                if (row.isNew) {
                    return acc;
                }
                // Restore original values
                acc.push({
                    ...row,
                    dateValue: row._originalDateValue,
                    amount: row._originalAmount,
                    formattedDate: this.formatDate(row._originalDateValue),
                    formattedAmount: this.formatCurrency(row._originalAmount),
                    isEditing: false,
                    _originalDateValue: undefined,
                    _originalAmount: undefined
                });
                return acc;
            }
            acc.push(row);
            return acc;
        }, []);
    }

    handleFieldChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;

        this.rows = this.rows.map(row => {
            if (row.clientKey === key) {
                return { ...row, [field]: value };
            }
            return row;
        });
    }

    async handleSave(event) {
        const key = event.currentTarget.dataset.key;
        const row = this.rows.find(r => r.clientKey === key);

        if (!row) return;

        // Client-side validation
        const validationError = this.validateRow(row);
        if (validationError) {
            this.showToast('Validation Error', validationError, 'warning');
            return;
        }

        this.isSaving = true;
        try {
            const input = {
                id: row.id,
                opportunityId: this.recordId,
                dateValue: row.dateValue,
                amount: parseFloat(row.amount)
            };

            let result;
            if (row.isNew) {
                result = await createPreWire({ inputJson: JSON.stringify(input) });
                this.showToast('Success', 'Pre Wire record created.', 'success');
            } else {
                result = await updatePreWire({ inputJson: JSON.stringify(input) });
                this.showToast('Success', 'Pre Wire record updated.', 'success');
            }

            // Replace the row with the server response
            this.rows = this.rows.map(r => {
                if (r.clientKey === key) {
                    return this.mapServerRecord(result);
                }
                return r;
            });
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDelete(event) {
        const key = event.currentTarget.dataset.key;
        const row = this.rows.find(r => r.clientKey === key);

        if (!row || !row.id) return;

        const confirmed = await LightningConfirm.open({
            message: 'Are you sure you want to delete this Pre Wire record?',
            variant: 'header',
            label: 'Confirm Delete',
            theme: 'error'
        });

        if (!confirmed) return;

        this.isSaving = true;
        try {
            await deletePreWire({ preWireId: row.id });
            this.rows = this.rows.filter(r => r.clientKey !== key);
            this.showToast('Success', 'Pre Wire record deleted.', 'success');
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ==================================================================================
    // Validation
    // ==================================================================================

    validateRow(row) {
        if (!row.dateValue) {
            return 'Date Value is required.';
        }
        if (row.amount === null || row.amount === undefined || row.amount === '') {
            return 'Amount is required.';
        }
        const numAmount = parseFloat(row.amount);
        if (isNaN(numAmount) || numAmount <= 0) {
            return 'Amount must be greater than zero.';
        }
        return null;
    }

    // ==================================================================================
    // Utility Methods
    // ==================================================================================

    mapServerRecord(pw) {
        return {
            clientKey: this.generateKey(),
            id: pw.id,
            name: pw.name,
            businessName: pw.businessName || this.accountName,
            dateValue: pw.dateValue,
            amount: pw.amount,
            formattedDate: this.formatDate(pw.dateValue),
            formattedAmount: this.formatCurrency(pw.amount),
            isEditing: false,
            isNew: false
        };
    }

    generateKey() {
        clientKeyCounter += 1;
        return 'pw-' + clientKeyCounter + '-' + Date.now();
    }

    formatDate(dateStr) {
        if (!dateStr) return '';
        // dateStr comes as YYYY-MM-DD from Apex Date serialization
        const parts = String(dateStr).split('-');
        if (parts.length === 3) {
            return parts[1] + '/' + parts[2] + '/' + parts[0];
        }
        return String(dateStr);
    }

    formatCurrency(value) {
        if (value === null || value === undefined) return '';
        return CURRENCY_FORMATTER.format(value);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) return 'An unknown error occurred.';
        if (error.body) {
            if (error.body.message) return error.body.message;
            if (typeof error.body === 'string') return error.body;
        }
        if (Array.isArray(error)) {
            return error.map(e => this.reduceError(e)).join(', ');
        }
        if (error.message) return error.message;
        if (typeof error === 'string') return error;
        return JSON.stringify(error);
    }
}
