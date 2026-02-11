// mrCleanData.js
import { LightningElement, api } from 'lwc';

// Import MrCleanDataBot static resource (updated from MrCleanDataLogo)
import MR_CLEAN_DATA_BOT from '@salesforce/resourceUrl/MrCleanDataBot';

export default class MrCleanData extends LightningElement {
    @api recordId; // Automatically gets the current Lead record ID
    
    // Component state
    isLoading = true;
    hasError = false;
    
    // MrCleanDataBot static resource URL (updated)
    imageUrl = MR_CLEAN_DATA_BOT;
    
    // Component lifecycle
    connectedCallback() {
        // Set loading to false after component is ready
        setTimeout(() => {
            this.isLoading = false;
        }, 100);
    }
    
    // Getter for final image URL
    get finalImageUrl() {
        return this.imageUrl;
    }
    
    // Getter for image alt text (updated)
    get imageAltText() {
        return 'Mr Clean Data Bot GIF';
    }
    
    // Handle image load success
    handleImageLoad() {
        this.isLoading = false;
        this.hasError = false;
        console.log('MrCleanDataBot GIF loaded successfully');
    }
    
    // Handle image load error
    handleImageError() {
        this.isLoading = false;
        this.hasError = true;
        console.log('MrCleanDataBot GIF failed to load');
    }
    
    // Show component is ready
    get showContent() {
        return !this.isLoading;
    }
}