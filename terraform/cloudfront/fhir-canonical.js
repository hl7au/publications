function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    var origUri = request.uri;
    if (origUri.length > 1 && origUri[origUri.length - 1] === "/") {
        origUri = origUri.substring(0, origUri.length - 1);
    }

    var pp = request.uri.split("/");
    var lastSeg = pp[pp.length - 1];

    // roots / directories -> let the origin serve index.html
    if (lastSeg === "" || lastSeg === "core" || lastSeg === "ereq" || lastSeg === "fhir") {
        return request;
    }

    var rt = pp[pp.length - 2];

    // base = everything except the last two segments (handles sub-IGs, e.g. /fhir/core/...)
    var base = "/";
    for (var i = 1; i < pp.length - 2; i++) {
        base += pp[i] + "/";
    }

    // terminology.hl7.org.au: the artifacts live under hl7.org.au/fhir -> cross-host redirect
    if (host === "terminology.hl7.org.au") {
        var tbase = (lastSeg.indexOf("au-erequesting") === 0) ? "/fhir/ereq/" : "/fhir/";
        return redirect("https://hl7.org.au" + tbase + rt + "/" + lastSeg);
    }

    // versioned canonical: <RT>/<id>|<version>  (raw "|" or url-encoded "%7C")
    // -> that version's publication folder (/fhir/<version>/...). Targets already exist;
    // version string must match the folder name (true for all semver-style releases).
    var sep = lastSeg.indexOf("|");
    var sepLen = 1;
    if (sep === -1) { sep = lastSeg.indexOf("%7C"); sepLen = 3; }
    if (sep === -1) { sep = lastSeg.indexOf("%7c"); sepLen = 3; }
    if (sep > -1) {
        var rid = lastSeg.substring(0, sep);
        var rver = lastSeg.substring(sep + sepLen);
        var vTarget = base + rver + "/" +
            (rt === "ImplementationGuide" ? "index.html" : rt + "-" + rid + ".html");
        return redirect(vTarget);
    }

    // unversioned conformance resources -> current-version page at the canonical root
    if (rt === "CapabilityStatement" || rt === "StructureDefinition" || rt === "ValueSet" || rt === "CodeSystem") {
        return redirect(base + rt + "-" + lastSeg + ".html");
    }

    // everything else -> directory index (static index.html stub from the IG publisher)
    return redirect(origUri + "/index.html");
}

function redirect(location) {
    return {
        statusCode: 302,
        statusDescription: "Found",
        headers: { "location": { "value": location } }
    };
}
