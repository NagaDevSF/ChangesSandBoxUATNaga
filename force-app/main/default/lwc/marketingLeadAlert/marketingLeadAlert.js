// marketingLeadAlert.js
import { LightningElement, api } from 'lwc';

export default class MarketingLeadAlert extends LightningElement {
    @api showAlert = false;

    // Called by flow to show the alert
    @api 
    showAlertMessage() {
        this.showAlert = true;
        // Auto-hide after 5 seconds
        setTimeout(() => {
            this.closeAlert();
        }, 5000);
    }

    closeAlert() {
        this.showAlert = false;
    }
}