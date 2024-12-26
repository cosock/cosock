#! /bin/bash


REPO_ROOT="$(dirname $(dirname "$(realpath "${BASH_SOURCE:-$0}")"))"

# install the test server binary in the ./bin directory
if ! command -v ./bin/cosock-test-server 2>&1 >/dev/null
then
    export COSOCK_TEST_SERVER_INSTALL_DIR="${REPO_ROOT}"
    curl --proto '=https' --tlsv1.2 -LsSf \
      https://github.com/cosock/test-http-server/releases/download/v0.1.7/cosock-test-server-installer.sh \
      | sh
fi

if ! [ -f ./cert.pem ]
then
    openssl req \
        -newkey rsa:2048 \
        -x509 \
        -sha256 \
        -days 10000 \
        -nodes \
        -out cert.pem \
        -keyout key.pem \
        -subj "/C=US/ST=MN/L=Minneapolis/O=cosock/CN=cosock/"
fi

$REPO_ROOT/bin/cosock-test-server 8080 &
HTTP_PID=$!
$REPO_ROOT/bin/cosock-test-server 8443 "$REPO_ROOT" &
HTTPS_PID=$!

sleep 1

EXIT_CODE=0
for f in $REPO_ROOT/test/**/*.lua
do
    test_name="$(basename $f)"
    printf "%s\n" $test_name
    ARG=""
    if [ "$test_name" = "http.lua" ] ; then
        ARG="8080"
    fi
    if [[ "$test_name" = https*.lua ]]; then
        ARG="8443"
    fi
    ./lua $f $ARG
    if [ $? != "0" ]; then
      printf "test $test_name failed!!\n"
      EXIT_CODE=1
      break
    fi
done

kill $HTTP_PID
kill $HTTPS_PID
exit $EXIT_CODE
