/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSAddFee2Mock
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Test class to cover the EPPSAddFee2Mock              
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Scott Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
global class EPPSAddFee2Mock implements HttpCalloutMock {

    public enum Mode {
        SUCCESS,
        FAILURE,
        THROW_EXCEPTION,
		HTTP_ERROR,
		SOAP_FAULT     
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

		if (mode == EPPSAddFee2Mock.Mode.HTTP_ERROR) {
			HttpResponse err = new HttpResponse();
			err.setStatusCode(500);
			err.setStatus('500 Internal Server Error');
			err.setBody('Server exploded');
			return err;
		}

		if (mode == EPPSAddFee2Mock.Mode.SOAP_FAULT) {
			HttpResponse faultRes = new HttpResponse();
			faultRes.setStatusCode(200);
			faultRes.setHeader('Content-Type', 'text/xml; charset=utf-8');

			faultRes.setBody(
				'<?xml version="1.0"?>' +
				'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' +
				'<soap:Body>' +
				'<soap:Fault>' +
				'<faultstring>AddFee2 failed</faultstring>' +
				'</soap:Fault>' +
				'</soap:Body>' +
				'</soap:Envelope>'
			);

			return faultRes;
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