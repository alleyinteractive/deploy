#!/bin/bash -e -o pipefail
#
# Deploy a branch from Alley to an upstream VIP mirror
#
# See https://github.com/alleyinteractive/deploy

# Sanity test for mandatory variables
for var in \
    'VIP_BRANCH_NAME' \
    'VIP_GIT_REPO' \
    'VIP_REPO_DIR' \
    'ALLEY_REPO_DIR'\
; do
    if [ -n "${!var}" ]; then
        echo "$var: ${!var}"
    else
        >&2 echo "$var must be defined!"
        exit 1
    fi
done

# Git/SSH Configuration
# Disable host key checking on github.com
echo "
Host github.com
	StrictHostKeyChecking no
" >> ~/.ssh/config

# Store the last commit author 
COMMIT_AUTHOR=$(git log -n1 --pretty=format:"%an <%ae>")
git config --global user.email "ops+buddy@alley.co"
git config --global user.name "Alley Operations"
git config --global push.default simple

cd ${ALLEY_REPO_DIR}

echo "Cloning ${VIP_GIT_REPO} to ${VIP_REPO_DIR}"
git clone \
    --recursive \
    --depth 1 \
    --quiet \
    -b $VIP_BRANCH_NAME \
    git@github.com:wpcomvip/${VIP_GIT_REPO}.git ${VIP_REPO_DIR}

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

# Adding changes to VIP repo
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