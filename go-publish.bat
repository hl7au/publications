git clone https://github.com/HL7/fhir-ig-history-template.git ig-history

git clone https://github.com/hl7au/ig-registry.git ig-registry

git clone https://github.com/hl7au/au-fhir-core %CD%\hl7au\au-fhir-core

java -jar publisher.jar -go-publish -source %CD%\hl7au\au-fhir-core -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates