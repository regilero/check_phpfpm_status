#!/bin/bash
ok=0;
nok=0;

PORT_PHPFPM=9001
PORT_NGINX_CLASSIC=8801
PORT_NGINX_CLASSICSSL=8443
PORT_NGINX_TLS11=9443
PORT_NGINX_BADSSL=10443

function test_last_check_code() {

    if [ "x${TEST_CODE}" == "x${EXPECTED_CODE}" ]; then
        return 0
    else
        echo " ^^^^" 2>&1
        echo " \=> FAILED TEST : last Check result ("${TEST_CODE}") is not the expected one ("${EXPECTED_CODE}")" 2>&1
        echo "  **** FAILURE **************************************************"
        echo ""
        return 1
    fi
}

function test_last_check_text() {
    if [ "x${TEST_TEXT}" == "x" ]; then
        echo " ^^^^" 2>&1
        echo " \=> FAILED TEST : no output" 2>&1
        echo "  **** FAILURE **************************************************"
        echo ""
        return 1
    fi
    if [[ ${TEST_TEXT} == *${EXPECTED_TEXT}* ]]; then
        echo "Yep"
        return 0
    else
        echo " ^^^^" 2>&1
        echo " \=> FAILED TEST : last Check result ("${TEST_TEXT}") is not the expected one ("${EXPECTED_TEXT}")" 2>&1
        echo "  **** FAILURE **************************************************"
        echo ""
        return 1
    fi
}

function test_result() {
    test_last_check_code
    if [ "x${?}" == "x0" ]; then
        test_last_check_text
        if [ "x${?}" == "x0" ]; then
            echo " \=> TEST is OK ("${TEST_CODE}" == "${EXPECTED_CODE}") and text contains '${EXPECTED_TEXT}'"
            echo ""
            let ok+=1
            return 0
        fi
    fi
    let nok+=1
    return 1
}

function run_test() {
    EXPECTED_CODE=$1
    echo "TESTING: "$TEST
    TEST_TEXT=""
    TEST_CODE=-1
    TEST_TEXT=`${TEST}`
    TEST_CODE=${?}
    # debug
    echo ${TEST_TEXT}
    # now check everything was as expected
    test_result
}

echo " ------------------------------------------------------------------------"
echo "                FASTCGI MODE"
echo " ------------------------------------------------------------------------"
echo
echo " * Checking required args in fastcgi mode -------------------------------"
TEST="./check_phpfpm_status.pl --fastcgi"
EXPECTED_TEXT="-H host argument required"
run_test 3

echo " * Checking phpfpm in fastcgi mode --------------------------------------"
TEST="./check_phpfpm_status.pl -H 127.0.0.1 -p ${PORT_PHPFPM} -u /check-status --fastcgi"
EXPECTED_TEXT="PHP-FPM OK"
run_test 0

echo " * Request the phpinfo page, -will fail the check -----------------------"
TEST="./check_phpfpm_status.pl -H 127.0.0.1 -p ${PORT_PHPFPM} -u /usr/src/app/index.php --fastcgi"
EXPECTED_TEXT="it's an HTML page"
run_test 2

echo " * Checking phpfpm in fastcgi mode, we should have name of the pool------"
TEST="./check_phpfpm_status.pl -H 127.0.0.1 -p ${PORT_PHPFPM} -u /check-status --fastcgi"
EXPECTED_TEXT="PHP-FPM OK - www"
run_test 0

echo " ------------------------------------------------------------------------"
echo "                HTTP MODE"
echo " ------------------------------------------------------------------------"
echo
echo
echo " * Checking required args in http mode ----------------------------------"
TEST="./check_phpfpm_status.pl"
EXPECTED_TEXT="-H host argument required"
run_test 3

echo " * Checking phpfpm in http mode : no server name, should fail ----------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSIC} -s -u /check-status"
EXPECTED_TEXT="400 Bad Request"
run_test 2

echo " * Checking phpfpm in http mode : bad server name, should fail ----------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSIC} -s doesnotexists.example.com -u /check-status"
EXPECTED_TEXT="404 Not Found"
run_test 2

echo " * Checking phpfpm in http mode : right server name ---------------------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSIC} -s phpfpm.example.com -u /check-status"
EXPECTED_TEXT="PHP-FPM OK - www"
run_test 0

echo " * Checking phpfpm in http mode : right server name, bad url-------------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSIC} -s phpfpm.example.com -u /checkstatus"
EXPECTED_TEXT="404 Not Found"
run_test 2

echo " ------------------------------------------------------------------------"
echo "                MISC OPTIONS"
echo " ------------------------------------------------------------------------"
echo " * Checking help option -------------------------------------------------"
TEST="./check_phpfpm_status.pl -h"
EXPECTED_TEXT="3 items can be managed on this check, this is why -w and -c parameters are using 3 values thresolds"
run_test 3

echo " * Checking help option -------------------------------------------------"
TEST="./check_phpfpm_status.pl --help"
EXPECTED_TEXT="This will lead to CRITICAL if you have 0 Idle process"
run_test 3

echo " * Checking version option ----------------------------------------------"
TEST="./check_phpfpm_status.pl -V"
EXPECTED_TEXT="check_phpfpm_status.pl version : 0.12"
run_test 3

echo " * Checking version option ----------------------------------------------"
TEST="./check_phpfpm_status.pl --version"
EXPECTED_TEXT="check_phpfpm_status.pl version : 0.12"
run_test 3

#FIXME: TODO
#echo " * Checking user/password/realm HTTP Auth -------------------------------------"
#TEST="./check_phpfpm_status.pl -H 127.0.0.1 -U foo -P bar -r zorg -p ${PORT_NGINX_CLASSIC} -s phpfpm.example.com -u /checkstatus"
#EXPECTED_TEXT="PHP-FPM OK - www"
#run_test 0

# FIXME: test timeout also?

echo " ------------------------------------------------------------------------"
echo "                THRESOLDS"
echo " ------------------------------------------------------------------------"
echo

BASE_TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSIC} -s phpfpm.example.com -u /check-status"

echo " * Checking phpfpm in http mode : bad thresolds v1a ---------------------"
TEST=${BASE_TEST}" -w 1,1,3 -c 0,2,2"
EXPECTED_TEXT="Check warning and critical values for MaxQueue (3rd part of thresold), warning level must be < crit level"
run_test 3

echo " * Checking phpfpm in http mode : bad thresolds v1b ---------------------"
TEST=${BASE_TEST}" -w 1,1,3 -c 0,2,3"
EXPECTED_TEXT="Check warning and critical values for MaxQueue (3rd part of thresold), warning level must be < crit level"
run_test 3

echo " * Checking phpfpm in http mode : bad thresolds v2a ---------------------"
TEST=${BASE_TEST}" -w 1,3,1 -c 0,2,2"
EXPECTED_TEXT="Check warning and critical values for MaxProcesses (2nd part of thresold), warning level must be < crit level"
run_test 3

echo " * Checking phpfpm in http mode : bad thresolds v2b ---------------------"
TEST=${BASE_TEST}" -w 1,3,1 -c 0,3,2"
EXPECTED_TEXT="Check warning and critical values for MaxProcesses (2nd part of thresold), warning level must be < crit level"
run_test 3

echo " * Checking phpfpm in http mode : bad thresolds v3a ---------------------"
TEST=${BASE_TEST}" -w 0,1,1 -c 1,2,2"
EXPECTED_TEXT="Check warning and critical values for IdleProcesses (1st part of thresold), warning level must be > crit level"
run_test 3

echo " * Checking phpfpm in http mode : bad thresolds v3b ---------------------"
TEST=${BASE_TEST}" -w 1,1,1 -c 1,2,2"
EXPECTED_TEXT="Check warning and critical values for IdleProcesses (1st part of thresold), warning level must be > crit level"
run_test 3

echo " * Checking phpfpm in http mode : Idle OK -------------------------------"
TEST=${BASE_TEST}" -w -1,-1,-1 -c 0,20,20"
EXPECTED_TEXT="PHP-FPM OK - www"
run_test 0

echo " * Checking phpfpm in http mode : Idle should warn  ---------------------"
TEST=${BASE_TEST}" -w 10,-1,-1 -c 0,20,20"
EXPECTED_TEXT="PHP-FPM WARNING - Idle workers are low"
run_test 1

echo " * Checking phpfpm in http mode : Idle should be critical ---------------"
TEST=${BASE_TEST}" -w 20,-1,-1 -c 10,20,20"
EXPECTED_TEXT="PHP-FPM CRITICAL - Idle workers are critically low"
run_test 2

echo " ------------------------------------------------------------------------"
echo "                HTTPS MODE"
echo " ------------------------------------------------------------------------"
echo

echo " * Checking phpfpm in https mode, https on http port failure--------------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSIC} -s phpfpm.example.com -u /check-status --ssl"
EXPECTED_TEXT="500 Can't connect to phpfpm.example.com"
run_test 2

echo " * Checking phpfpm in https mode, no peer check -------------------------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSICSSL} -s phpfpm.example.com -u /check-status --ssl"
EXPECTED_TEXT="PHP-FPM OK - www"
run_test 0

# This one will work because we do not check the SSL certificate by default
# this container has a certificate with a wrong peer name
echo " * Checking phpfpm in https mode, no peer check on bad ssl --------------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_BADSSL} -s phpfpm.example.com -u /check-status --ssl"
EXPECTED_TEXT="PHP-FPM OK - www"
run_test 0

echo " * Checking phpfpm in https mode, peer check failure on bad ssl ---------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_BADSSL} -s phpfpm.example.com -u /check-status --ssl --verifyssl 1"
EXPECTED_TEXT="(certificate verify failed)"
run_test 2

# FIXME: Arrgh: currently I cannot get ssl verifications working...
echo " * Checking https mode, request google, just for the certs part ---------"
TEST="./check_phpfpm_status.pl -t 15 -H www.google.com -u /wont-work --ssl --verifyssl 1"
EXPECTED_TEXT="PHP-FPM CRITICAL - 404 Not Found"
echo " \=> SKIPPED: this test does not work currently"
echo
#run_test 2

# FIXME: Arrgh: currently I cannot get ssl verifications working...
echo " * Checking phpfpm in https mode, verifyssl ok on classical -------------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSICSSL} -s phpfpm.example.com -u /check-status --ssl --verifyssl 1"
EXPECTED_TEXT="PHP-FPM OK - www"
echo " \=> SKIPPED: this test does not work currently"
echo
#run_test 0

echo " * Checking phpfpm in https mode, bad SSL versions failure --------------"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_CLASSICSSL} -s phpfpm.example.com -u /check-status --ssl SSLV3"
EXPECTED_TEXT="500 Can't connect to phpfpm.example.com"
run_test 2

echo " * Checking phpfpm in https mode, bad TLS1.2 versions ok in TLS1.1 only server"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_TLS11} -s phpfpm.example.com -u /check-status --ssl TLSv1_2"
EXPECTED_TEXT="500 Can't connect to phpfpm.example.com"
run_test 2

echo " * Checking phpfpm in https mode, ok TLS1.1 in TLS1.1 only server server -"
TEST="./check_phpfpm_status.pl -t 15 -H 127.0.0.1 -p ${PORT_NGINX_TLS11} -s phpfpm.example.com -u /check-status --ssl TLSv1_1"
EXPECTED_TEXT="PHP-FPM OK - www"
run_test 0

echo
echo "**** FINAL TESTS STATUS ****"
echo " TESTS OK: ${ok}"
echo " FAILED TESTS: ${nok}"
if [ "x${nok}" == "x0" ]; then
    echo "++++ SUCCESS ++++" 2>&1
    exit 0
else
    echo "---- FAILURE ---- (${nok} fail(s))" 2>&1
    exit 1
fi