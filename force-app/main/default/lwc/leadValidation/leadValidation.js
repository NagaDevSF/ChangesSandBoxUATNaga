import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

import EMAIL from '@salesforce/schema/Lead.Email';
import PHONE from '@salesforce/schema/Lead.Phone';
import MOBILE from '@salesforce/schema/Lead.MobilePhone';

export default class LeadValidation extends LightningElement {

    @api recordId; 
    errors = [];
    noErrors = false;

    @wire(getRecord, { recordId: '$recordId', fields: [EMAIL, PHONE, MOBILE] })
    leadRecord({ data, error }) {
        if (data) {
            const email = data.fields.Email.value;
            const phone = data.fields.Phone.value;
            const mobile = data.fields.MobilePhone.value;

            this.validateFields(email, phone, mobile);
        }
        if (error) {
            this.errors = ['Error fetching Lead fields'];
        }
    }

    validateFields(email, phone, mobile) {
        this.errors = [];

        // ---------- PHONE VALIDATION ----------
        if (!phone) {
            this.errors.push('Phone number is empty, please fill it.');
        } else if (phone.replace(/\D/g, '').length !== 10) {
            this.errors.push('Phone number must be exactly 10 digits.');
        }

        // ---------- MOBILE VALIDATION ----------
        if (!mobile) {
            this.errors.push('Mobile number is empty, please fill it.');
        } else if (mobile.replace(/\D/g, '').length !== 10) {
            this.errors.push('Mobile number must be exactly 10 digits.');
        }

        // ---------- EMAIL VALIDATION ----------
        if (!email) {
            this.errors.push('Email address is empty, please fill it.');
        } else {
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(email)) {
                this.errors.push('Email address is not valid.');
            }
        }

        this.noErrors = this.errors.length === 0;
    }

}