public class HTTPCalloutInvocable {
    
    @InvocableMethod(label='HTTP Callout' description='Makes HTTP callout to external system')
    public static List<CalloutResponse> makeHttpCallout(List<CalloutRequest> requests) {
        List<CalloutResponse> responses = new List<CalloutResponse>();
        
        for (CalloutRequest request : requests) {
            CalloutResponse response = new CalloutResponse();
            
            try {
                Http http = new Http();
                HttpRequest httpReq = new HttpRequest();
                
                httpReq.setEndpoint(request.endpoint);
                httpReq.setMethod(request.httpMethod);
                
                if (String.isNotBlank(request.requestBody)) {
                    httpReq.setBody(request.requestBody);
                }
                
                if (String.isNotBlank(request.contentType)) {
                    httpReq.setHeader('Content-Type', request.contentType);
                }
                
                if (request.timeout != null && request.timeout > 0) {
                    httpReq.setTimeout(request.timeout);
                } else {
                    httpReq.setTimeout(120000);
                }
                
                httpReq.setHeader('Accept', 'application/json');
                
                HttpResponse httpRes = http.send(httpReq);
                
                response.statusCode = httpRes.getStatusCode();
                response.responseBody = httpRes.getBody();
                response.isSuccess = (httpRes.getStatusCode() >= 200 && httpRes.getStatusCode() < 300);
                
                if (!response.isSuccess) {
                    response.errorMessage = 'HTTP ' + httpRes.getStatusCode() + ': ' + httpRes.getStatus();
                }
                
            } catch (Exception e) {
                response.isSuccess = false;
                response.errorMessage = e.getMessage();
                response.statusCode = 0;
            }
            
            responses.add(response);
        }
        
        return responses;
    }
    
    public class CalloutRequest {
        @InvocableVariable(label='Endpoint URL' required=true)
        public String endpoint;
        
        @InvocableVariable(label='HTTP Method' required=true)
        public String httpMethod;
        
        @InvocableVariable(label='Request Body')
        public String requestBody;
        
        @InvocableVariable(label='Content Type')
        public String contentType;
        
        @InvocableVariable(label='Timeout')
        public Integer timeout;
    }
    
    public class CalloutResponse {
        @InvocableVariable(label='Status Code')
        public Integer statusCode;
        
        @InvocableVariable(label='Response Body')
        public String responseBody;
        
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess;
        
        @InvocableVariable(label='Error Message')
        public String errorMessage;
        
        public CalloutResponse() {
            this.isSuccess = false;
            this.statusCode = 0;
            this.responseBody = '';
            this.errorMessage = '';
        }
    }
}