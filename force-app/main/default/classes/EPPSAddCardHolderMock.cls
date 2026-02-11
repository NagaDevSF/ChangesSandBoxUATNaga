/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : EPPSAddCardHolderMock
 * Author          : Shell Black (Scott Fawcett)
 * Created Date    : Jan 27, 2026
 * Last Modified By:
 * Last Modified On: Jan 27, 2026
 * Description     : Test class to cover the EPPSAddCardHolderMock              
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 27, 2026  │ Sean Fawcett │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
@IsTest
public class EPPSAddCardHolderMock implements HttpCalloutMock {

    public enum Mode {
        SUCCESS,
        SOAP_ERROR,
        HTTP_ERROR,
        THROW_EXCEPTION,
		SOAP_FAULT,
		MISSING_RESULT,
		MISSING_BODY,
		BAD_XML,
		FAILURE_RESULT
    }

    private Mode mode;

    public EPPSAddCardHolderMock(Mode mode) {
        this.mode = mode;
    }

    public HTTPResponse respond(HTTPRequest req) {

		// Force transport-level failure (hits try/catch)
		if (mode == EPPSAddCardHolderMock.Mode.THROW_EXCEPTION) {
			throw new System.CalloutException('Simulated EPPS timeout');
		}

		HttpResponse res = new HttpResponse();

		if (mode == EPPSAddCardHolderMock.Mode.HTTP_ERROR) {
			res.setStatusCode(500);
			res.setStatus('500 Internal Server Error');
			res.setBody('Server error');
			return res;
		}

		res.setStatusCode(200);
		res.setStatus('200 OK');

		// ---------------- SOAP FAULT ----------------
		if (mode == EPPSAddCardHolderMock.Mode.SOAP_FAULT) {
			res.setBody(
				'<?xml version="1.0"?>' +
				'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' +
				'<soap:Body>' +
				'<soap:Fault>' +
				'<faultcode>500</faultcode>' +
				'<faultstring>Failure</faultstring>' +
				'</soap:Fault>' +
				'</soap:Body>' +
				'</soap:Envelope>'
			);
			return res;
		}

		// ---------------- BAD XML ----------------
		if (mode == EPPSAddCardHolderMock.Mode.BAD_XML) {
			res.setBody('<<<not xml>>>');
			return res;
		}

		// ---------------- MISSING BODY (optional) ----------------
		if (mode == EPPSAddCardHolderMock.Mode.MISSING_BODY) {
			res.setBody(
				'<?xml version="1.0"?>' +
				'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"/>' 
			);
			return res;
		}

		// ---------------- MISSING RESULT ----------------
		if (mode == EPPSAddCardHolderMock.Mode.MISSING_RESULT) {
			res.setBody(
				'<?xml version="1.0"?>' +
				'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://tempuri.org/">' +
				'<soap:Body>' +
				'<UpdateCardHolderResponse />' +
				'</soap:Body>' +
				'</soap:Envelope>'
			);
			return res;
		}

		String reqBody = req.getBody();

		// ---------------- NORMAL PATH ----------------
		if (mode == EPPSAddCardHolderMock.Mode.SOAP_ERROR) {
			res.setBody(buildSoapError());
		} else if (reqBody != null && reqBody.contains('<AddCardHolder')) {
			res.setBody(buildAddCardHolderSuccess());
		} else if (reqBody != null && reqBody.contains('<UpdateCardHolder')) {
			res.setBody(buildUpdateCardHolderSuccess());
		} else {
			res.setBody(buildAddCardHolderSuccess()); // safe fallback
		}

		return res;
	}

	private static String buildAddCardHolderSuccess() {
		return
			'<?xml version="1.0"?>' +
			'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://tempuri.org/">' +
			'<soap:Body>' +
			'<ns:AddCardHolderResponse>' +
			'<ns:AddCardHolderResult>' +
			'<ns:StatusCode>0</ns:StatusCode>' +
			'<ns:Message>Success</ns:Message>' +
			'</ns:AddCardHolderResult>' +
			'</ns:AddCardHolderResponse>' +
			'</soap:Body>' +
			'</soap:Envelope>';
	}

    // ---------- SOAP PAYLOADS ----------
    private String buildSoapSuccess() {
		return
			'<?xml version="1.0"?>' +
			'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://tempuri.org/">' +
			'<soap:Body>' +
			'<ns:UpdateCardHolderResponse>' +
			'<ns:UpdateCardHolderResult>' +
			'<ns:StatusCode>0</ns:StatusCode>' +
			'<ns:Message>Success</ns:Message>' +
			'</ns:UpdateCardHolderResult>' +
			'</ns:UpdateCardHolderResponse>' +
			'</soap:Body>' +
			'</soap:Envelope>';
	}

	private static String buildUpdateCardHolderSuccess() {
		return
			'<?xml version="1.0"?>' +
			'<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://tempuri.org/">' +
			'<soap:Body>' +
			'<ns:UpdateCardHolderResponse>' +
			'<ns:UpdateCardHolderResult>' +
			'<ns:StatusCode>0</ns:StatusCode>' +
			'<ns:Message>Success</ns:Message>' +
			'</ns:UpdateCardHolderResult>' +
			'</ns:UpdateCardHolderResponse>' +
			'</soap:Body>' +
			'</soap:Envelope>';
	}

    private static String buildSoapError() {
        return
            '<?xml version="1.0" encoding="utf-8"?>' +
            '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">' +
            '<soap:Body>' +
            '<AddCardHolderResponse xmlns="http://tempuri.org/">' +
            '<AddCardHolderResult>' +
            '<Message>Invalid CardHolder</Message>' +
            '</AddCardHolderResult>' +
            '</AddCardHolderResponse>' +
            '</soap:Body>' +
            '</soap:Envelope>';
    }
}