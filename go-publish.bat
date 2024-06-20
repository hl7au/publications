git clone https://github.com/HL7/fhir-ig-history-template.git ig-history

git clone https://github.com/hl7au/ig-registry.git ig-registry

git clone -b 0.4.0-preview https://github.com/hl7au/au-fhir-core %CD%\hl7au\au-fhir-core
del %CD%\hl7au\au-fhir-core\package-list.json

git clone -b 4.2.1-preview https://github.com/hl7au/au-fhir-base %CD%\hl7au\au-fhir-base
del %CD%\hl7au\au-fhir-base\package-list.json

mkdir %CD%\webroot\fhir
mkdir %CD%\webroot\fhir\core
curl.exe --output %CD%\webroot\fhir\core\package-list.json --url https://hl7.org.au/fhir/core/package-list.json

mkdir %CD%\webroot\fhir\base
curl.exe --output %CD%\webroot\fhir\base\package-list.json --url https://hl7.org.au/fhir/package-list.json

curl.exe --output %CD%\webroot\fhir\package-feed.xml --url https://hl7.org.au/fhir/package-feed.xml
curl.exe --output %CD%\webroot\fhir\publication-feed.xml --url https://hl7.org.au/fhir/publication-feed.xml

java -jar publisher.jar -generate-package-registry %CD%\webroot

SET publisher_jar=publisher.jar
SET input_cache_path=%CD%\input-cache
SET JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8
rem SET txoption= -tx https://txreg.azurewebsites.net/txdev

cd %CD%\hl7au\au-fhir-core
JAVA -jar "%input_cache_path%\%publisher_jar%" -ig . %txoption% %*
cd ..\..

cd %CD%\hl7au\au-fhir-base
JAVA -jar "%input_cache_path%\%publisher_jar%" -ig . %txoption% %*
cd ..\..

java -jar "%input_cache_path%\%publisher_jar%" -go-publish -source %CD%\hl7au\au-fhir-core -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates

java -jar "%input_cache_path%\%publisher_jar%" -go-publish -source %CD%\hl7au\au-fhir-base -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates