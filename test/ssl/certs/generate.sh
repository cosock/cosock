#!/bin/sh

##### Generate Test Certificates and Private Keys #####

# Remove all existing generated certs, csrs, private keys, etc
rm -rf csr newcerts private index.txt* index.txt.attr* serial*

# Create necessary directories
mkdir -p csr newcerts private

# Create DB index and serial files
touch index.txt
touch index.txt.attr
echo '1000' > serial

# Generate encrypted private keys for all root, intermediate, and leaf entities using "cosock" for passphrase
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes256 -pass pass:"cosock" -out private/root.key.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes256 -pass pass:"cosock" -out private/intermediate1.key.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes256 -pass pass:"cosock" -out private/intermediate2.key.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes256 -pass pass:"cosock" -out private/leafA.key.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes256 -pass pass:"cosock" -out private/leafB.key.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes256 -pass pass:"cosock" -out private/leafC.key.pem
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -aes256 -pass pass:"cosock" -out private/leafD.key.pem

# Create and self-signed root certificate
openssl req -new -config openssl.cnf -x509 -extensions v3_ca -key private/root.key.pem -passin pass:"cosock" -subj "/C=US/ST=Minnesota/L=Minneapolis/O=Cosock & Devices/CN=Cosock Test Root Certificate" -days 3652 -set_serial 0 -out root.crt.pem

# Generate CSR's for intermediate and leaf certificates
openssl req -new -key private/intermediate1.key.pem -passin pass:"cosock" -subj "/C=US/ST=Minnesota/L=Minneapoli/O=Cosock & Devices/CN=Cosock Test Intermediate Certificate 1" -out csr/intermediate1.csr.pem
openssl req -new -key private/intermediate2.key.pem -passin pass:"cosock" -subj "/C=US/ST=Minnesota/L=Minneapolis/O=Cosock & Devices/CN=Cosock Test Intermediate Certificate 2" -out csr/intermediate2.csr.pem
openssl req -new -key private/leafA.key.pem -passin pass:"cosock" -subj "/C=US/ST=Minnesota/L=Minneapolis/O=Cosock & Devices/CN=Cosock Test Leaf Certificate A" -out csr/leafA.csr.pem
openssl req -new -key private/leafB.key.pem -passin pass:"cosock" -subj "/C=US/ST=Minnesota/L=Minneapolis/O=Cosock & Devices/CN=Cosock Test Leaf Certificate B" -out csr/leafB.csr.pem
openssl req -new -key private/leafC.key.pem -passin pass:"cosock" -subj "/C=US/ST=Minnesota/L=Minneapolis/O=Cosock & Devices/CN=Cosock Test Leaf Certificate C" -out csr/leafC.csr.pem
openssl req -new -key private/leafD.key.pem -passin pass:"cosock" -subj "/C=US/ST=Minnesota/L=Minneapolis/O=Cosock & Devices/CN=Cosock Test Leaf Certificate D" -out csr/leafD.csr.pem 

# Sign intermeidiate certificates 1 and 2 with root certificate. Include text output for added parsing test coverage.
openssl ca -batch -config openssl.cnf -extensions v3_intermediate_ca -in csr/intermediate1.csr.pem -cert root.crt.pem -keyfile private/root.key.pem -passin pass:"cosock" -out intermediate1.crt.pem
openssl ca -batch -config openssl.cnf -extensions v3_intermediate_ca -in csr/intermediate2.csr.pem -cert root.crt.pem -keyfile private/root.key.pem -passin pass:"cosock" -out intermediate2.crt.pem

# Sign leaf certificates A and B with intermediate certificate 1
openssl ca -batch -config openssl.cnf -extensions end_entity_cert -notext -in csr/leafA.csr.pem -cert intermediate1.crt.pem -keyfile private/intermediate1.key.pem -passin pass:"cosock" -out leafA.crt.pem
openssl ca -batch -config openssl.cnf -extensions end_entity_cert -notext -in csr/leafB.csr.pem -cert intermediate1.crt.pem -keyfile private/intermediate1.key.pem -passin pass:"cosock" -out leafB.crt.pem

# Sign leaf certificate C and D with intermediate certificate 2
openssl ca -batch -config openssl.cnf -extensions end_entity_cert -notext -in csr/leafC.csr.pem -cert intermediate2.crt.pem -keyfile private/intermediate2.key.pem -passin pass:"cosock" -out leafC.crt.pem
openssl ca -batch -config openssl.cnf -extensions end_entity_cert -notext -in csr/leafD.csr.pem -cert intermediate2.crt.pem -keyfile private/intermediate2.key.pem -passin pass:"cosock" -out leafD.crt.pem

# Verify certificate chains
openssl verify -CAfile root.crt.pem -untrusted intermediate1.crt.pem leafA.crt.pem
openssl verify -CAfile root.crt.pem -untrusted intermediate1.crt.pem leafB.crt.pem
openssl verify -CAfile root.crt.pem -untrusted intermediate2.crt.pem leafC.crt.pem
openssl verify -CAfile root.crt.pem -untrusted intermediate2.crt.pem leafD.crt.pem

# Create chained certificate files
cat leafA.crt.pem intermediate1.crt.pem > leafA_intermediate1_chain.crt.pem
cat leafB.crt.pem intermediate1.crt.pem > leafB_intermediate1_chain.crt.pem
cat leafC.crt.pem intermediate2.crt.pem > leafC_intermediate2_chain.crt.pem
cat leafD.crt.pem intermediate2.crt.pem > leafD_intermediate2_chain.crt.pem

# We only care about certificates and private keys for testing, remove everything else
rm -rf csr newcerts index.txt* index.txt.attr* serial*
