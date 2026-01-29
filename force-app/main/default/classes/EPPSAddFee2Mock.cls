@IsTest
global class EPPSAddFee2Mock implements HttpCalloutMock {

    public enum Mode {
        SUCCESS,
        FAILURE,
        THROW_EXCEPTION
    }

    private Mode mode;
    private String feeId;
    private String message;

    // === Primary constructor ===
    public EPPSAddFee2Mock(
        Mode mode,
        String feeId,
        String message
    ) {
        this.mode = mode;
        this.feeId = feeId;
        this.message = message;
    }

    // === Convenience SUCCESS constructor ===
    public EPPSAddFee2Mock(String feeId) {
        this(
            EPPSAddFee2Mock.Mode.SUCCESS,
            feeId,
            'Success'
        );
    }

    // === Convenience EXCEPTION constructor ===
    public EPPSAddFee2Mock() {
        this.mode = EPPSAddFee2Mock.Mode.THROW_EXCEPTION;
    }

    global HTTPResponse respond(HTTPRequest req) {

        if (mode == EPPSAddFee2Mock.Mode.THROW_EXCEPTION) {
            throw new CalloutException('Simulated EPPS AddFee2 outage');
        }

        HttpResponse res = new HttpResponse();
        res.setStatusCode(200);
        res.setHeader('Content-Type', 'text/xml; charset=utf-8');

        String msg =
            (mode == EPPSAddFee2Mock.Mode.FAILURE)
                ? 'Failure'
                : message;

        res.setBody(
            '<?xml version="1.0" encoding="utf-8"?>' +
            '<soap:Envelope ' +
                'xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
                'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
              '<soap:Body>' +
                '<AddFee2Response xmlns="http://tempuri.org/">' +
                  '<AddFee2Result>' +
                    '<FeeID>' + feeId + '</FeeID>' +
                    '<Message>' + msg + '</Message>' +
                  '</AddFee2Result>' +
                '</AddFee2Response>' +
              '</soap:Body>' +
            '</soap:Envelope>'
        );

        return res;
    }
}