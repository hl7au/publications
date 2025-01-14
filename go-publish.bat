git clone https://github.com/HL7/fhir-ig-history-template.git ig-history

git clone https://github.com/hl7au/ig-registry.git ig-registry

rem git clone -b 5.0.0 https://github.com/hl7au/au-fhir-core %CD%\hl7au\au-fhir-core
rem del %CD%\hl7au\au-fhir-core\package-list.json

rem git clone -b ft-cicd https://github.com/hl7au/au-fhir-erequesting %CD%\hl7au\au-fhir-erequesting
rem del %CD%\hl7au\au-fhir-erequesting\package-list.json

git clone -b 5.0.0 https://github.com/hl7au/au-fhir-base %CD%\hl7au\au-fhir-base
del %CD%\hl7au\au-fhir-base\package-list.json

mkdir %CD%\webroot\fhir

rem mkdir %CD%\webroot\fhir\core
rem curl.exe --output %CD%\webroot\fhir\core\package-list.json --url https://hl7.org.au/fhir/core/package-list.json

rem mkdir %CD%\webroot\fhir\ereq
rem curl.exe --output %CD%\webroot\fhir\core\package-list.json --url https://hl7.org.au/fhir/ereq/package-list.json

rem mkdir %CD%\webroot\fhir\base
curl.exe --output %CD%\webroot\fhir\base\package-list.json --insecure --url https://hl7.org.au/fhir/package-list.json
curl.exe --output %CD%\webroot\fhir\package-feed.xml  --insecure --url https://hl7.org.au/fhir/package-feed.xml
curl.exe --output %CD%\webroot\fhir\publication-feed.xml  --insecure --url https://hl7.org.au/fhir/publication-feed.xml

java -jar publisher.jar -generate-package-registry %CD%\webroot

SET publisher_jar=publisher.jar
SET input_cache_path=%CD%\input-cache
SET JAVA_TOOL_OPTIONS=-Dfile.encoding=UTF-8
rem SET txoption= -tx https://txreg.azurewebsites.net/txdev

cd %CD%\hl7au\au-fhir-base
JAVA -jar "%input_cache_path%\%publisher_jar%" -ig . %txoption% %*
cd ..\..

rem cd %CD%\hl7au\au-fhir-core
rem JAVA -jar "%input_cache_path%\%publisher_jar%" -ig . %txoption% %*
rem cd ..\..

rem cd %CD%\hl7au\au-fhir-erequesting
rem JAVA -jar "%input_cache_path%\%publisher_jar%" -ig . %txoption% %*
rem cd ..\..

java -jar "%input_cache_path%\%publisher_jar%" -go-publish -source %CD%\hl7au\au-fhir-base -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates

rem java -jar "%input_cache_path%\%publisher_jar%" -go-publish -source %CD%\hl7au\au-fhir-core -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates

rem java -jar "%input_cache_path%\%publisher_jar%" -go-publish -source %CD%\hl7au\au-fhir-erequesting -web %CD%\webroot -history %CD%\ig-history -registry %CD%\ig-registry\fhir-ig-list.json -temp %CD%\temp -templates %CD%\templates
