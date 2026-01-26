import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import SettlementPlanModal from 'c/settlementPlanModal';

/**
 * @description Headless Quick Action button that opens the Settlement Plan Builder modal.
 *              Uses verified LightningModal pattern from Salesforce documentation.
 * @author Settlement Calculator Team
 * @date January 2026 (Updated from direct calculate to modal approach)
 */
export default class CalculatePaymentPlanButton extends LightningElement {
    @api recordId;

    // Prevent double-click (verified pattern)
    _isExecuting = false;

    /**
     * @description Called automatically when the quick action is triggered.
     *              Opens the Settlement Plan Builder modal for preview and activation.
     */
    @api async invoke() {
        // Prevent double execution (verified pattern from Salesforce docs)
        if (this._isExecuting) {
            return;
        }
        this._isExecuting = true;

        try {
            // Open the modal (verified pattern)
            // NOTE: recordId must be passed explicitly - NOT auto-passed to modal
            const result = await SettlementPlanModal.open({
                size: 'large',
                description: 'Settlement Plan Builder',
                creditorOpportunityId: this.recordId
            });

            // Handle result (undefined if closed via X button)
            if (result === 'activated') {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Payment plan activated successfully',
                        variant: 'success'
                    })
                );
                // Refresh the page to show new related list items
                this.dispatchEvent(new RefreshEvent());
            }
            // If result is 'cancelled' or undefined, do nothing - user closed modal

        } catch (error) {
            const errorMessage = error.body?.message || error.message || 'An unexpected error occurred';
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: errorMessage,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        } finally {
            this._isExecuting = false;
        }
    }
}