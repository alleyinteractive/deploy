#!/bin/bash -e -o pipefail
#
# Deploy a branch from Alley to an upstream VIP mirror
#
# Usage:
#   deploy-vip.sh [<pr>]
#
# Options: 
#   pr        Instead of pushing directly to the branch, create a PR.
#
# Examples:
#   deploy-vip.sh
#   deploy-vip.sh pr
#
# Reference:
# https://github.com/alleyinteractive/deploy
# https://infosphere.alley.co/production/standards/deployment.html

# Set git config variables
git config user.email "9137529+alley-ci@users.noreply.github.com"
git config user.name "Alley CI"
git config push.default simple

# Check for the presence of a pull request flag (pr) and proceed accordingly
PR=false
if [[ "$1" == "pr" || "$1" == "-pr" ]]; then
	PR=true
    VIP_PR_BRANCH="merge/"
    
    # Append Jira ticket in merge branch name if present
    JIRA_TICKET="$( echo $BUDDY_EXECUTION_REVISION_MESSAGE | grep -oE -m 1 "[A-Za-z]+-[0-9]+" | head -1 | tr ' ' '-' | xargs echo -n )"

    if [ -n $JIRA_TICKET ]; then
        VIP_PR_BRANCH+="${JIRA_TICKET}/"
    fi

    # Append the (short) SHA and unix timestamp to ensure uniqueness
    VIP_PR_BRANCH+="/${BUDDY_EXECUTION_REVISION_SHORT}/$( date +%s )"

fi

# Check for changes to submodules as they require a full (rsync) deployment.
SUBMODULE_CHANGES="$( git diff "${BUDDY_EXECUTION_PREVIOUS_REVISION}..${BUDDY_EXECUTION_REVISION}" | grep -ci "Subproject commit" || true )"

# Function to rsync alley repo over vip repo, excluding default paths
function deploy_from_scratch {
    echo "Rsyncing ${ALLEY_REPO_DIR} over ${VIP_REPO_DIR}"
    rsync -aq \
        --exclude .git \
        --exclude .gitmodules \
        --exclude .revision \
        --exclude .deployment-state \
        --exclude .github/ \
        --exclude node_modules/ \
        --exclude no-vip/ \
        --delete \
        ${ALLEY_REPO_DIR} ${VIP_REPO_DIR}
}

# Default VIP_REPO_DIR to /tmp if unset
VIP_REPO_DIR="${VIP_REPO_DIR:-/tmp/${VIP_BRANCH_NAME}}"
mkdir -p ${VIP_REPO_DIR}

# Default ALLEY_REPO_DIR to script invocation directory if unset
ALLEY_REPO_DIR="${ALLEY_REPO_DIR:-$( pwd )}"

# Test for required variables
for var in \
    'PR' \
    'SUBMODULE_CHANGES' \
    'ALLEY_REPO_DIR' \
    'VIP_BRANCH_NAME' \
    'VIP_GIT_REPO' \
    'VIP_REPO_DIR' \
    'BUDDY_EXECUTION_REVISION_MESSAGE' \
    'BUDDY_EXECUTION_REVISION_SHORT' \
; do
    if [ -n "${!var}" ]; then
        echo "$var: ${!var}"
    else
        >&2 echo "$var must be defined!"
        exit 1
    fi
done

# Disable host key checking on github.com
echo "
Host github.com
	StrictHostKeyChecking no
" >> ~/.ssh/config

# Store the last commit author 
COMMIT_AUTHOR=$(git log -n1 --pretty=format:"%an <%ae>")

cd ${ALLEY_REPO_DIR}

# Clone VIP_GIT_REPO to VIP_REPO_DIR
echo "Cloning ${VIP_GIT_REPO} to ${VIP_REPO_DIR}"
git clone \
    --recursive \
    --depth 1 \
    --quiet \
    -b $VIP_BRANCH_NAME \
    git@github.com:wpcomvip/${VIP_GIT_REPO}.git ${VIP_REPO_DIR}

# If we should deploy from scratch
if [[ \
    ! $PR || \
    $BUDDY_EXECUTION_REFRESH == "true" || \
    $BUDDY_EXECUTION_CLEAR_CACHE == "true" || \
    $SUBMODULE_CHANGES != "0" \
]]; then
    deploy_from_scratch
else # Attempt to create an atomic patch for the PR

    cd ${ALLEY_REPO_DIR}
        if \
            git format-patch \
            --ignore-submodules \
            "${BUDDY_EXECUTION_PREVIOUS_REVISION}..${BUDDY_EXECUTION_REVISION}" \
            --stdout > /tmp/PR.patch
        then
            cd ${VIP_REPO_DIR}

            if \
                git am \
                --exclude=.gitmodules \
                --exclude=no-vip/ \
                --exclude .github/ \
                /tmp/PR.patch
            then
                echo "Patch successful"
            else
                >&2 echo "Failed to apply patch; falling back to deploy from scratch"
                git am --abort
                git reset --hard HEAD
                git clean -f -d
                deploy_from_scratch
            fi
        else
            >&2 echo "Failed to git format-patch; falling back to deploy from scratch"
            deploy_from_scratch
        fi
fi

cat << COMMIT_EOF > /tmp/commit.message
$BUDDY_EXECUTION_REVISION_MESSAGE
COMMIT_EOF

cd ${VIP_REPO_DIR}

# Commit changes to VIP repo
git add -A
git status
git commit \
    --allow-empty \
    -a \
    --author="${COMMIT_AUTHOR}" \
    --file=/tmp/commit.message

# Push changes to VIP repo
echo "Pushing to VIP ${VIP_BRANCH_NAME}"
git push -u origin

echo "Done"
