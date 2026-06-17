function handler(event) {
    var request = event.request;

    var origUri = request.uri;

    var headers = request.headers;

    var newUri = "/";

    if (origUri[origUri.length - 1] == "/")
        origUri = origUri.substring(0, origUri.length - 1);

    var pp = request.uri.split("/");
    for (var i = 1; i < pp.length - 2; i++) {
        newUri += pp[i] + "/";
    }


    if (pp[pp.length - 1] == "" || pp[pp.length - 1] == "core" || pp[pp.length - 1] == "ereq" || pp[pp.length - 1] == "fhir") {
        return request;
    }

    if (event.request.headers.host.value == "terminology.hl7.org.au") {
        var ttype = pp[pp.length - 2];
        var tid = pp[pp.length - 1];

        // erquesting naming convention used to locate lastest version of the artefact
        if (tid.indexOf("au-erequesting") == 0)
            newUri = "https://hl7.org.au/fhir/ereq/" + ttype + "/" + tid;     // AU eRequesting terminology
        else
            newUri = "https://hl7.org.au/fhir/" + ttype + "/" + tid;   // AU Base terminology

        //newUri = "https://tx.hl7.org.au/fhir/" + ttype + "?url=http://terminology.hl7.org.au" + origUri;
    }
    else if (pp[pp.length - 2] == "CapabilityStatement" || pp[pp.length - 2] == "StructureDefinition" || pp[pp.length - 2] == "ValueSet" || pp[pp.length - 2] == "CodeSystem") {
        newUri += (pp[pp.length - 2] + "-" + pp[pp.length - 1]);
        newUri += ".html";
    }

    else {
        newUri = origUri + "/index.html";
    }
    
    var response = {
        statusCode: 302,
        statusDescription: 'Found',
        headers: {
            "location": { "value": newUri }
        }
    };
    return response;

}