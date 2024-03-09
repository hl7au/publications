#!/bin/bash

# Clone repositories
git clone https://github.com/HL7/fhir-ig-history-template.git ig-history
git clone https://github.com/hl7au/ig-registry.git ig-registry
git clone https://github.com/hl7au/au-fhir-core ./hl7au/au-fhir-core
rm ./hl7au/au-fhir-core/package-list.json
git clone https://github.com/hl7au/au-fhir-base ./hl7au/au-fhir-base
rm ./hl7au/au-fhir-base/package-list.json

# Make directories and download files
mkdir -p ./webroot/fhir/core
curl --output ./webroot/fhir/core/package-list.json --url https://hl7.org.au/fhir/core/package-list.json
mkdir -p ./webroot/fhir/base
curl --output ./webroot/fhir/base/package-list.json --url https://hl7.org.au/fhir/package-list.json
curl --output ./webroot/fhir/package-feed.xml --url https://hl7.org.au/fhir/package-feed.xml
curl --output ./webroot/fhir/publication-feed.xml --url https://hl7.org.au/fhir/publication-feed.xml

# Generate package registry
java -jar publisher.jar -generate-package-registry ./webroot

# Update and generate for au-fhir-core
cd ./hl7au/au-fhir-core
chmod +x _updatePublisher.sh
./_updatePublisher.sh  -f -y
chmod +x _genonce.sh
./_genonce.sh
cd ../..

# Update and generate for au-fhir-base
cd ./hl7au/au-fhir-base
chmod +x _updatePublisher.sh
./_updatePublisher.sh  -f -y
chmod +x _genonce.sh
./_genonce.sh
cd ../..

# Publish for au-fhir-core and au-fhir-base
java -jar publisher.jar -go-publish -source ./hl7au/au-fhir-core -web ./webroot -history ./ig-history -registry ./ig-registry/fhir-ig-list.json -temp ./temp -templates ./templates
java -jar publisher.jar -go-publish -source ./hl7au/au-fhir-base -web ./webroot -history ./ig-history -registry ./ig-registry/fhir-ig-list.json -temp ./temp -templates ./templates
