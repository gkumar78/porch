#!/usr/bin/env bash
# Copyright 2022-2024 The kpt and Nephio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Stricter error handling
set -e # Exit on error
set -u # Must predefine variables
set -o pipefail # Check errors in piped commands
self_dir="$(dirname "$(readlink -f "$0")")"

porch_cluster_name=${PORCH_TEST_CLUSTER:-porch-test}
git_repo_name="$porch_cluster_name"
gitea_ip=172.18.255.200  # should be from the address range in deployments/local/metallb-conf.yaml

git_root="$(readlink -f "${self_dir}/..")"
cd "${git_root}"

function h1() {
  echo
  echo "** $*"
  echo 
}

##############################################
# check if git user.name is set in your environment
if ! git config --global user.name > /dev/null ; then
  cat << ENDOFEMSG
Please set the user.name and user.email global configuration values in your git environment.
This is needed for porch tests to run correctly. 
E.g:
  git config --global user.name "My Name"
  git config --global user.email "myemail@example.com"
ENDOFEMSG
  exit 128
fi

##############################################
h1 "Install kind cluster: $porch_cluster_name"
if ! kind get clusters | grep -q "^$porch_cluster_name\$" ; then
  mkdir -p ~/.kube
  kind create cluster \
    --config="${git_root}/deployments/local/kind_porch_test_cluster.yaml" \
    --name "$porch_cluster_name" \
    --kubeconfig ~/.kube/"kind-$porch_cluster_name"
else
  echo "Cluster already exists."
fi
kind export kubeconfig --name="$porch_cluster_name"

##############################################
h1 Instal MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
sleep 1
echo "Waiting for controller to become ready..."
kubectl wait --namespace metallb-system deploy controller \
                --for=condition=available \
                --timeout=90s
kubectl apply -f "${git_root}/deployments/local/metallb-conf.yaml"

############################################
h1 Install Gitea
mkdir -p "${git_root}/.build"
cd "${git_root}/.build"
if [ -d gitea ]; then
  kpt pkg update gitea
else
  kpt pkg get https://github.com/nephio-project/catalog/tree/main/distros/sandbox/gitea
fi
cd gitea
kpt fn eval \
  --image gcr.io/kpt-fn/set-annotations:v0.1.4 \
  --match-kind Service \
  --match-name gitea \
  --match-namespace gitea \
  -- "metallb.universe.tf/loadBalancerIPs=${gitea_ip}"

cp -f "${git_root}/deployments/local/kind_porch_test_cluster.yaml" cluster-config.yaml
# turn kind's cluster-config into a valid KRM
cat >> cluster-config.yaml <<EOF1
metadata: 
  name: not-used 
  annotations:
    config.kubernetes.io/local-config: "true"
EOF1
kpt fn eval \
  --image gcr.io/kpt-fn/apply-replacements:v0.1.1 \
  --fn-config "${git_root}/deployments/local/replace-gitea-service-ports.yaml"

kpt fn render 
kpt live init || true
kpt live apply --inventory-policy=adopt
echo "Waiting for gitea to become ready..."
kubectl wait --namespace gitea statefulset gitea \
                --for='jsonpath={.status.readyReplicas}=1' \
                --timeout=90s

############################################
h1 Create git repos in gitea
curl -v -k -H "content-type: application/json" "http://nephio:secret@localhost:3000/api/v1/user/repos" --data "{\"name\":\"$git_repo_name\"}"
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git clone "http://nephio:secret@localhost:3000/nephio/$git_repo_name.git"
cd "$git_repo_name"
if ! git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
  echo "Add main branch to git repo:"
  git switch -c  main
  touch README.md
  git add README.md
  git config user.name nephio
  git commit -m "first commit"
  git push -u origin main
else
  echo "main branch already exists in git repo."
fi
cd "${git_root}"
rm -fr "$TMP_DIR"

############################################
h1 Generate certs and keys
cd "${git_root}"
./deployments/local/makekeys.sh

############################################
h1 "Build the porch CLI (.build/porchctl)"
cd "${git_root}"
make porchctl

############################################
echo
echo Done.
