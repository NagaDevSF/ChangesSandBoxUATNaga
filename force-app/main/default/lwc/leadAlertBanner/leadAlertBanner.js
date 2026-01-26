import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class LeadAlertBanner extends NavigationMixin(LightningElement) {
  @api leadId;

  navigateToLead() {
    if (this.leadId) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
          recordId: this.leadId,
          objectApiName: 'Lead',
          actionName: 'view'
        }
      });
    }
  }
}