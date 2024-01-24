git clone https://github.com/HL7/fhir-ig-history-template.git ig-history

git clone https://github.com/hl7au/ig-registry.git ig-registry

git clone https://github.com/hl7au/au-fhir-core %CD%\hl7au\au-fhir-core
ren CD%\hl7au\au-fhir-core\package-list.json CD%\hl7au\au-fhir-core\package-list.json.000

java -jar publisher.jar -generate-package-registry %CD%\webroot

curl.exe --output %CD%\webroot\fhir\core\package-list.json --url https://hl7.org.au/fhir/core/package-list.json
curl.exe --output %CD%\webroot\fhir\package-feed.xml --url https://hl7.org.au/fhir/package-feed.xml
curl.exe --output %CD%\webroot\fhir\publication-feed.xml --url https://hl7.org.au/fhir/publication-feed.xml


cd %CD%\hl7au\au-fhir-core
call _updatePublisher.bat
call _genonce.bat
cd ..\..

java -jar publisher.jar -go-publish -source %CD%\hl7au\au-fhir-core -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates