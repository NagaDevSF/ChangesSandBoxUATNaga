@IsTest
public class EPPSAddCardHolderMock implements HttpCalloutMock {

    public enum Mode {
        SUCCESS,
        SOAP_ERROR,
        HTTP_ERROR,
        THROW_EXCEPTION
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

        if (mode == EPPSAddCardHolderMock.Mode.SOAP_ERROR) {
            res.setBody(buildSoapError());
        } else {
            res.setBody(buildSoapSuccess());
        }

        return res;
    }

    // ---------- SOAP PAYLOADS ----------

    private static String buildSoapSuccess() {
        return
            '<?xml version="1.0" encoding="utf-8"?>' +
            '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
            'xmlns:xsd="http://www.w3.org/2001/XMLSchema">' +
            '<soap:Body>' +
            '<AddCardHolderResponse xmlns="http://tempuri.org/">' +
            '<AddCardHolderResult>' +
            '<CardHolderID>10006</CardHolderID>' +
            '<Message>Success</Message>' +
            '<StatusCode>Pending</StatusCode>' +
            '</AddCardHolderResult>' +
            '</AddCardHolderResponse>' +
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