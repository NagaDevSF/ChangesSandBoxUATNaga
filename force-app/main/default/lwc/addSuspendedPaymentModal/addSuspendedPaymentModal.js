import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import LightningConfirm from 'lightning/confirm';

import validatePaymentDates from '@salesforce/apex/SettlementDraftController.validatePaymentDates';

export default class AddSuspendedPaymentModal extends LightningModal {
    @api commissionFee;

    paymentDate = null;
    paymentAmount = null;
    commissionFeeValue = 0;

    connectedCallback() {
        if (this.commissionFee !== null && this.commissionFee !== undefined) {
            this.commissionFeeValue = this.commissionFee;
        }
    }

    handleDateChange(event) {
        this.paymentDate = event.target.value;
    }

    handleAmountChange(event) {
        this.paymentAmount = event.target.value;
    }

    handleCommissionFeeChange(event) {
        this.commissionFeeValue = event.target.value;
    }

    handleCancel() {
        this.close();
    }

    formatDate(dateValue) {
        if (!dateValue) return '';
        const date = typeof dateValue === 'string' ? new Date(dateValue + 'T00:00:00') : dateValue;
        return date.toLocaleDateString('en-US', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit'
        });
    }

    async handleSubmit() {
        const inputs = Array.from(this.template.querySelectorAll('lightning-input'));
        const allValid = inputs.reduce((validSoFar, inputCmp) => {
            inputCmp.reportValidity();
            return validSoFar && inputCmp.checkValidity();
        }, true);

        if (!allValid) {
            return;
        }

        const paymentAmount = parseFloat(this.paymentAmount) || 0;
        if (paymentAmount <= 0) {
            return;
        }

        const commissionFee = parseFloat(this.commissionFeeValue) || 0;

        // Warn on weekend/holiday, but save as entered (same behavior as draft Save)
        try {
            this.disableClose = true;
            const dateValidation = await validatePaymentDates({ paymentDates: [this.paymentDate] });
            if (dateValidation?.hasNonBusinessDays) {
                const info = (dateValidation.nonBusinessDays || [])[0];
                const dateType = info?.dateType || 'Non-business day';
                const message = 'The selected payment date falls on a weekend or holiday:\n\n' +
                    `${this.formatDate(this.paymentDate)} (${dateType})` +
                    '\n\nDate will be saved as entered. Continue?';

                const confirmed = await LightningConfirm.open({
                    message,
                    label: 'Non-Business Day Warning',
                    theme: 'warning'
                });

                if (!confirmed) {
                    this.disableClose = false;
                    return;
                }
            }
        } catch (e) {
            // If validation fails, proceed (same as handleSaveDraft)
        } finally {
            this.disableClose = false;
        }

        this.close({
            paymentDate: this.paymentDate,
            paymentAmount,
            commissionFee
        });
    }
}