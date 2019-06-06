#!/bin/bash

CONSOLE_RED="\033[2;31m"
CONSOLE_GREEN="\033[2;32m"
CONSOLE_CLEAR="\033[0m"
CONFIG_FILE='.gitbuilder'
QUERY_TIMEOUT_SECONDS=5
CONNECTION_STATUS=0

check_auth () {
    CONNECTION_STATUS=$(curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" --write-out %{http_code} --silent --output /dev/null "$JENKINS_SERVER/user/$JENKINS_USERNAME/configure")
    if [[ "$CONNECTION_STATUS" -eq 200 ]]; then
        return 1
    fi

    return 0
}

notify() {
   osascript -e 'display notification "'"$2"'" with title "'"$1"'"'
}

check_build()
{
    JOB_STATUS_JSON=`curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" --silent "${JENKINS_SERVER}${JOB_QUERY}${BUILD_STATUS_QUERY}"`
    LAST_STABLE_BUILD_JSON=`curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" --silent "${JENKINS_SERVER}${JOB_QUERY}${LAST_STABLE_BUILD_NUMBER_QUERY}"`
    GOOD_BUILD="${CONSOLE_GREEN}Last build successful. "
    BAD_BUILD="${CONSOLE_RED}Last build failed. "
    CLEAR_COLOURS=${CONSOLE_CLEAR}
    RESULT=`echo "${JOB_STATUS_JSON}" | sed -n 's/.*"result":\([\"A-Za-z]*\),.*/\1/p'`

    CURRENT_BUILD_NUMBER=${CURRENT_BUILD_JSON}
    LAST_STABLE_BUILD_NUMBER=${LAST_STABLE_BUILD_JSON}
    LAST_BUILD_STATUS=${GOOD_BUILD}


    echo "${LAST_STABLE_BUILD_NUMBER}" | grep "is not available" > /dev/null
    GREP_RETURN_CODE=$?
    if [ ${GREP_RETURN_CODE} -ne 0 ]; then
        if [ `expr ${CURRENT_BUILD_NUMBER} - 1` -gt ${LAST_STABLE_BUILD_NUMBER} ]; then
            LAST_BUILD_STATUS=${BAD_BUILD}
        fi
    fi

    if [ "${RESULT}" = "null" ]; then
        printf "."
    elif [ "${RESULT}" = "\"SUCCESS\"" ]; then
        echo ""
        echo -e "${LAST_BUILD_STATUS}${JOB} ${CURRENT_BUILD_NUMBER} completed successfully.${CLEAR_COLOURS}"

        PREV_ADDR=`echo "${JOB_STATUS_JSON}" | cut -d "'" -f4`

        notify "Build $NEW_BUILD_ID successfuly!" "$PREV_ADDR"
        echo -e "Address: $PREV_ADDR"

        exit 0
    elif [ "${RESULT}" = "\"FAILURE\"" ]; then
        echo ""
        LAST_BUILD_STATUS=${BAD_BUILD}
        echo -e "${LAST_BUILD_STATUS}${JENKINS_JOB} ${CURRENT_BUILD_NUMBER} failed${CLEAR_COLOURS}"
        notify "Build $NEW_BUILD_ID failed!" "Branch $BRANCH"
        exit 1
    else
        echo ""
        LAST_BUILD_STATUS=${BAD_BUILD}
        echo -e "${LAST_BUILD_STATUS}${JENKINS_JOB} ${CURRENT_BUILD_NUMBER} status unknown - '${RESULT}'${CLEAR_COLOURS}"
        exit 1
    fi
}


if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${CONSOLE_RED}Configuration doesn't exists!${CONSOLE_CLEAR}"

    while [[ ! -f "$CONFIG_FILE" ]] || [[ "$CONNECTION_STATUS" -ne 200 ]]; do
        read -p "Enter Jenkins URI: " JENKINS_SERVER
        read -p "Enter username: " JENKINS_USERNAME
        read -p "Enter token: " JENKINS_TOKEN
        read -p "Enter job name: " JENKINS_JOB

        $(check_auth)
        RESULT="$?"

        if [[ "$RESULT" -eq 1 ]]; then
            CONNECTION_STATUS=200
            echo "export JENKINS_SERVER=\"$JENKINS_SERVER\""  >> $CONFIG_FILE
            echo "export JENKINS_USERNAME=\"$JENKINS_USERNAME\""  >> $CONFIG_FILE
            echo "export JENKINS_TOKEN=\"$JENKINS_TOKEN\""  >> $CONFIG_FILE
            echo "export JENKINS_JOB=\"$JENKINS_JOB\"" >> $CONFIG_FILE
        else
            echo -e "${CONSOLE_RED}Configuration failed!${CONSOLE_CLEAR}"
        fi
    done
fi

source "$CONFIG_FILE"
$(check_auth)

if [[ "$?" -eq 1 ]]; then
    echo -e "${CONSOLE_GREEN}Authentication test: SUCCESS${CONSOLE_CLEAR}"
else
    echo "Config file cleaned!"
    rm "$CONFIG_FILE"
    exit 1
fi

BRANCH=`git rev-parse --abbrev-ref HEAD`
echo "Jenkins server: $JENKINS_SERVER"
echo "Branch: $BRANCH"

JJ="/job/$JENKINS_JOB"
JOB_QUERY=${JJ// /"%20"}
BUILD_STATUS_QUERY=/lastBuild/api/json

CRUMB=$(curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" -s "$JENKINS_SERVER/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")
BUILD_TASK_QUERY="/buildWithParameters?BRANCH=$BRANCH"
BUILD_TASK_LOCATION=`curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" -X POST -H "$CRUMB" -s -i "${JENKINS_SERVER}${JOB_QUERY}${BUILD_TASK_QUERY}"`

QUEUE=$(echo "$BUILD_TASK_LOCATION" | grep Location)
QUEUE_ITEM="${QUEUE:10}"
QUEUE_QUERY="api/json"
QUEUE_ITEM_ADDRESS=$(echo "$QUEUE_ITEM" | tr -d '\r' | tr -d '\n')
QUEUE_ITEM_ADDRESS="$QUEUE_ITEM_ADDRESS$QUEUE_QUERY"

echo "Queue endpoint: $QUEUE_ITEM_ADDRESS"

printf "Waiting."

BUILD_NEW_ITEM=""
while [[ ! $BUILD_NEW_ITEM =~ "executable" ]]
do
    BUILD_NEW_ITEM=`curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" --silent "$QUEUE_ITEM_ADDRESS"`
    printf "."
    $(sleep 1)
done

NEW_BUILD_ID=$(echo $BUILD_NEW_ITEM | sed 's/.*executable.*number\"://' | cut -d ',' -f1)
echo  ""
echo "New build id: $NEW_BUILD_ID"

CURRENT_BUILD_NUMBER_QUERY=/lastBuild/buildNumber
CURRENT_BUILD_JSON=`curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" --silent "${JENKINS_SERVER}${JOB_QUERY}${CURRENT_BUILD_NUMBER_QUERY}"`

LAST_STABLE_BUILD_NUMBER_QUERY=/lastStableBuild/buildNumber
LAST_STABLE_BUILD_JSON=`curl -u "$JENKINS_USERNAME:$JENKINS_TOKEN" --silent "${JENKINS_SERVER}${JOB_QUERY}${LAST_STABLE_BUILD_NUMBER_QUERY}"`

printf "Building"

while [ true ]
do
    check_build
    sleep ${QUERY_TIMEOUT_SECONDS}
done