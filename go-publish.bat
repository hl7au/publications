git clone https://github.com/HL7/fhir-ig-history-template.git ig-history

git clone https://github.com/hl7au/ig-registry.git ig-registry

git clone https://github.com/hl7au/au-fhir-core %CD%\hl7au\au-fhir-core
del %CD%\hl7au\au-fhir-core\package-list.json

git clone https://github.com/hl7au/au-fhir-base %CD%\hl7au\au-fhir-base
del %CD%\hl7au\au-fhir-base\package-list.json

mkdir %CD%\webroot\fhir
mkdir %CD%\webroot\fhir\core
curl.exe --output %CD%\webroot\fhir\core\package-list.json --url https://hl7.org.au/fhir/core/package-list.json

mkdir %CD%\webroot\fhir\base
curl.exe --output %CD%\webroot\fhir\base\package-list.json --url https://hl7.org.au/fhir/package-list.json

curl.exe --output %CD%\webroot\fhir\package-feed.xml --url https://hl7.org.au/fhir/package-feed.xml
curl.exe --output %CD%\webroot\fhir\publication-feed.xml --url https://hl7.org.au/fhir/publication-feed.xml

java -jar publisher.jar -generate-package-registry %CD%\webroot

cd %CD%\hl7au\au-fhir-core
call _updatePublisher.bat
call _genonce.bat
cd ..\..

cd %CD%\hl7au\au-fhir-base
call _updatePublisher.bat
call _genonce.bat
cd ..\..

java -jar publisher.jar -go-publish -source %CD%\hl7au\au-fhir-core -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates

java -jar publisher.jar -go-publish -source %CD%\hl7au\au-fhir-base -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates