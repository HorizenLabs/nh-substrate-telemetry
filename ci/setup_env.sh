#!/bin/bash
set -eEo pipefail

export IS_A_RELEASE="false"
export PROD_RELEASE="false"
export DEV_RELEASE="false"
release_branch="${RELEASE_BRANCH:-master}"
type="${TYPE:-}"

if [ -z "${TRAVIS_TAG:-}" ]; then
  echo "TRAVIS_TAG:                     No TAG"
else
  echo "TRAVIS_TAG:                     ${TRAVIS_TAG}"
fi
echo "Production release branch is:   ${release_branch}"

target_version=""
if [ "${type}" = "backend" ]; then
  target_version=$(grep '^version' backend/Cargo.toml | awk '{ print $3 }' | tr -d '"')
  echo "cargo_toml_version file version:    ${target_version}"
else
  target_version=$(jq -r '.version' frontend/package.json)
  echo "package.json file version:    ${target_version}"
fi

# Functions
function fn_die() {
  echo -e "$1" >&2
  exit "${2:-1}"
}

# Functions
function import_gpg_keys() {
  # shellcheck disable=SC2207
  declare -r my_arr=( $(echo "${@}" | tr " " "\n") )

  if [ "${#my_arr[@]}" -eq 0 ]; then
    echo "Warning: there are ZERO gpg keys to import. Please check if MAINTAINERS_KEYS variable(s) are set correctly. The build is not going to be released ..."
    export IS_A_RELEASE="false"
  else
    # shellcheck disable=SC2145
    printf "%s\n" "Tagged build, fetching keys:" "${@}" ""
    for key in "${my_arr[@]}"; do
      gpg -v --batch --keyserver hkps://keys.openpgp.org --recv-keys "${key}" ||
      gpg -v --batch --keyserver hkp://keyserver.ubuntu.com --recv-keys "${key}" ||
      gpg -v --batch --keyserver hkp://pgp.mit.edu:80 --recv-keys "${key}" ||
      gpg -v --batch --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "${key}" ||
      { echo -e "Warning: ${key} can not be found on GPG key servers. Please upload it to at least one of the following GPG key servers:\nhttps://keys.openpgp.org/\nhttps://keyserver.ubuntu.com/\nhttps://pgp.mit.edu/"; export IS_A_RELEASE="false"; }
    done
  fi
}

function check_signed_tag() {
  local tag="${1}"

  if git verify-tag -v "${tag}"; then
    echo "${tag} is a valid signed tag"
  else
    echo "" && echo "=== Warning: GIT's tag = ${tag} signature is NOT valid. The build is not going to be released ... ===" && echo ""
    export IS_A_RELEASE="false"
  fi
}

function  check_versions_match () {
  local versions_to_check=("$@")

  if [ "${#versions_to_check[@]}" -eq 1 ]; then
    echo "" && echo "=== Warning: ${FUNCNAME[0]} requires more than one version to be able to compare with.  The build is not going to be released ... ===" && echo ""
    export IS_A_RELEASE="false" && return
  fi

  for (( i=0; i<((${#versions_to_check[@]}-1)); i++ )); do
    [ "${versions_to_check[$i]}" != "${versions_to_check[(($i+1))]}" ] &&
    { echo "" && echo -e "=== Warning: one or more module(s) versions do NOT match. The build is not going to be released ... ===\nThe versions are ${versions_to_check[*]}" && echo ""; export IS_A_RELEASE="false" && return; }
  done

  export IS_A_RELEASE="true"
}

# empty key.asc file in case we're not signing
touch "${HOME}/key.asc"

# Checking if it is a release build
if [ -n "${TRAVIS_TAG:-}" ]; then

  # Checking versions match
  check_versions_match "${TRAVIS_TAG}" "${target_version}"

  if [ -z "${MAINTAINERS_KEYS}" ]; then
    echo "Warning: MAINTAINERS_KEYS variable is not set. Make sure to set it up for PROD|DEV release build !!!"
  fi

  import_gpg_keys "${MAINTAINERS_KEYS}"

  # Checking git tag gpg signature requirement
  check_signed_tag "${TRAVIS_TAG}"

  # Release test
  if [ "${IS_A_RELEASE}" = "true" ]; then
    if (git branch -r --contains "${TRAVIS_TAG}" | grep -xqE ". origin\/${release_branch}$"); then
      # Checking format of production vs development release version
      if [[ "${TRAVIS_TAG}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        export PROD_RELEASE="true"
      elif [[ "${TRAVIS_TAG}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?(-rc[0-9]+){1}$ ]]; then
        export DEV_RELEASE="true"
      else
        echo "" && echo -e "=== Warning: package(s) version is in the wrong format for the RELEASE.  Expecting the following formats: ===\nd.d.d for PRODUCTION and d.d.d-rc[0-9] for DEVELOPMENT.\nThe build is not going to be released ..." && echo ""
        export IS_A_RELEASE="false"
      fi
    else
      export IS_A_RELEASE="false"
    fi
  fi
fi

# Final check for release vs non-release build
if [ "${PROD_RELEASE}" = "true" ]; then
  echo "" && echo "=== Production release ===" && echo ""
elif [ "${DEV_RELEASE}" = "true" ]; then
  echo "" && echo "=== Development release ===" && echo ""
elif [ "${IS_A_RELEASE}" = "false" ]; then
  echo "" && echo "=== NOT a RELEASE build ===" && echo ""
fi

set +eo pipefail
