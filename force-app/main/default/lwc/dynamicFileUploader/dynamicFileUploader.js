import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import LightningConfirm from 'lightning/confirm';
import XLSX_LIB from '@salesforce/resourceUrl/SheetJS';
import getAvailableObjects from '@salesforce/apex/DynamicFileUploadController.getAvailableObjects';
import getObjectFields from '@salesforce/apex/DynamicFileUploadController.getObjectFields';
import validateMappedData from '@salesforce/apex/DynamicFileUploadController.validateMappedData';
import createMappedRecords from '@salesforce/apex/DynamicFileUploadController.createMappedRecords';
import resolveScheduleItems from '@salesforce/apex/DynamicFileUploadController.resolveScheduleItems';

// ============================================================
// Constants
// ============================================================
const CHUNK_SIZE = 2000;
const PREVIEW_PAGE_SIZE = 50;
const SAMPLE_ROW_COUNT = 3;
const ACCEPTED_EXTENSIONS = ['.xlsx', '.csv'];
const MAX_ROW_LIMIT = 10000;

const STEP_CONFIG = [
    { label: 'Upload File', value: 'upload', number: '1' },
    { label: 'Map Fields', value: 'mapping', number: '2' },
    { label: 'Preview & Edit', value: 'preview', number: '3' },
    { label: 'Processing', value: 'processing', number: '4' },
    { label: 'Results', value: 'results', number: '5' }
];

const SF_TYPE_TO_DT_TYPE = {
    STRING: 'text',
    TEXTAREA: 'text',
    PICKLIST: 'text',
    MULTIPICKLIST: 'text',
    REFERENCE: 'text',
    ID: 'text',
    DOUBLE: 'number',
    CURRENCY: 'currency',
    PERCENT: 'percent',
    INTEGER: 'number',
    LONG: 'number',
    DATE: 'date-local',
    DATETIME: 'date',
    BOOLEAN: 'boolean',
    EMAIL: 'email',
    PHONE: 'phone',
    URL: 'url'
};

export default class DynamicFileUploader extends LightningElement {
    // ============================================================
    // Public Properties
    // ============================================================
    @api defaultObjectApiName = 'Payment_Fee__c';

    // ============================================================
    // Tracked Properties
    // ============================================================
    @track currentStep = 'home';
    @track selectedMode = '';
    @track objectOptions = [];
    @track selectedObject = '';
    @track objectFields = [];
    @track parsedHeaders = [];
    @track parsedRows = [];
    @track fieldMappings = [];
    @track previewData = [];
    @track previewColumns = [];
    @track validationResults = [];
    @track creationResults = [];
    @track processingProgress = { processed: 0, total: 0, success: 0, failed: 0 };
    @track selectedEppsIdColumn = '';
    @track selectedFeeDateColumn = '';

    // ============================================================
    // Regular Properties
    // ============================================================
    isLoading = false;
    xlsxLoaded = false;
    fileName = '';
    fileSize = 0;
    currentPage = 1;
    pageSize = PREVIEW_PAGE_SIZE;
    previewFilter = 'all';
    isValidated = false;
    isProcessing = false;
    isCancelled = false;
    _dragActive = false;

    // ============================================================
    // Lifecycle Methods
    // ============================================================
    connectedCallback() {
        this.selectedObject = this.defaultObjectApiName;
        this.loadAvailableObjects();
    }

    renderedCallback() {
        if (!this.xlsxLoaded) {
            this.xlsxLoaded = true;
            loadScript(this, XLSX_LIB)
                .then(() => {
                    // SheetJS library loaded successfully
                })
                .catch((error) => {
                    this.showToast('Library Error', 'Failed to load Excel parsing library: ' + this.reduceError(error), 'error');
                    this.xlsxLoaded = false;
                });
        }
    }

    // ============================================================
    // Computed Properties — Step Visibility
    // ============================================================
    get isHomeStep() {
        return this.currentStep === 'home';
    }

    get showWizard() {
        return this.currentStep !== 'home';
    }

    get isUploadStep() {
        return this.currentStep === 'upload';
    }

    get isMappingStep() {
        return this.currentStep === 'mapping';
    }

    get isPreviewStep() {
        return this.currentStep === 'preview';
    }

    get isProcessingStep() {
        return this.currentStep === 'processing';
    }

    get isResultsStep() {
        return this.currentStep === 'results';
    }

    // ============================================================
    // Computed Properties — Step Indicator
    // ============================================================
    get stepIndicator() {
        const stepOrder = STEP_CONFIG.map((s) => s.value);
        const currentIndex = stepOrder.indexOf(this.currentStep);

        return STEP_CONFIG.map((step, index) => {
            const isActive = step.value === this.currentStep;
            const isCompleted = index < currentIndex;
            const hasConnector = index < STEP_CONFIG.length - 1;
            const connectorCompleted = index < currentIndex;

            let circleClass = 'step-circle step-circle-pending';
            if (isActive) {
                circleClass = 'step-circle step-circle-active';
            } else if (isCompleted) {
                circleClass = 'step-circle step-circle-completed';
            }

            let labelClass = 'step-label';
            if (isActive) {
                labelClass += ' step-label-active';
            } else if (isCompleted) {
                labelClass += ' step-label-completed';
            }

            return {
                ...step,
                isActive,
                isCompleted,
                hasConnector,
                circleClass,
                labelClass,
                connectorClass: connectorCompleted ? 'step-connector step-connector-completed' : 'step-connector',
                className: 'step-item'
            };
        });
    }

    // ============================================================
    // Computed Properties — Upload Step
    // ============================================================
    get formattedFileSize() {
        return this.formatBytes(this.fileSize);
    }

    get hasFile() {
        return !!this.fileName;
    }

    get acceptedFormats() {
        return '.xlsx,.csv';
    }

    get totalRows() {
        return this.parsedRows.length;
    }

    get isNextDisabled() {
        return !this.hasFile || !this.selectedObject;
    }

    get dropZoneClass() {
        let cls = 'drop-zone';
        if (this._dragActive) {
            cls += ' drop-zone-active';
        }
        if (this.hasFile) {
            cls += ' drop-zone-has-file';
        }
        return cls;
    }

    // ============================================================
    // Computed Properties — Mapping Step
    // ============================================================
    get mappedFieldCount() {
        return this.fieldMappings.filter((m) => m.salesforceField).length;
    }

    get totalMappings() {
        return this.fieldMappings.length;
    }

    get requiredFields() {
        return this.objectFields.filter((f) => f.required);
    }

    get hasRequiredUnmapped() {
        const mappedApiNames = new Set(this.fieldMappings.filter((m) => m.salesforceField).map((m) => m.salesforceField));
        return this.requiredFields.some((f) => !mappedApiNames.has(f.apiName));
    }

    get unmappedRequiredFields() {
        const mappedApiNames = new Set(this.fieldMappings.filter((m) => m.salesforceField).map((m) => m.salesforceField));
        return this.requiredFields.filter((f) => !mappedApiNames.has(f.apiName));
    }

    get unmappedRequiredFieldsList() {
        return this.unmappedRequiredFields.map((f) => f.label).join(', ');
    }

    get availableFieldOptions() {
        const options = [{ label: '-- None --', value: '' }];
        this.objectFields.forEach((field) => {
            const reqLabel = field.isRequired ? ' *' : '';
            options.push({
                label: field.label + ' (' + field.apiName + ')' + reqLabel,
                value: field.apiName
            });
        });
        return options;
    }

    get canProceedToPreview() {
        return this.mappedFieldCount > 0;
    }

    get cannotProceedToPreview() {
        return !this.canProceedToPreview;
    }

    get excelColumnOptions() {
        const options = [{ label: '-- None --', value: '' }];
        this.parsedHeaders.forEach((header) => {
            options.push({ label: header, value: header });
        });
        return options;
    }

    get hasResolutionColumns() {
        return this.selectedEppsIdColumn && this.selectedFeeDateColumn;
    }

    // ============================================================
    // Computed Properties — Preview Step
    // ============================================================
    get filteredPreviewData() {
        if (this.previewFilter === 'valid') {
            return this.previewData.filter((row) => row._isValid === true);
        }
        if (this.previewFilter === 'invalid') {
            return this.previewData.filter((row) => row._isValid === false);
        }
        return this.previewData;
    }

    get currentPageData() {
        const data = this.filteredPreviewData;
        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        return data.slice(start, end);
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredPreviewData.length / this.pageSize));
    }

    get pageInfo() {
        return `Page ${this.currentPage} of ${this.totalPages} (${this.filteredPreviewData.length} rows)`;
    }

    get hasPrevPage() {
        return this.currentPage > 1;
    }

    get noPrevPage() {
        return !this.hasPrevPage;
    }

    get hasNextPage() {
        return this.currentPage < this.totalPages;
    }

    get noNextPage() {
        return !this.hasNextPage;
    }

    get validRowCount() {
        return this.previewData.filter((row) => row._isValid === true).length;
    }

    get invalidRowCount() {
        return this.previewData.filter((row) => row._isValid === false).length;
    }

    get filterOptions() {
        return [
            { label: `All (${this.previewData.length})`, value: 'all' },
            { label: `Valid (${this.validRowCount})`, value: 'valid' },
            { label: `Invalid (${this.invalidRowCount})`, value: 'invalid' }
        ];
    }

    // ============================================================
    // Computed Properties — Processing Step
    // ============================================================
    get progressPercent() {
        if (this.processingProgress.total === 0) return 0;
        return Math.round((this.processingProgress.processed / this.processingProgress.total) * 100);
    }

    get progressLabel() {
        return `Processing ${this.processingProgress.processed} of ${this.processingProgress.total} rows...`;
    }

    get progressBarStyle() {
        return `width: ${this.progressPercent}%`;
    }

    // ============================================================
    // Computed Properties — Results Step
    // ============================================================
    get resultsSummary() {
        const total = this.creationResults.length;
        const success = this.creationResults.filter((r) => r._resultStatus === 'Success').length;
        const failed = total - success;
        const successPercent = total > 0 ? Math.round((success / total) * 100) : 0;
        return { total, success, failed, successPercent };
    }

    get resultsColumns() {
        return [
            { label: '#', fieldName: 'rowIndex', type: 'number', initialWidth: 70 },
            { label: 'Status', fieldName: '_resultStatus', type: 'text', initialWidth: 100 },
            { label: 'Record ID', fieldName: '_recordId', type: 'text', initialWidth: 200 },
            { label: 'Message', fieldName: '_resultMessage', type: 'text' }
        ];
    }

    get hasResults() {
        return this.creationResults.length > 0;
    }

    // ============================================================
    // Data Loading Methods
    // ============================================================
    async loadAvailableObjects() {
        try {
            const result = await getAvailableObjects();
            this.objectOptions = result.map((obj) => ({
                label: obj.label + ' (' + obj.value + ')',
                value: obj.value
            }));
            if (this.selectedObject) {
                await this.loadObjectFields();
            }
        } catch (error) {
            this.showToast('Error', 'Failed to load available objects: ' + this.reduceError(error), 'error');
        }
    }

    async loadObjectFields() {
        this.isLoading = true;
        try {
            const fields = await getObjectFields({ objectApiName: this.selectedObject });
            this.objectFields = fields;
        } catch (error) {
            this.showToast('Error', 'Failed to load object fields: ' + this.reduceError(error), 'error');
            this.objectFields = [];
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================================
    // Event Handlers — Home: Mode Selection
    // ============================================================
    handleModeSelect(event) {
        this.selectedMode = event.currentTarget.dataset.mode;
        if (this.selectedMode === 'final-wires') {
            this.currentStep = 'upload';
        } else {
            this.showToast('Coming Soon', `The "${this.selectedMode === 'collecting-wires' ? 'Collecting Wires' : 'Other'}" module is under development.`, 'info');
        }
    }

    handleBackToHome() {
        this.resetAllState();
        this.currentStep = 'home';
        this.selectedMode = '';
    }

    // ============================================================
    // Event Handlers — Step 1: Upload
    // ============================================================
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.loadObjectFields();
        this.resetFileState();
    }

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        this._dragActive = true;
    }

    handleDragLeave(event) {
        event.preventDefault();
        event.stopPropagation();
        this._dragActive = false;
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        this._dragActive = false;

        const files = event.dataTransfer.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
    }

    handleFileInputChange(event) {
        const files = event.target.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
    }

    handleRemoveFile() {
        this.resetFileState();
    }

    processFile(file) {
        const name = file.name.toLowerCase();
        const ext = name.substring(name.lastIndexOf('.'));

        if (!ACCEPTED_EXTENSIONS.includes(ext)) {
            this.showToast('Invalid File', 'Please upload an .xlsx or .csv file.', 'error');
            return;
        }

        this.fileName = file.name;
        this.fileSize = file.size;
        this.isLoading = true;

        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const data = new Uint8Array(e.target.result);
                /* global XLSX */
                const workbook = XLSX.read(data, { type: 'array', cellDates: false });
                const firstSheetName = workbook.SheetNames[0];
                const worksheet = workbook.Sheets[firstSheetName];
                const jsonData = XLSX.utils.sheet_to_json(worksheet, { defval: '' });

                if (!jsonData || jsonData.length === 0) {
                    this.showToast('Empty File', 'The uploaded file contains no data rows.', 'warning');
                    this.resetFileState();
                    this.isLoading = false;
                    return;
                }

                const headers = Object.keys(jsonData[0]);
                if (headers.length === 0) {
                    this.showToast('No Columns', 'Could not detect any columns in the file.', 'error');
                    this.resetFileState();
                    this.isLoading = false;
                    return;
                }

                // CRITICAL: Filter out rows where the FIRST column value is null/empty/blank
                const firstColumn = headers[0];
                const filteredData = jsonData.filter((row) => {
                    const val = row[firstColumn];
                    return val !== null && val !== undefined && String(val).trim() !== '';
                });

                if (filteredData.length > MAX_ROW_LIMIT) {
                    this.showToast(
                        'Too Many Rows',
                        `File contains ${filteredData.length} rows. Maximum supported is ${MAX_ROW_LIMIT}.`,
                        'error'
                    );
                    this.resetFileState();
                    this.isLoading = false;
                    return;
                }

                this.parsedHeaders = headers;
                this.parsedRows = filteredData;

                const skippedCount = jsonData.length - filteredData.length;
                let message = `${filteredData.length} rows parsed from "${firstSheetName}"`;
                if (skippedCount > 0) {
                    message += ` (${skippedCount} blank rows filtered)`;
                }
                this.showToast('File Loaded', message, 'success');
            } catch (parseError) {
                this.showToast('Parse Error', 'Failed to parse file: ' + parseError.message, 'error');
                this.resetFileState();
            } finally {
                this.isLoading = false;
            }
        };
        reader.onerror = () => {
            this.showToast('Read Error', 'Failed to read the file.', 'error');
            this.resetFileState();
            this.isLoading = false;
        };
        reader.readAsArrayBuffer(file);
    }

    handleProceedToMapping() {
        if (!this.selectedObject) {
            this.showToast('Missing Object', 'Please select a target Salesforce object.', 'error');
            return;
        }
        if (!this.hasFile || this.parsedRows.length === 0) {
            this.showToast('No File', 'Please upload a file first.', 'error');
            return;
        }
        if (this.objectFields.length === 0) {
            this.loadObjectFields().then(() => {
                this.initializeFieldMappings();
                this.handleAutoMap();
                this.autoDetectResolutionColumns();
                this.currentStep = 'mapping';
            });
            return;
        }
        this.initializeFieldMappings();
        this.handleAutoMap();
        this.autoDetectResolutionColumns();
        this.currentStep = 'mapping';
    }

    // ============================================================
    // Event Handlers — Step 2: Mapping
    // ============================================================
    initializeFieldMappings() {
        this.fieldMappings = this.parsedHeaders.map((header) => {
            const samples = [];
            for (let i = 0; i < Math.min(SAMPLE_ROW_COUNT, this.parsedRows.length); i++) {
                const val = this.parsedRows[i][header];
                samples.push({
                    id: header + '_sample_' + i,
                    value: val !== null && val !== undefined ? String(val).substring(0, 40) : ''
                });
            }
            return {
                excelColumn: header,
                salesforceField: '',
                salesforceLabel: '',
                fieldType: '',
                sampleValues: samples,
                isAutoMapped: false,
                rowClass: 'mapping-row slds-grid slds-p-around_small slds-grid_vertical-align-center'
            };
        });
    }

    handleAutoMap() {
        let matchCount = 0;
        const updatedMappings = this.fieldMappings.map((mapping) => {
            const normalizedCol = this.normalizeString(mapping.excelColumn);
            let matchedField = null;

            // Exact label match
            matchedField = this.objectFields.find(
                (f) => f.label.toLowerCase() === mapping.excelColumn.toLowerCase()
            );

            // Exact normalized label match
            if (!matchedField) {
                matchedField = this.objectFields.find(
                    (f) => this.normalizeString(f.label) === normalizedCol
                );
            }

            // API name match (strip __c and underscores)
            if (!matchedField) {
                matchedField = this.objectFields.find(
                    (f) =>
                        this.normalizeString(f.apiName.replace(/__c$/i, '').replace(/_/g, ' ')) ===
                        normalizedCol
                );
            }

            // Contains match: SF label contains column or column contains SF label
            if (!matchedField) {
                matchedField = this.objectFields.find((f) => {
                    const normLabel = this.normalizeString(f.label);
                    return (
                        (normLabel.includes(normalizedCol) && normalizedCol.length >= 3) ||
                        (normalizedCol.includes(normLabel) && normLabel.length >= 3)
                    );
                });
            }

            if (matchedField) {
                matchCount++;
                return {
                    ...mapping,
                    salesforceField: matchedField.apiName,
                    salesforceLabel: matchedField.label,
                    fieldType: matchedField.fieldType || matchedField.type,
                    isAutoMapped: true,
                    rowClass: 'mapping-row mapping-row-auto slds-grid slds-p-around_small slds-grid_vertical-align-center'
                };
            }
            return {
                ...mapping,
                isAutoMapped: false,
                rowClass: 'mapping-row slds-grid slds-p-around_small slds-grid_vertical-align-center'
            };
        });

        this.fieldMappings = updatedMappings;
        this.showToast('Auto-Map Complete', `Matched ${matchCount} of ${this.fieldMappings.length} columns.`, 'info');
    }

    autoDetectResolutionColumns() {
        const eppsAliases = ['cardholderid', 'cardholder id', 'cardholder_id', 'epps id', 'eppsid', 'epps_id', 'accountholderid', 'accountholder id'];
        const dateAliases = ['fee date', 'feedate', 'fee_date', 'feedate'];

        for (const header of this.parsedHeaders) {
            const normalized = header.toLowerCase().trim().replace(/[_\-]/g, ' ');

            if (!this.selectedEppsIdColumn && eppsAliases.includes(normalized)) {
                this.selectedEppsIdColumn = header;
            }
            if (!this.selectedFeeDateColumn && dateAliases.includes(normalized)) {
                this.selectedFeeDateColumn = header;
            }
        }
    }

    handleFieldMappingChange(event) {
        const columnName = event.target.dataset.column;
        const newValue = event.detail.value;

        this.fieldMappings = this.fieldMappings.map((mapping) => {
            if (mapping.excelColumn === columnName) {
                const baseClass = 'mapping-row slds-grid slds-p-around_small slds-grid_vertical-align-center';
                if (!newValue) {
                    return {
                        ...mapping,
                        salesforceField: '',
                        salesforceLabel: '',
                        fieldType: '',
                        isAutoMapped: false,
                        rowClass: baseClass
                    };
                }
                const sfField = this.objectFields.find((f) => f.apiName === newValue);
                return {
                    ...mapping,
                    salesforceField: newValue,
                    salesforceLabel: sfField ? sfField.label : newValue,
                    fieldType: sfField ? sfField.type : 'STRING',
                    isAutoMapped: false,
                    rowClass: baseClass
                };
            }
            return mapping;
        });
    }

    handleClearMappings() {
        this.fieldMappings = this.fieldMappings.map((mapping) => ({
            ...mapping,
            salesforceField: '',
            salesforceLabel: '',
            fieldType: ''
        }));
        this.showToast('Mappings Cleared', 'All field mappings have been removed.', 'info');
    }

    handleEppsIdColumnChange(event) {
        this.selectedEppsIdColumn = event.detail.value;
    }

    handleFeeDateColumnChange(event) {
        this.selectedFeeDateColumn = event.detail.value;
    }

    handleBackToUpload() {
        this.currentStep = 'upload';
    }

    async handleProceedToPreview() {
        if (this.mappedFieldCount === 0) {
            this.showToast('No Mappings', 'Please map at least one column to a Salesforce field.', 'error');
            return;
        }

        if (this.hasRequiredUnmapped) {
            const proceed = await LightningConfirm.open({
                message: `The following required fields are not mapped: ${this.unmappedRequiredFieldsList}. Records may fail during creation. Continue anyway?`,
                variant: 'header',
                label: 'Required Fields Not Mapped',
                theme: 'warning'
            });
            if (!proceed) {
                return;
            }
        }

        this.buildPreviewData();
        this.buildPreviewColumns();
        this.currentPage = 1;
        this.previewFilter = 'all';
        this.isValidated = false;

        // Resolve EPPS ID + Fee Date → PSI if resolution columns are selected
        if (this.hasResolutionColumns) {
            await this.resolveRows();
        }

        this.currentStep = 'preview';
    }

    // ============================================================
    // Event Handlers — Step 3: Preview
    // ============================================================
    buildPreviewData() {
        const activeMappings = this.fieldMappings.filter((m) => m.salesforceField);

        this.previewData = this.parsedRows.map((row, index) => {
            const record = { rowIndex: index + 1 };
            activeMappings.forEach((mapping) => {
                let value = row[mapping.excelColumn];

                // Type-specific transformations
                if (mapping.fieldType === 'DATE' || mapping.fieldType === 'DATETIME') {
                    value = this.parseExcelDate(value);
                } else if (mapping.fieldType === 'CURRENCY' || mapping.fieldType === 'DOUBLE' || mapping.fieldType === 'PERCENT') {
                    value = this.parseCurrency(value);
                } else if (mapping.fieldType === 'INTEGER' || mapping.fieldType === 'LONG') {
                    const parsed = parseInt(String(value).replace(/[^0-9-]/g, ''), 10);
                    value = isNaN(parsed) ? value : parsed;
                } else if (mapping.fieldType === 'BOOLEAN') {
                    const strVal = String(value).toLowerCase().trim();
                    value = strVal === 'true' || strVal === '1' || strVal === 'yes';
                }

                record[mapping.salesforceField] = value;
            });
            record._isValid = null;
            record._status = '';
            record._errors = '';
            return record;
        });
    }

    buildPreviewColumns() {
        const activeMappings = this.fieldMappings.filter((m) => m.salesforceField);

        const columns = [
            {
                label: '#',
                fieldName: 'rowIndex',
                type: 'number',
                initialWidth: 70,
                editable: false,
                cellAttributes: { alignment: 'center' }
            }
        ];

        activeMappings.forEach((mapping) => {
            const dtType = SF_TYPE_TO_DT_TYPE[mapping.fieldType] || 'text';
            const col = {
                label: mapping.salesforceLabel,
                fieldName: mapping.salesforceField,
                type: dtType,
                editable: true
            };

            if (dtType === 'currency') {
                col.typeAttributes = { currencyCode: 'USD', minimumFractionDigits: 2, maximumFractionDigits: 2 };
            }
            if (dtType === 'percent') {
                col.typeAttributes = { minimumFractionDigits: 2, maximumFractionDigits: 2 };
            }
            if (dtType === 'date-local') {
                col.typeAttributes = { year: 'numeric', month: '2-digit', day: '2-digit' };
            }

            columns.push(col);
        });

        columns.push({
            label: 'Status',
            fieldName: '_status',
            type: 'text',
            initialWidth: 140,
            editable: false,
            cellAttributes: {
                class: { fieldName: '_statusClass' }
            }
        });

        this.previewColumns = columns;
    }

    async resolveRows() {
        this.isLoading = true;
        try {
            // Build resolution inputs from raw parsed data
            const inputs = this.previewData.map((row) => ({
                rowIndex: row.rowIndex,
                eppsId: String(this.parsedRows[row.rowIndex - 1][this.selectedEppsIdColumn] || '').trim(),
                feeDate: this.parseExcelDate(this.parsedRows[row.rowIndex - 1][this.selectedFeeDateColumn])
            }));

            // Call Apex in chunks
            const allResolved = [];
            for (let i = 0; i < inputs.length; i += CHUNK_SIZE) {
                const chunk = inputs.slice(i, i + CHUNK_SIZE);
                const chunkResults = await resolveScheduleItems({ rowsJson: JSON.stringify(chunk) });
                allResolved.push(...chunkResults);
            }

            // Build resolution map by rowIndex
            const resolutionMap = {};
            allResolved.forEach((r) => {
                resolutionMap[r.rowIndex] = r;
            });

            // Merge resolution into preview data
            let resolvedCount = 0;
            let unresolvedCount = 0;
            this.previewData = this.previewData.map((row) => {
                const resolution = resolutionMap[row.rowIndex];
                const updated = { ...row };

                if (resolution && resolution.isResolved) {
                    updated.Payment_Schedule_Item__c = resolution.psiId;
                    updated.Type__c = 'Wire';
                    updated._resolution = resolution.psiName + ' (' + resolution.paymentDate + ')';
                    updated._resolutionClass = 'slds-text-color_success';
                    updated._isResolved = true;
                    updated._oppName = resolution.opportunityName;
                    resolvedCount++;
                } else {
                    updated._resolution = resolution ? resolution.errorMessage : 'Unresolved';
                    updated._resolutionClass = 'slds-text-color_error';
                    updated._isResolved = false;
                    unresolvedCount++;
                }
                return updated;
            });

            // Add resolution column to preview columns
            const resolutionCol = {
                label: 'Matched PSI',
                fieldName: '_resolution',
                type: 'text',
                initialWidth: 220,
                editable: false,
                cellAttributes: {
                    class: { fieldName: '_resolutionClass' }
                }
            };
            // Insert before the Status column (last column)
            const cols = [...this.previewColumns];
            cols.splice(cols.length - 1, 0, resolutionCol);
            this.previewColumns = cols;

            this.showToast(
                'Resolution Complete',
                `Resolved ${resolvedCount} of ${resolvedCount + unresolvedCount} rows to Payment Schedule Items.`,
                resolvedCount > 0 ? 'success' : 'warning'
            );
        } catch (error) {
            this.showToast('Resolution Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCellChange(event) {
        const draftValues = event.detail.draftValues;
        const updatedData = [...this.previewData];

        draftValues.forEach((draft) => {
            const idx = updatedData.findIndex((row) => row.rowIndex === draft.rowIndex);
            if (idx !== -1) {
                Object.keys(draft).forEach((key) => {
                    if (key !== 'rowIndex') {
                        updatedData[idx] = { ...updatedData[idx], [key]: draft[key] };
                    }
                });
            }
        });

        this.previewData = updatedData;

        // Clear draft values from the datatable
        const datatable = this.template.querySelector('lightning-datatable');
        if (datatable) {
            datatable.draftValues = [];
        }

        this.showToast('Row Updated', `${draftValues.length} cell(s) updated.`, 'success');
    }

    handlePrevPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
        }
    }

    handleFilterChange(event) {
        this.previewFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleBackToMapping() {
        this.currentStep = 'mapping';
        this.isValidated = false;
        this.validationResults = [];
    }

    async handleValidate() {
        this.isLoading = true;
        try {
            const activeMappings = this.fieldMappings.filter((m) => m.salesforceField);
            const fieldNames = activeMappings.map((m) => m.salesforceField);

            const records = this.previewData.map((row) => {
                const fieldValues = {};
                fieldNames.forEach((fn) => {
                    const val = row[fn];
                    fieldValues[fn] = val !== null && val !== undefined ? String(val) : '';
                });
                // Include resolved PSI ID and Type for wire resolution
                if (row.Payment_Schedule_Item__c) {
                    fieldValues['Payment_Schedule_Item__c'] = row.Payment_Schedule_Item__c;
                }
                if (row.Type__c) {
                    fieldValues['Type__c'] = row.Type__c;
                }
                return { rowIndex: row.rowIndex, fieldValues };
            });

            // Process in chunks
            const allResults = [];
            for (let i = 0; i < records.length; i += CHUNK_SIZE) {
                const chunk = records.slice(i, i + CHUNK_SIZE);
                const chunkResults = await validateMappedData({
                    objectApiName: this.selectedObject,
                    records: JSON.stringify(chunk)
                });
                allResults.push(...chunkResults);
            }

            // Merge validation results into preview data
            const resultsMap = new Map();
            allResults.forEach((r) => {
                resultsMap.set(r.rowIndex, r);
            });

            this.previewData = this.previewData.map((row) => {
                const result = resultsMap.get(row.rowIndex);
                if (result) {
                    return {
                        ...row,
                        _isValid: result.isValid,
                        _status: result.isValid ? 'Valid' : 'Invalid',
                        _errors: result.errorMessage || '',
                        _statusClass: result.isValid ? 'slds-text-color_success' : 'slds-text-color_error'
                    };
                }
                return row;
            });

            this.validationResults = allResults;
            this.isValidated = true;

            const validCount = allResults.filter((r) => r.isValid).length;
            const invalidCount = allResults.length - validCount;
            this.showToast(
                'Validation Complete',
                `${validCount} valid, ${invalidCount} invalid out of ${allResults.length} rows.`,
                invalidCount > 0 ? 'warning' : 'success'
            );
        } catch (error) {
            this.showToast('Validation Error', 'Failed to validate data: ' + this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleProcess() {
        const rowsToProcess = this.isValidated
            ? this.previewData.filter((r) => r._isValid !== false)
            : this.previewData;

        if (rowsToProcess.length === 0) {
            this.showToast('No Valid Rows', 'There are no valid rows to process.', 'warning');
            return;
        }

        const objectLabel = this.objectOptions.find((o) => o.value === this.selectedObject);
        const displayName = objectLabel ? objectLabel.label : this.selectedObject;

        const confirmed = await LightningConfirm.open({
            message: `Create ${rowsToProcess.length} record(s) in ${displayName}? This action cannot be undone.`,
            variant: 'header',
            label: 'Confirm Record Creation',
            theme: 'warning'
        });

        if (!confirmed) {
            return;
        }

        this.currentStep = 'processing';
        this.processChunks(rowsToProcess);
    }

    // ============================================================
    // Event Handlers — Step 4: Processing
    // ============================================================
    async processChunks(rowsToProcess) {
        this.isProcessing = true;
        this.isCancelled = false;
        this.creationResults = [];

        const activeMappings = this.fieldMappings.filter((m) => m.salesforceField);
        const fieldNames = activeMappings.map((m) => m.salesforceField);

        const records = rowsToProcess.map((row) => {
            const fieldValues = {};
            fieldNames.forEach((fn) => {
                const val = row[fn];
                fieldValues[fn] = val !== null && val !== undefined ? String(val) : '';
            });
            // Include resolved PSI ID and Type for wire resolution
            if (row.Payment_Schedule_Item__c) {
                fieldValues['Payment_Schedule_Item__c'] = row.Payment_Schedule_Item__c;
            }
            if (row.Type__c) {
                fieldValues['Type__c'] = row.Type__c;
            }
            return { rowIndex: row.rowIndex, fieldValues };
        });

        this.processingProgress = {
            processed: 0,
            total: records.length,
            success: 0,
            failed: 0
        };

        const allResults = [];

        for (let i = 0; i < records.length; i += CHUNK_SIZE) {
            if (this.isCancelled) {
                this.showToast('Cancelled', 'Processing was cancelled by user.', 'warning');
                break;
            }

            const chunk = records.slice(i, i + CHUNK_SIZE);
            try {
                const chunkResults = await createMappedRecords({
                    objectApiName: this.selectedObject,
                    records: JSON.stringify(chunk)
                });

                chunkResults.forEach((result) => {
                    allResults.push({
                        rowIndex: result.rowIndex,
                        _resultStatus: result.isSuccess ? 'Success' : 'Failed',
                        _recordId: result.recordId || '',
                        _resultMessage: result.errorMessage || 'Record created successfully'
                    });
                });

                const successCount = chunkResults.filter((r) => r.isSuccess).length;
                const failCount = chunkResults.length - successCount;

                this.processingProgress = {
                    ...this.processingProgress,
                    processed: this.processingProgress.processed + chunk.length,
                    success: this.processingProgress.success + successCount,
                    failed: this.processingProgress.failed + failCount
                };
            } catch (error) {
                // If entire chunk fails, mark all as failed
                chunk.forEach((rec) => {
                    allResults.push({
                        rowIndex: rec.rowIndex,
                        _resultStatus: 'Failed',
                        _recordId: '',
                        _resultMessage: this.reduceError(error)
                    });
                });

                this.processingProgress = {
                    ...this.processingProgress,
                    processed: this.processingProgress.processed + chunk.length,
                    failed: this.processingProgress.failed + chunk.length
                };
            }
        }

        this.creationResults = allResults;
        this.isProcessing = false;
        this.currentStep = 'results';
    }

    handleCancelProcessing() {
        this.isCancelled = true;
    }

    // ============================================================
    // Event Handlers — Step 5: Results
    // ============================================================
    handleUploadAnother() {
        this.resetAllState();
        this.currentStep = 'home';
        this.selectedMode = '';
    }

    handleDownloadResults() {
        if (this.creationResults.length === 0) {
            this.showToast('No Results', 'There are no results to download.', 'warning');
            return;
        }

        const headers = ['Row #', 'Status', 'Record ID', 'Message'];
        const csvRows = [headers.join(',')];

        this.creationResults.forEach((result) => {
            const row = [
                result.rowIndex,
                this.escapeCsvValue(result._resultStatus),
                this.escapeCsvValue(result._recordId),
                this.escapeCsvValue(result._resultMessage)
            ];
            csvRows.push(row.join(','));
        });

        const csvContent = csvRows.join('\n');
        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);

        const link = document.createElement('a');
        link.href = url;
        link.download = `upload_results_${new Date().toISOString().slice(0, 10)}.csv`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);

        this.showToast('Download Started', 'Results CSV has been downloaded.', 'success');
    }

    // ============================================================
    // Utility Methods
    // ============================================================
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (typeof error === 'string') {
            return error;
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.body && Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error?.message) {
            return error.message;
        }
        try {
            return JSON.stringify(error);
        } catch (e) {
            return 'An unknown error occurred';
        }
    }

    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    }

    parseExcelDate(value) {
        if (value === null || value === undefined || value === '') {
            return '';
        }

        // If it is a number, treat as Excel serial date
        if (typeof value === 'number') {
            // Excel epoch is January 0, 1900 (Dec 30, 1899)
            // Adjust for the Excel leap year bug (serial 60 = Feb 29, 1900, which does not exist)
            const epoch = new Date(1899, 11, 30);
            const adjustedValue = value > 59 ? value - 1 : value;
            const date = new Date(epoch.getTime() + adjustedValue * 86400000);
            const year = date.getFullYear();
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const day = String(date.getDate()).padStart(2, '0');
            return `${year}-${month}-${day}`;
        }

        const strVal = String(value).trim();

        // Already ISO format (YYYY-MM-DD)
        if (/^\d{4}-\d{2}-\d{2}/.test(strVal)) {
            return strVal.substring(0, 10);
        }

        // M/D/YYYY or M/D/YY format
        const slashMatch = strVal.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
        if (slashMatch) {
            const month = slashMatch[1].padStart(2, '0');
            const day = slashMatch[2].padStart(2, '0');
            let year = slashMatch[3];
            if (year.length === 2) {
                year = parseInt(year, 10) > 50 ? '19' + year : '20' + year;
            }
            return `${year}-${month}-${day}`;
        }

        return strVal;
    }

    parseCurrency(value) {
        if (value === null || value === undefined || value === '') {
            return null;
        }
        if (typeof value === 'number') {
            return value;
        }
        const cleaned = String(value).replace(/[$,\s]/g, '');
        const parsed = parseFloat(cleaned);
        return isNaN(parsed) ? value : parsed;
    }

    normalizeString(str) {
        if (!str) return '';
        return str
            .toLowerCase()
            .trim()
            .replace(/[_\-]/g, ' ')
            .replace(/\s+/g, ' ');
    }

    escapeCsvValue(val) {
        if (val === null || val === undefined) return '';
        const strVal = String(val);
        if (strVal.includes(',') || strVal.includes('"') || strVal.includes('\n')) {
            return '"' + strVal.replace(/"/g, '""') + '"';
        }
        return strVal;
    }

    resetFileState() {
        this.fileName = '';
        this.fileSize = 0;
        this.parsedHeaders = [];
        this.parsedRows = [];
        this.fieldMappings = [];
    }

    resetAllState() {
        this.resetFileState();
        this.previewData = [];
        this.previewColumns = [];
        this.validationResults = [];
        this.creationResults = [];
        this.processingProgress = { processed: 0, total: 0, success: 0, failed: 0 };
        this.currentPage = 1;
        this.previewFilter = 'all';
        this.isValidated = false;
        this.isProcessing = false;
        this.isCancelled = false;
        this.selectedEppsIdColumn = '';
        this.selectedFeeDateColumn = '';
    }
}
