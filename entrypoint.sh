#!/bin/bash -l
set -e -o pipefail

main (){
    cmd=$1
    dir=$2
    ops=$3
    token=$4
    if [ ! -e ${dir} ]; then
        echo "${dir}: No such file or directoy exists";
        exit 1;
    fi
    if [ $GITHUB_EVENT_NAME != "pull_request" ] && 
       [ $GITHUB_EVENT_NAME != "push" ]; then
        echo "Event ${GITHUB_EVENT_NAME} with deck ${cmd} is not supported";
        exit 1;        
    fi

    # TODO: if files to sync don't exists on commits, tell so to stdo
    if [[ $GITHUB_EVENT_NAME = "pull_request" ]]; then
        # get the pull request number 
        pull_number=$(cat $GITHUB_EVENT_PATH | jq .number)

        # get file lists on the pull request we're on 
        files=$(curl -H "Authorization: token $token" https://api.github.com/repos/$GITHUB_REPOSITORY/pulls/$pull_number/files | jq -r ".[] | .filename");
    elif [[ $GITHUB_EVENT_NAME = "push" ]]; then
        files=$(curl -H "Authorization: token $token" https://api.github.com/repos/$GITHUB_REPOSITORY/commits/$GITHUB_SHA |  jq ".files[].filename")
    fi

    
    # execute deck command only for the files in the configured directry
    for file in $files; do
        if [[ $file =~ ${dir}/.+\.(yml|yaml) ]]; then
            echo $file
            case $cmd in
                "validate") deck $cmd $ops -s $file ;; 
                "diff") deck $cmd $ops -s $file ;; # TODO: add a code review comment if a diff exists
                "sync") deploy $cmd $ops $file ;;
                * ) echo "deck $cmd is not supported." && exit 1 ;;
            esac
        fi
    done
}

# decK sync after dry-run and use GitHub Deployment API for visibility
deploy () {
    # dry-run
    deck diff $ops -s $file --non-zero-exit-code

    # only if there is a diff present, then start the process
    if [[ $? = 2 ]]; then
        # create deployment on github
        dep_id=$(curl -X POST https://api.github.com/repos/$GITHUB_REPOSITORY/deployments -H "Authorization: token  $token" -d '{ "ref": "'$GITHUB_REF'", "payload": { "deploy": "migrate" }, "description": "Executing decK sync..." }' | jq -r ".id")

        echo $dep_id

        # deck sync
        deck $cmd $ops -s $file

        # update deployment on github
        curl -X POST  https://api.github.com/repos/$GITHUB_REPOSITORY/deployments/$dep_id/statuses -H "Authorization: token  $token" -d '{ "state": "success", "environment_url": "'$ENV_URL'" }'
    else
        echo "There is no diff to sync"
    fi

  
}

case $1 in
    "ping") deck $1 $3;;
    "validate"|"diff"|"sync") main $1 $2 "$3" $4;;
    * ) echo "deck $1 is not supported." && exit 1 ;;
esac