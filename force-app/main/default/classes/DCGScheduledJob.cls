global class DCGScheduledJob implements Schedulable {
    
    private String apiEndpoint;
    private Boolean createLeads;
    private Integer interval;
    private String messageOption;
    
    // Constructor to set parameters
    global DCGScheduledJob(String apiEndpoint, Boolean createLeads, Integer interval, String messageOption) {
        this.apiEndpoint = apiEndpoint;
        this.createLeads = createLeads;
        this.interval = interval;
        this.messageOption = messageOption;
    }
    
    global void execute(SchedulableContext sc) {
        try {
            System.debug('DCG Scheduled Job Started - Endpoint: ' + apiEndpoint);
            
            // Create input for your DCGFlowControlledProcessor
            DCGFlowControlledProcessor.DCGFlowInput input = new DCGFlowControlledProcessor.DCGFlowInput();
            input.apiEndpoint = this.apiEndpoint;
            input.createLeads = this.createLeads;
            input.interval = this.interval;
            input.messageOption = this.messageOption;
            
            // Execute your processor
            List<DCGFlowControlledProcessor.DCGFlowInput> inputs = new List<DCGFlowControlledProcessor.DCGFlowInput>{input};
            List<DCGFlowControlledProcessor.DCGFlowOutput> outputs = DCGFlowControlledProcessor.getDataWithFlowControl(inputs);
            
            // Log results
            if (!outputs.isEmpty()) {
                DCGFlowControlledProcessor.DCGFlowOutput output = outputs[0];
                System.debug('DCG Job Results:');
                System.debug('- Success: ' + output.success);
                System.debug('- Endpoint: ' + output.apiEndpointUsed);
                System.debug('- Records Retrieved: ' + output.totalRecordsRetrieved);
                System.debug('- Leads Created: ' + output.leadsCreated);
                
                if (!output.success) {
                    System.debug('- Error: ' + output.errorMessage);
                }
            }
            
        } catch (Exception e) {
            System.debug('Error in DCG Scheduled Job: ' + e.getMessage());
        }
    }
}