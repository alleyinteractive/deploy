#!/bin/bash -e -o pipefail
#
# Deploy a branch from Alley to an upstream VIP mirror
#
# Reference:
# https://github.com/alleyinteractive/deploy
# https://infosphere.alley.co/production/standards/deployment.html


# Default VIP_REPO_DIR to /tmp if unset
VIP_REPO_DIR="${VIP_REPO_DIR:-'/tmp'}"

# Default ALLEY_REPO_DIR to script invocation directory if unset
ALLEY_REPO_DIR="${ALLEY_REPO_DIR:-$( pwd )}"

# Test for required variables
for var in \
    'ALLEY_REPO_DIR'\
    'VIP_BRANCH_NAME' \
    'VIP_GIT_REPO' \
    'VIP_REPO_DIR' \
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

# Copy (rsync) alley repo over vip repo, excluding some paths
rsync -aq \
	--exclude .git \
	--exclude .gitmodules \
	--exclude .revision \
	--exclude .deployment-state \
	--exclude .buddy/ \
	--exclude .github/ \
	--exclude node_modules/ \
	--exclude no-vip/ \
    --delete \
	${ALLEY_REPO_DIR} ${VIP_REPO_DIR}

cat << COMMIT_EOF > /tmp/commit.message
$BUDDY_EXECUTION_REVISION_MESSAGE
COMMIT_EOF

cd ${VIP_REPO_DIR}

# Set git config variables
git config user.email "ops+buddy@alley.co"
git config user.name "Alley Operations"
git config push.default simple

# Add changes to VIP repo
git add -A
git status
git commit \
    --allow-empty \
    -a \
    --author="${COMMIT_AUTHOR}" \
    --file=/tmp/commit.message

echo "Pushing to VIP ${VIP_BRANCH_NAME}"
git push -u origin

echo "Done"